# Custocub

[English](README.md) · [简体中文](README.zh-CN.md)

> Vibe Coding而成（DeepSeek V4.1 Flash / OpenCode）

**Custocub = custos（拉丁语：守护、看守）+ cubby（收纳格）。**

Custocub 是一个用 Swift 6 / SwiftUI 编写的原生 macOS 应用清单与快照管理器。它把 Mac 上的应用收进一个清晰的清单里，说明每个应用从哪里来、运行在什么架构上、是系统还是第三方应用，并支持历史快照与快照对比。

- **版本：** 1.2
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
- **清单报告**：从「更多 → 导出报告」把当前扫描或选中的快照导出为独立 HTML、分页 PDF 或 CSV 表格。
- **Homebrew 深度支持**：独立的 Homebrew 管理界面、Formula / Cask 列表、升级中心、SOCKS5 / HTTP 代理、独立 Homebrew 快照、Brewfile 导出和实时命令日志。
- **探索完整仓库**：按近 30 天真实下载量浏览全部可安装的 Formula 与 Cask（可切换到 90 / 365 天），支持按包名、别名和描述搜索。
- **展示框**：浏览已安装应用，也展示历史快照中已经卸载的应用。
- **原生体验**：系统表格虚拟化、原生滚动条、可拖拽列宽和系统选择行为。
- **布局记忆**：侧边栏宽度与窗口宽度分别记住，「应用清单」和「Homebrew」各有一套；应用详情面板默认收起，展开后按上次的宽度显示。
- **中英文界面**：默认跟随系统语言，也可以在设置中手动切换，切换后立即生效，无需重新启动。
- **浅色 / 深色外观**：默认跟随系统，也可以手动选择浅色或深色，立即生效。

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

**版本要求**

Custocub 的 Homebrew 功能需要 **Homebrew 7.0 或更高版本**。

- 启动时用 `brew --version` 读取一次版本，界面立即知道功能是否可用
- 版本过低时，Homebrew 界面会显示专门的「Homebrew 版本过低」状态，包含当前版本、所需版本、可复制的 `brew update && brew upgrade` 命令，以及「重新检测版本」按钮
- 与 Homebrew 无关的功能（应用扫描、来源、快照、展示框）完全不受影响
- 升级 Homebrew 后，`brew update` 会自动重新检测版本并解除限制，不需要重启

**整体开关**

- Homebrew 支持**默认开启**，只有检测到本机存在 `brew` 可执行文件时才会真正生效
- 如果没有安装 Homebrew，则完全不显示也不执行任何操作：侧边栏不出现 Homebrew 入口，也不会派生 `brew` 进程
- 开关只影响 Homebrew **管理界面**，原有功能完全不受影响：
  - 应用清单中的 Homebrew 应用仍归类为 **Homebrew 来源**
  - 来源统计、系统 / 第三方划分、平台识别、展示框、体积缓存、快照行为都与之前一致
  - 应用快照照常保存，只是关闭时会跳过可选的 Cask 列表
- 关闭开关后侧边栏的 Homebrew 入口会完全消失：不执行任何 `brew` 命令、不读取包列表、也无法进入 Homebrew 界面。快照文件仍保留在磁盘上，不会被删除
- 重新开启会自动重新读取包列表

**包列表**

- 通过一次 `brew info --json=v2 --installed` 读取全部已安装包
- 区分 **Formula**（命令行包）与 **Cask**（图形界面包）
- 显示已安装版本、最新版本、Tap、安装时间、运行时依赖，以及 `outdated`、`pinned`、`auto_updates` 状态
- 支持按类型、可更新、已固定筛选，也可以搜索包名、描述和版本
- 包详情面板的命令行把操作按钮放在最前面（安装、升级、重新安装、卸载），后面是命令文本与复制按钮；卸载按钮为红色
- 包详情面板用可点击的小胶囊列出**直接依赖**与**反向依赖**，点击即可跳转到对应包的详情，左侧包列表会滚动到对应行并高亮，可以在相互依赖的包之间来回切换

**两种不同性质的快照**

| 快照 | 记录内容 | 用途 |
| --- | --- | --- |
| 应用快照 | GUI 应用 + 当时的 Homebrew **Cask** 列表 | 重建 GUI 应用集合；Cask 页可以导出后直接安装 |
| Homebrew 快照 | Homebrew **Formula + Cask** 列表 | 完整的包管理器备份，与应用清单互相独立 |

应用快照现在会额外保存 `casks` 数组。快照界面中新增 **Homebrew Cask** 页，可以复制安装命令、复制 Brewfile，或导出 Brewfile / 安装脚本。旧快照没有该字段时仍然可以正常读取，只是 Cask 列表为空。

**探索完整仓库**

「探索」分区和「包」的区别：「包」只列出这台 Mac 上已安装的包，「探索」列出 Homebrew 仓库里**全部**的 Formula 与 Cask，装没装都可以看到。

- 目录来源：`formulae.brew.sh` 官方的 `formula.json` 与 `cask.json`，和 Homebrew 自己使用的文件一致
- 下载量来源：`analytics/install/{30,90,365}d.json` 与 `analytics/cask-install/{30,90,365}d.json`，也就是 `brew formula-analytics` 背后的同一份匿名统计
- **默认显示近 30 天下载量最大的包**，可以在近 30 / 90 / 365 天之间调整统计范围，也可以调整显示条数（前 50 / 100 / 200 / 500 / 全部）
- 搜索覆盖包名、显示名、别名、描述、Tap 与版本；搜索时不受条数限制，匹配项全部列出
- 可按下载量或名称排序，按 Formula / Cask 筛选，也可以选择是否显示已弃用、已停用的包
- `#排名` 列显示该包在自己分类中的名次，占比列显示它在对应统计范围内的下载量占比
- 已安装的包会带「已安装」徽章，详情面板里同时显示已安装版本
- **先搜索再安装**：结果行直接带「安装」按钮，详情面板也可以安装；没有匹配项时可以直接用输入的名称执行 `brew install`
- 头部的「可更新」数量可以直接点击，跳转到「升级」分区
- 目录缓存在本地：目录 1 天过期，下载量 1 小时过期；命中缓存后打开探索不会发起任何网络请求

Homebrew 的全局工具栏在每个分区都完全一致。**Brewfile 导出**放在「包」分区的筛选栏里，**快照对比**放在「快照」分区的标题栏里，切换分区时工具栏不会变化。

**网络代理**

- Homebrew 设置页可以让 Homebrew 的 `curl` 请求与「探索」目录下载走 **SOCKS5** 或 **HTTP** 代理。填写主机和端口后，可以用「测试连接」验证到 `formulae.brew.sh` 的连通性
- Git 有自己的代理优先级：`git config` 里的 `http.proxy` 会覆盖 `http_proxy` / `all_proxy` 环境变量。因此 `brew update` 的 `git fetch` 默认使用 Git 配置的代理，而不是应用里的代理
- **接管 Git 代理配置（仅 brew 子进程）** 默认关闭。开启后，Custocub 会向 brew 子进程注入命令级 `http.proxy` / `https.proxy`（包括按 URL 单独设置的 `http.<url>.proxy`），让 `brew update` 也走应用代理；不会写入 Git 全局配置
- SOCKS5 使用远程 DNS（`socks5h`），域名由代理解析，不依赖本机 DNS
- 它只影响 Custocub 启动的进程，不会修改系统、Git 或 Homebrew 的配置文件
- 同一页还会**只读**显示 `git config --global` 中的代理配置，方便确认 Git 实际使用的代理，但无法在应用内修改

Homebrew 快照单独存放：

```text
~/Library/Application Support/Custocub/BrewSnapshots/<UUID>.json
```

**日常命令**

新包的安装集中在**探索**：先搜索，再在结果行上点「安装」，或在详情面板安装。

**升级**是独立分区：列出所有可更新的 Formula 与 Cask，显示已安装与最新版本，支持逐行升级、升级所选和**升级全部**，也可以点「检查更新」执行 `brew update`。工具栏不再保留升级按钮。

**升级策略**

Custocub 不会默默继承 shell 里恰好导出的 `HOMEBREW_*` 环境变量，而是给每次 brew 调用显式指定策略。可以在升级分区顶部切换，也可以在**设置 → Homebrew → 升级**里切换：

| 策略 | Cask 范围 |
| --- | --- |
| **标准** | Homebrew 自身默认行为：Formula，加上应用 bundle 版本落后于 tap 版本的自动更新 Cask；`:latest` 仍然跳过 |
| **非贪婪** | 自动更新与 `:latest` 的 Cask 完全跳过，只升级普通包 |
| **贪婪** | 一并升级自动更新与 `:latest` 的 Cask |

策略会同时作用于三处，保证列表和实际命令一致：

- `brew info --json=v2 --installed` 与 `brew outdated` 对同一批包判定为可更新，驱动「可更新」数量与升级列表
- `brew upgrade` 只在贪婪模式追加 `--greedy`
- 复制的升级命令、包详情里展示的可复制命令带同样的参数

切换策略后会立刻重新读取清单，数量和列表都不用重启或重新执行 `brew update`。

本机的差异很直观：114 个已安装 Cask 中，标准策略报告 5 个可更新，非贪婪只报告 2 个，因为其中 3 个是 `auto_updates` 且会被 Homebrew 默认接管。

卸载、重新安装、固定和取消固定仍然在包列表右键菜单和包详情面板里。

「维护」菜单还提供更新索引、清理缓存与旧版本、移除不再需要的依赖、检查环境、查看配置和查看可更新的包。

**命令日志**

Custocub 执行的每条命令都会实时写入日志：

- 以 `$` 开头的完整命令行
- 按行聚合的 stdout / stderr 实时输出
- 成功或失败的结果，附带退出码和耗时
- Homebrew 界面底部可折叠的日志面板，以及带历史记录的独立日志窗口
- 可以停止正在执行的命令：先发送 `SIGINT`，如果 Homebrew 未退出再依次发送 `SIGTERM` / `SIGKILL`

**后台服务**

新增独立的 **服务** 标签页，管理带有 `service` 定义的 Formula（postgresql、redis、nginx 等）。通过 `brew services info --all --json` 读取真实状态，而不是靠猜测：

| 字段 | 含义 |
| --- | --- |
| `status` | `started` / `stopped` / `scheduled` / `none` / `error` / `unknown` / `other` |
| `running` | 当前进程是否存活（有 PID） |
| `registered` | 是否已注册为登录（或开机）自动启动 |
| `schedulable` | 是否为定时任务（`interval` / `cron`） |

操作与 Homebrew 子命令一一对应：

| 操作 | 命令 | 效果 |
| --- | --- | --- |
| 启动 | `brew services start <name>` | 立即启动并注册自动启动 |
| 启动全部 | `brew services start --all` | 启动所有已注册服务 |
| 停止 | `brew services stop <name>` | 停止并取消自动启动 |
| 停止全部 | `brew services stop --all` | 停止并取消全部注册 |
| 重启 | `brew services restart <name>` | 必要时先停止再启动 |
| 运行一次 | `brew services run <name>` | 仅运行，不注册自动启动 |
| 立即停止 | `brew services kill <name>` | 立即结束但保留注册 |
| 停止但保留自动启动 | `brew services stop --keep <name>` | 停止但不取消注册 |
| 清理无用服务 | `brew services cleanup` | 移除失效的服务文件 |

列表会把运行中 / 已注册的服务排在前面，并标记定时任务；详情面板显示启动命令、PID、退出码、运行用户、工作目录、服务文件与日志路径，并提供「打开日志」按钮。

**配置与诊断**

单独的 **配置与诊断** 标签页整合了两项只读检查：

- `brew config` — 按分组解析展示（版本、Tap、路径、工具链、系统、环境变量），支持筛选，并保留原始输出与复制按钮
- `brew doctor` — 通过 `--json` 获取结构化结果（旧版 Homebrew 自动回退到文本解析）。按错误 / 警告 / 提示分级展示，附受影响的包、修复说明、可复制的修复命令和链接，同样可以查看原始输出

诊断过程不会修改任何内容，只做报告。

**清理**

新增独立的 **清理** 页，先分析再执行 Homebrew 的真实清理命令。分析阶段只用只读命令（`-n` 试运行 + 目录统计），在你点击执行前不会改动任何文件。

| 操作 | 命令 | 作用 |
| --- | --- | --- |
| 标准清理 | `brew cleanup` | 移除过期下载、旧版本、残留锁文件与日志，并自动移除无用依赖 |
| 移除无用依赖 | `brew autoremove` | 卸载「只作为依赖安装、且已不再被需要」的 formula |
| 清理全部缓存 | `brew cleanup --prune=all` | 删除全部下载缓存（含最新版本），保留已安装的包 |
| 清空下载缓存 | `brew cleanup --prune=all --scrub` | 连 Ruby 缓存与临时文件一并清理 |
| 修复安装前缀链接 | `brew cleanup --prune-prefix` | 只清理失效的符号链接和空目录 |

界面会分别给出标准清理与深度清理预计可释放的空间、按目录拆分的缓存占用（`downloads`、`api`、`bootsnap`）、旧版本、无用依赖，以及 `brew missing` 健康检查。破坏性操作执行前会二次确认。

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

### 清单报告

在工具栏的 **更多 → 导出报告** 中，可以把应用清单分享或归档：

- **HTML**：单个自包含文件，包含统计卡片、来源明细和适合打印的表格；即使 macOS 设置为自动隐藏滚动条，页面也会始终显示滚动条
- **PDF**：A4 分页报告，包含同样的统计和表格，适合打印或长期归档
- **CSV**：带 BOM 的 UTF-8 表格，可直接用表格软件打开，包含 Bundle ID、构建号、架构、原始字节大小、更新时间和安装路径

侧边栏选中历史快照时，报告描述该快照；否则导出当前扫描结果。

### 展示框

「展示框」用图标网格浏览软件收藏：

- 已安装应用来自实时扫描
- **已卸载应用**来自历史快照；即使应用已经被删除，仍会继续展示快照中的图标和最后已知元数据
- 支持按已安装/已卸载、来源、平台、系统/第三方筛选

侧边栏另外提供三个快照对比入口：

- **新安装**：最近一次快照之后新安装的应用
- **已更新**：版本与最近一次快照不同的应用
- **已卸载**：最近一次快照里记录过、但当前没有安装的应用

这些视图都以最近保存的快照为基准；还没有快照时，页面会提示先保存一个快照。

## 性能说明

- **体积缓存**：`~/Library/Application Support/Custocub/size-cache.json`
  - 应用更新时间或安装时间变化时自动失效
  - 缓存最长保留 7 天
  - 未变化的应用不会在每次扫描时重新遍历文件
  - 设置 → 数据 → **清除体积缓存并重算** 可强制重新测量
- **异步图标**：图标在后台加载，扫描完成后会预取
- **按住 ⌥ 点击「扫描应用」** 触发全量刷新：按钮会变成橙色，重新生成所有图标、重新测量所有应用体积，不经过缓存
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

- Marketing Version：`1.2`
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
│  ├─ BrewVersion.swift          # 版本号解析与最低版本限制
│  ├─ BrewCatalog.swift          # 探索目录条目、下载量统计与筛选条件
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
│  ├─ BrewSnapshotRepository.swift # Homebrew 快照持久化
│  ├─ BrewCleanupService.swift   # 清理分析：缓存、旧版本、无用依赖
│  ├─ BrewHealthService.swift    # brew config / doctor 解析
│  ├─ BrewServicesService.swift  # brew services 解析
│  └─ BrewCatalogService.swift   # 探索目录下载、缓存与解析
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
│  ├─ BrewCleanupView.swift      # 清理分析与操作
│  ├─ BrewHealthView.swift       # 配置与诊断
│  ├─ BrewServicesView.swift     # 后台服务管理
│  ├─ BrewExploreView.swift      # 全量目录浏览与搜索
│  ├─ BrewUpgradeView.swift      # 可升级列表、逐行与批量升级
│  ├─ BrewCatalogDetailView.swift # 目录条目详情面板
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


