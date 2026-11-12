# Custocub

**Custocub = custos（拉丁语：守护、看守）+ cubby（收纳格）。**

一个原生 macOS 应用管理器，用 Swift / SwiftUI 编写。它把 Mac 上的应用收进一个清晰的应用清单里，说明每个应用**从哪里来、是什么平台、是系统还是第三方**，并支持历史快照与快照对比。

## 功能

### 1. 快速扫描应用

扫描以下目录，自动去重符号链接：

- `/Applications`（含子目录）
- `~/Applications`
- `/System/Applications`
- `/System/Library/CoreServices`
- `/Library/Apple/System/Applications`

元数据扫描通常在 **1 秒左右**完成；应用体积在后台分批并发计算，列表可以先出现，体积随后补齐。

### 2. 来源识别

| 来源 | 判断方式 |
| --- | --- |
| 系统应用 | 路径位于 `/System/`、`/System/Cryptexes/` 或 `/Library/Apple/` |
| App Store | `Contents/_MASReceipt/receipt`，并用 Spotlight 的 `kMDItemAppStoreAdamID` 兜底 |
| App Store · iOS | `Wrapper/*.app`、`WrappedBundle`、`iTunesMetadata.plist`，以及 `DTPlatformName` / `LSRequiresIPhoneOS` 等标记 |
| Homebrew | `/opt/homebrew/Caskroom`、`/usr/local/Caskroom` 的符号链接或 Cask 应用名索引 |
| Steam | `Contents/MacOS/run.sh` 中带有 `steam://run/<AppID>`，或真实游戏位于 Steam 库的 `steamapps/common` 下 |
| JetBrains Toolbox | 读取 `~/Library/Application Support/JetBrains/Toolbox/state.json` 中 `tools[].installLocation`，只匹配 Toolbox 实际安装的路径 |
| 手动安装 | 以上规则都不匹配 |

系统应用优先级最高，因此 Apple 自带应用即使带 App Store 收据也会被标为「系统应用」。Xcode、Apple Configurator 等从 App Store 安装的 Apple 工具会正确显示为 App Store。

侧边栏「来源」区可以一键筛选 Homebrew、App Store、App Store · iOS、Steam、JetBrains Toolbox、手动安装和系统应用，并实时显示每类应用数量；数量为 0 的来源会自动隐藏。

### 3. 平台与类型

直接读取主可执行文件的 Mach-O 头，不调用 `lipo` 子进程：

- `arm64`（Apple 芯片）
- `x86_64`（Intel）
- 通用二进制（arm64 + x86_64）
- iOS 应用
- 未知（脚本类或缺少可执行文件）

同时记录 Bundle ID、版本、构建号、最低系统版本、安装时间、更新时间、实际占用空间、可执行文件路径。

### 4. 快照与对比

- 一键保存当前应用清单为历史快照。
- 快照包含体积、安装时间、更新时间、Bundle ID、版本、架构、来源和 **PNG 图标**。
- 每个快照单独存为一个 JSON 文件，重命名/写备注不会重写所有历史快照。
- 支持导入、导出单个或一组快照。
- 快照对比会列出新增、移除、更新，并显示字段级变化（版本、大小、路径、架构等）。
- 可以把「当前状态」作为比较的一方。

### 5. 展示框

「展示框」用图标网格浏览所有软件：

- 已安装应用来自实时扫描。
- **已卸载应用**来自历史快照；即使磁盘上的应用已经删除，仍会用快照中的图标和元数据继续展示它们。
- 支持按已安装/已卸载、来源、平台、系统/第三方筛选和搜索。

## 构建

已在 macOS 14+ 上测试。仓库中已经包含生成好的 `Custocub.xcodeproj`：

```bash
open Custocub.xcodeproj
```

选择 `Custocub` scheme 运行即可。

也可以使用命令行构建：

```bash
xcodebuild -project Custocub.xcodeproj \
  -scheme Custocub \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

如果修改了 `project.yml`，重新生成工程：

```bash
xcodegen generate
```

## 数据位置

快照保存在：

```
~/Library/Application Support/Custocub/Snapshots/<UUID>.json
```

设置中可以重新扫描或清除图标缓存。应用本身不需要 App Sandbox 权限（仅读取应用目录并写入自己的 Application Support 目录）。

## 快捷键

| 快捷键 | 操作 |
| --- | --- |
| `⌘R` | 重新扫描应用 |
| `⌘S` | 保存当前快照 |
| `⇧⌘O` | 导入快照 |
| `⇧⌘E` | 导出当前快照 |
| `⌘,` | 打开设置 |

## 工程结构

```
Custocub/
├─ App/
│  ├─ CustocubApp.swift       # App 入口、菜单命令
│  └─ CustocubStore.swift     # 扫描、快照、展示框状态
├─ Models/
│  ├─ AppSource.swift         # 来源与平台枚举
│  ├─ AppRecord.swift         # 应用记录
│  ├─ AppSnapshot.swift       # 快照
│  ├─ AppChange.swift         # 快照对比与 Markdown 报告
│  └─ GalleryItem.swift       # 展示框条目
├─ Services/
│  ├─ AppScanner.swift        # 目录发现、Info.plist、来源识别
│  ├─ HomebrewIndex.swift     # Caskroom 索引
│  ├─ MachOReader.swift       # Mach-O 架构解析
│  ├─ DirectorySize.swift     # 应用体积
│  ├─ IconProvider.swift      # 图标读取与快照 PNG
│  └─ SnapshotRepository.swift
├─ Views/
│  ├─ ContentView.swift
│  ├─ SidebarView.swift
│  ├─ AppListView.swift
│  ├─ GalleryView.swift
│  ├─ AppDetailView.swift
│  ├─ ComparisonView.swift
│  ├─ SettingsView.swift
│  ├─ Components.swift
│  └─ FileActions.swift
└─ Resources/Assets.xcassets
```

`sample/` 中是制作过程中的参考项目，不参与本工程构建。
