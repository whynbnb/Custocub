# Custocub

[English](README.md) · [简体中文](README.zh-CN.md)

> Vibe coded with DeepSeek V4.1 Flash / OpenCode.

**Custocub = custos (Latin: guardian, keeper) + cubby (a small storage compartment).**

Custocub is a native macOS app inventory and snapshot manager built with Swift 6 and SwiftUI. It gives you a clear view of every app on your Mac: where it came from, which architecture it runs on, whether it is a system or third-party app, and what changed over time.

- **Version:** 1.0
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
- **Gallery** — browse installed apps and apps that have been uninstalled but still exist in historical snapshots.
- **Native macOS experience** — native table virtualization, scrollbars, resizable columns, and system selection behavior.
- **English and Chinese** — follows the system language by default, with a manual switch (restart required).
- **Light and dark appearance** — follows the system by default, with manual Light / Dark options.

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
- Compare against the **Current State** without saving it first.
- Export a Markdown comparison report.

### Gallery

The Gallery is an icon-grid view of your software collection:

- Installed apps come from the latest live scan.
- **Uninstalled apps** come from historical snapshots. Even after the app bundle is deleted, Custocub can keep showing its icon and last-known metadata.
- Filter by installed/uninstalled, source, platform, and system/third-party type.

## Performance notes

- **Size cache** at `~/Library/Application Support/Custocub/size-cache.json`
  - Entries are invalidated when an app's update or install date changes.
  - Cache entries expire after 7 days.
  - Unchanged apps are not re-walked on every scan.
  - Settings → Data → **Clear Size Cache & Recalculate** forces a full re-measure.
- **Async icons** are loaded off the main thread and prefetched in the background after scanning.
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

- Marketing version: `1.0`
- Bundle identifier: `me.whynbnb.Custocub`

## Data locations

Snapshots:

```text
~/Library/Application Support/Custocub/Snapshots/<UUID>.json
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
| `⌘,` | Open Settings |

## Project structure

```text
Custocub/
├─ App/
│  ├─ CustocubApp.swift          # App entry point and menu commands
│  └─ CustocubStore.swift        # Scan, snapshot, gallery, and selection state
├─ Models/
│  ├─ AppSource.swift            # Source and platform enums
│  ├─ AppRecord.swift            # App record
│  ├─ AppSnapshot.swift          # Snapshot model
│  ├─ AppChange.swift            # Snapshot comparison and Markdown report
│  └─ GalleryItem.swift          # Gallery item model
├─ Services/
│  ├─ AppScanner.swift           # Directory discovery, Info.plist, source detection
│  ├─ HomebrewIndex.swift        # Caskroom index
│  ├─ SteamDetector.swift        # Steam shortcut and library detection
│  ├─ JetBrainsToolboxIndex.swift # Toolbox install-location index
│  ├─ MachOReader.swift          # Mach-O architecture parsing
│  ├─ DirectorySize.swift        # App size measurement
│  ├─ SizeCache.swift            # Persistent size cache
│  ├─ IconProvider.swift         # Icon loading, prefetching, snapshot PNGs
│  └─ SnapshotRepository.swift   # Snapshot persistence
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

## License

Custocub is released under the [MIT License](LICENSE).

Copyright © 2026 0x574859.

## Acknowledgements

Thanks to the large language model companies, to DeepSeek, and to the various community API relay sites. Without tokens, I could not have run the many tests needed to build this app (even though it did take a few months).

Finally, thanks to Homebrew, the best package manager on macOS.


