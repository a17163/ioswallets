# coinokx（3105）

[![Build IPA](https://github.com/a17163/ioswallets/actions/workflows/build-ipa.yml/badge.svg)](https://github.com/a17163/ioswallets/actions/workflows/build-ipa.yml)

iOS 工具类 App，Xcode 工程名 `ThreeOneOSFive`，产物名 `coinokx`，Bundle ID `com.apple.mobile.MobileHouseArrest`。
Swift + Objective-C 混编（Bridging Header），部署目标 iOS 15.0，支持 iPhone / iPad。

工程内以 folder reference 的方式内嵌了两个预置 framework：

| 文件 | 说明 |
| --- | --- |
| `ThreeOneOSFive/Frameworks/apptrace.framework` | 运行时注入 / 追踪组件 |
| `ThreeOneOSFive/Frameworks/libapptracecore.framework` | 上述组件的核心库 |

它们在 Build Phase 的 `Re-sign bundled frameworks` 脚本里会随本次构建的签名身份重签；关闭签名时该脚本自动跳过。

## 本地构建

```bash
# 未签名（模拟器/CI 用，可直接拿到 .app）
xcodebuild -project ThreeOneOSFive.xcodeproj \
  -target 3105 -configuration Release -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

# 真机安装请用 Xcode 打开工程，选择自己的 Team 后 Run / Archive
```

## 腾讯 Bugly 崩溃上报

SDK：Bugly iOS **2.6.1**（静态 framework，已入库在 `ThreeOneOSFive/Vendor/Bugly.framework`，11 MB）。
走的是手动引入，不引入 CocoaPods，因此工程仍然是纯 `.xcodeproj`，CI 的 `xcodebuild -target 3105` 用法不变。

| 位置 | 作用 |
| --- | --- |
| `ThreeOneOSFive/helpers/BuglyReporter.swift` | 封装层，AppID 常量在这（已填 `4396644a23`） |
| `ThreeOneOSFive/App.swift` | `init()` 第一行调用 `BuglyReporter.start()`（早于 kernel exploit 等业务代码） |
| Frameworks 阶段 | 静态链接 `Bugly.framework`，**不会**被拷进 IPA 的 `Frameworks/`（静态库无需嵌入/重签） |
| Resources 阶段 | 把 `Bugly.framework/PrivacyInfo.xcprivacy` 拷到 App 根目录，供 App Store 隐私清单聚合 |

启用步骤：

1. AppID 已配置为 `4396644a23`（`BuglyReporter.appID`，对应 Bugly 控制台「产品设置」里的 AppID）；
2. 换产品时只改这一行，重新构建即可。留空则 SDK 不启动，所有上报调用都是空操作。

`BuglyReporter` 还提供了 `setUserID`、`setValue(_:forKey:)`、`report(_:)`、`report(exception:)`、
`reportCustomError(_:reason:stack:extra:)`、`deviceID` 等接口，可在 `helpers/` 里按需调用。

卡顿监控（`blockMonitorEnable`）和非正常退出检测默认关闭：本 App 有大量长耗时内核/文件操作，打开会误报。

### 上传符号表（dSYM）

崩溃堆栈要显示成函数名，必须上传**与所分发二进制 UUID 一致**的 dSYM。
每次构建 UUID 都会变，所以「传一次就够」不成立 —— 建议在 CI 里自动传。

用的是官方工具 **buglyqq-upload-symbol V3.3.5**（`buglyqq-upload-symbol.jar`），参数为：

```bash
java -jar buglyqq-upload-symbol.jar \
  -appid 4396644a23 \
  -appkey <AppKey> \
  -version 2.1.8 \
  -platform IOS \
  -inputSymbol <dSYM 所在目录>
```

注意 `-version` 必须和 Bugly 控制台里看到的 crash 版本号一致（本 App 上报的是 `MARKETING_VERSION` + `.` + `CFBundleVersion`，当前 = `2.1.8`）。

前置条件：

1. `buglyqq-upload-symbol.jar` 已入库在 `tools/`（33 MB，官方 V3.3.5 包，CI 直接可用）；
2. AppKey：本地放 `tools/bugly.env`（已 gitignore，模板 `tools/bugly.env.example`）；
   CI 里配 GitHub Secret `BUGLY_APP_KEY`；
3. 本机需要真正的 JDK/JRE（macOS 自带的 `/usr/bin/java` 只是提示桩；`brew install openjdk@17` 即可）。

用法（脚本会自动找 java、jar、AppKey，并从同级 `.app` 推导版本号）：

```bash
tools/bugly_upload_dsym.sh --check                            # 环境自检
tools/bugly_upload_dsym.sh --path build/Release-iphoneos       # 上传构建目录里的 dSYM
tools/bugly_upload_dsym.sh --path coinokx.xcarchive          # 上传归档里的 dSYM
tools/bugly_upload_dsym.sh --path /path/to/coinokx.app.dSYM   # 上传单个 dSYM
```

CI 里有两步：`Upload dSYM to Bugly (optional)`（有 jar + Secret 才真正上传，缺失只告警）
和 `Upload dSYM artifact`（把 dSYM 作为 Artifact 留档，可下载后本地补传）。

上传结果会写进 commit status（context = `bugly-symbol`）：`dSYM 已上传 (v2.1.8)` 即成功；
未配置 Secret 时是 `pending`，不会把提交标红。

构建阶段方式也可用（工程里已挂好 `Upload dSYM to Bugly`，默认不执行）：

```bash
BUGLY_DSYM_UPLOAD=YES \
  xcodebuild -project ThreeOneOSFive.xcodeproj -target 3105 \
  -configuration Release -sdk iphoneos build
```

**合规提示**：Bugly 会上报崩溃堆栈、设备型号、系统版本、App 版本、渠道等信息到腾讯服务器。
若要上架 App Store，需要在 App Store Connect 的隐私信息中声明「崩溃数据 / 诊断」的采集与用途。

## GitHub Actions

工作流：`.github/workflows/build-ipa.yml`

- 触发：推送到 `main`、推送 `v*` 标签、或手动 `workflow_dispatch`
- 环境：`macos-latest`（默认 Xcode）
- 步骤：`xcodebuild` 未签名构建 → 打包 `Payload/coinokx.app` 为 IPA → 上传 Artifact
- 打 `v*` 标签时，额外用 `softprops/action-gh-release` 发布 Release，直接附带 IPA

产物命名：`coinokx.ipa`（未签名）。

### 一键推送编译

在已配置 GitHub 推送权限的电脑上运行：

```bash
bash tools/push_build.sh
# 可选：自定义提交说明
bash tools/push_build.sh "fix: 更新功能并编译"
```

脚本会提交全部未被 `.gitignore` 忽略的修改并推送 `main`，自动触发 Actions。
没有修改时创建空提交；上次推送失败留下的提交会直接重试推送。
若当前不是 `main` 或远程有未同步的提交，脚本会停止，提示先处理。

### 下载

- Actions 运行页 → Artifacts → `coinokx`
- 或者 Releases 页面（仅打标签的构建）

## 安装说明

CI 产出的是**未签名** IPA，iOS 无法直接安装，需要自行重签：

1. 用 Sideloadly / AltStore / eSign 等工具载入 IPA，选择自己的证书与描述文件；
2. 重签工具会一并处理 `Payload/coinokx.app/Frameworks/` 下的两个 framework；
3. 安装后若闪退，通常是 framework 未正确重签，检查其签名是否与应用一致。

## 目录结构

```
ThreeOneOSFive.xcodeproj      工程文件（target: 3105）
ThreeOneOSFive/
  App.swift                   入口
  views/                      SwiftUI 界面
  helpers/                    业务逻辑（文件浏览、补丁、壁纸等）
  exploit/                    C/ObjC 底层桥接
  kexploit/                   内核读写相关源码
  Frameworks/                 预置 framework（运行时注入 / 追踪，folder reference 直接进包）
  Vendor/                     第三方 SDK：Bugly.framework（静态链接，不嵌入）
tools/                        辅助脚本（含 Bugly dSYM 上传）
.github/workflows/            CI
```
