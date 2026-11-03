import Foundation
import IOKit
import Darwin

// MARK: - sysctl 小工具
func sysctlString(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
    var buf = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return "" }
    return String(cString: buf)
}

func sysctlInt(_ name: String) -> Int64 {
    var v: Int64 = 0
    var size = MemoryLayout<Int64>.size
    if sysctlbyname(name, &v, &size, nil, 0) != 0 { return 0 }
    if size == 4 { return Int64(Int32(truncatingIfNeeded: v)) }
    return v
}

/// 后台采样器：CPU / 内存 / GPU / 磁盘 / 网络 / 进程。全部走无需 root 的公开接口。
final class Sampler {
    private let queue = DispatchQueue(label: "perfticker.sampler", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    private var _latest = Snapshot()
    private var tickNo: Int64 = 0

    var intervalMs: Int = 1000 {
        didSet { restartTimer() }
    }
    let cores: Int = max(1, ProcessInfo.processInfo.processorCount)
    let cpuName: String = {
        let n = sysctlString("machdep.cpu.brand_string")
        return n.isEmpty ? "处理器" : n
    }()

    var latest: Snapshot { lock.lock(); defer { lock.unlock() }; return _latest }

    // 上一次采样状态
    private var prevCpu: [[UInt32]] = []
    private var prevWall: Double = 0
    private var prevDiskR: Int64 = -1, prevDiskW: Int64 = -1
    private var prevIf: [String: (UInt64, UInt64)] = [:]
    private var prevProc: [Int32: (cpuNs: UInt64, csw: Int32)] = [:]
    private var prevGpuNs: [Int32: UInt64] = [:]
    private var tb = mach_timebase_info_data_t()
    private let pageSize = Double(vm_kernel_page_size)

    init() {
        mach_timebase_info(&tb)
        restartTimer()
    }

    deinit { timer?.cancel() }

    private func restartTimer() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(max(200, intervalMs)), leeway: .milliseconds(20))
        t.setEventHandler { [weak self] in self?.sample() }
        t.resume()
        timer = t
    }

    func stop() { timer?.cancel(); timer = nil }

    // MARK: 主采样
    private func sample() {
        let s = Snapshot()
        let wall = Double(DispatchTime.now().uptimeNanoseconds) / 1e9
        let dt = prevWall > 0 ? max(0.05, wall - prevWall) : 0
        prevWall = wall
        tickNo += 1
        s.tick = tickNo
        s.cpuName = cpuName

        sampleCpu(s)
        sampleMemory(s)
        sampleGpu(s, dt: dt)
        sampleDisk(s, dt: dt)
        sampleNet(s, dt: dt)
        sampleProcs(s, dt: dt)
        s.thermal = ProcessInfo.processInfo.thermalState.rawValue

        lock.lock(); _latest = s; lock.unlock()
    }

    // MARK: CPU
    private func sampleCpu(_ s: Snapshot) {
        var n: natural_t = 0
        var info: processor_info_array_t?
        var cnt: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &n, &info, &cnt) == KERN_SUCCESS,
              let info = info else { return }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(cnt) * vm_size_t(MemoryLayout<integer_t>.size)) }
        var cur: [[UInt32]] = []
        for i in 0..<Int(n) {
            let b = i * Int(CPU_STATE_MAX)
            cur.append([UInt32(bitPattern: info[b + Int(CPU_STATE_USER)]),
                        UInt32(bitPattern: info[b + Int(CPU_STATE_SYSTEM)]),
                        UInt32(bitPattern: info[b + Int(CPU_STATE_IDLE)]),
                        UInt32(bitPattern: info[b + Int(CPU_STATE_NICE)])])
        }
        var tu = 0.0, ts = 0.0, tt = 0.0
        var core: [Double] = []
        if prevCpu.count == cur.count {
            for i in 0..<cur.count {
                let u = Double(cur[i][0] &- prevCpu[i][0]) + Double(cur[i][3] &- prevCpu[i][3])
                let sy = Double(cur[i][1] &- prevCpu[i][1])
                let id = Double(cur[i][2] &- prevCpu[i][2])
                let tot = u + sy + id
                core.append(tot > 0 ? (u + sy) / tot * 100 : 0)
                tu += u; ts += sy; tt += tot
            }
        }
        prevCpu = cur
        s.corePct = core
        if tt > 0 {
            s.cpuUserPct = tu / tt * 100
            s.cpuSysPct = ts / tt * 100
            s.cpuPct = (tu + ts) / tt * 100
        }
    }

    // MARK: 内存
    private func sampleMemory(_ s: Snapshot) {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        var st = vm_statistics64()
        var cnt = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &st) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(cnt)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &cnt) }
        }
        let gb = 1024.0 * 1024 * 1024
        s.memTotalGB = total / gb
        if kr == KERN_SUCCESS {
            // 与活动监视器「已使用内存」口径一致：App 内存 + 联动内存 + 被压缩
            let appPages = Double(st.internal_page_count) - Double(st.purgeable_count)
            let used = (max(0, appPages) + Double(st.wire_count) + Double(st.compressor_page_count)) * pageSize
            s.memUsedGB = used / gb
            s.compressedGB = Double(st.compressor_page_count) * pageSize / gb
        }
        s.memPct = s.memTotalGB > 0 ? min(100, s.memUsedGB / s.memTotalGB * 100) : 0
        var sw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &sw, &size, nil, 0) == 0 { s.swapUsedGB = Double(sw.xsu_used) / gb }
    }

    // MARK: GPU（IOAccelerator 的 PerformanceStatistics）
    private func sampleGpu(_ s: Snapshot, dt: Double) {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(it) }
        var e = IOIteratorNext(it)
        var best: GpuInfo?
        while e != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(e, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let d = props?.takeRetainedValue() as? [String: Any],
               let perf = d["PerformanceStatistics"] as? [String: Any] {
                var g = GpuInfo()
                g.available = true
                g.utilPct = (perf["Device Utilization %"] as? NSNumber)?.doubleValue ?? 0
                g.rendererPct = (perf["Renderer Utilization %"] as? NSNumber)?.doubleValue ?? 0
                g.memUsedMB = ((perf["In use system memory"] as? NSNumber)?.doubleValue ?? 0) / 1024 / 1024
                if let m = d["model"] as? String { g.name = m }
                else if let m = d["model"] as? Data { g.name = String(decoding: m.filter { $0 != 0 }, as: UTF8.self) }
                g.cores = (d["gpu-core-count"] as? NSNumber)?.intValue ?? 0
                if best == nil || g.utilPct > best!.utilPct { best = g }
            }
            IOObjectRelease(e)
            e = IOIteratorNext(it)
        }
        if let b = best { s.gpu = b }
    }

    /// 每进程累计 GPU 时间（纳秒）：来自 IOAccelerator 子节点 AppUsage。
    private func gpuTimePerPid() -> [Int32: UInt64] {
        var res: [Int32: UInt64] = [:]
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return res }
        defer { IOObjectRelease(it) }
        var acc = IOIteratorNext(it)
        while acc != 0 {
            var child: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(acc, kIOServicePlane, &child) == KERN_SUCCESS {
                var c = IOIteratorNext(child)
                while c != 0 {
                    var props: Unmanaged<CFMutableDictionary>?
                    if IORegistryEntryCreateCFProperties(c, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                       let d = props?.takeRetainedValue() as? [String: Any],
                       let creator = d["IOUserClientCreator"] as? String,
                       creator.hasPrefix("pid "),
                       let pid = Int32(creator.dropFirst(4).prefix { $0 != "," }) {
                        if let usage = d["AppUsage"] as? [[String: Any]] {
                            for u in usage {
                                if let t = (u["accumulatedGPUTime"] as? NSNumber)?.uint64Value { res[pid, default: 0] += t }
                            }
                        }
                    }
                    IOObjectRelease(c)
                    c = IOIteratorNext(child)
                }
                IOObjectRelease(child)
            }
            IOObjectRelease(acc)
            acc = IOIteratorNext(it)
        }
        return res
    }

    // MARK: 磁盘
    private func sampleDisk(_ s: Snapshot, dt: Double) {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &it) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(it) }
        var r: Int64 = 0, w: Int64 = 0
        var e = IOIteratorNext(it)
        while e != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(e, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let d = props?.takeRetainedValue() as? [String: Any],
               let st = d["Statistics"] as? [String: Any] {
                r += (st["Bytes (Read)"] as? NSNumber)?.int64Value ?? 0
                w += (st["Bytes (Write)"] as? NSNumber)?.int64Value ?? 0
            }
            IOObjectRelease(e)
            e = IOIteratorNext(it)
        }
        if prevDiskR >= 0, dt > 0 {
            s.diskReadMBps = max(0, Double(r - prevDiskR)) / dt / 1_048_576
            s.diskWriteMBps = max(0, Double(w - prevDiskW)) / dt / 1_048_576
        }
        prevDiskR = r; prevDiskW = w
    }

    // MARK: 网络
    private func sampleNet(_ s: Snapshot, dt: Double) {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return }
        defer { freeifaddrs(ifap) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        var rxDelta: UInt64 = 0, txDelta: UInt64 = 0
        var cur: [String: (UInt64, UInt64)] = [:]
        while let ifa = p {
            defer { p = ifa.pointee.ifa_next }
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = ifa.pointee.ifa_data else { continue }
            let flags = Int32(ifa.pointee.ifa_flags)
            if flags & IFF_UP == 0 || flags & IFF_LOOPBACK != 0 { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            if name.hasPrefix("awdl") || name.hasPrefix("llw") || name.hasPrefix("ap") || name.hasPrefix("bridge") { continue }
            // 高速接口优先走 64 位计数器（if_data.ifi_ibytes 是 32 位，1 秒内 >4GB 即回绕）
            if Int(addr.pointee.sa_len) >= MemoryLayout<if_data64>.size {
                let d = data.assumingMemoryBound(to: if_data64.self).pointee
                cur[name] = (d.ifi_ibytes, d.ifi_obytes)
            } else {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                cur[name] = (UInt64(d.ifi_ibytes), UInt64(d.ifi_obytes))
            }
            if let pv = prevIf[name] {
                rxDelta += cur[name]!.0 &- pv.0   // 无符号回绕安全
                txDelta += cur[name]!.1 &- pv.1
            }
        }
        prevIf = cur
        if dt > 0 {
            s.netRxMBps = Double(rxDelta) / dt / 1_048_576
            s.netTxMBps = Double(txDelta) / dt / 1_048_576
        }
    }

    // MARK: 进程
    private func sampleProcs(_ s: Snapshot, dt: Double) {
        // 先取实际进程数再分配缓冲，避免固定 4096 上限静默截断高 PID 新进程
        let n0 = proc_listallpids(nil, 0)
        guard n0 > 0 else { return }
        let cap = Int(n0) + 64   // 预留采样间隙里新起的进程
        var pids = [Int32](repeating: 0, count: cap)
        let n = Int(proc_listallpids(&pids, Int32(cap * MemoryLayout<Int32>.size)))
        guard n > 0 else { return }
        let gpuNow = gpuTimePerPid()
        var procs: [ProcSample] = []
        procs.reserveCapacity(n)
        var curProc: [Int32: (cpuNs: UInt64, csw: Int32)] = [:]
        var nameBuf = [CChar](repeating: 0, count: 64)
        var threads = 0, handles = 0
        var csw: Double = 0
        let fdSize = Int32(MemoryLayout<proc_fdinfo>.size)
        for i in 0..<n {
            let pid = pids[i]
            if pid <= 0 { continue }
            var ti = proc_taskinfo()
            let got = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, Int32(MemoryLayout<proc_taskinfo>.size))
            if got != Int32(MemoryLayout<proc_taskinfo>.size) { continue }
            let p = ProcSample()
            p.pid = pid
            nameBuf[0] = 0
            proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let nm = String(cString: nameBuf)
            p.name = nm.isEmpty ? "pid \(pid)" : nm
            p.memMB = Double(ti.pti_resident_size) / 1_048_576
            p.threads = Int(ti.pti_threadnum)
            let fds = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            p.handles = fds > 0 ? Int(fds / fdSize) : 0
            threads += p.threads
            handles += p.handles

            let ticks = ti.pti_total_user &+ ti.pti_total_system
            let ns = ticks &* UInt64(tb.numer) / UInt64(tb.denom)
            curProc[pid] = (ns, ti.pti_csw)
            if dt > 0, let pv = prevProc[pid] {
                // 整机口径：占满一颗核心 = 100/核数，钳制 0-100（与进程表阈值体系一致）
                if ns >= pv.cpuNs { p.cpuPct = min(100, Double(ns - pv.cpuNs) / (dt * 1e9) * 100 / Double(cores)) }
                let dc = Double(ti.pti_csw &- pv.csw)
                if dc > 0 { csw += dc }
                if let g = gpuNow[pid], let pg = prevGpuNs[pid], g >= pg {
                    p.gpuPct = min(100, Double(g - pg) / (dt * 1e9) * 100)
                }
            }
            procs.append(p)
        }
        prevProc = curProc
        prevGpuNs = gpuNow
        s.procs = procs
        s.procCount = procs.count
        s.threads = threads
        s.handles = handles
        if dt > 0 { s.ctxSwitchPerSec = csw / dt }
    }
}
