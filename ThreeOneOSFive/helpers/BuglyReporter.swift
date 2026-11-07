import Foundation
import Bugly

/// 腾讯 Bugly（崩溃上报）接入层 —— 对应 SDK 2.7.1.1。
///
/// 2.7 起 API 变化：不再 `Bugly.startWithAppId:`，而是把 AppID/AppKey 放进
/// `BuglyConfig(appId:appKey:)` 再 `Bugly.start(withConfig:)`。
///
/// AppID 写死在代码里；AppKey **不进仓库**：构建时由 CI Secret（`BUGLY_APP_KEY`）
/// 或本地 `tools/bugly.env` 写入包内 `BuglyAppKey.txt`，运行时再读出来。
/// 缺任一项就不启动 SDK，其它功能不受影响。
enum BuglyReporter {

    /// Bugly 控制台 → 产品设置 → AppID
    static let appID = "4396644a23"

    /// SDK 是否已成功初始化。
    private(set) static var isStarted = false

    // MARK: - 生命周期

    /// 尽可能早地启动 Bugly（放在 App init 的第一行）。
    @discardableResult
    static func start() -> Bool {
        guard !isStarted else { return true }

        let id = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            log("bugly: AppID 未配置，跳过初始化")
            return false
        }
        let key = appKey
        guard !key.isEmpty else {
            log("bugly: AppKey 缺失，跳过初始化（构建时由 BUGLY_APP_KEY / tools/bugly.env 注入包内 BuglyAppKey.txt）")
            return false
        }

        let config = BuglyConfig(appId: id, appKey: key)
        // 需要看 SDK 内部日志时：在 Xcode scheme 里加环境变量 BUGLY_DEBUG=1
        config.debugMode = ProcessInfo.processInfo.environment["BUGLY_DEBUG"] == "1"
        config.channel = channel
        config.version = appVersion

        // 主线程卡顿监控默认关闭：本 App 有大量长耗时的内核读写 / 文件遍历，
        // 打开后会把正常的长任务误判成卡顿上报。
        // 崩溃捕获显式打开（2.7 把各类监控拆成了独立开关）
        config.crashMonitorEnable = true
        config.blockMonitorEnable = false
        // 非正常退出检测同样默认关闭，避免与 App 自身的退出/重启流程互相干扰。
        config.unexpectedTerminatingDetectionEnable = false

        Bugly.start(with: config)
        isStarted = true

        let device = Bugly.buglyDeviceId()
        log("bugly: started appId=\(id) sdk=\(Bugly.sdkVersion()) version=\(appVersion) channel=\(channel) device=\(device)")
        if Bugly.isAppCrashedOnStartUpExceedTheLimit() {
            log("bugly: 检测到连续闪退（启动 5 秒内崩溃 ≥3 次）")
        }
        return true
    }

    // MARK: - 自检

    /// 给诊断面板用的状态描述，便于现场判断「没启动」还是「没崩溃」。
    static var statusText: String {
        if isStarted {
            return "已启动 · sdk \(Bugly.sdkVersion())"
        }
        if appID.trimmingCharacters(in: .whitespaces).isEmpty { return "未配置 AppID" }
        if appKey.isEmpty { return "未配置 AppKey" }
        return "未启动"
    }

    /// 当前上报使用的版本号 / 渠道（Bugly 后台按这两项归类）。
    static var versionChannelText: String {
        "\(appVersion) · \(channel)"
    }

    static var appIDText: String {
        let id = appID.trimmingCharacters(in: .whitespaces)
        return id.isEmpty ? "未配置" : id
    }

    /// AppKey 是否已随包注入（只显示是否，不显示内容）。
    static var appKeyText: String {
        appKey.isEmpty ? "缺失" : "已注入（\(appKey.count) 位）"
    }

    /// 构建号：CI 会把 git 短 SHA 写进包内 GitCommit.txt，用来确认手机上装的是哪一版。
    static var buildStamp: String {
        if let sha = Bundle.main.object(forInfoDictionaryKey: "GitCommit") as? String, !sha.isEmpty {
            return sha
        }
        if let url = Bundle.main.url(forResource: "GitCommit", withExtension: "txt"),
           let sha = try? String(contentsOf: url, encoding: .utf8)
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !sha.isEmpty {
            return sha
        }
        return "dev"
    }

    static var deviceIDText: String {
        deviceID ?? "—"
    }

    // MARK: - 业务信息

    /// 设置用户标识（Bugly 控制台可按其筛选崩溃）。
    static func setUserID(_ id: String) {
        guard isStarted else { return }
        Bugly.updateUserIdentifier(id)
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
        Bugly.report(exception)
    }

    /// 以「自定义错误」形式上报：把内部失败（解压失败、签名失败等）也送到 Bugly。
    static func reportCustomError(_ name: String,
                                  reason: String,
                                  stack: [String] = Thread.callStackSymbols,
                                  extra: [String: Any] = [:]) {
        guard isStarted else { return }
        Bugly.reportException(withCategory: 3,   // Cocoa
                              name: name,
                              reason: reason,
                              callStack: stack,
                              extraInfo: extra,
                              terminateApp: false)
    }

    /// 主动上报一条测试错误（验证链路用，不会崩）。
    static func sendTestError() {
        guard isStarted else {
            log("bugly: 测试上报失败 — SDK 未启动")
            return
        }
        let info: [String: Any] = [
            "app": "3105",
            "ios": "\(AppInfo.osVersion) (\(AppInfo.osBuild))",
            "build": buildStamp,
            "time": Date().description,
        ]
        reportCustomError("BuglyTestError",
                          reason: "手动触发的测试错误（忽略即可）",
                          extra: info)
        log("bugly: 已上报测试错误 BuglyTestError")
    }

    /// 制造一次真实崩溃（验证崩溃捕获用）。**会立即终止进程。**
    static func triggerTestCrash() -> Never {
        log("bugly: 触发测试崩溃（进程即将退出）")
        let exception = NSException(name: NSExceptionName("BuglyTestCrash"),
                                    reason: "手动触发的测试崩溃（忽略即可）",
                                    userInfo: nil)
        exception.raise()
        fatalError("BuglyTestCrash")   // 兜底：raise() 若被拦截也会在这里终止
    }

    // MARK: - 私有

    /// AppKey：优先包内注入的资源文件，其次 Info.plist，最后为空。
    private static var appKey: String {
        if let url = Bundle.main.url(forResource: "BuglyAppKey", withExtension: "txt"),
           let key = try? String(contentsOf: url, encoding: .utf8)
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty {
            return key
        }
        if let key = Bundle.main.object(forInfoDictionaryKey: "BuglyAppKey") as? String,
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    /// 上报渠道，在 Bugly 控制台「渠道」维度里展示。
    private static var channel: String {
        #if DEBUG
        return "Debug"
        #else
        return "Direct"
        #endif
    }

    /// 上报版本号需和 Bugly 控制台里填写的版本一致，这里用 App 的版本号。
    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short).\($0)" } ?? short
    }
}
