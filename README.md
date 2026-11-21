# Custocub

[English](README.md) · [简体中文](README.zh-CN.md)

> Vibe coded with DeepSeek V4.1 Flash / OpenCode.

**Custocub = custos (Latin: guardian, keeper) + cubby (a small storage compartment).**

Custocub is a native macOS app inventory and snapshot manager built with Swift 6 and SwiftUI. It gives you a clear view of every app on your Mac: where it came from, which architecture it runs on, whether it is a system or third-party app, and what changed over time.

- **Version:** 1.2
- **Bundle ID:** `me.whynbnb.Custocub`
- **Platform:** macOS 15+
- **UI language:** English / Simplified Chinese (follows the system by default)
- **License:** MIT

## Highlights

- **Fast metadata scan** — usually around one second; app sizes are calculated in the background.
- **Accurate source detection** — System, App Store, App Store · iOS, Homebrew, Steam, JetBrains Toolbox, and manual installs.
- **Clear app types** — system vs. third-party, with `arm64` / `x86_64` / universal architecture detection.
- **Developer apps smart group** — fixed `me.whynbnb.` Bundle ID prefix, with a show/hide toggle; shown only when more than two apps match.
- **Snapshots and comparison** — keep historical inventories, compare changes, export or import snapshots, and generate Markdown reports.
- **Inventory reports** — export the current scan or a selected snapshot as a self-contained HTML report, a paginated PDF, or a CSV spreadsheet from **More → Export Report**.
- **Snapshot icon history** — icons are captured with snapshots; the Gallery and detail pane only show snapshots where an app's icon actually changed.
- **Deep Homebrew support** — a dedicated Homebrew screen for formulae and casks, an upgrade center, SOCKS5/HTTP proxy support, standalone Homebrew snapshots, Brewfile export, and a live command log.
- **Explore the whole repository** — browse every available Formula and Cask ranked by real download counts from the last 30 days (switchable to 90 or 365), with full search across names, aliases, and descriptions.
- **Snapshot time machine** — scrub the Gallery back through saved snapshots to see exactly which apps, versions, and icons existed on that date.
- **App Story** — a per-app retrospective that combines first/last appearance, version timeline, source changes, and icon history from every saved snapshot.
- **Favorites and collections** — star apps or curate custom collections that can include both installed and uninstalled apps.
- **Gallery** — browse installed apps and apps that have been uninstalled but still exist in historical snapshots, with multi-select filters for status, source, platform, and type.
- **Native macOS experience** — native table virtualization, scrollbars, resizable columns, and system selection behavior.
- **Remembered layout** — the sidebar width and window width are remembered separately for the app inventory and the Homebrew screen. The app detail pane is collapsed by default, opens on demand, and remembers its width.
- **English and Chinese** — follows the system language by default, with a manual switch that applies instantly (no restart).
- **Light and dark appearance** — follows the system by default, with manual Light / Dark options that apply instantly.

## Features

### Fast app scanning

Custocub scans the standard application locations and de-duplicates symlinks:

- `/Applications` (including subdirectories)
- `~/Applications`
- `/System/Applications`
- `/System/Library/CoreServices`
- `/Library/Apple/System/Applications`

Metadata is parsed directly from `Info.plist`; app sizes are measured in the background so the list appears first and fills in sizes as they become available.

### Source detection

| Source | Detection rule |
| --- | --- |
| System | Path under `/System/`, `/System/Cryptexes/`, or `/Library/Apple/` |
| App Store | `Contents/_MASReceipt/receipt`, with Spotlight `kMDItemAppStoreAdamID` as a fallback |
| App Store · iOS | `Wrapper/*.app`, `WrappedBundle`, `iTunesMetadata.plist`, plus `DTPlatformName` / `LSRequiresIPhoneOS` markers |
| Homebrew | Symlinks into `/opt/homebrew/Caskroom` or `/usr/local/Caskroom`, plus a Cask app-name index |
| Steam | `Contents/MacOS/run.sh` containing `steam://run/<AppID>`, or a real game under a Steam library `steamapps/common` |
| JetBrains Toolbox | Paths listed in `~/Library/Application Support/JetBrains/Toolbox/state.json` under `tools[].installLocation` |
| Manual | Anything that does not match the rules above |

System apps take priority, so Apple's built-in apps remain classified as system even when they carry an App Store receipt. Apple tools installed from the App Store, such as Xcode or Apple Configurator, are correctly reported as App Store apps.

Steam and JetBrains Toolbox detection use their own generated metadata/paths rather than guessing from app names, so directly installed apps with the same name are not confused with managed installs.

### Developer apps

Developer apps are identified by the fixed Bundle ID prefix `me.whynbnb.`.

- A **Show Developer Apps** toggle in Settings controls the category; it is on by default.
- The **Developer Apps** row appears in the Sources section, next to Homebrew, Steam, and the other sources.
- The category is only shown when more than two apps match.
- Real sources take priority in the counts: Homebrew, the App Store, Steam, and others keep their apps. Only manually installed developer apps are counted in the Developer Apps row, so source totals are not double-counted.
- Selecting the Developer Apps filter still shows every app that matches the Bundle ID prefix, including apps from other sources.
- It does **not** overwrite the real installation source; source badges and snapshot data stay accurate.

### Manager nodes (Steam and JetBrains Toolbox)

The Steam client and the JetBrains Toolbox client are added to their own source categories as manager nodes:

- The Steam app appears in the **Steam** category, and the JetBrains Toolbox app appears in the **JetBrains Toolbox** category.
- They are marked with a **Manager** badge and are not counted again in that category.
- They remain counted under their real source, such as Manual Install or Homebrew, so source totals do not change and still add up.

### Homebrew integration

Custocub has a dedicated **Homebrew** screen in the sidebar, separate from the app inventory.

**Version requirement**

Custocub's Homebrew features require **Homebrew 7.0 or later**.

- The version is read once at launch with `brew --version`, so the UI knows immediately whether the features are usable.
- On an older Homebrew the Homebrew screen shows a dedicated **Homebrew Version Too Old** state with the current version, the required version, a copyable `brew update && brew upgrade` command, and a **Check version again** button.
- Everything unrelated to Homebrew (app scanning, sources, snapshots, gallery) keeps working normally.
- After upgrading Homebrew, `brew update` re-detects the version automatically and unlocks the features without a restart.

**Master switch**

- Homebrew support is **on by default** and only activates when a `brew` executable is detected on the machine.
- If Homebrew is not installed, nothing is shown or run: the Homebrew sidebar entry is hidden and no `brew` process is spawned.
- The switch only controls the Homebrew **management** screen. Everything that already existed is untouched:
  - Homebrew apps stay classified as the **Homebrew source** in the app inventory.
  - Source counts, system/third-party split, platform detection, gallery, size cache, and snapshots all behave exactly as before.
  - App snapshots keep saving normally; they simply skip the optional cask list when the switch is off.
- When the switch is off, the Homebrew entry disappears from the sidebar entirely: no `brew` command runs, the package list is not read, and the Homebrew screens are not reachable. Saved snapshot files stay on disk, so nothing is deleted.
- Turning it back on reloads the package list automatically.

**Package list**

- Reads the installed inventory with a single `brew info --json=v2 --installed` call.
- Separates **Formula** (command-line packages) from **Cask** (GUI app packages).
- Shows installed and latest versions, tap, install time, dependencies, `outdated`, `pinned`, and `auto_updates` state.
- Filter by kind, outdated, or pinned; search by name, description, or version.
- In the package detail panel, every command row puts its action button first (install, upgrade, reinstall, uninstall), followed by the command text and a copy button. Uninstall is shown in red.
- The detail panel lists both **direct dependencies** and **reverse dependencies** as small clickable chips. Selecting one jumps to its detail, scrolls the package list to the matching row, and highlights it, so you can move back and forth between connected packages.

**Two different kinds of snapshots**

| Snapshot | Records | Purpose |
| --- | --- | --- |
| App snapshot | GUI apps + the Homebrew **cask** list at that moment | Rebuild the GUI app set; the cask tab can be exported and installed directly |
| Homebrew snapshot | Homebrew **formula + cask** list | Full package-manager backup, independent of the GUI inventory |

An app snapshot now carries a `casks` array. The snapshot screen has an extra **Homebrew Cask** tab where you can copy the install command, copy the Brewfile, or export a Brewfile or install script. Older snapshots without the field still load; the cask list is simply empty.

**Explore the full catalog**

The **Explore** tab is different from **Packages**: Packages lists what is installed on this Mac, while Explore lists **every** Formula and Cask in the Homebrew repository, whether or not it is installed.

- Catalog source: the official `formula.json` and `cask.json` from `formulae.brew.sh` — the same files Homebrew itself uses.
- Download counts: `analytics/install/{30,90,365}d.json` and `analytics/cask-install/{30,90,365}d.json`, the same anonymous statistics behind `brew formula-analytics`.
- **By default it shows the most downloaded packages in the last 30 days.** Switch the range between 30, 90, and 365 days, and adjust how many packages are listed (50 / 100 / 200 / 500 / all).
- Search covers names, display names, aliases, descriptions, taps, and versions. While searching, every match is shown regardless of the list limit.
- Sort by downloads or by name; filter by Formula/Cask; optionally hide deprecated or disabled packages.
- The `#rank` column shows the package's position in its own category, and the share column shows its percentage of all downloads in the range.
- Already-installed packages are badged, and their installed version appears in the detail panel.
- **Search, then install**: every row has an Install button; the detail panel also installs. If nothing matches, the empty state offers to run `brew install` with the typed name.
- The header's outdated count is clickable and jumps straight to the **Upgrade** tab.
- The catalog is cached locally: the catalog expires after 1 day and download counts after 1 hour. Once cached, opening Explore costs no network request.

The global Homebrew toolbar is identical on every tab. **Brewfile export** lives in the Packages tab filter bar, and **snapshot comparison** lives in the Snapshots tab header, so switching tabs never changes the toolbar.

**Proxy**

- The Homebrew settings tab can route Homebrew's `curl` traffic and Explore catalog downloads through a **SOCKS5** or **HTTP** proxy. Enter the host and port, then use **Test Connection** to verify the path to `formulae.brew.sh`.
- Git has its own proxy priority: `http.proxy` in `git config` overrides the `http_proxy` / `all_proxy` environment variables. That means `brew update`'s `git fetch` normally uses the Git configuration rather than the app proxy.
- **Override Git Proxy for brew (Child Processes)** is off by default. When enabled, Custocub injects command-level `http.proxy` / `https.proxy` entries, including any URL-specific `http.<url>.proxy` keys, into brew's child processes, so `brew update` also uses the app proxy. It never writes to the global Git configuration.
- SOCKS5 uses remote DNS (`socks5h`), so hostnames are resolved through the proxy instead of relying on the local resolver.
- It only affects processes started by Custocub. System, Git, and Homebrew configuration files are left untouched.
- The same tab shows the proxy entries from `git config --global` **read-only**, so the effective Git configuration is visible without being editable.

Homebrew snapshots are stored separately:

```text
~/Library/Application Support/Custocub/BrewSnapshots/<UUID>.json
```

**Everyday commands**

New packages are installed from **Explore**: search, then press **Install** on a row (or in the detail panel).

**Upgrade** is a dedicated tab: it lists every outdated Formula and Cask with installed and latest versions, and offers per-row upgrade, selected upgrade, and **Upgrade All**. It also runs `brew update` via **Check for Updates**. The toolbar no longer carries an upgrade button.

**Upgrade policy**

Custocub does not silently inherit whatever `HOMEBREW_*` variables your shell happens to export. Each brew invocation gets an explicit policy, selectable from the Upgrade tab or **Settings → Homebrew → Upgrade**:

| Policy | Cask scope |
| --- | --- |
| **Standard** | Homebrew's own default: formulae plus auto-updating casks whose installed bundle is behind the tap version. `:latest` casks are still skipped. |
| **Non-greedy** | Explicitly skips auto-updating and `:latest` casks entirely; only regular formulae and versioned casks are upgraded. |
| **Greedy** | Also upgrades auto-updating and `:latest` casks. |

The policy is applied consistently in three places, so the list and the command always agree:

- `brew info --json=v2 --installed` and `brew outdated` mark the same packages as outdated, which drives the upgradable count and the Upgrade table.
- `brew upgrade` receives `--greedy` only in Greedy mode.
- Copied upgrade commands and the pasteable command shown in the package detail include the same flag.

Changing the policy reloads the inventory immediately, so the counts update without restarting or running `brew update`.

On this machine the difference is visible: with 114 casks installed, Standard reports 5 outdated casks and Non-greedy reports 2, because three of them are `auto_updates` casks that Homebrew would otherwise take over.

Uninstall, reinstall, pin, and unpin stay on the package table context menu and the package detail panel.

The **Maintenance** menu also offers index update, cache/old-version cleanup, autoremove, environment check, config, and outdated listing.

**Command log**

Every command Custocub runs is streamed into a live log:

- The command line itself, prefixed with `$`.
- Real-time stdout/stderr output, aggregated by line.
- A success or failure footer with the exit code and duration.
- A collapsible panel at the bottom of the Homebrew screen, plus a standalone log window with the recent command history.
- Running commands can be cancelled: `SIGINT` first, then `SIGTERM`/`SIGKILL` if Homebrew does not exit.

**Background services**

A dedicated **Services** tab manages formulae that ship a `service` definition (postgresql, redis, nginx, …). It reads `brew services info --all --json`, so it shows the real daemon state rather than a guess:

| Field | Meaning |
| --- | --- |
| `status` | `started` / `stopped` / `scheduled` / `none` / `error` / `unknown` / `other` |
| `running` | whether the process currently has a PID |
| `registered` | whether it is registered to start at login (or boot) |
| `schedulable` | whether it is a timed task (`interval` / `cron`) |

Actions map one-to-one to Homebrew's subcommands:

| Action | Command | Effect |
| --- | --- | --- |
| Start | `brew services start <name>` | Start now and register at login |
| Start All | `brew services start --all` | Start every registered service |
| Stop | `brew services stop <name>` | Stop and unregister |
| Stop All | `brew services stop --all` | Stop and unregister all |
| Restart | `brew services restart <name>` | Stop if needed, then start |
| Run once | `brew services run <name>` | Run without registering |
| Stop immediately | `brew services kill <name>` | Kill but keep registered |
| Stop, keep auto-start | `brew services stop --keep <name>` | Stop without unregistering |
| Clean unused | `brew services cleanup` | Remove stale service files |

The list groups running/registered services first, marks scheduled tasks, and the detail pane shows the launch command, PID, exit code, run-as user, working directory, service file, and log paths with an **Open log** button.

**Configuration & diagnostics**

A single **Configuration & Diagnostics** tab combines two read-only inspections:

- `brew config` — parsed into grouped sections (version, taps, paths, toolchain, system, environment) with a filter box, plus the raw output and a copy button.
- `brew doctor` — runs with `--json` to get structured findings (falls back to parsing plain text on older Homebrew). Findings are shown by severity (error / warning / note) with affected packages, remediation text, copyable fix commands, and links. A raw-output view is available too.

Diagnostics never modify anything; they only report.

**Cleanup**

A dedicated **Cleanup** tab analyzes and then runs Homebrew's real cleanup commands. Analysis uses read-only commands only (`-n` dry runs plus directory sizing), so nothing is changed until you press Run.

| Action | Command | What it does |
| --- | --- | --- |
| Standard cleanup | `brew cleanup` | Removes stale downloads, old kegs, stale lock files, logs, and autoremoves unneeded dependencies |
| Remove unneeded dependencies | `brew autoremove` | Uninstalls formulae installed only as dependencies that are no longer needed |
| Clean all caches | `brew cleanup --prune=all` | Deletes every download cache, including current versions; installed packages stay |
| Wipe download cache | `brew cleanup --prune=all --scrub` | Also clears the Ruby cache and temporary files |
| Repair prefix links | `brew cleanup --prune-prefix` | Removes only broken symlinks and empty directories |

The screen shows reclaimable size for both a standard and a deep cleanup, a per-directory cache breakdown (`downloads`, `api`, `bootsnap`), old kegs, unneeded dependencies, and a `brew missing` health check. Destructive actions ask for confirmation first.

**Exports**

- Export the current inventory as a `Brewfile` for `brew bundle`.
- Export formulae only or casks only when you want to back up each half separately.
- Export any Homebrew snapshot as a `Brewfile`, a formula-only or cask-only `Brewfile`, or a ready-to-run install script.
- Copy a single package's `brew install …` command.

Custocub always uses the real `brew` binary, so it respects your installed prefix, taps, and Homebrew configuration.

### Architecture and app type

Custocub reads the main executable's Mach-O header directly, without calling `lipo`:

- `arm64` (Apple silicon)
- `x86_64` (Intel)
- Universal (`arm64` + `x86_64`)
- iOS apps
- Unknown (scripts or apps without a regular executable)

Each record also includes Bundle ID, version, build number, minimum macOS version, install time, update time, allocated disk size, executable path, and source.

### Snapshots and comparison

- Save the current app inventory as a historical snapshot with one command.
- A snapshot contains size, install/update time, Bundle ID, version, architecture, source, and a **PNG icon**.
- Each snapshot is stored as its own JSON file; renaming or editing a note does not rewrite every snapshot.
- Import or export individual snapshots or a collection of snapshots.
- Compare two snapshots to see added, removed, and updated apps with field-level changes.
- When app snapshots contain Homebrew casks, the comparison view also has a **Homebrew Cask** tab for cask additions, removals, and version changes.
- Compare against the **Current State** without saving it first.
- Export a Markdown comparison report.

### Inventory reports

Use **More → Export Report** in the toolbar to share or archive the app inventory:

- **HTML** — a single self-contained file with summary cards, a source breakdown, and a print-friendly table. The page always shows a scrollbar, even when macOS is set to hide scrollbars.
- **PDF** — a paginated A4 report with the same summary and table, suitable for printing or long-term archiving.
- **CSV** — UTF-8 with BOM for spreadsheet apps, including Bundle ID, build, architecture, raw size in bytes, update time, and install path.

When a historical snapshot is selected in the sidebar, the report describes that snapshot. Otherwise it exports the current scan.

### SwiftLens integration

If [SwiftLens](https://github.com/whynbnb/SwiftLens) is installed (`me.whynbnb.SwiftLens`), the app context menu adds **Open with SwiftLens** for installed bundles. Custocub hands the `.app` to SwiftLens through LaunchServices' open-file mechanism, which also grants the sandboxed receiver access to the bundle.

SwiftLens needs to handle opened files (`application(_:open:)`) to load them in its window; its command-line summary mode is separate.

### Gallery

The Gallery is an icon-grid view of your software collection:

- Installed apps come from the latest live scan.
- **Uninstalled apps** come from historical snapshots. Even after the app bundle is deleted, Custocub can keep showing its icon and last-known metadata.
- **Snapshot timeline** at the top: choose **Today** or any saved snapshot to view the collection as it existed at that moment. Apps installed later disappear, apps uninstalled later stay visible, and the header counts reflect that snapshot.
- Multi-select filters for installed/uninstalled status, source, platform, and system/third-party type.
- The summary chips at the top are also filters: click **Installed**, **Uninstalled**, **System**, or **Third-party** to toggle them.
- The toolbar shows how many apps are currently visible.

The sidebar also has two snapshot-comparison views:

- **New** — apps installed after the most recent snapshot.
- **Updated** — apps whose version differs from the most recent snapshot.
- **Uninstalled** — apps recorded in the most recent snapshot that are no longer installed.

These views compare against the latest saved snapshot; when no snapshot exists, they explain how to create one.

### Favorites and collections

- Star an app from its context menu or detail view to add it to **Favorites**.
- Create custom collections such as “Developer Tools” or “Must Have”, and add apps from any context menu.
- Collections can contain installed and uninstalled apps, and can be browsed with the same snapshot timeline and multi-select filters as the Gallery.
- Rename or delete collections from the sidebar context menu.

### App Story

From the app detail pane, the app table context menu, or a Gallery card, open **App Story** to see a retrospective built from saved snapshots:

- First and last appearance, plus how many snapshots contain the app
- Version timeline with source, build, size, and snapshot date
- Source changes over time
- The snapshot-based icon history timeline

### Icon history

Icon history is derived entirely from saved snapshots:

- Every snapshot stores each app's icon. Custocub compares consecutive snapshots and only lists the snapshots where the icon actually differs.
- Identical icons across several snapshots are collapsed into one entry. If an icon changes and later reverts, both changes appear.
- Click the clock badge on a Gallery card, or choose **View Icon History…** from its context menu, to see the full timeline.
- The app detail pane shows an **Icon History** strip and the snapshot where the icon last changed.

There is no separate scan-time icon log. If you want a richer icon history, save snapshots when apps update.

## Performance notes

- **Size cache** at `~/Library/Application Support/Custocub/size-cache.json`
  - Entries are invalidated when an app's update or install date changes.
  - Cache entries expire after 7 days.
  - Unchanged apps are not re-walked on every scan.
  - Settings → Data → **Clear Size Cache & Recalculate** forces a full re-measure.
- **Async icons** are loaded off the main thread and prefetched in the background after scanning.
- **Hold ⌥ while clicking Rescan** to force a full refresh: the button turns orange, every icon is re-rendered and every app size is measured again, bypassing both caches.
- **Batched size updates** avoid refreshing the whole table for every app.
- **Native SwiftUI Table** is used for NSTableView-backed virtualization, native scrollbars, and resizable columns.
- Switching sources rebuilds the table instead of animating hundreds of row removals, which keeps the UI responsive.

The first size scan can take longer because it must walk app bundles; later scans reuse the cache. Metadata scanning itself is fast.

## Build

The generated Xcode project is included:

```bash
open Custocub.xcodeproj
```

Select the `Custocub` scheme and run.

Command-line build:

```bash
xcodebuild -project Custocub.xcodeproj \
  -scheme Custocub \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

If you edit `project.yml`, regenerate the project:

```bash
xcodegen generate
```

### Regenerating the app icon

The icon is drawn entirely in code. To regenerate all macOS icon sizes:

```bash
swift Tools/GenerateAppIcon.swift
```

This writes the full set of AppIcon PNGs into `Custocub/Resources/Assets.xcassets/AppIcon.appiconset`.

Project settings:

- Marketing version: `1.2`
- Bundle identifier: `me.whynbnb.Custocub`

## Data locations

Snapshots:

```text
~/Library/Application Support/Custocub/Snapshots/<UUID>.json
```

Homebrew snapshots:

```text
~/Library/Application Support/Custocub/BrewSnapshots/<UUID>.json
```

Size cache:

```text
~/Library/Application Support/Custocub/size-cache.json
```

Custocub is not sandboxed. It only reads application directories and writes its own Application Support data. It does not send data over the network.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘R` | Rescan applications |
| `⌘S` | Save the current snapshot |
| `⇧⌘O` | Import snapshots |
| `⇧⌘E` | Export the selected snapshot |
| `⇧⌘B` | Open the Homebrew screen |
| `⇧⌘S` | Save a Homebrew snapshot |
| `⌘,` | Open Settings |

## Project structure

```text
Custocub/
├─ App/
│  ├─ CustocubApp.swift          # App entry point and menu commands
│  ├─ CustocubStore.swift        # Scan, snapshot, gallery, and selection state
│  └─ BrewStore.swift            # Homebrew inventory, snapshots, and command log
├─ Models/
│  ├─ AppSource.swift            # Source and platform enums
│  ├─ AppRecord.swift            # App record
│  ├─ AppSnapshot.swift          # Snapshot model
│  ├─ AppChange.swift            # Snapshot comparison and Markdown report
│  ├─ GalleryItem.swift          # Gallery item model
│  ├─ BrewPackage.swift          # Homebrew formula/cask record and cask snapshot entry
│  ├─ BrewVersion.swift          # Version parsing and minimum-version check
│  ├─ BrewCatalog.swift          # Explore catalog entries, download stats, query
│  └─ BrewSnapshot.swift         # Homebrew snapshot model and Brewfile builder
├─ Services/
│  ├─ AppScanner.swift           # Directory discovery, Info.plist, source detection
│  ├─ HomebrewIndex.swift        # Caskroom index
│  ├─ SteamDetector.swift        # Steam shortcut and library detection
│  ├─ JetBrainsToolboxIndex.swift # Toolbox install-location index
│  ├─ MachOReader.swift          # Mach-O architecture parsing
│  ├─ DirectorySize.swift        # App size measurement
│  ├─ SizeCache.swift            # Persistent size cache
│  ├─ IconProvider.swift         # Icon loading, prefetching, snapshot PNGs
│  ├─ SnapshotRepository.swift   # Snapshot persistence
│  ├─ BrewService.swift          # brew discovery, streaming execution, JSON inventory
│  ├─ BrewSnapshotRepository.swift # Homebrew snapshot persistence
│  ├─ BrewCleanupService.swift   # Cleanup analysis: cache, old kegs, autoremove
│  ├─ BrewHealthService.swift    # brew config / doctor parsing
│  ├─ BrewServicesService.swift  # brew services parsing
│  └─ BrewCatalogService.swift   # Explore catalog download, cache, and decoding
├─ Views/
│  ├─ ContentView.swift
│  ├─ SidebarView.swift
│  ├─ AppListView.swift
│  ├─ GalleryView.swift
│  ├─ AppDetailView.swift
│  ├─ ComparisonView.swift
│  ├─ SettingsView.swift
│  ├─ HomebrewView.swift         # Homebrew package list, filters, install sheet
│  ├─ BrewSnapshotListView.swift # Homebrew snapshots and Brewfile export
│  ├─ BrewPackageDetailView.swift # Formula/cask detail and commands
│  ├─ BrewConsoleView.swift      # Live command log and history
│  ├─ BrewCleanupView.swift      # Cleanup analysis and actions
│  ├─ BrewHealthView.swift       # Configuration & diagnostics
│  ├─ BrewServicesView.swift     # Background service management
│  ├─ BrewExploreView.swift      # Full catalog browse and search
│  ├─ BrewUpgradeView.swift      # Outdated list, per-row and bulk upgrade
│  ├─ BrewCatalogDetailView.swift # Catalog entry detail panel
│  ├─ Components.swift
│  └─ FileActions.swift
└─ Resources/Assets.xcassets
```

## License

Custocub is released under the [MIT License](LICENSE).

Copyright © 2026 0x574859.

## Acknowledgements

Thanks to the large language model companies, to DeepSeek, and to the various community API relay sites. Without tokens, I could not have run the many tests needed to build this app (even though it did take a few months).

Finally, thanks to Homebrew, the best package manager on macOS.


