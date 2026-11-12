import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: CustocubStore

    @AppStorage("autoScanOnLaunch") private var autoScanOnLaunch = true
    @AppStorage("refreshOnActivate") private var refreshOnActivate = true
    @AppStorage("computeSizes") private var computeSizes = true

    var body: some View {
        Form {
            Section("扫描") {
                Toggle("启动时自动扫描", isOn: $autoScanOnLaunch)
                Toggle("回到应用时自动刷新", isOn: $refreshOnActivate)
                Toggle("扫描后计算应用体积", isOn: $computeSizes)

                Text("关闭体积计算后，列表会更快出现；保存快照时仍会补齐体积。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("扫描目录") {
                Text("/Applications")
                Text("~/Applications")
                Text("/System/Applications")
                Text("/System/Library/CoreServices")
                Text("/Library/Apple/System/Applications")
            }
            .font(.caption.monospaced())

            Section("数据") {
                HStack {
                    Button("重新扫描") {
                        Task { await store.refresh(ignoreRecentScan: true) }
                    }
                    .disabled(store.isScanning)

                    Button("清除图标缓存") {
                        IconProvider.shared.clear()
                    }

                    Button("在访达中显示快照文件夹") {
                        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        let directory = support
                            .appendingPathComponent("Custocub", isDirectory: true)
                            .appendingPathComponent("Snapshots", isDirectory: true)
                        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(directory)
                    }

                    Spacer()

                    Text("\(store.snapshots.count) 个已保存快照")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("关于") {
                LabeledContent("Custocub", value: "1.2.0")
                Text("Custocub = custos（守护） + cubby（收纳格）。用于清点 macOS 软件来源、架构与变化。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 430)
        .navigationTitle("Custocub 设置")
    }
}
