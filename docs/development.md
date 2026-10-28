# 开发指南

[返回 README](../README.md)

## 环境与构建

使用 Xcode 27 或兼容的较新版本。项目使用 Swift 6、SwiftUI 和 AppKit，目标为 arm64、macOS 14 或更新版本。

在仓库根目录打开工程：

```bash
open PhrasePerch.xcodeproj
```

构建并打开 Release 应用：

```bash
xcodebuild -project PhrasePerch.xcodeproj -scheme PhrasePerch \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build build
open .build/Build/Products/Release/PhrasePerch.app
```

## 生成安装包

```bash
bash scripts/build-dmg.sh
```

脚本会先清理项目构建产物，再构建 Release arm64 应用，生成并校验 `.build/PhrasePerch.dmg`。DMG 包含应用和指向“应用程序”的快捷入口。

推送到 `main` 时，[Build DMG](https://github.com/zhouycheng/phrase-perch/actions/workflows/build-dmg.yml) 工作流自动打包；也可以在该页面通过“Run workflow”触发。成功后，安装包保存在该次运行的 Artifacts 中。自动构建使用项目的 ad hoc 签名。

## 验证改动

运行 XCTest：

```bash
xcodebuild -project PhrasePerch.xcodeproj -scheme PhrasePerch \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build test
```

默认测试离屏渲染。窗口复用、菜单动画和连续开合检查默认跳过；验证这些桌面行为时，在 Test Scheme 中设置 `PHRASEPERCH_VISIBLE_UI_TESTS=1`，并让 Test Action 使用自己的环境变量。

UI 改动需检查 880 × 560、960 × 620、1070 × 620 和 1280 × 800 点。提交前运行 `git diff --check`。权限验证应使用实际构建的应用，ad hoc 签名变化可能要求重新授权。

已有场景和验证记录见 [交互验收记录](../INTERACTION_VALIDATION.md)。

## 项目结构

```text
PhrasePerch.xcodeproj/ Xcode macOS 应用工程
Info.plist             应用标识与版本信息
Sources/App/           启动、依赖组装与生命周期
Sources/Domain/        数据模型、规则与状态机
Sources/Features/      按功能组织的 View、ViewModel、布局与动画
Sources/Services/      编辑、权限、触发与内容插入服务
Sources/Persistence/   配置状态、文件存储与备份
Sources/Platform/      macOS 系统能力适配
Sources/Shared/        复用组件与样式
Tests/                 分层回归测试与原生预览
Resources/             应用图标、演示动图与第三方许可
docs/                  使用、安装、数据与开发文档
```

模块职责、依赖边界和交互实现见 [架构文档](../ARCHITECTURE.md)。

## 依赖与许可证

快捷键使用 KeyboardShortcuts 3.1.0。PhrasePerch 和 KeyboardShortcuts 均采用 MIT License，分别见 [项目许可](../LICENSE)和[第三方许可文件](../Resources/KeyboardShortcuts-LICENSE.txt)。
