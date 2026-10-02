<p align="center"><img src="Assets.xcassets/AppIcon.appiconset/icon_512x512.png" alt="PhrasePerch app icon" width="128"></p>
<p align="center"><strong>PhrasePerch 是一款为 macOS 设计的悬浮文案快捷栏</strong></p>

<p align="center">
  <a href="#安装与授权"><img src="https://img.shields.io/badge/target-macOS%2014%20%7C%20arm64-000000" alt="Target platform"></a>
  <a href="https://www.swift.org/"><img src="https://img.shields.io/badge/built%20with-Swift%206-F05138" alt="Swift 6"></a>
  <a href="https://developer.apple.com/documentation/appkit"><img src="https://img.shields.io/badge/UI-AppKit%20%2B%20SwiftUI-147EFB" alt="AppKit and SwiftUI"></a>
  <br>
  <a href="#核心能力">核心能力</a> ·
  <a href="#安装与授权">安装与授权</a> ·
  <a href="#开发">开发</a> ·
  <a href="docs/ACCEPTANCE.md">测试记录</a> ·
  <a href="https://github.com/zhouycheng/PhrasePerch/issues">问题反馈</a>
</p>

## 核心能力

- 单窗口工作台使用图标侧栏：首页预览快捷栏胶囊，设置中管理触发、权限和启动入口；Dock 与菜单栏至少保留一个入口。
- 为不同应用维护各自的文案按钮，配置保存在本机。
- 默认按住 Option 点击输入框，或按住它拖动选择文字；松开后在鼠标旁显示快捷栏。触发键可改为 Command 或 Shift。
- 也可以录制独立快捷键。规则按应用匹配，浏览器规则覆盖整个浏览器。
- 点击按钮后，PhrasePerch 将文案写入系统剪贴板并投递一次 `⌘V`。剪贴板会被该文案替换并保留，应用不会自动发送内容。
- 快捷栏不激活目标应用，选择文案后淡出；密码框、只读位置和无法确认的输入位置不会写入。

## 安装与授权

项目提供 Apple Silicon 开发构建，最低部署目标为 macOS 14。当前构建使用 ad hoc 签名，尚未公证；macOS 可能要求确认打开应用并单独授予输入权限。

设置页会分别显示辅助功能和粘贴输入状态。未授权时，点击对应行的“授权”：辅助功能会打开系统设置并显示拖入指引；粘贴输入会请求 macOS 的事件投递授权。将 PhrasePerch 加入系统列表并开启开关后，页面会自动刷新状态，已就绪的权限显示绿色“已授权”。

辅助功能和粘贴事件权限都需要可用，快捷栏才会自动粘贴。ad hoc 签名更新可能让 macOS 要求重新授权。应用不修改系统权限开关。

## 数据与剪贴板

文案配置保存在 `~/Library/Application Support/local.FloatingInputBar/`。插入时，剪贴板原内容会被替换；PhrasePerch 不会自动恢复旧内容。每次最多投递一次 `⌘V`，不自动发送，也不重试。

单条文案上限为 64 KiB UTF-8。支持中文、Emoji、Tab 和换行。中文输入法候选文字请先提交，再触发快捷栏。

## 开发

需要 Xcode 27 或兼容的较新 Xcode。依赖 KeyboardShortcuts 3.1.0 已固定在 `Package.resolved`。

打开工程：

```bash
open PhrasePerch.xcodeproj
```

```bash
xcodebuild -project PhrasePerch.xcodeproj -scheme PhrasePerch \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build build

xcodebuild -project PhrasePerch.xcodeproj -scheme PhrasePerch \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build test
```

项目结构：

```text
Assets.xcassets/       应用图标
Sources/               AppKit、SwiftUI 与输入逻辑
Tests/                 自动化测试及浏览器输入夹具
Tools/                 剪贴板状态检查工具
Resources/             第三方依赖许可
docs/                  使用验收记录和构建资料
```

## 许可

仓库暂不附 PhrasePerch 代码许可证。KeyboardShortcuts 依赖按 MIT License 发布，许可文本见 [第三方许可文件](Resources/KeyboardShortcuts-LICENSE.txt)。版本为 0.0.1（build 4）。
