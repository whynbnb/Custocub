import AppKit
import SwiftUI

/// SwiftUI 的 `Table` 没有提供「滚动到指定行」的 API。
///
/// 这里放一个不可见视图，在选中项变化时找到底层的 `NSTableView`，
/// 把对应行滚动到可见区域。命令面板跳转到应用后，列表也会跟着定位。
struct TableRowScroller: NSViewRepresentable {
    let selectedID: String?
    let rowIDs: [String]

    func makeNSView(context: Context) -> ScrollerView {
        ScrollerView()
    }

    func updateNSView(_ nsView: ScrollerView, context: Context) {
        nsView.scroll(to: selectedID, rowIDs: rowIDs)
    }

    final class ScrollerView: NSView {
        private var lastRequestedKey: String?

        func scroll(to id: String?, rowIDs: [String]) {
            guard let id, let row = rowIDs.firstIndex(of: id) else { return }

            let key = "\(id)#\(row)#\(rowIDs.count)"
            guard key != lastRequestedKey else { return }
            lastRequestedKey = key

            attemptScroll(row: row, expectedRows: rowIDs.count, remainingAttempts: 3)
        }

        /// 列表筛选变化时行数会延后更新，因此失败后短暂重试。
        private func attemptScroll(row: Int, expectedRows: Int, remainingAttempts: Int) {
            let delay: TimeInterval = remainingAttempts == 3 ? 0 : 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }

                guard let root = self.window?.contentView,
                      let table = Self.findTableView(in: root, expectedRows: expectedRows),
                      row < table.numberOfRows else {
                    if remainingAttempts > 1 {
                        self.attemptScroll(
                            row: row,
                            expectedRows: expectedRows,
                            remainingAttempts: remainingAttempts - 1
                        )
                    }
                    return
                }

                table.scrollRowToVisible(row)
            }
        }

        /// 只接受行数与当前列表一致的表格，避免误滚动侧边栏等其他表格。
        private static func findTableView(in view: NSView, expectedRows: Int) -> NSTableView? {
            var tables: [NSTableView] = []
            collectTables(in: view, into: &tables)
            return tables.first { $0.numberOfRows == expectedRows }
        }

        private static func collectTables(in view: NSView, into tables: inout [NSTableView]) {
            if let table = view as? NSTableView {
                tables.append(table)
            }
            for subview in view.subviews {
                collectTables(in: subview, into: &tables)
            }
        }
    }
}
