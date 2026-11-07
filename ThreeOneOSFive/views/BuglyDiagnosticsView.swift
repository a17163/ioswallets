import SwiftUI

/// Bugly 诊断面板。
///
/// 入口：在手机上用浏览器打开 `threeoneosfive://bugly`（App 已注册该 scheme），
/// 会弹出这个原生面板。之所以不用设置页：App 的界面是 WKWebView，
/// 原生 SettingsView 并不在界面路径上。
@available(iOS 16.0, *)
struct BuglyDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmCrash = false
    @State private var showReported = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("状态", value: BuglyReporter.statusText)
                    LabeledContent("版本 / 渠道", value: BuglyReporter.versionChannelText)
                    LabeledContent("构建", value: BuglyReporter.buildStamp)
                } header: {
                    Text("Bugly")
                } footer: {
                    Text("「已启动」表示崩溃处理器已装好；版本号和渠道必须和 Bugly 控制台一致。")
                }

                Section {
                    LabeledContent("AppID", value: BuglyReporter.appIDText)
                    LabeledContent("设备 ID", value: BuglyReporter.deviceIDText)
                } header: {
                    Text("标识")
                } footer: {
                    Text("设备 ID 可在 Bugly 控制台按用户检索时对账。")
                }

                Section {
                    Button {
                        BuglyReporter.sendTestError()
                        showReported = true
                    } label: {
                        Label("上报测试错误", systemImage: "paperplane")
                    }
                    .disabled(!BuglyReporter.isStarted)

                    Button(role: .destructive) {
                        confirmCrash = true
                    } label: {
                        Label("触发测试崩溃", systemImage: "bolt.trianglebadge.exclamationmark")
                    }
                    .disabled(!BuglyReporter.isStarted)
                } header: {
                    Text("验证")
                } footer: {
                    Text("测试错误 1~2 分钟后出现在「错误分析」；测试崩溃会立即退出 App，重新打开后出现在「崩溃分析」。")
                }

                if !BuglyReporter.isStarted {
                    Section {
                        Text("SDK 未启动：常见原因是 AppID 未配置，或这版包没带 Bugly。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Bugly 诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .confirmationDialog(
                "测试崩溃会立即退出 App，确定继续？",
                isPresented: $confirmCrash,
                titleVisibility: .visible
            ) {
                Button("触发崩溃", role: .destructive) {
                    BuglyReporter.triggerTestCrash()
                }
                Button("取消", role: .cancel) {}
            }
            .alert("已上报测试错误", isPresented: $showReported) {
                Button("好", role: .cancel) {}
            } message: {
                Text("1~2 分钟后到 Bugly 控制台「错误分析」查看 BuglyTestError。")
            }
        }
    }
}
