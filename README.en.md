# PerfTicker for macOS

[简体中文](README.md) | **English**

> Turn the macOS Activity Monitor into a **stock-market trading terminal**: CPU / GPU / memory / disk / network —
> every system metric becomes a listed "stock", complete with live candlestick charts, order books, tick-by-tick trades and a favorites list.
> Native Swift / AppKit, zero external dependencies, ships as a single binary.
>
> Author **QiuSui** · Organization **QiuSui_Studio** · License **GPL-3.0**

![Preview](cover.png)

## 1. What is this?

A traditional activity monitor is a "list"; PerfTicker translates the same data into the visual language of a **securities trading terminal**:

| Market concept | System metric |
| --- | --- |
| Index strip | CPU composite index, CPU load, GPU load, memory usage, GPU memory, network download, process count |
| Favorites list | Monitored metrics (incl. per-core usage) |
| Ticker codes | `000001`, `600519`… every metric has an exchange-style code |
| Candlesticks | Samples are ticks, aggregated into OHLC candles at 2s / 5s / 10s / 30s / 1min; **solid red up / solid green down** with MA5/10/20 and volume |
| Change / % change | Relative to today's open; deltas shown in native units (`+2.8pt`, `+0.4GB`) |
| Sampling intervals | 0.5s / 1s / 2s / 5s / 10s |
| Order book · Momentum | Top 10 processes for the selected metric, with heat bars and rank badges |
| Tick-by-tick feed | Process launches/exits, load spikes, memory/load alerts, active-process trade flow |
| Stock list | Full process table: PID / name / CPU% / change / GPU% / memory / threads / mini candles; search, pin, kill process |
| Marquee | Rolling news ticker across all metrics |

**Red up / green down** follows the A-share convention; the "红涨" (red-up) title-bar button switches to the international scheme (green up / red down) in one click.

## 2. Layout

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Brand · live sampling status · interval · pause · pin · colors · clock   │
├──────────────────────────────────────────────────────────────────────────┤
│ Index strip (multi-cell, with mini candles)                              │
├───────────────┬──────────────────────────────────┬───────────────────────┤
│ Favorites     │ Instrument header (last/change/ │ Momentum (Top 10)     │
│ grouped       │ open/high/low)                   │ heat bars + badges    │
│ Mini candles  │ Candle period switcher           ├───────────────────────┤
│ last / change │ Chart: candles + MA + volume +   │ Tick-by-tick feed     │
│               │ crosshair with OHLC tooltip      │                       │
├───────────────┴──────────────────────────────────┴───────────────────────┤
│ Stock list (process table, sortable, scrollable, mini candles per row)   │
├──────────────────────────────────────────────────────────────────────────┤
│ Sampling/uptime/processes/threads + marquee + shortcut hints             │
└──────────────────────────────────────────────────────────────────────────┘
```

## 3. Settings / status bar / About

- **Settings**: `Launch at login` (SMAppService), `bottom marquee` toggle, `theme` with three modes (dark / light / follow system, live-tracking appearance changes). Changes apply instantly and persist automatically.
- **Closing the window does not quit**: sampling and economy settlement keep running in the status bar; the status-bar menu offers `Open main window` / `Reset earnings` / `Quit`.
- **About window**: developer, organization, GPL-3.0 license, plus runtime environment (macOS version/architecture), hardware profile (chip/cores, GPU cores, memory, disks, network) and the earnings baseline factors.

## 4. Desktop gadget

Toggle via the title-bar "gadget" switch, the status-bar menu, or `F9` in the main window; position and on/off state are remembered.

- **Drag anywhere** to move — position is persisted;
- **Double-click** the gadget to open the main window;
- Top-right "顶" = always on top (off by default — it won't steal focus);
- Lives outside the Dock and `⌘+Tab`, visible across all Spaces.

## 5. Interaction

| Action | Result |
| --- | --- |
| Click index cell / favorites row | Switch the selected "stock"; chart, order book and feed follow |
| Click `2s`…`1min` | Switch candle period |
| Hover the chart | Crosshair + OHLC / change tooltip |
| Click "CPU / GPU / Memory" | Sort the process table (click again to reverse) |
| Search box (or `⌘F`) | Filter by process name / PID, `Esc` clears |
| Right-click a process row | Menu: **kill process** (with confirmation) / **pin to top** |
| Scroll wheel | Scroll favorites / process table |

**Shortcuts**: `Space` pause/resume · `1`-`5` candle periods · `E` economy · `⌘F` search · `T` pin window · `C` red/green swap · `F9` gadget · `⌘,` settings

Window position, size, sampling interval, color scheme, selected stock and sort order are remembered (`~/Library/Application Support/PerfTicker/settings.json`).

## 6. Economy system (compute business)

Toggle "earnings" in the title bar (off by default, shortcut `E`). A dedicated area appears under the chart: every utilization becomes production capacity — sustained high load earns money, idling loses it.

| Unit | Full-load yield | Break-even utilization |
| --- | --- | --- |
| CPU composite | ¥22.0/s | 30% |
| GPU engine | ¥30.0/s | 28% |
| Memory | ¥12.0/s | 35% |
| Disk IO | ¥7.2/s | 25% |
| Network | ¥7.2/s | 25% |

> Cumulative earnings persist locally (`EcoTotal / EcoPeak / EcoSeconds` in `settings.json`, settled against real wall-clock time, saved every 15s and on exit) and survive restarts.
> Toggling earnings only pauses/resumes settlement — it never resets; only the in-panel "reset" button or the status-bar menu clears the ledger.
>
> **Hardware adaptive**: at startup the app probes the chip (P/E cores), GPU core count, unified memory, fixed disks and OS version, then scales full-load yields against a reference machine (clamped to 0.3–4.0×).

Settlement rule (`Economy.NetOf`):

```
net (¥/s) = full-load yield × (utilization/100)^1.7 − idle cost
idle cost = full-load yield × (break-even/100)^1.7
```

The exponent 1.7 models increasing marginal returns; below break-even the unit loses money. System thermal pressure (`thermalState`) throttles CPU/GPU yields (overheat derating); pausing (`Space`) halts settlement.

## 7. Performance

- Hidden/minimized windows stop all redraws; only sampling and settlement continue (heartbeat keeps running);
- Panels repaint on independent schedules — static regions are never redrawn;
- Pixel-aligned candles/grids, shared pens/brushes, cached formatters and paragraph styles;
- Diagnostics log (rolling) at `~/Library/Logs/PerfTicker`.

## 8. Data sources

| Metric | Mechanism | Notes |
| --- | --- | --- |
| CPU usage | `mach host_processor_info` | per-core user+sys/total, averaged machine-wide |
| Memory | `mach host_statistics64` + `sysctl vm.swapusage` | app/wired/compressed + swap |
| GPU engine usage / per-process GPU | IOKit `IOAccelerator` stats | unified-memory semantics on Apple Silicon |
| Disk read/write | IOKit `IOBlockStorageDriver` | bytes/s |
| Network up/down | `getifaddrs` (prefers 64-bit counters) | bytes/s |
| Process CPU / memory / threads | `libproc` (`proc_listallpids` / `proc_pidinfo`) | process CPU% is machine-share (0–100) |
| Thermal pressure | `ProcessInfo.thermalState` | Nominal/Fair/Serious/Critical derating |

> Apple Silicon does not expose real-time frequencies or dedicated VRAM sensors to third-party apps; those panels use utilization/thermal substitutes (noted in the UI). All collection is **read-only** and needs no administrator privileges.

## 9. Build

Requires Xcode 15+ / Swift 5.9+:

```bash
swift build -c release
# binary: .build/release/PerfTicker
```

Package a DMG (.app bundle, icon, universal binary, ad-hoc signature):

```bash
./build_dmg.sh
```

## 10. Code layout

```
├─ Package.swift          SwiftPM manifest
├─ build_dmg.sh           DMG packaging script (universal binary)
├─ Sources/PerfTicker/
│  ├─ main.swift          entry, single-instance guard, standard menu bar
│  ├─ AppController.swift status bar, heartbeat, data feeds, events, economy
│  ├─ Sampler.swift       background sampler: CPU/mem/GPU/disk/net/processes
│  ├─ Model.swift         metric catalog (codes, units, precision), ticks & candles
│  ├─ Theme.swift         dark-terminal visual system: colors, type scale, tools
│  ├─ Panels.swift        title bar / index strip / favorites / instrument header
│  ├─ Panels2.swift       momentum / tick feed / footer marquee
│  ├─ ChartPanel.swift    chart: candles + MA + volume + crosshair
│  ├─ MainContentView.swift content view & shortcuts
│  ├─ GadgetWindow.swift  desktop gadget panel
│  ├─ AboutWindow.swift   about window
│  ├─ Hardware.swift      hardware probing & earnings baseline weights
│  └─ Art.swift           runtime-generated app icon
└─ video/promo/           Remotion promo-video project
```

## 11. Known limitations

- **Real-time CPU/GPU frequencies and temperatures**: Apple Silicon hides these sensors from third-party apps; utilization and thermal substitutes are used instead;
- Per-process GPU usage relies on IOAccelerator stats and may be unavailable on some models/OS versions (shown as `—`);
- "Launch at login" uses SMAppService — most reliable when the .app is installed in `/Applications`.

## 12. License & credits

| | |
| --- | --- |
| Developer | QiuSui |
| Organization | QiuSui_Studio |
| GitHub | https://github.com/QiuSui1145/ |
| Bilibili | https://space.bilibili.com/1764510273 |
| License | [GPL-3.0](LICENSE) |

This project is licensed under the GNU General Public License v3.0: free to use, modify and distribute; derivatives must remain GPL-3.0 with the copyright notice preserved.
