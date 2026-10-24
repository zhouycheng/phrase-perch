# PhrasePerch 1.0.0 验收记录

## 2026-10-25 本轮实现验收

- 完整 XCTest 共 119 项：110 项通过、9 项桌面检查跳过、0 失败。结果：`.build/Logs/Test/Test-PhrasePerch-2026.10.25_01-18-32-+0800.xcresult`。
- Release 构建通过；签名校验通过，产物标识为 `local.PhrasePerch`，版本为 1.0.0。
- `git diff --check` 通过。
- Safari／ChatGPT 真实输入、辅助功能授权及实体多屏：待用户实机验收。

## 2026-10-25 上一页朝向来路

- 进入分组、下一页或返回历史页时，以当前导航节点为期望圆心；新页面的上一页指向本次进入方向的反面，与下一页严格对角。返回根页恢复顶部起始。
- 指定方向后按水平按钮尺寸重新求角度和半径，保持圆周、中心安全区域及至少 12 点边缘间距。屏幕避让整体平移，保留导航发生前确定的方向。
- 定向 XCTest 31 项：29 项执行通过、2 项桌面检查跳过、0 失败，覆盖三种按钮宽度、1–8 槽、16 个方向、分页与多层返回、负坐标边界。证据：`.build/entry-direction-checks.log`。
- 补充分组方向断言及渲染检查 2 项通过，已查看横向与斜向预览。证据：`.build/entry-direction-render.log`、`.build/previews/radial-entry-*.png`。
- Release 构建、签名及差异检查通过，已替换安装版本并打开，安装二进制与 Release 一致。证据：`.build/entry-direction-release.log`。旧包备份于 `~/Library/Application Support/PhrasePerch-Recovery/entry-direction-20261025-005315/PhrasePerch-previous.app`。
- 连续下一页仍可能沿同一方向推进；半径变化和边界避让可能使返回圆心与历史圆心不同。真实交互与系统授权由用户验收。

## 2026-10-25 上一页节点中心展开

- 上一页恢复历史内容、页码和槽位顺序，以当前上一页节点为期望中心展开。边缘整体避让，布局无法容纳时保留当前页并提示。
- 定向 XCTest 21 项：19 项执行通过、2 项桌面检查跳过、0 失败，覆盖连续翻页返回、多层分组返回、负坐标屏幕四边四角定位和空间不足。证据：`.build/previous-node-checks.log`。
- Release 构建和差异检查通过，证据：`.build/previous-node-release.log`。已替换安装版本并打开，安装包签名有效且二进制与 Release 一致。旧包备份于 `~/Library/Application Support/PhrasePerch-Recovery/previous-node-20261025-004400/PhrasePerch-previous.app`。
- 实际交互由用户验收，系统授权保持用户管理。

## 2026-10-25 当前导航与视觉间距

- 层级导航统一以导航节点为中心展开，设置页只保留现有触发方式与初始定位选项。
- 运行时轮盘与编辑预览共享圆角按钮边缘间距计算；长标题按实际字体宽度省略，按钮宽度上限 132 点。
- 上一页恢复历史内容和页码，以当前上一页节点为期望中心展开；上一页和下一页同时出现时保持上下对角。
- 版本 1 旧配置中的 `menuExpansionMode` 被忽略，保存和导出省略该字段，其他偏好字段继续严格校验。
- 定向 XCTest 40 项：38 项执行通过、2 项桌面检查跳过、0 失败，覆盖配置兼容、触发流程、分页、多层返回、边界与标题展示。证据：`.build/navigation-only-checks.log`。
- 实际交互与系统授权由用户验收。
- Release 构建与差异检查通过，证据：`.build/navigation-only-release.log`。已替换 `/Applications/PhrasePerch.app` 并打开；安装包签名校验通过，二进制与 Release 产物一致。旧包位于 `~/Library/Application Support/PhrasePerch-Recovery/navigation-only-20261025-004026/PhrasePerch-previous.app`。

## 2026-10-25 历史节点与布局更新

以下记录对应此前安装版本，展开模式与布局规则以当前记录为准。

- 运行时节点统一为文本、分组、上一页和下一页，共用布局、命中与动作分发。上一页恢复访问记录中的上一张轮盘。
- 默认以导航节点为中心展开，三节点为顶部朝上的三角形、四节点为菱形。上一页与下一页同时出现时采用偶数槽位，下一页位于顶部、上一页位于底部。
- 固定中心模式保持进入方向为空槽，上一页放在正对面；总槽数向上取偶数，额外空位不参与命中和无障碍访问。
- 设置新增层级展开方式，下次打开轮盘生效；旧配置缺少该字段时默认节点中心模式，配置格式仍为 1。
- 授权卡片按系统设置窗口右侧下方区域定位，并跟随窗口识别、移动、缩放和切屏。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 完整 XCTest | 119 项，110 项执行通过，9 项桌面检查默认跳过，0 失败 | `.build/node-tests.log` |
| 原生桌面测试 | 显式启用嵌套导航动画与常驻轮盘点击测试，2 项通过 | `.build/node-native-tests.log` |
| 几何与分页 | 固定中心空槽、导航对角、连续分页、恢复原页、边缘平移及空间不足保留原页通过 | `RadialPagingTests`、`GroupedMenuTests` |
| 设置兼容 | 旧字段缺省、新设置往返、非法值拒绝、下一会话应用通过 | `ConfigurationFormatTests`、`TriggerSessionServiceTests` |
| 授权定位 | 窗口迟到、移动、缩放与负坐标切屏的定位测试通过 | `FloatingMenuTests` |
| 渲染 | 已检查三角形、菱形、八节点、固定中心空位和上下对角导航；设置页四种规定尺寸已渲染并查看 | `.build/previews/radial-*.png`、`.build/previews/page-settings-*.png` |
| Release | 构建通过 | `.build/node-release.log` |

Release 版本已替换至 `/Applications/PhrasePerch.app` 并打开。安装包签名有效，安装二进制与本次 Release 产物校验值一致；旧应用包保存在 `~/Library/Application Support/PhrasePerch-Recovery/1.0.0-20261025/PhrasePerch-previous.app`。按本次操作要求，替换后未运行测试或触碰授权设置。Safari／ChatGPT 的真实输入、授权卡片与系统设置同屏位置及物理多屏由用户实际验收；窗口比例定位随系统设置布局变化可能需要校准。

以下为 2026-10-24 历史验收与交付记录；其中构建、安装及测试结果对应当日版本。

## 历史行为（2026-10-24）

应用身份：`local.PhrasePerch`，版本 1.0.0，build 1，配置格式 1。

- 主窗口默认内容区为 1070 × 620 点，顶部四个按钮为 104 × 28 点。标题与按钮组左对齐，宽窗口横排、窄窗口竖排。
- 首次启动创建 Safari、ChatGPT 两个空配置，默认 Option 按住入口。文案行的图标、标题和空白可点击选中，行尾开关与操作按钮独立响应。
- 每级只有一圈，最多八个槽位，按实际节点数等角度均分，返回和下一页计入容量并参与均分。导航节点常亮高亮色；悬停 180 ms 后进入，以进入节点为中心展开，上一层中心作为圈内返回槽位。空间不足时减少容量并重新均分整圈。
- 导航使用同一父级栈保存内容、布局和页码。切换后清除选择，鼠标重新移动超过三点后才可选中文案；动画与悬停回调检查展示代次。
- Option 按住展开、松开提交；组合快捷键按一次打开，点击提交。输入焦点决定插入或复制，插入继续使用目标核验、单次写入和读回保护。
- 展开、插入和复制成功时保持静默，结果保留在诊断中。失败或写入结果待核验时，在鼠标下方显示原因；屏幕边缘自动避让，文本按控件实际尺寸排版。
- 标题通过手工编辑。配置只接受格式 1，使用原子保存、校验及最近三个有效备份，损坏文件保留并提示恢复。

## 历史自动化结果（2026-10-24）

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 完整 XCTest | 112 项，103 执行通过，9 项桌面检查按开关跳过，0 失败 | `.build/ring-feedback-full-tests.log` |
| 原生轮盘检查 | 两项通过：嵌套分组导航动画、常驻轮盘动画及点击 | `.build/ring-feedback-native-tests.log` |
| 分页导航 | 连续翻页覆盖全部内容、逐级返回、悬停离开取消、过期回调与快速重开通过 | `RadialPagingTests` |
| 布局 | 1～8 项等角度均分、返回参与均分、碰撞与边界、负坐标及屏幕上下排列通过 | `RadialPagingTests`、`GroupedMenuTests` |
| 配置 | 首次预设仅创建一次、格式往返、其他格式拒绝、缺失根节点拒绝、保存失败恢复通过 | `ConfigurationFormatTests`、`ConfigurationRepositoryTests` |
| 输入保护 | 粘贴、直接写入、空白复制、剪贴板竞争及最多一次写入通过 | 输入服务与会话测试 |
| 反馈 | 成功展开、验证插入和复制保持静默，超时反馈、未知目标与 Esc 取消、鼠标下方及屏幕边缘定位通过 | `TriggerSessionServiceTests`、`RadialPagingTests` |
| 界面 | 880×560、960×620、1070×620、1280×800 渲染通过，已检查默认尺寸与导航节点图 | `.build/previews/quick-content-*.png`、`.build/previews/radial-next-page-*.png` |

## 历史本机交付（2026-10-24）

Release 构建、严格签名校验与 `git diff --check` 通过，日志为 `.build/ring-feedback-release.log`。已替换 `/Applications/PhrasePerch.app` 并经 Finder 启动；已核对安装二进制与 Release 产物一致，以及安装路径下的运行进程。

首次配置已确认只有 Safari、ChatGPT 两个空预设，使用 Option、鼠标定位及复制后插入的默认偏好。旧应用与数据回退副本保存在用户资料库的 `Application Support/PhrasePerch-Recovery/1.0.0-20261024/`，旧版登录启动注册已关闭。

用户完成系统确认后，已观察到“设备控制和数据访问”列表显示 PhrasePerch.app、正式应用图标和开启的权限开关，旧命名条目已消失。

桌面控制工具仍把原安装路径解析为旧应用身份，并拒绝连接新标识 `local.PhrasePerch`；已通过 Finder 成功启动新版，但未能读取其主窗口状态。当前自动化结果不代表真实 Safari／ChatGPT 编辑器已完成验收。物理多屏、输入法候选及真实编辑器连续触发仍需独立检查。

AX 直接写入依赖编辑器公开可写选区能力；写入结果不确定时不会重发。真实验收只插入测试文案，不发送消息。

后续交付按用户最新要求直接替换应用并打开；授权和真实应用验收由用户操作。
