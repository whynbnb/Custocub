# Custocub

[English](README.md) · [简体中文](README.zh-CN.md)

> Vibe Coding而成（DeepSeek V4.1 Flash / OpenCode）

**Custocub = custos（拉丁语：守护、看守）+ cubby（收纳格）。**

Custocub 是一个用 Swift / SwiftUI 编写的原生 macOS 应用清单与快照管理器。它把 Mac 上的应用收进一个清晰的清单里，说明每个应用从哪里来、运行在什么架构上、是系统还是第三方应用，并支持历史快照与快照对比。

- **版本：** 1.0
- **Bundle ID：** `me.whynbnb.Custocub`
- **平台：** macOS 14+
- **界面语言：** 简体中文
- **许可证：** MIT

## 核心亮点

- **快速扫描**：元数据通常在 1 秒左右完成，应用体积在后台计算。
- **准确的来源识别**：系统、App Store、App Store · iOS、Homebrew、Steam、JetBrains Toolbox、手动安装。
- **平台与类型**：系统 / 第三方，以及 `arm64` / `x86_64` / 通用二进制检测。
- **开发者的应用**：按可配置的 Bundle ID 前缀自动归类，匹配数量大于 2 时显示。
- **快照与对比**：保存历史清单、比较变化、导入导出、生成 Markdown 报告。
- **展示框**：浏览已安装应用，也展示历史快照中已经卸载的应用。
- **原生体验**：系统表格虚拟化、原生滚动条、可拖拽列宽和系统选择行为。

## 功能

### 快速扫描

扫描以下应用目录，并自动去重符号链接：

- `/Applications`（含子目录）
- `~/Applications`
- `/System/Applications`
- `/System/Library/CoreServices`
- `/Library/Apple/System/Applications`

元数据直接读取 `Info.plist`；应用体积在后台测量，列表会先出现，体积随后补齐。

### 来源识别

| 来源 | 判断方式 |
| --- | --- |
| 系统应用 | 路径位于 `/System/`、`/System/Cryptexes/` 或 `/Library/Apple/` |
| App Store | `Contents/_MASReceipt/receipt`，并用 Spotlight 的 `kMDItemAppStoreAdamID` 兜底 |
| App Store · iOS | `Wrapper/*.app`、`WrappedBundle`、`iTunesMetadata.plist`，以及 `DTPlatformName` / `LSRequiresIPhoneOS` 等标记 |
| Homebrew | `/opt/homebrew/Caskroom`、`/usr/local/Caskroom` 的符号链接，以及 Cask 应用名索引 |
| Steam | `Contents/MacOS/run.sh` 中包含 `steam://run/<AppID>`，或真实游戏位于 Steam 库的 `steamapps/common` 下 |
| JetBrains Toolbox | 读取 `~/Library/Application Support/JetBrains/Toolbox/state.json` 中的 `tools[].installLocation` |
| 手动安装 | 以上规则都不匹配 |

系统应用优先级最高，因此 Apple 自带应用即使带 App Store 收据也会被标为「系统应用」。从 App Store 安装的 Xcode、Apple Configurator 等工具会正确显示为 App Store。

Steam 和 JetBrains Toolbox 使用它们自己生成的元数据/路径进行判断，而不是猜测应用名称，因此不会把直接安装的同名应用混为一谈。

### 开发者的应用

在设置中配置个人应用的 Bundle ID 前缀，默认是 `me.whynbnb.`。

- 匹配的应用会出现在侧边栏的「开发者的应用」分类中
- 匹配数量大于 2 时才显示该分类
- 不会覆盖真实的安装来源，来源徽章和快照数据仍然保持准确

### 平台与类型

直接读取主可执行文件的 Mach-O 头，不调用 `lipo` 子进程：

- `arm64`（Apple 芯片）
- `x86_64`（Intel）
- 通用二进制（arm64 + x86_64）
- iOS 应用
- 未知（脚本类或缺少常规可执行文件）

同时记录 Bundle ID、版本、构建号、最低系统版本、安装时间、更新时间、实际占用空间、可执行文件路径和来源。

### 快照与对比

- 一键把当前应用清单保存为历史快照
- 快照包含体积、安装/更新时间、Bundle ID、版本、架构、来源和 **PNG 图标**
- 每个快照单独存为一个 JSON 文件，重命名或写备注不会重写所有历史快照
- 支持导入、导出单个或一组快照
- 比较两个快照，列出新增、移除、更新，并显示字段级变化
- 可以把「当前状态」作为比较的一方
- 导出 Markdown 对比报告

### 展示框

「展示框」用图标网格浏览软件收藏：

- 已安装应用来自实时扫描
- **已卸载应用**来自历史快照；即使应用已经被删除，仍会继续展示快照中的图标和最后已知元数据
- 支持按已安装/已卸载、来源、平台、系统/第三方筛选

## 性能说明

- **体积缓存**：`~/Library/Application Support/Custocub/size-cache.json`
  - 应用更新时间或安装时间变化时自动失效
  - 缓存最长保留 7 天
  - 未变化的应用不会在每次扫描时重新遍历文件
  - 设置 → 数据 → **清除体积缓存并重算** 可强制重新测量
- **异步图标**：图标在后台加载，扫描完成后会预取
- **批量更新体积**：不会每完成一个应用就刷新整张表
- **原生 SwiftUI Table**：由 NSTableView 提供虚拟化、系统滚动条和可拖拽列宽
- **切换来源时重建表格**：避免对数百行执行删除动画，保持界面响应

首次体积扫描需要遍历应用包，可能较慢；之后的扫描会复用缓存。元数据扫描本身很快。

## 构建

仓库中已经包含生成好的 Xcode 工程：

```bash
open Custocub.xcodeproj
```

选择 `Custocub` scheme 运行。

命令行构建：

```bash
xcodebuild -project Custocub.xcodeproj \
  -scheme Custocub \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

修改 `project.yml` 后重新生成工程：

```bash
xcodegen generate
```

工程设置：

- Marketing Version：`1.0`
- Bundle Identifier：`me.whynbnb.Custocub`

## 数据位置

快照：

```text
~/Library/Application Support/Custocub/Snapshots/<UUID>.json
```

体积缓存：

```text
~/Library/Application Support/Custocub/size-cache.json
```

Custocub 未启用 App Sandbox，只读取应用目录并写入自己的 Application Support 数据，不发送任何网络请求。

## 快捷键

| 快捷键 | 操作 |
| --- | --- |
| `⌘R` | 重新扫描应用 |
| `⌘S` | 保存当前快照 |
| `⇧⌘O` | 导入快照 |
| `⇧⌘E` | 导出当前快照 |
| `⌘,` | 打开设置 |

## 工程结构

```text
Custocub/
├─ App/
│  ├─ CustocubApp.swift          # App 入口与菜单命令
│  └─ CustocubStore.swift        # 扫描、快照、展示框和选择状态
├─ Models/
│  ├─ AppSource.swift            # 来源与平台枚举
│  ├─ AppRecord.swift            # 应用记录
│  ├─ AppSnapshot.swift          # 快照模型
│  ├─ AppChange.swift            # 快照对比与 Markdown 报告
│  └─ GalleryItem.swift          # 展示框条目
├─ Services/
│  ├─ AppScanner.swift           # 目录发现、Info.plist、来源识别
│  ├─ HomebrewIndex.swift        # Caskroom 索引
│  ├─ SteamDetector.swift        # Steam 快捷方式与库识别
│  ├─ JetBrainsToolboxIndex.swift # Toolbox 安装路径索引
│  ├─ MachOReader.swift          # Mach-O 架构解析
│  ├─ DirectorySize.swift        # 应用体积
│  ├─ SizeCache.swift            # 持久化体积缓存
│  ├─ IconProvider.swift         # 图标加载、预取与快照 PNG
│  └─ SnapshotRepository.swift   # 快照持久化
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

## 许可证

Custocub 以 [MIT License](LICENSE) 开源发布。

Copyright © 2026 0x574859。

