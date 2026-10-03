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
- 先点入普通输入框，将鼠标放在其中，按住 Option 即可从鼠标位置展开径向文案菜单；触发键可改为 Command 或 Shift。
- 可选择从鼠标位置或输入光标位置展开。光标模式只需输入框已聚焦；无法取得光标坐标时回退到鼠标位置。展开后移动鼠标才会开始选择，避免静止鼠标误选。
- 可以录制独立快捷键，同样采用按住展开、松开收起的方式。
- 鼠标移到文案按钮后高亮，松开触发键即收起菜单、替换系统剪贴板内容并发送一次 `⌘V`。未选中按钮时松开则取消，点击按钮不会立即粘贴。剪贴板会保留该文案，应用不会自动提交或发送内容。
- 全部启用文案同时展开，数量较多时增加外圈，屏幕边缘整组移入屏内，保持对称圆环；无法完整排入当前屏幕时会提示减少启用文案。
- 径向菜单不会抢走输入焦点；原输入框、选区、应用或权限发生变化时取消粘贴。密码框、只读位置和无法确认的输入位置不会写入。
- Esc、其他按键、外部点击、滚动或切换应用会取消操作。组合快捷键松开后会等待剩余修饰键最多 500 ms，超时则取消。

## 安装与授权

项目提供 Apple Silicon 应用构建，最低部署目标为 macOS 14。当前构建使用 ad hoc 签名，尚未公证；首次打开时，macOS 可能要求确认运行应用。

设置页的“系统权限”只保留辅助功能一行。点击“授权”打开系统设置并显示可拖拽的应用卡片，将卡片拖入授权列表，添加 `/Applications/PhrasePerch.app` 并开启权限；返回应用后，同一按钮变为“重启”。重启前会保存配置，重新打开同一路径的应用。

重启后，读取输入位置和粘贴均可用时显示“已就绪”。若仍不可粘贴，同一按钮显示“重新授权”，请在系统设置中重新添加当前应用。较新 macOS 中该权限页名为“设备控制和数据访问”。

当前构建使用 ad hoc 签名，更新可能要求重新授权。系统权限列表若仍显示旧版 `FloatingInputBar.app` 或通用图标，请重新添加固定安装位置的当前 PhrasePerch。应用内部始终复核真实权限，再执行粘贴。

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

默认测试使用离屏渲染，不会在桌面展示测试窗口或快捷菜单。窗口复用、菜单动画和连续开合测试默认跳过；需要专门验证这些可见行为时，在 Xcode 的测试 Scheme 中设置 `PHRASEPERCH_VISIBLE_UI_TESTS=1` 后运行。

项目结构：

```text
PhrasePerch.xcodeproj/ Xcode macOS 应用工程
Info.plist             macOS 应用信息
Sources/               AppKit、SwiftUI 与输入逻辑
Resources/             应用图标与第三方许可
```

## 许可证

PhrasePerch 使用 MIT License，许可条款见 [LICENSE](LICENSE)。第三方依赖 KeyboardShortcuts 3.1.0 也采用 MIT License，文本见 [第三方许可文件](Resources/KeyboardShortcuts-LICENSE.txt)。版本为 0.0.1（build 4）。
