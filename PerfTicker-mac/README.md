# PerfTicker for macOS (性能行情终端 · Mac 原生移植版)

本项目是 Windows 版 [PerfTicker (性能行情终端)](../README.md) 的 **macOS 原生 Swift / AppKit 实现**。
**设计理念完全不变**：依然把系统指标包装成**证券股票终端**的交互语言（实时 K 线、均线、逐笔成交、主力动向、自选行情、算力营收账本、桌面小挂件、状态栏托盘等）。

---

## 🛠 架构与技术选型

| 模块 | Windows 版原实现 | macOS 原生实现 (`PerfTicker-mac`) |
| :--- | :--- | :--- |
| **语言与框架** | C# (.NET 10) + Windows Forms (GDI+) | **Swift 5.9+ / AppKit (CoreGraphics 硬件加速渲染)** |
| **无依赖运行** | 自包含单文件 exe | **原生 Mach-O 独立二进制程序，零外部依赖** |
| **CPU 监控** | `Pdh` / `NtQuerySystemInformation` | `mach/host_processor_info` (多核/逐核/用户态/内核态) |
| **GPU 监控** | `NVML` + `D3DKMT` (Nvidia/Windows D3D) | `IOKit / IOAccelerator` (Metal 引擎/渲染负载/统一显存) |
| **内存与交换** | `GlobalMemoryStatusEx` | `mach/host_statistics64` (App内存/联动/压缩) + `vm.swapusage` |
| **磁盘与网络** | `DeviceIoControl` + `GetIfTable2` | `IOBlockStorageDriver` + `getifaddrs` |
| **进程采样** | `NtGetNextProcess` / `Process.GetProcesses` | `libproc (proc_listallpids, proc_pidinfo)` + `IOUserClientCreator` (GPU 耗时) |
| **热压力感知** | GPU 摄氏度 / 功耗 | `ProcessInfo.thermalState` (Nominal / Fair / Serious / Critical) |
| **桌面小挂件** | WinForms `WS_EX_TOOLWINDOW` 悬浮层 | `NSWindow` 无边框浮动悬浮面板 (`.floating` + `.canJoinAllSpaces`) |
| **托盘图标** | `NotifyIcon` (系统托盘) | `NSStatusItem` (macOS 顶部状态栏) 实时显示 CPU/GPU/内存 |

---

## 🚀 编译与运行

在 macOS 终端进入本目录即可构建：

```bash
cd PerfTicker-mac
swift build -c release
```

编译出的可执行文件位于：
`.build/release/PerfTicker`

直接运行：
```bash
./.build/release/PerfTicker
```

---

## 🎨 核心功能与交互保持一致

1. **红涨绿跌 / 绿涨红跌**：支持 A 股经典配色（红涨绿跌，默认开启），并支持浅色/深色主题切换。
2. **K 线走势与均线**：实时聚合采样为 2秒K、5秒K、10秒K、30秒K、1分K，计算 MA5 / MA10 / MA20，十字光标 + OHLC 悬浮窗。
3. **主力动向**：实时捕捉占用 CPU / GPU / 内存最高的前十活跃进程及热度条。
4. **逐笔成交**：将进程启动/退出、主力拉升、高负载预警转化为交易所逐笔流水。
5. **算力营收专区**：根据 CPU、GPU、内存、网络及磁盘吞吐，按盈亏平衡点模拟实时“挖矿/算力产能”营收流水。
6. **桌面小挂件 (Gadget)**：独立悬浮置顶窗，双击直接激活展开主终端。
7. **快捷键**：
   - `空格`：暂停 / 恢复行情
   - `1` ~ `5`：切换 K 线周期 (2s / 5s / 10s / 30s / 1min)
   - `T`：窗口置顶切换
   - `E`：算力营收中心开关
   - `C`：红涨 / 绿涨 配色切换
   - `⌘ + F`：筛选进程 / PID
