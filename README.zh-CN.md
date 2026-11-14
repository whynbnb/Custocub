# Custocub

[English](README.md) · [简体中文](README.zh-CN.md)

> Vibe Coding而成（DeepSeek V4.1 Flash / OpenCode）

**Custocub = custos（拉丁语：守护、看守）+ cubby（收纳格）。**

Custocub 是一个用 Swift 6 / SwiftUI 编写的原生 macOS 应用清单与快照管理器。它把 Mac 上的应用收进一个清晰的清单里，说明每个应用从哪里来、运行在什么架构上、是系统还是第三方应用，并支持历史快照与快照对比。

- **版本：** 1.0
- **Bundle ID：** `me.whynbnb.Custocub`
- **平台：** macOS 15+
- **界面语言：** 英文 / 简体中文（默认跟随系统）
- **许可证：** MIT

## 核心亮点

- **快速扫描**：元数据通常在 1 秒左右完成，应用体积在后台计算。
- **准确的来源识别**：系统、App Store、App Store · iOS、Homebrew、Steam、JetBrains Toolbox、手动安装。
- **平台与类型**：系统 / 第三方，以及 `arm64` / `x86_64` / 通用二进制检测。
- **开发者的应用**：使用固定前缀 `me.whynbnb.` 自动归类，可开关显示，匹配数量大于 2 时出现。
- **快照与对比**：保存历史清单、比较变化、导入导出、生成 Markdown 报告。
- **Homebrew 深度支持**：独立的 Homebrew 管理界面、Formula / Cask 列表、独立 Homebrew 快照、Brewfile 导出和实时命令日志。
- **展示框**：浏览已安装应用，也展示历史快照中已经卸载的应用。
- **原生体验**：系统表格虚拟化、原生滚动条、可拖拽列宽和系统选择行为。
- **中英文界面**：默认跟随系统语言，也可以在设置中手动切换（需重新启动）。
- **浅色 / 深色外观**：默认跟随系统，也可以手动选择浅色或深色。

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

开发者的应用使用固定的 Bundle ID 前缀 `me.whynbnb.`。

- 设置中的「显示开发者的应用」开关控制该分类，默认打开
- 「开发者的应用」位于「来源」区域，与 Homebrew、Steam 等来源并列
- 匹配数量大于 2 时才显示
- 统计时真实来源优先：Homebrew、App Store、Steam 等保留自己的应用；只有仍属于「手动安装」的开发者的应用会计入该行，避免来源总数重复
- 点击「开发者的应用」筛选时，仍会显示所有匹配该 Bundle ID 前缀的应用，包括来自其他来源的应用
- 不会覆盖真实的安装来源，来源徽章和快照数据仍然保持准确

### 管理工具节点（Steam 与 JetBrains Toolbox）

Steam 客户端和 JetBrains Toolbox 客户端会作为管理工具加入各自的来源分类：

- Steam 应用出现在 **Steam** 分类中，JetBrains Toolbox 应用出现在 **JetBrains Toolbox** 分类中
- 它们带有「管理工具」标记，且不会在该分类中重复计数
- 它们仍按真实来源（如手动安装、Homebrew）计数，因此来源总数不变，并且仍然相加相等

### Homebrew 支持

侧边栏提供独立的 **Homebrew** 界面，与应用清单分开。

**包列表**

- 通过一次 `brew info --json=v2 --installed` 读取全部已安装包
- 区分 **Formula**（命令行包）与 **Cask**（图形界面包）
- 显示已安装版本、最新版本、Tap、安装时间、运行时依赖，以及 `outdated`、`pinned`、`auto_updates` 状态
- 支持按类型、可更新、已固定筛选，也可以搜索包名、描述和版本

**两种不同性质的快照**

| 快照 | 记录内容 | 用途 |
| --- | --- | --- |
| 应用快照 | GUI 应用 + 当时的 Homebrew **Cask** 列表 | 重建 GUI 应用集合；Cask 页可以导出后直接安装 |
| Homebrew 快照 | Homebrew **Formula + Cask** 列表 | 完整的包管理器备份，与应用清单互相独立 |

应用快照现在会额外保存 `casks` 数组。快照界面中新增 **Homebrew Cask** 页，可以复制安装命令、复制 Brewfile，或导出 Brewfile / 安装脚本。旧快照没有该字段时仍然可以正常读取，只是 Cask 列表为空。

Homebrew 快照单独存放：

```text
~/Library/Application Support/Custocub/BrewSnapshots/<UUID>.json
```

**日常命令**

安装、卸载、升级、全部升级、重新安装、固定和取消固定都可以从工具栏、表格右键菜单和包详情面板执行。

「维护」菜单还提供更新索引、清理缓存与旧版本、移除不再需要的依赖、检查环境、查看配置和查看可更新的包。

**命令日志**

Custocub 执行的每条命令都会实时写入日志：

- 以 `$` 开头的完整命令行
- 按行聚合的 stdout / stderr 实时输出
- 成功或失败的结果，附带退出码和耗时
- Homebrew 界面底部可折叠的日志面板，以及带历史记录的独立日志窗口
- 可以停止正在执行的命令：先发送 `SIGINT`，如果 Homebrew 未退出再依次发送 `SIGTERM` / `SIGKILL`

**导出**

- 把当前已安装包导出为 `Brewfile`，可直接交给 `brew bundle`
- 可以只导出 Formula 或只导出 Cask，分别备份两部分
- 把任意 Homebrew 快照导出为 `Brewfile`、仅 Formula / 仅 Cask 的 `Brewfile`，或可直接执行的安装脚本
- 复制单个包的 `brew install …` 命令

Custocub 始终使用真实的 `brew` 可执行文件，因此会沿用你的安装前缀、Tap 和 Homebrew 配置。

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

### 重新生成应用图标

图标完全由代码绘制。重新生成全部 macOS 尺寸：

```bash
swift Tools/GenerateAppIcon.swift
```

脚本会把完整的 AppIcon PNG 写入 `Custocub/Resources/Assets.xcassets/AppIcon.appiconset`。

工程设置：

- Marketing Version：`1.0`
- Bundle Identifier：`me.whynbnb.Custocub`

## 数据位置

快照：

```text
~/Library/Application Support/Custocub/Snapshots/<UUID>.json
```

Homebrew 快照：

```text
~/Library/Application Support/Custocub/BrewSnapshots/<UUID>.json
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
| `⇧⌘B` | 打开 Homebrew 界面 |
| `⇧⌘S` | 保存 Homebrew 快照 |
| `⌘,` | 打开设置 |

## 工程结构

```text
Custocub/
├─ App/
│  ├─ CustocubApp.swift          # App 入口与菜单命令
│  ├─ CustocubStore.swift        # 扫描、快照、展示框和选择状态
│  └─ BrewStore.swift            # Homebrew 清单、快照与命令日志
├─ Models/
│  ├─ AppSource.swift            # 来源与平台枚举
│  ├─ AppRecord.swift            # 应用记录
│  ├─ AppSnapshot.swift          # 快照模型
│  ├─ AppChange.swift            # 快照对比与 Markdown 报告
│  ├─ GalleryItem.swift          # 展示框条目
│  ├─ BrewPackage.swift          # Homebrew 包记录与 Cask 快照条目
│  └─ BrewSnapshot.swift         # Homebrew 快照模型与 Brewfile 生成
├─ Services/
│  ├─ AppScanner.swift           # 目录发现、Info.plist、来源识别
│  ├─ HomebrewIndex.swift        # Caskroom 索引
│  ├─ SteamDetector.swift        # Steam 快捷方式与库识别
│  ├─ JetBrainsToolboxIndex.swift # Toolbox 安装路径索引
│  ├─ MachOReader.swift          # Mach-O 架构解析
│  ├─ DirectorySize.swift        # 应用体积
│  ├─ SizeCache.swift            # 持久化体积缓存
│  ├─ IconProvider.swift         # 图标加载、预取与快照 PNG
│  ├─ SnapshotRepository.swift   # 快照持久化
│  ├─ BrewService.swift          # brew 定位、流式执行与 JSON 清单
│  └─ BrewSnapshotRepository.swift # Homebrew 快照持久化
├─ Views/
│  ├─ ContentView.swift
│  ├─ SidebarView.swift
│  ├─ AppListView.swift
│  ├─ GalleryView.swift
│  ├─ AppDetailView.swift
│  ├─ ComparisonView.swift
│  ├─ SettingsView.swift
│  ├─ HomebrewView.swift         # Homebrew 包列表、筛选与安装
│  ├─ BrewSnapshotListView.swift # Homebrew 快照与 Brewfile 导出
│  ├─ BrewPackageDetailView.swift # Formula / Cask 详情与命令
│  ├─ BrewConsoleView.swift      # 实时命令日志与历史
│  ├─ Components.swift
│  └─ FileActions.swift
└─ Resources/Assets.xcassets
```

## 许可证

Custocub 以 [MIT License](LICENSE) 开源发布。

Copyright © 2026 0x574859。

## 鸣谢

感谢各大模型公司，感谢 DeepSeek，感谢各种公益站。没有 token，我就没办法做大量测试并做出这个软件（虽然还是拖延了几个月）。

最后，也感谢 macOS 上最好用的包管理器 Homebrew。


