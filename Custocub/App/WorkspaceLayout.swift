import AppKit
import SwiftUI

/// 工作区布局记忆。
///
/// 侧边栏宽度和窗口宽度按「应用」与「Homebrew」分别保存：
/// 在两个工作区之间切换时，会恢复各自上次使用的宽度。
///
/// 只影响 Custocub 自己的窗口尺寸，不修改系统或其他应用的设置。
enum WorkspaceLayoutStore {
    /// 两种独立的工作区。
    enum Mode: String, CaseIterable, Sendable {
        case apps
        case homebrew

        static func mode(for selection: SidebarSelection) -> Mode {
            selection == .brew ? .homebrew : .apps
        }
    }

    static let sidebarMinWidth: CGFloat = 220
    static let sidebarMaxWidth: CGFloat = 300
    static let sidebarDefaultWidth: CGFloat = 240
    static let windowMinWidth: CGFloat = 1240
    static let windowMinHeight: CGFloat = 700

    // MARK: - 侧边栏宽度

    private static func sidebarKey(_ mode: Mode) -> String {
        "workspace.sidebarWidth.\(mode.rawValue)"
    }

    static func sidebarWidth(for mode: Mode) -> CGFloat {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: sidebarKey(mode)) != nil else {
            return sidebarDefaultWidth
        }
        let width = CGFloat(defaults.double(forKey: sidebarKey(mode)))
        return min(max(width, sidebarMinWidth), sidebarMaxWidth)
    }

    /// 保存侧边栏宽度。过窄（例如被折叠）的值会被忽略，避免下次启动只剩一条细边。
    static func setSidebarWidth(_ width: CGFloat, for mode: Mode) {
        guard width >= sidebarMinWidth - 1,
              width <= sidebarMaxWidth + 1 else { return }
        UserDefaults.standard.set(Double(width), forKey: sidebarKey(mode))
    }

    // MARK: - 窗口宽度

    private static func windowKey(_ mode: Mode) -> String {
        "workspace.windowWidth.\(mode.rawValue)"
    }

    static func windowWidth(for mode: Mode) -> CGFloat? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: windowKey(mode)) != nil else { return nil }
        return CGFloat(defaults.double(forKey: windowKey(mode)))
    }

    static func setWindowWidth(_ width: CGFloat, for mode: Mode) {
        guard width >= windowMinWidth - 1 else { return }
        UserDefaults.standard.set(Double(width), forKey: windowKey(mode))
    }
}

// MARK: - 侧边栏宽度同步

/// 把 `NavigationSplitView` 侧边栏的实际宽度与 `WorkspaceLayoutStore` 双向同步。
///
/// SwiftUI 没有提供侧边栏宽度的绑定，所以这里找到底层的 `NSSplitView`：
/// 用户拖动时读取宽度并保存，切换工作区或启动时把保存的宽度写回去。
struct SidebarWidthMemory: NSViewRepresentable {
    let mode: WorkspaceLayoutStore.Mode

    func makeCoordinator() -> Coordinator { Coordinator(mode: mode) }

    func makeNSView(context: Context) -> NSView {
        let view = ProbeView()
        view.onLayout = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.viewDidLayout(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(mode: mode)
        if let view = nsView as? ProbeView {
            context.coordinator.viewDidLayout(view)
        }
    }

    /// 用来在窗口层级里定位自身位置的小视图。
    final class ProbeView: NSView {
        var onLayout: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onLayout?()
        }

        override func layout() {
            super.layout()
            onLayout?()
        }
    }

    @MainActor
    final class Coordinator {
        private weak var probe: NSView?
        private weak var splitView: NSSplitView?
        private weak var sidebarContainer: NSView?
        private var observer: NSObjectProtocol?
        private var mode: WorkspaceLayoutStore.Mode
        private var hasUserResized = false
        private var retries: [DispatchWorkItem] = []
        private var saveTask: Task<Void, Never>?
        /// 程序化设置宽度后会立刻收到 resize 通知，用这个值把它排除掉。
        private var lastAppliedWidth: CGFloat?
        /// 启动或切换工作区后的一小段时间内不保存宽度，
        /// 避免把 SwiftUI 自己恢复的宽度误写成记忆值。
        private var suppressSavesUntil = Date.distantPast
        /// 首次应用记忆宽度时即使侧边栏处于折叠状态也展开一次，
        /// 避免上次意外折叠后再也看不到侧边栏。
        private var isInitialApply = true

        init(mode: WorkspaceLayoutStore.Mode) {
            self.mode = mode
        }

        func viewDidLayout(_ view: NSView) {
            probe = view
            bindIfNeeded()
        }

        func update(mode: WorkspaceLayoutStore.Mode) {
            let changed = mode != self.mode
            self.mode = mode

            if splitView == nil {
                if let probe { viewDidLayout(probe) }
                return
            }
            if changed {
                hasUserResized = false
                lastAppliedWidth = nil
                suppressSavesUntil = Date().addingTimeInterval(1.6)
                scheduleApply()
            }
        }

        private func bindIfNeeded() {
            guard splitView == nil, let probe else { return }
            guard let split = Self.enclosingSplitView(of: probe) else { return }

            splitView = split
            sidebarContainer = Self.directChild(of: probe, in: split)

            observer = NotificationCenter.default.addObserver(
                forName: NSSplitView.didResizeSubviewsNotification,
                object: split,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.splitDidResize()
                }
            }

            // 启动后的第一次布局和 SwiftUI 的恢复都发生在很短时间内，
            // 这期间只应用记忆值，不反写。
            suppressSavesUntil = Date().addingTimeInterval(1.6)
            scheduleApply()
        }

        private func splitDidResize() {
            guard Date() >= suppressSavesUntil else { return }
            guard let width = currentWidth() else { return }

            // 排除自己 setPosition 触发的那次通知。
            if let lastAppliedWidth, abs(width - lastAppliedWidth) < 1 { return }

            hasUserResized = true
            saveTask?.cancel()

            let mode = mode
            saveTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                WorkspaceLayoutStore.setSidebarWidth(width, for: mode)
            }
        }

        /// SwiftUI 会在窗口显示后恢复自己保存的分栏宽度，
        /// 因此在用户主动拖动之前，分几次把记忆宽度写回去。
        private func scheduleApply() {
            retries.forEach { $0.cancel() }
            retries = []

            for delay in [0.0, 0.15, 0.45, 0.9, 1.4] {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, !self.hasUserResized else { return }
                    self.applySavedWidth()
                }
                retries.append(work)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            }
        }

        private func applySavedWidth() {
            guard let splitView, let sidebarContainer else { return }

            // 启动时恢复一次宽度，即便上次是折叠状态也会展开；
            // 之后切换工作区时尊重用户当前的折叠选择。
            let collapsed = splitView.isSubviewCollapsed(sidebarContainer)
            if collapsed, !isInitialApply { return }

            let target = WorkspaceLayoutStore.sidebarWidth(for: mode)
            let current = sidebarContainer.frame.width
            // 折叠状态下容器宽度可能仍是旧值，需要显式展开。
            guard collapsed || abs(current - target) >= 1 else {
                isInitialApply = false
                return
            }

            lastAppliedWidth = target
            splitView.setPosition(target, ofDividerAt: 0)
            isInitialApply = false
        }

        private func currentWidth() -> CGFloat? {
            guard let container = sidebarContainer else { return nil }
            let width = container.frame.width
            // 侧边栏被折叠或尚未布局时宽度会很小，不保存这种状态。
            guard width > 100 else { return nil }
            return width
        }

        private static func enclosingSplitView(of view: NSView) -> NSSplitView? {
            var current = view.superview
            while let candidate = current {
                if let split = candidate as? NSSplitView { return split }
                current = candidate.superview
            }
            return nil
        }

        /// 找到 `view` 在分栏视图中的直接子视图，也就是侧边栏容器。
        private static func directChild(of view: NSView, in split: NSSplitView) -> NSView? {
            var current: NSView? = view
            while let candidate = current {
                if candidate.superview === split { return candidate }
                current = candidate.superview
            }
            return nil
        }
    }
}

// MARK: - 窗口宽度同步

/// 按工作区记住窗口宽度。
///
/// 用户拖动窗口时保存当前工作区的宽度；切换工作区时恢复对应宽度。
struct WindowWidthMemory: NSViewRepresentable {
    let mode: WorkspaceLayoutStore.Mode

    func makeCoordinator() -> Coordinator { Coordinator(mode: mode) }

    func makeNSView(context: Context) -> NSView {
        let view = WindowProbeView()
        view.onWindowChange = { [weak coordinator = context.coordinator, weak view] in
            coordinator?.attach(view?.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if nsView.window !== context.coordinator.window {
            context.coordinator.attach(nsView.window)
        }
        context.coordinator.update(mode: mode)
    }

    final class WindowProbeView: NSView {
        var onWindowChange: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?()
        }
    }

    @MainActor
    final class Coordinator {
        private(set) weak var window: NSWindow?
        private var mode: WorkspaceLayoutStore.Mode
        private var observers: [NSObjectProtocol] = []
        private var hasUserResized = false
        private var lastAppliedWidth: CGFloat?
        private var saveTask: Task<Void, Never>?
        private var suppressSavesUntil = Date.distantPast

        init(mode: WorkspaceLayoutStore.Mode) {
            self.mode = mode
        }

        func attach(_ window: NSWindow?) {
            guard let window, window !== self.window else { return }
            self.window = window
            hasUserResized = false
            suppressSavesUntil = Date().addingTimeInterval(1.2)

            window.minSize = NSSize(
                width: WorkspaceLayoutStore.windowMinWidth,
                height: WorkspaceLayoutStore.windowMinHeight
            )

            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            // 程序化 setFrame 也会触发 didResize，所以用 lastAppliedWidth 区分；
            // 只有宽度确实变化到别的值时才保存，这样拖动、缩放按钮都能记住。
            observers = [
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.scheduleSave()
                    }
                },
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didEndLiveResizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.saveNow()
                    }
                }
            ]

            // SwiftUI 会在窗口显示后恢复自己保存的 frame。
            // 在用户主动调整之前，分几次把记忆宽度写回去，确保最终生效。
            for delay in [0.0, 0.15, 0.45, 0.9] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.window === window, !self.hasUserResized else { return }
                    self.applyWindowWidth()
                }
            }
        }

        func update(mode: WorkspaceLayoutStore.Mode) {
            let changed = mode != self.mode
            guard changed else { return }

            // 切换前先记下当前工作区的宽度，再应用新工作区的宽度。
            saveNow()
            self.mode = mode
            hasUserResized = false
            saveTask?.cancel()
            suppressSavesUntil = Date().addingTimeInterval(0.5)
            applyWindowWidth()
        }

        private func scheduleSave() {
            guard Date() >= suppressSavesUntil else { return }
            guard let window else { return }
            // 排除自己 setFrame 触发的那次通知。
            if let lastAppliedWidth, abs(window.frame.width - lastAppliedWidth) < 1 { return }

            hasUserResized = true
            saveTask?.cancel()

            let mode = mode
            let width = window.frame.width
            saveTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                WorkspaceLayoutStore.setWindowWidth(width, for: mode)
            }
        }

        private func saveNow() {
            guard let window else { return }
            WorkspaceLayoutStore.setWindowWidth(window.frame.width, for: mode)
        }

        private func applyWindowWidth() {
            guard let window else { return }

            let saved = WorkspaceLayoutStore.windowWidth(for: mode)
            let visibleWidth = window.screen?.visibleFrame.width ?? 1920

            var target = saved ?? window.frame.width
            target = min(max(target, WorkspaceLayoutStore.windowMinWidth), visibleWidth)

            var frame = window.frame
            // 没有保存过这个工作区的宽度时，只在窗口小于最小值时纠正，
            // 避免每次切换都强行改变用户当前的窗口尺寸。
            if saved == nil, frame.width >= WorkspaceLayoutStore.windowMinWidth {
                return
            }
            guard abs(frame.width - target) >= 1 else { return }

            frame.size.width = target
            if let visible = window.screen?.visibleFrame, frame.maxX > visible.maxX {
                frame.origin.x = max(visible.minX, visible.maxX - target)
            }
            lastAppliedWidth = target
            window.setFrame(frame, display: true)
        }
    }
}

// MARK: - 详情面板宽度

/// 「列表 + 详情」布局里详情面板的宽度。
///
/// 详情面板默认收起，展开后用户可以拖动分隔条调整宽度，
/// 关掉再打开、或者下次启动都会用回上次的宽度。
enum DetailPaneWidth {
    static let minWidth: CGFloat = 240
    static let idealWidth: CGFloat = 300
    static let maxWidth: CGFloat = 420

    private static let key = "workspace.detailPaneWidth"

    static func load() -> CGFloat {
        guard let value = UserDefaults.standard.object(forKey: key) as? Double else {
            return idealWidth
        }
        return clamp(CGFloat(value))
    }

    static func save(_ width: CGFloat) {
        UserDefaults.standard.set(Double(clamp(width)), forKey: key)
    }

    static func clamp(_ width: CGFloat) -> CGFloat {
        min(max(width, minWidth), maxWidth)
    }
}
