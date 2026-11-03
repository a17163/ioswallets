# 3105 (向阳)

[![Build IPA](https://github.com/lin-yang-7/3105/actions/workflows/build-ipa.yml/badge.svg)](https://github.com/lin-yang-7/3105/actions/workflows/build-ipa.yml)

iOS 工具类 App，Xcode 工程名 `ThreeOneOSFive`，产物名 `XiangYang`，Bundle ID `com.yangjiii.3105`。
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

## GitHub Actions

工作流：`.github/workflows/build-ipa.yml`

- 触发：推送到 `main`、推送 `v*` 标签、或手动 `workflow_dispatch`
- 环境：`macos-latest`（默认 Xcode）
- 步骤：`xcodebuild` 未签名构建 → 打包 `Payload/XiangYang.app` 为 IPA → 上传 Artifact
- 打 `v*` 标签时，额外用 `softprops/action-gh-release` 发布 Release，直接附带 IPA

产物命名：`3105-v<CFBundleShortVersionString>-<CFBundleVersion>-unsigned.ipa`，例如 `3105-v2.0-8-unsigned.ipa`。

### 下载

- Actions 运行页 → Artifacts → `3105-unsigned-ipa`
- 或者 Releases 页面（仅打标签的构建）

## 安装说明

CI 产出的是**未签名** IPA，iOS 无法直接安装，需要自行重签：

1. 用 Sideloadly / AltStore / eSign 等工具载入 IPA，选择自己的证书与描述文件；
2. 重签工具会一并处理 `Payload/XiangYang.app/Frameworks/` 下的两个 framework；
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
  Frameworks/                 预置 framework
.github/workflows/            CI
```
