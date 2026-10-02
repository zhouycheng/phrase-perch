<p align="center"><img src="Resources/AppIcon.png" alt="PhrasePerch app icon" width="128"></p>
<p align="center"><strong>PhrasePerch 是一款原生 macOS 快捷文案工具</strong></p>

<p align="center">
  <a href="#安装与授权"><img src="https://img.shields.io/badge/target-macOS%2014%20%7C%20arm64-000000" alt="Target platform"></a>
  <a href="https://www.swift.org/"><img src="https://img.shields.io/badge/built%20with-Swift%206-F05138" alt="Swift 6"></a>
  <a href="https://developer.apple.com/documentation/appkit"><img src="https://img.shields.io/badge/UI-AppKit%20%2B%20SwiftUI-147EFB" alt="AppKit and SwiftUI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-3DA639" alt="MIT License"></a>
  <br>
  <a href="#核心能力">核心能力</a> ·
  <a href="#安装与授权">安装与授权</a> ·
  <a href="#数据与剪贴板">数据与剪贴板</a> ·
  <a href="#开发">开发</a> ·
  <a href="https://github.com/zhouycheng/phrase-perch/issues">问题反馈</a>
</p>

## 核心能力

- 在单窗口工作台中管理应用规则、快捷文案、触发方式和系统权限；Dock 与菜单栏至少保留一个入口。
- 为不同应用设置独立文案，配置保存在本机；浏览器规则按浏览器生效。
- 默认按住 Option 点击可编辑位置，或拖动选中文字；松开后在鼠标附近显示快捷栏。触发键可改为 Command 或 Shift。
- 可以录制独立快捷键，用于打开或收起快捷栏。
- 点击文案后，PhrasePerch 会替换系统剪贴板内容并发送一次 `⌘V`。剪贴板会保留该文案，应用不会自动提交或发送内容。
- 快捷栏不会激活目标应用；密码框、只读位置和无法确认的输入位置不会写入。

## 安装与授权

项目提供 Apple Silicon 应用构建，最低部署目标为 macOS 14。当前构建使用 ad hoc 签名，尚未公证；首次打开时，macOS 可能要求确认运行应用。

设置页会显示辅助功能和粘贴输入权限状态。点击“授权”后，辅助功能会打开系统设置并显示拖入指引；粘贴输入会请求 macOS 的事件投递权限。权限状态会自动刷新。

辅助功能和粘贴输入权限都已就绪后，快捷栏才能自动粘贴。ad hoc 签名更新可能要求重新授权。应用不会修改系统权限设置。

## 数据与剪贴板

文案和偏好设置保存在 `~/Library/Application Support/local.FloatingInputBar/`。插入时，剪贴板原内容会被文案替换并保留；应用不会自动恢复旧内容，也不会自动发送内容。

单条文案上限为 64 KiB UTF-8，支持中文、Emoji、Tab 和换行。使用中文输入法时，请先提交候选文字，再触发快捷栏。

## 开发

需要 Xcode 27 或兼容的较新 Xcode。快捷键使用 KeyboardShortcuts 3.1.0。

打开工程：

```bash
open PhrasePerch.xcodeproj
```

```bash
xcodebuild -project PhrasePerch.xcodeproj -scheme PhrasePerch \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build build
```

项目结构：

```text
PhrasePerch.xcodeproj/ Xcode macOS 应用工程
Info.plist             macOS 应用信息
Sources/               AppKit、SwiftUI 与输入逻辑
Resources/             应用图标与第三方许可
```

## 许可证

PhrasePerch 使用 MIT License，许可条款见 [LICENSE](LICENSE)。第三方依赖 KeyboardShortcuts 3.1.0 也采用 MIT License，文本见 [第三方许可文件](Resources/KeyboardShortcuts-LICENSE.txt)。版本为 0.0.1（build 4）。
