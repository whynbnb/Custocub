import AppKit
import SwiftUI

enum GalleryPresentation {
    static let windowID = "gallery-presentation"
}

/// 独立窗口里的沉浸式图标墙。
struct GalleryPresentationView: View {
    @EnvironmentObject private var store: CustocubStore
    @EnvironmentObject private var brew: BrewStore
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var showsChrome = true
    @State private var hideTask: Task<Void, Never>?
    @State private var showingCommandPalette = false

    private var items: [GalleryItem] {
        store.filteredGalleryItems(store.galleryScopedItems)
    }

    private var snapshotLabel: String {
        store.gallerySnapshot?.name ?? L.t("今天")
    }

    var body: some View {
        ZStack(alignment: .top) {
            background
            content

            if showsChrome {
                chrome
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onContinuousHover { phase in
            if case .active = phase {
                revealChrome()
            }
        }
        .onAppear {
            revealChrome()
        }
        .onDisappear {
            hideTask?.cancel()
        }
        .onExitCommand {
            close()
        }
        .onReceive(NotificationCenter.default.publisher(for: .custocubShowCommandPalette)) { _ in
            showingCommandPalette = true
        }
        .sheet(isPresented: $showingCommandPalette) {
            CommandPaletteView()
                .environmentObject(store)
                .environmentObject(brew)
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.04, blue: 0.055),
                    Color(red: 0.07, green: 0.08, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 520, height: 520)
                .blur(radius: 100)
                .offset(x: 380, y: -260)

            Circle()
                .fill(Color.purple.opacity(0.12))
                .frame(width: 460, height: 460)
                .blur(radius: 110)
                .offset(x: -420, y: 320)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "rectangle.grid.2x2")
                    .font(.system(size: 42))
                    .foregroundStyle(.white.opacity(0.35))
                Text("没有可展示的应用")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                Text("调整展示框的筛选条件后再试。")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190, maximum: 270), spacing: 26)],
                    spacing: 26
                ) {
                    ForEach(items) { item in
                        PresentationCard(item: item)
                    }
                }
                .padding(.horizontal, 52)
                .padding(.top, 112)
                .padding(.bottom, 64)
            }
            .scrollIndicators(.never)
        }
    }

    private var chrome: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.galleryScopeTitle)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Text(L.t("%d 个应用", items.count))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Menu {
                Button(L.t("今天")) {
                    store.gallerySnapshotID = nil
                }
                if !store.snapshots.isEmpty {
                    Divider()
                    ForEach(store.snapshots) { snapshot in
                        Button(snapshot.name) {
                            store.gallerySnapshotID = snapshot.id
                        }
                    }
                }
            } label: {
                Label(snapshotLabel, systemImage: "camera")
                    .font(.callout)
                    .foregroundStyle(.white)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            chromeButton("进入全屏", symbol: "arrow.up.left.and.arrow.down.right") {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }

            chromeButton("退出展示模式", symbol: "xmark") {
                close()
            }
        }
        .padding(.leading, 92)
        .padding(.trailing, 30)
        .padding(.vertical, 22)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private func chromeButton(
        _ help: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .help(Text(L.t(help)))
    }

    private func revealChrome() {
        if !showsChrome {
            withAnimation(.easeOut(duration: 0.18)) {
                showsChrome = true
            }
        }

        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) {
                showsChrome = false
            }
        }
    }

    private func close() {
        dismissWindow(id: GalleryPresentation.windowID)
    }
}

private struct PresentationCard: View {
    let item: GalleryItem

    var body: some View {
        VStack(spacing: 9) {
            AppIconView(app: item.app, size: 92, cornerRadius: 20)

            Text(item.app.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 7) {
                Text(item.app.displayVersion)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))

                if item.status == .uninstalled {
                    Text("已卸载")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red.opacity(0.9))
                }
            }

            SourceBadge(source: item.app.source, compact: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        }
    }
}
