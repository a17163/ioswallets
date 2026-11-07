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
        config.debugMode = false
        config.channel = channel
        config.version = appVersion

        // 主线程卡顿监控默认关闭：本 App 里有大量长耗时的内核读写 / 文件遍历，
        // 打开后会把正常的长任务误判成卡顿上报。
        config.blockMonitorEnable = false
        // 非正常退出检测同样默认关闭，避免与 App 自身的退出/重启流程互相干扰。
        config.unexpectedTerminatingDetectionEnable = false

        Bugly.start(withAppId: id, config: config)
        isStarted = true

        log("bugly: started appId=\(id) sdk=\(Bugly.sdkVersion()) version=\(appVersion) channel=\(channel)")
        if Bugly.isAppCrashedOnStartUpExceedTheLimit() {
            log("bugly: 检测到连续闪退（启动 5 秒内崩溃 ≥3 次）")
        }
        return true
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
