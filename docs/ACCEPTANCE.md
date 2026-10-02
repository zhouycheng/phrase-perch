# 测试与验收记录

当前版本：PhrasePerch 0.0.1（build 1） · Apple Silicon · macOS 27.0.1

## 构建

当前 Release 构建成功。产物为 arm64 macOS 应用，最低部署目标 macOS 14；签名为 ad hoc，未公证。A1 应用图标已通过 `Assets.xcassets/AppIcon.appiconset` 编入应用，包内 `CFBundleIconName` 为 `AppIcon`，`codesign --verify --strict` 检查通过。

## 自动化与原生界面检查

Debug XCTest 共 26 项，通过 26 项，失败和跳过均为 0。覆盖应用身份、配置校验与保存、快捷键修饰状态、拖动选区条件、菜单分页、显示动画、取消后的过期回调及权限状态。

原生 AppKit 检查覆盖拖动文件 URL、剪贴板未被拖动过程改动、提示条位置边界和共享单面板行为。权限引导的拖入接受／拒绝收起分支以原生回调验证，不代表已经对系统设置列表完成实机拖入验收。

测试摘要：[CoreTests-summary.json](CoreTests-summary.json)。界面预览：[快捷栏](FloatingBar-preview.png)、[权限引导](Authorization-guide-preview.png)。

## 实机验收状态

| 场景 | 状态 |
| --- | --- |
| 设置页显示权限状态并打开系统授权页面 | 已核验 |
| TextEdit 和 ChatGPT 的应用规则与示例文案 | 配置样本存在 |
| 当前 A1 版本的权限授予与拖入后提示消失 | 待实机确认 |
| TextEdit 中点击、框选、选区替换和焦点保持 | 待实机确认 |
| ChatGPT 草稿真实出现、无重复且未自动发送 | 待实机确认 |
| macOS 14、外接显示器、全屏与减少动态效果 | 待测试 |

当前包采用 ad hoc 签名，更新后 macOS 可能要求重新授权。本机没有固定 Developer ID 证书。

## 复现测试

在项目目录执行：

```bash
xcodebuild -project PhrasePerch.xcodeproj -scheme PhrasePerch \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build test
```

`Tests/Fixtures/input-fixture.html` 是本地浏览器输入页，不联网、不提交内容。`Tools/clipboard-check.swift` 输出剪贴板类型与 SHA-256，便于人工比对，不打印剪贴板正文。
