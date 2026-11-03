import AppKit

struct Tick { var ms: Int64 = 0; var v: Double = 0; var vol: Double = 0 }

final class Candle {
    var bucket: Int64
    var o: Double, h: Double, l: Double, c: Double, vol: Double
    init(bucket: Int64, v: Double, vol: Double) { self.bucket = bucket; o = v; h = v; l = v; c = v; self.vol = vol }
}

func nowMs() -> Int64 { Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000) }

func fmtD(_ v: Double, _ d: Int) -> String { String(format: "%.\(d)f", v) }

private var nfCache: [Int: NumberFormatter] = [:]
func fmtThousands(_ v: Double, decimals: Int = 0) -> String {
    let f: NumberFormatter
    if let cached = nfCache[decimals] {
        f = cached
    } else {
        f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = decimals
        f.maximumFractionDigits = decimals
        f.locale = Locale(identifier: "en_US")
        nfCache[decimals] = f
    }
    return f.string(from: NSNumber(value: v)) ?? String(v)
}

/// 一条「个股」：把一项性能指标包装成行情品种（带分时、K 线、涨跌幅）。
final class Metric {
    var code = "", name = "", group = "", unit = ""
    var decimals = 2
    var read: (Snapshot) -> Double = { _ in 0 }

    private let tickCap = 3600
    private var ring: [Tick]
    private var head = 0, count_ = 0
    var tickCount: Int { count_ }
    func tickAt(_ i: Int) -> Tick { ring[(head + i) % tickCap] }

    private func append(_ t: Tick) {
        let idx = (head + count_) % tickCap
        ring[idx] = t
        if count_ < tickCap { count_ += 1 } else { head = (head + 1) % tickCap }
    }

    var candles: [Candle] = []
    var value = 0.0, prev = 0.0, open = 0.0
    var high = -Double.greatestFiniteMagnitude, low = Double.greatestFiniteMagnitude
    var sum = 0.0
    var count = 0
    var flashUntil: Int64 = 0
    var flashDir = 0
    var shown = 0.0

    init() { ring = [Tick](repeating: Tick(), count: 3600) }
    static let empty: Metric = { let m = Metric(); m.code = "000000"; m.name = "--"; return m }()

    func tween() -> Bool {
        let d = value - shown
        if abs(d) < 1e-6 { shown = value; return false }
        shown += d * 0.42
        if abs(value - shown) < 1e-4 { shown = value }
        return true
    }

    var shownChg: Double { shown - open }
    var shownText: String { fmt(shown) }
    var chg: Double { value - open }
    var chgPct: Double { abs(open) > 1e-9 ? (value - open) / abs(open) * 100 : 0 }

    func deltaText(_ d: Double) -> String {
        let sign = d >= 0 ? "+" : "-"
        switch unit {
        case "%": return sign + String(format: "%.2f", abs(d)) + "pt"
        case "": return sign + String(format: "%.0f", abs(d))
        default: return sign + String(format: decimals <= 0 ? "%.0f" : "%.2f", abs(d)) + unit
        }
    }
    var chgText: String { deltaText(chg) }
    var shownChgText: String { deltaText(shownChg) }

    func fmt(_ v: Double) -> String {
        if abs(v) >= 10000 { return fmtThousands(v) }
        return fmtD(v, decimals)
    }
    var display: String { fmt(value) }

    func push(_ v: Double, _ ms: Int64, _ vol: Double) {
        if v.isNaN || v.isInfinite { return }
        prev = count == 0 ? v : value
        value = v
        if count == 0 { open = v; high = v; low = v }
        if v > high { high = v }
        if v < low { low = v }
        sum += v
        count += 1
        if count <= 60 { open = sum / Double(count) }   // 开盘价用前若干采样均值平滑
        if abs(v - prev) > 1e-9 && count > 1 {
            flashDir = v > prev ? 1 : -1
            flashUntil = ms + 700
        }
        if count <= 1 { shown = v }
        append(Tick(ms: ms, v: v, vol: vol))
    }

    func rebuildCandles(_ periodMs: Int64) {
        candles.removeAll(keepingCapacity: true)
        let period = periodMs < 1 ? 1000 : periodMs
        var cur: Candle?
        var curBucket: Int64 = -1
        for ti in 0..<count_ {
            let t = tickAt(ti)
            let b = t.ms / period
            if cur == nil || b != curBucket {
                if let c = cur { candles.append(c) }
                cur = Candle(bucket: b, v: t.v, vol: t.vol)
                curBucket = b
            } else if let c = cur {
                if t.v > c.h { c.h = t.v }
                if t.v < c.l { c.l = t.v }
                c.c = t.v
                c.vol += t.vol
            }
        }
        if let c = cur { candles.append(c) }
        if candles.count > 900 { candles.removeFirst(candles.count - 900) }
    }

    func spark(_ nIn: Int) -> [Double] {
        let n = min(nIn, count_)
        if n <= 0 { return [] }
        return (0..<n).map { tickAt(count_ - n + $0).v }
    }
}

enum Catalog {
    static let groupOrder = ["指数", "处理器", "图形", "内存", "存储网络", "系统"]

    static func build(cores: Int) -> [Metric] {
        var list: [Metric] = []
        func add(_ code: String, _ name: String, _ group: String, _ unit: String, _ dec: Int, _ read: @escaping (Snapshot) -> Double) {
            let m = Metric()
            m.code = code; m.name = name; m.group = group; m.unit = unit; m.decimals = dec; m.read = read
            list.append(m)
        }
        // 指数
        add("000001", "CPU 用户态", "指数", "%", 1) { $0.cpuUserPct }
        add("000002", "CPU 负载", "指数", "%", 1) { $0.cpuPct }
        add("000003", "内存占用", "指数", "%", 1) { $0.memPct }
        // 处理器各核心（Apple Silicon 不开放逐核频率，改为逐核占用率）
        for i in 0..<cores {
            add(String(format: "0001%02d", i + 1), String(format: "核心 %02d", i + 1), "处理器", "%", 1) { s in
                i < s.corePct.count ? s.corePct[i] : 0
            }
        }
        add("000004", "CPU 系统态", "处理器", "%", 1) { $0.cpuSysPct }
        // 图形
        add("600521", "GPU 负载", "图形", "%", 1) { $0.gpu.utilPct }
        add("600520", "渲染器负载", "图形", "%", 1) { $0.gpu.rendererPct }
        add("600522", "显存占用", "图形", "%", 1) { s in
            s.memTotalGB > 0 ? s.gpu.memUsedMB / 1024 / s.memTotalGB * 100 : 0
        }
        add("600524", "GPU 显存用量", "图形", "GB", 2) { $0.gpu.memUsedMB / 1024 }
        // 内存
        add("000858", "已用内存", "内存", "GB", 2) { $0.memUsedGB }
        add("000859", "交换已用", "内存", "GB", 2) { $0.swapUsedGB }
        add("000860", "压缩内存", "内存", "GB", 2) { $0.compressedGB }
        // 存储 / 网络
        add("601398", "磁盘读取", "存储网络", "MB/s", 2) { $0.diskReadMBps }
        add("601399", "磁盘写入", "存储网络", "MB/s", 2) { $0.diskWriteMBps }
        add("600036", "网络下行", "存储网络", "MB/s", 2) { $0.netRxMBps }
        add("600037", "网络上行", "存储网络", "MB/s", 2) { $0.netTxMBps }
        // 系统
        add("000300", "上下文切换", "系统", "K/s", 1) { $0.ctxSwitchPerSec / 1000 }
        add("000301", "进程数", "系统", "", 0) { Double($0.procCount) }
        add("000302", "线程数", "系统", "", 0) { Double($0.threads) }
        add("000303", "句柄数", "系统", "", 0) { Double($0.handles) }
        add("000304", "热压力", "系统", "级", 0) { Double($0.thermal) }
        return list
    }
}

final class ProcSample {
    var pid: Int32 = 0
    var name = ""
    var cpuPct = 0.0       // 整机占比（0-100）：占满全部核心 = 100
    var gpuPct = 0.0
    var memMB = 0.0
    var threads = 0
    var handles = 0
    var cpuDelta = 0.0
}

struct GpuInfo {
    var available = false
    var name = "图形处理器"
    var utilPct = 0.0
    var rendererPct = 0.0
    var memUsedMB = 0.0
    var cores = 0
}

final class Snapshot {
    var tick: Int64 = 0
    var cpuPct = 0.0, cpuUserPct = 0.0, cpuSysPct = 0.0
    var corePct: [Double] = []
    var cpuName = "处理器"
    var memUsedGB = 0.0, memTotalGB = 0.0, memPct = 0.0
    var swapUsedGB = 0.0, compressedGB = 0.0
    var gpu = GpuInfo()
    var diskReadMBps = 0.0, diskWriteMBps = 0.0
    var netRxMBps = 0.0, netTxMBps = 0.0
    var ctxSwitchPerSec = 0.0
    var threads = 0, handles = 0, procCount = 0
    var thermal = 0            // 0 nominal · 1 fair · 2 serious · 3 critical
    var procs: [ProcSample] = []
}

struct TapeEvent { var ms: Int64; var time: String; var text: String; var color: NSColor }

final class ProcHist {
    private(set) var v = [Double](repeating: 0, count: 36)
    private(set) var len = 0
    func push(_ x: Double) {
        v.removeFirst(); v.append(x)
        if len < v.count { len += 1 }
    }
    func snapshot() -> [Double] { len <= 0 ? [] : Array(v.suffix(len)) }
}

final class AppState {
    var metrics: [Metric] = []
    var snap = Snapshot()
    var selectedIndex = 1
    var selected: Metric { metrics.isEmpty ? Metric.empty : metrics[max(0, min(selectedIndex, metrics.count - 1))] }
    var periodMs: Int64 = 5000
    var intervalMs = 1000
    var paused = false
    var topMost = false
    var redUp = true
    var marquee = true
    var tape: [TapeEvent] = []
    var procHist: [Int32: ProcHist] = [:]
    var procs: [ProcSample] = []
    var watchScroll: CGFloat = 0
    var searchActive = false
    var procFilter = ""
    var pinned = Set<String>()
    var procScroll = 0
    var procSort = 0           // 0=CPU 1=GPU 2=内存 3=线程
    var procSortDesc = true
    var hoverProc = -1
    var selectedProc = -1
    var frame = 0.0
    var startMs = nowMs()
    var cpuName = ""
    let economy = Economy()

    func byCode(_ code: String) -> Metric? { metrics.first { $0.code == code } }
    func applyColorMode() { Theme.applyColorMode(redUp: redUp) }
}

// ── 营收系统 ──
final class EcoPart {
    var name = ""
    var load = 0.0, loadShown = 0.0
    var baseFull = 0.0, full = 0.0
    var net = 0.0, total = 0.0
    var breakEven = 0.0
    init(_ name: String, _ baseFull: Double, _ breakEven: Double) {
        self.name = name; self.baseFull = baseFull; self.full = baseFull; self.breakEven = breakEven
    }
}

/// 算力经营账本：每个部件按占用率产生「营收」，低于盈亏平衡点即开始亏损，高负载越久赚得越多。
final class Economy {
    var enabled = false
    var total = 0.0, rate = 0.0, peakRate = 0.0, seconds = 0.0
    var tempPenalty = 1.0
    let parts = [
        EcoPart("CPU 综合", 22.0, 30), EcoPart("GPU 引擎", 30.0, 28), EcoPart("内存", 12.0, 35),
        EcoPart("磁盘 IO", 7.2, 25), EcoPart("网络", 7.2, 25),
    ]
    var rateHist: [Double] = []
    private var histAcc = 0.0
    private let K = 1.7

    func applyWeights(_ hw: Hardware) {
        let w = [hw.wcpu, hw.wgpu, hw.wmem, hw.wdisk, hw.wnet]
        for i in 0..<min(parts.count, w.count) { parts[i].full = parts[i].baseFull * w[i] }
    }

    func restore(total: Double, peak: Double, seconds: Double) {
        self.total = total; peakRate = peak; self.seconds = seconds; rate = 0
    }

    func reset() {
        total = 0; rate = 0; peakRate = 0; seconds = 0
        rateHist.removeAll(); histAcc = 0
        for p in parts { p.load = 0; p.loadShown = 0; p.net = 0; p.total = 0 }
    }

    private func clamp(_ v: Double) -> Double { v < 0 ? 0 : v > 100 ? 100 : v }

    func netOf(_ p: EcoPart, _ load: Double, _ penalty: Double) -> Double {
        let x = load / 100.0
        let gross = p.full * pow(x, K)
        let cost = p.full * pow(p.breakEven / 100.0, K)
        return gross * penalty - cost
    }

    func accrue(_ dtIn: Double, _ s: Snapshot) {
        var dt = dtIn
        if !enabled || dt <= 0 { return }
        if dt > 0.5 { dt = 0.5 }   // 防止长时间挂起后一次性灌入大量营收
        seconds += dt
        let loads = [
            clamp(s.cpuPct), s.gpu.available ? clamp(s.gpu.utilPct) : 0, clamp(s.memPct),
            clamp((s.diskReadMBps + s.diskWriteMBps) * 10), clamp((s.netRxMBps + s.netTxMBps) * 20),
        ]
        // 过热降频：macOS 以热压力等级体现（Nominal/Fair/Serious/Critical）
        let penalty: Double = [1.0, 0.95, 0.88, 0.78][max(0, min(3, s.thermal))]
        tempPenalty = penalty
        var sum = 0.0
        for i in 0..<parts.count {
            let p = parts[i]
            let pen = i <= 1 ? penalty : 1.0
            let n = netOf(p, loads[i], pen)
            p.load = loads[i]
            p.loadShown += (loads[i] - p.loadShown) * 0.12
            p.net += (n - p.net) * 0.12
            p.total += n * dt
            sum += n
        }
        total += sum * dt
        rate += (sum - rate) * 0.12
        if rate > peakRate { peakRate = rate }
        histAcc += dt
        if histAcc >= 1.0 {
            histAcc = 0
            rateHist.append(rate)
            if rateHist.count > 200 { rateHist.removeFirst() }
        }
    }
}

// ── 设置持久化：~/Library/Application Support/PerfTicker/settings.json ──
struct Settings: Codable {
    var schemaVersion = 1
    var x: Double = -99999, y: Double = -99999, w: Double = 0, h: Double = 0
    var maximized = false
    var intervalMs = 1000
    var periodMs: Int64 = 2000
    var redUp = true
    var topMost = false
    var economyOn = false
    var gadget = false
    var gadgetX: Double = -1, gadgetY: Double = -1
    var autoStart = false
    var marquee = true
    var themeMode = 1            // 0=深色 1=浅色 2=跟随系统
    var ecoTotal = 0.0, ecoPeak = 0.0, ecoSeconds = 0.0
    var selectedCode = "000002"
    var procSort = 0
    var procSortDesc = true

    static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PerfTicker")
    }
    static var file: URL { dir.appendingPathComponent("settings.json") }

    static func load() -> (Settings, String?) {
        guard FileManager.default.fileExists(atPath: file.path) else { return (Settings(), nil) }
        do {
            let data = try Data(contentsOf: file)
            return (try JSONDecoder().decode(Settings.self, from: data), nil)
        } catch {
            Diag.error("SETTINGS", "\(error)")
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
            let bak = file.path + ".bak-" + f.string(from: Date())
            try? FileManager.default.copyItem(atPath: file.path, toPath: bak)
            return (Settings(), "配置文件损坏，已备份并恢复默认（\((bak as NSString).lastPathComponent)）")
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: Settings.dir, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted]
            try enc.encode(self).write(to: Settings.file, options: .atomic)
        } catch { Diag.error("SETTINGS-SAVE", "\(error)") }
    }
}

// ── 诊断日志：~/Library/Logs/PerfTicker ──
enum Diag {
    static let lock = NSLock()
    static var logDir: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/PerfTicker")
    }
    static var file: URL { logDir.appendingPathComponent("perfticker.log") }

    private static var dirEnsured = false
    static func write(_ tag: String, _ msg: String) {
        lock.lock(); defer { lock.unlock() }
        if !dirEnsured {
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
            dirEnsured = true
        }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let line = "\(f.string(from: Date())) [\(tag)] \(msg)\n"
        if let attr = try? FileManager.default.attributesOfItem(atPath: file.path),
           let size = attr[.size] as? Int, size > 1_048_576 {
            let old = logDir.appendingPathComponent("perfticker.1.log")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: file, to: old)
        }
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.data(using: .utf8)?.write(to: file)
        }
    }
    static func error(_ tag: String, _ msg: String) { write(tag, "ERROR " + msg) }
}
