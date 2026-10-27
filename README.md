<p align="center"><img src="Resources/AppIcon.png" alt="PhrasePerch app icon" width="128"></p>
<p align="center"><strong>PhrasePerch 是一款原生 macOS 快捷内容工具</strong></p>

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

默认工作台内容区为 1070 × 620 点，两组顶部按钮横排；窄窗口自动竖排。点击文案整行可选中，行尾开关和操作按钮独立响应。

- 在单窗口工作台中管理应用规则、快捷文案、触发方式和系统权限。左键点击菜单栏图标打开主窗口，右键显示操作菜单；已最小化的窗口会恢复。
- “静默启动”默认开启，登录自启动时在后台运行；手动打开应用时显示主窗口。主窗口打开或最小化时显示 Dock 图标；“后台运行时隐藏 Dock 图标”控制关闭窗口后的显示，后台至少保留 Dock 或菜单栏中的一个入口。
- 为不同应用设置独立文案，可选择“修饰键”“快捷键”或“两种都启用”；应用规则和文案保存在本机。
- 默认按住 Option 120 ms 展开菜单，移动鼠标选择文案，松开后提交；输入框中插入，普通空白区域复制，未选中则取消。修饰键可改为 Command 或 Shift。
- 录制组合快捷键后，按一次打开常驻轮盘，点击文案提交；再次按快捷键、Esc、外部点击或切换应用关闭菜单。
- 展开位置可选鼠标或输入光标。输入目标始终来自焦点；光标不可用时在输入框可见范围内或鼠标附近展开，界面显示回退原因。
- 两种入口共用单圈轮盘，每圈最多八个槽位。文案、附件、分组、上一页与下一页统一布局；悬停导航节点 180 ms 后切换，“上一页”以反向旋转恢复上一张轮盘。标题显示上限可在设置中调整为 1–30 个字符，默认 10；按钮保持单行并分别向外延伸。空间不足时先减少页容量，再适当省略标题。导航以所选节点为中心展开，上一页与下一页同时出现时严格对角。
- 菜单保持原输入焦点。目标、选区或权限发生变化时取消；密码框和安全输入会明确提示。无法可靠识别的编辑器进入“仅复制”模式。
- 设置中的“文案使用剪贴板粘贴”默认开启：复制并发送一次 `⌘V`。关闭后文案通过可写的 `AXSelectedText` 直接替换选区；附件始终使用剪贴板。失败或写入结果待核验时，在鼠标下方显示原因，靠近屏幕边缘时避让。
- 工具栏支持“添加附件”，也可将一个或多个文件拖入内容列表，按完整文件名添加到当前分组末尾。每个文件生成一个快捷按钮。附件可改标题、替换文件，并参与分组、排序、启停和复制。原文件移动或删除后仍可使用本机副本；接收的文件类型取决于目标应用。
- 编辑区支持创建、重命名、启停及移动分组；分组与文案可混合排序。移除分组会将内容移回父级，嵌套路径便于逐级管理。
- 设置页展示最近 20 次交互的阶段、耗时和定位来源；诊断保存在内存，日志不包含文案正文和输入框全文。

## 安装与授权

项目提供 Apple Silicon 应用构建，最低部署目标为 macOS 14。当前构建使用 ad hoc 签名，尚未公证；首次打开时，macOS 可能要求确认运行应用。

设置页的“系统权限”只保留辅助功能一行。点击“授权”打开系统设置并显示可拖拽的应用卡片，将卡片拖入授权列表，添加 `/Applications/PhrasePerch.app` 并开启权限；返回应用后，同一按钮变为“重启”。重启前会保存配置，重新打开同一路径的应用。

重启后，读取输入位置和粘贴均可用时显示“已就绪”。若仍不可粘贴，同一按钮显示“重新授权”，请在系统设置中重新添加当前应用。较新 macOS 中该权限页名为“设备控制和数据访问”。

应用身份为 `local.PhrasePerch`。使用 `/Applications/PhrasePerch.app` 建立辅助功能授权，系统列表显示 PhrasePerch 及应用图标。当前构建使用 ad hoc 签名，更新可能要求重新授权；应用内部会复核输入与粘贴权限。

## 数据与剪贴板

配置格式为版本 2，读取版本 1 时自动升级并保留原文件备份。首次启动预建 Safari、ChatGPT 两个空配置，使用本机安装包的真实身份；默认启用 Option 按住入口。应用规则、快捷内容、分组和偏好使用原子保存，并保留最近三个有效配置备份。

快捷内容和偏好设置保存在 `~/Library/Application Support/local.PhrasePerch/`。开启“文案使用剪贴板粘贴”时，文案替换并保留在剪贴板；关闭时直接写入。普通空白区域选择内容执行复制。应用不发送 Return。

静默启动、后台 Dock 和菜单栏显示偏好保存在本机 UserDefaults，随当前应用生效。

附件副本位于数据目录的 `attachments/<资源ID>/<文件名>`，复制条目共享资源。回收时保留当前配置、最近三个有效备份、剪贴板和进行中操作引用的附件；文件缺失时可在编辑区重新选择。

导出生成 `.phraseperch` 备份包，包含当前配置和引用的附件副本；导入支持完整备份包及旧 JSON。导入先校验并暂存附件，确认后替换配置，失败时保留当前数据。备份包包含实际文件内容，分享时请核对其中的附件。

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
Sources/App/           启动、依赖组装与生命周期
Sources/Domain/        数据模型、规则与状态机
Sources/Features/      按功能组织的 View、ViewModel、布局与动画
Sources/Services/      编辑、权限、触发与文本插入服务
Sources/Persistence/   配置状态、文件存储与备份
Sources/Platform/      macOS 系统能力适配
Sources/Shared/        可复用组件与样式
Tests/                 分层回归测试与原生预览
Resources/             应用图标与第三方许可
```

架构和职责说明见 [架构文档](ARCHITECTURE.md)。

## 许可证

PhrasePerch 使用 MIT License，许可条款见 [LICENSE](LICENSE)。第三方依赖 KeyboardShortcuts 3.1.0 也采用 MIT License，文本见 [第三方许可文件](Resources/KeyboardShortcuts-LICENSE.txt)。版本为 1.0.0（build 1）。
