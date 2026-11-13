import AppKit
import SwiftUI

struct AppDetailView: View {
    @EnvironmentObject private var store: CustocubStore
    let context: SelectedAppContext?

    var body: some View {
        Group {
            if let context {
                detail(for: context)
            } else {
                ContentUnavailableView(
                    "选择一个应用",
                    systemImage: "app.dashed",
                    description: Text("从应用列表或展示框中选择一个软件，查看详细信息。")
                )
            }
        }
        .navigationTitle("应用详情")
    }

    private func detail(for context: SelectedAppContext) -> some View {
        let app = context.app
        let isInstalled = FileManager.default.fileExists(atPath: app.path)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(app: app, context: context, isInstalled: isInstalled)

                HStack(spacing: 8) {
                    if isInstalled {
                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
                        } label: {
                            Label("打开", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
                        } label: {
                            Label("在访达中显示", systemImage: "folder")
                                .labelStyle(.iconOnly)
                        }
                        .help(Text(L.t("在访达中显示")))
                    }

                    Button {
                        copy(app.displayBundleIdentifier)
                    } label: {
                        Label("复制 Bundle ID", systemImage: "doc.on.doc")
                            .labelStyle(.iconOnly)
                    }
                    .help(Text(L.t("复制 Bundle ID")))
                    .disabled(app.bundleIdentifier == nil)

                    if (store.activeSelection == .installed || store.activeSelection == .own), isInstalled {
                        Button {
                            store.sidebarSelection = .gallery
                            store.galleryStatusFilter = nil
                            store.selectedAppID = app.id
                        } label: {
                            Label("在展示框中查看", systemImage: "rectangle.grid.2x2")
                                .labelStyle(.iconOnly)
                        }
                        .help(Text(L.t("在展示框中查看")))
                    }
                }
                .controlSize(.small)

                SectionCard(title: "基本信息") {
                    DetailRow(label: "版本", value: app.displayVersion)
                    DetailRow(label: "构建号", value: app.build ?? L.t("无"))
                    DetailRow(label: "Bundle ID", value: app.displayBundleIdentifier, monospaced: true)
                    DetailRow(label: "大小", value: app.displaySize)
                    DetailRow(label: "最低系统", value: app.minimumSystemVersion ?? L.t("未声明"))
                }

                SectionCard(title: "来源与平台") {
                    HStack(spacing: 8) {
                        SourceBadge(source: app.source)
                        PlatformBadge(platform: app.platform)
                        TypeBadge(isSystem: app.isSystemApp)
                        Spacer()
                    }
                    DetailRow(label: "来源", value: app.source.title)
                    DetailRow(label: "类型", value: app.isSystemApp ? L.t("系统内置应用") : L.t("第三方应用"))
                    DetailRow(label: "架构", value: app.architectureText, monospaced: true)
                    if let steamAppID = app.steamAppID {
                        DetailRow(label: "Steam App ID", value: steamAppID, monospaced: true)
                    }
                    if app.source == .steam {
                        Text(app.steamAppID == nil
                            ? L.t("该应用位于 Steam 库中，由 Steam 管理。")
                            : L.t("这是 Steam 创建的启动快捷方式；游戏本体由 Steam 管理。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if app.source == .jetbrainsToolbox {
                        Text("该应用由 JetBrains Toolbox 安装和管理。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if app.isIOSApp {
                        DetailRow(label: "运行方式", value: L.t("iPhone / iPad 应用（Apple 芯片）"))
                    }
                    if let wrapped = app.wrappedAppPath {
                        DetailRow(label: "包装路径", value: wrapped, monospaced: true)
                    }
                }

                SectionCard(title: "时间") {
                    DetailRow(label: "安装时间", value: app.installedAtText)
                    DetailRow(label: "更新时间", value: app.updatedAtText)
                    DetailRow(label: "最后扫描", value: app.lastSeenAtText)
                }

                SectionCard(title: "安装位置") {
                    DetailRow(label: "应用路径", value: app.path, monospaced: true)
                    if app.resolvedPath != app.path {
                        DetailRow(label: "实际路径", value: app.resolvedPath, monospaced: true)
                    }
                    if let executable = app.executablePath {
                        DetailRow(label: "可执行文件", value: executable, monospaced: true)
                    }
                }

                if let item = context.galleryItem, item.status == .uninstalled {
                    SectionCard(title: "展示框记录") {
                        HStack(spacing: 8) {
                            GalleryStatusBadge(status: item.status)
                            if let snapshotName = item.snapshotName {
                                Text(L.t("最后出现于快照「%@」", snapshotName))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("这个应用当前不在磁盘上。Custocub 使用历史快照中的图标和元数据继续展示它。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let snapshot = context.snapshot {
                    SectionCard(title: "快照信息") {
                        DetailRow(label: "快照", value: snapshot.name)
                        DetailRow(label: "保存时间", value: snapshot.createdAt.formatted(date: .long, time: .shortened))
                        if !snapshot.note.isEmpty {
                            DetailRow(label: "备注", value: snapshot.note)
                        }
                        Text("这是快照中的历史记录，不代表应用当前仍安装在磁盘上。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(18)
        }
    }

    private func header(app: AppRecord, context: SelectedAppContext, isInstalled: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            AppIconView(app: app, size: 82, cornerRadius: 18)

            VStack(alignment: .leading, spacing: 7) {
                Text(app.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)

                HStack(spacing: 7) {
                    SourceBadge(source: app.source)
                    PlatformBadge(platform: app.platform)
                    TypeBadge(isSystem: app.isSystemApp)
                    if store.isManagerNode(app) {
                        ManagerBadge()
                    }
                    if app.isOwn {
                        OwnAppBadge()
                    }
                    if let item = context.galleryItem, item.status == .uninstalled {
                        GalleryStatusBadge(status: .uninstalled)
                    }
                    Spacer(minLength: 0)
                }

                Text(app.listSubtitle)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
