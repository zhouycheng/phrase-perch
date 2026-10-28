# 安装与授权

[返回 README](../README.md)

## 下载与安装

PhrasePerch 支持 Apple Silicon Mac，系统需 macOS 14 或更新版本。

1. 登录 GitHub，打开 [Build DMG 下载页](https://github.com/zhouycheng/phrase-perch/actions/workflows/build-dmg.yml)。
2. 选择最近一次成功的运行，在 Artifacts 区域下载 `PhrasePerch.dmg`。
3. 打开 DMG，将 PhrasePerch 拖入“应用程序”，再从那里启动。

当前安装包使用 ad hoc 签名，尚未经过 Apple 公证。首次打开时，macOS 可能显示运行确认或安全提示；请核对下载来源后按系统提示处理。

## 首次授权

PhrasePerch 需要辅助功能权限来读取输入位置和粘贴内容。应用会按当前权限状态显示引导，也可以在“设置”的“系统权限”中操作。

1. 点击“授权”，打开系统设置和应用拖拽卡片。
2. 将卡片中的 PhrasePerch 拖入系统权限列表，开启开关。安装在“应用程序”中的路径为 `/Applications/PhrasePerch.app`。
3. 返回 PhrasePerch，点击“重启”。应用会先保存配置，再重新打开。

重启后显示“已就绪”，即可使用快捷菜单。若按钮显示“重新授权”，请在系统权限列表中重新添加当前应用，开启权限后再次重启。

## 更新应用

下载新的 DMG，退出 PhrasePerch 后替换“应用程序”中的旧版本。配置和附件保存在本机数据目录，位置见 [数据与备份](data.md)。

应用标识为 `local.PhrasePerch`。当前构建使用 ad hoc 签名，更新后可能需要重新授权；请以应用显示的权限状态为准。
