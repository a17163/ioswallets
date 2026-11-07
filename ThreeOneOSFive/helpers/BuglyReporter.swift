import Foundation
import Bugly

/// 腾讯 Bugly（崩溃 / 卡顿上报）接入层。
///
/// 用法：
///   1. 在 https://bugly.qq.com 注册产品，拿到 AppID；
///   2. 把 AppID 填到下面的 `appID`；
///   3. 重新构建。App 启动时 `App.swift` 会最早调用 `BuglyReporter.start()`。
///
/// AppID 为空时 SDK 不会启动，所有上报调用都是空操作，不影响其它功能。
enum BuglyReporter {

    /// Bugly 控制台 →「产品设置」里的 AppID（约 10~12 位十六进制字符串）。
    /// 留空 = 不启用。
    static let appID = "4396644a23"

    /// SDK 是否已成功初始化。
    private(set) static var isStarted = false

    // MARK: - 生命周期

    /// 尽可能早地启动 Bugly（应放在 App init 的第一行）。
    /// - Returns: 是否真的启动了 SDK。
    @discardableResult
    static func start() -> Bool {
        guard !isStarted else { return true }

        let id = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            log("bugly: AppID 未配置（helpers/BuglyReporter.swift → BuglyReporter.appID），跳过初始化")
            return false
        }

        let config = BuglyConfig()
        // 需要看 SDK 内部日志时：在 Xcode scheme 里加环境变量 BUGLY_DEBUG=1
        config.debugMode = ProcessInfo.processInfo.environment["BUGLY_DEBUG"] == "1"
        config.channel = channel
        config.version = appVersion

        // 主线程卡顿监控默认关闭：本 App 里有大量长耗时的内核读写 / 文件遍历，
        // 打开后会把正常的长任务误判成卡顿上报。
        config.blockMonitorEnable = false
        // 非正常退出检测同样默认关闭，避免与 App 自身的退出/重启流程互相干扰。
        config.unexpectedTerminatingDetectionEnable = false

        Bugly.start(withAppId: id, config: config)
        isStarted = true

        let device = Bugly.buglyDeviceId()
        log("bugly: started appId=\(id) sdk=\(Bugly.sdkVersion()) version=\(appVersion) channel=\(channel) device=\(device)")
        if Bugly.isAppCrashedOnStartUpExceedTheLimit() {
            log("bugly: 检测到连续闪退（启动 5 秒内崩溃 ≥3 次）")
        }
        return true
    }

    // MARK: - 自检

    /// 给设置页用的状态描述，便于现场判断「没启动」还是「没崩溃」。
    static var statusText: String {
        if isStarted {
            return "已启动 · sdk \(Bugly.sdkVersion())"
        }
        return appID.trimmingCharacters(in: .whitespaces).isEmpty ? "未配置 AppID" : "未启动"
    }

    /// 当前上报使用的版本号 / 渠道（Bugly 后台按这两项归类）。
    static var versionChannelText: String {
        "\(appVersion) · \(channel)"
    }

    static var appIDText: String {
        let id = appID.trimmingCharacters(in: .whitespaces)
        return id.isEmpty ? "未配置" : id
    }

    static var deviceIDText: String {
        deviceID ?? "—"
    }

    /// 主动上报一条「自定义错误」，用于验证网络与上报链路（不会让 App 崩溃）。
    static func sendTestError() {
        guard isStarted else {
            log("bugly: 测试上报失败 — SDK 未启动")
            return
        }
        let info: [String: Any] = [
            "app": "3105",
            "ios": "\(AppInfo.osVersion) (\(AppInfo.osBuild))",
            "time": Date().description,
        ]
        reportCustomError("BuglyTestError",
                          reason: "手动触发的测试错误（忽略即可）",
                          extra: info)
        log("bugly: 已上报测试错误 BuglyTestError")
    }

    /// 制造一次真实崩溃，用于验证崩溃捕获链路。**会立即终止进程。**
    static func triggerTestCrash() -> Never {
        log("bugly: 触发测试崩溃（进程即将退出）")
        let exception = NSException(name: NSExceptionName("BuglyTestCrash"),
                                    reason: "手动触发的测试崩溃（忽略即可）",
                                    userInfo: nil)
        exception.raise()
        fatalError("BuglyTestCrash")   // 兜底：raise() 若被拦截也会在这里终止
    }

    // MARK: - 业务信息

    /// 设置用户标识（Bugly 控制台可按其筛选崩溃）。
    static func setUserID(_ id: String) {
        guard isStarted else { return }
        Bugly.setUserIdentifier(id)
    }

    /// 附带在崩溃报告里的自定义键值。
    static func setValue(_ value: String, forKey key: String) {
        guard isStarted else { return }
        Bugly.setUserValue(value, forKey: key)
    }

    /// 当前 Bugly 设备 ID（用于和后台日志对账）。
    static var deviceID: String? {
        guard isStarted else { return nil }
        return Bugly.buglyDeviceId()
    }

    // MARK: - 主动上报

    /// 上报一个错误（不会中断 App）。
    static func report(_ error: Error) {
        guard isStarted else { return }
        Bugly.reportError(error)
    }

    /// 上报一个 Objective-C 异常（不会中断 App）。
    static func report(exception: NSException) {
        guard isStarted else { return }
        // SDK 把 `reportException:` 在 Swift 里重命名成了 `report(_:)`。
        Bugly.report(exception)
    }

    /// 以「自定义错误」形式上报：便于把内部失败（解压失败、签名失败等）也送到 Bugly。
    /// - Parameters:
    ///   - name: 错误名（控制台「错误名称」列）
    ///   - reason: 错误原因
    ///   - stack: 调用栈（`Thread.callStackSymbols` 即可）
    ///   - extra: 附加信息
    static func reportCustomError(_ name: String,
                                  reason: String,
                                  stack: [String] = Thread.callStackSymbols,
                                  extra: [String: Any] = [:]) {
        guard isStarted else { return }
        // category: Cocoa = 3
        Bugly.reportException(withCategory: 3,
                              name: name,
                              reason: reason,
                              callStack: stack,
                              extraInfo: extra,
                              terminateApp: false)
    }

    // MARK: - 环境信息

    /// 上报渠道，在 Bugly 控制台「渠道」维度里展示。
    private static var channel: String {
        #if DEBUG
        return "Debug"
        #else
        return "Direct"
        #endif
    }

    /// 上报版本号需要和 Bugly 控制台里填写的版本一致，这里直接用 App 的版本号。
    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short).\($0)" } ?? short
    }
}
