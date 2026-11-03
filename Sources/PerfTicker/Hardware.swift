import Foundation

/// 硬件探测：识别实际设备并按算力给出「营收基准权重」。
final class Hardware {
    var cpuName = "处理器"
    var logicalCores = 1, physicalCores = 0
    var perfCores = 0, effCores = 0
    var baseMhz = 0.0
    var gpuName = "图形处理器"
    var gpuCores = 0
    var hasGpu = false
    var memTotalGB = 0.0
    var fixedDisks = 1
    var osName = "macOS", osBuild = "", arch = "", runtime = "Swift"
    var wcpu = 1.0, wgpu = 1.0, wmem = 1.0, wdisk = 1.0, wnet = 1.0

    var cpuLine: String {
        var s = "\(cpuName) · " + (physicalCores > 0 ? "\(physicalCores)C/\(logicalCores)T" : "\(logicalCores)T")
        if perfCores > 0 && effCores > 0 { s += " (\(perfCores)P+\(effCores)E)" }
        if baseMhz > 0 { s += String(format: " · %.1fGHz", baseMhz / 1000) }
        return s
    }
    var gpuLine: String {
        hasGpu ? gpuName + (gpuCores > 0 ? " · \(gpuCores) 核" : "") + " · 统一内存" : "\(gpuName) · 未检测到 GPU"
    }
    var memLine: String { String(format: "%.0fGB 内存 · 本地磁盘 ×%d", memTotalGB, fixedDisks) }
    var osLine: String { "\(osName) · Build \(osBuild) · \(arch) · \(runtime)" }
    var weightLine: String {
        String(format: "CPU ×%.2f ｜ GPU ×%.2f ｜ 内存 ×%.2f ｜ 磁盘 ×%.2f ｜ 网络 ×%.2f", wcpu, wgpu, wmem, wdisk, wnet)
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

    func probe(cpuName name: String, gpuName gn: String, gpuCores gc: Int, hasGpu hg: Bool, memTotalGB mem: Double) {
        logicalCores = max(1, ProcessInfo.processInfo.processorCount)
        physicalCores = Int(sysctlInt("hw.physicalcpu"))
        if physicalCores <= 0 || physicalCores > logicalCores { physicalCores = logicalCores }
        perfCores = Int(sysctlInt("hw.perflevel0.physicalcpu"))
        effCores = Int(sysctlInt("hw.perflevel1.physicalcpu"))
        cpuName = name
        baseMhz = Double(sysctlInt("hw.cpufrequency")) / 1e6   // Intel Mac 才有；Apple Silicon 为 0
        hasGpu = hg; gpuName = gn; gpuCores = gc
        memTotalGB = mem
        let keys: [URLResourceKey] = [.volumeIsLocalKey, .volumeIsInternalKey]
        let vols = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        fixedDisks = max(1, vols.filter { (try? $0.resourceValues(forKeys: Set(keys)).volumeIsLocal) == true }.count)

        let v = ProcessInfo.processInfo.operatingSystemVersion
        osName = "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
        osBuild = sysctlString("kern.osversion")
        arch = sysctlString("hw.machine") == "x86_64" ? "x86_64" : "arm64"
        #if swift(>=6.0)
        runtime = "Swift 6"
        #else
        runtime = "Swift 5"
        #endif

        // 营收基准：按真实算力归一化（16 线程 / 统一内存 32G / 10 核 GPU 为 1.0）
        wcpu = clamp(Double(logicalCores) / 16, 0.30, 4.0)
        wgpu = hasGpu ? clamp(gpuCores > 0 ? Double(gpuCores) / 10 : 1.0, 0.30, 4.0) : 0.25
        wmem = clamp(memTotalGB / 32, 0.30, 4.0)
        wdisk = clamp(Double(fixedDisks) / 2, 0.50, 2.0)
        wnet = 1.0
    }
}
