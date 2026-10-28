# Bingodays Mac

原生 SwiftUI 桌面入口，最低系统版本为 macOS 26。使用现有棋盘、任务规则、积分、日记记录和原生 iCloud 数据模型。

## 桌面使用方式

日常入口为原生 macOS WidgetKit 桌面小组件：只显示棋盘、任务文字、完成状态和所选皮肤，不含标题栏、侧边栏、工具栏或进度区。点击棋盘会通过 `bingodays-mac://board/<UUID>` 打开对应棋盘的操作窗口。

首次运行应用后，在桌面空白处右键 → 编辑小组件 → 搜索 Bingodays → 添加「桌面棋盘」。支持小号和大号方形布局。添加后可关闭操作窗口，小组件仍保留在桌面。应用工具栏「桌面棋盘」中也有放置说明。

小组件跟随操作窗口当前选中的棋盘。任务、主题或皮肤修改后发布只读快照并请求 WidgetKit 刷新。快照还包含未来 14 天的本地规则投影，用于窗口关闭后的每日重置与定时可见性展示；这些投影不修改任务、积分或日记。真实刷新时机由 macOS 调度。

`BingodaysMacWidget` 已嵌入 Mac 应用。小组件和主应用之间需要有效的 App Group 签名权限；无签名本机版本可验证操作界面，但不能验证系统小组件共享真实数据。应用关闭期间来自其他设备的云端变更，仍需主应用接收同步后才会发布到桌面快照。

## 运行

在 `BingoADHD.xcodeproj` 中选择 `BingodaysMac` Scheme 和 My Mac。

已为团队 `R2372567GG` 配置 Mac 主应用与小组件的开发描述文件。本机签名构建可用：

```sh
xcodebuild -project BingoADHD.xcodeproj -scheme BingodaysMac \
  -configuration Debug -destination 'platform=macOS' \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
```

需要验证无签名编译时可使用：

```sh
xcodebuild -project BingoADHD.xcodeproj -scheme BingodaysMac \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

未获得 App Group 权限的构建使用应用自己的 Application Support 子目录和标准偏好设置。获得权限的签名构建使用原有 App Group。两种开发运行方式的文件目录不同，请勿将无签名构建用于正式跨设备同步验证。

## 功能

- 左侧切换、新建、重命名、排序和删除棋盘。
- 点击已有任务完成或取消完成，点击空白格添加任务；悬停按钮或右键进入编辑。
- 右侧编辑任务名称、强制任务、重复规则、时间、预计时长及开始提醒。
- 整理模式允许拖动任务位置；更多菜单提供棋盘大小、倒计时、打乱、重置和清空。
- 外观面板切换八种主题配色与已有免费背景皮肤。会员皮肤目前引导前往移动端，尚未实现 Mac 跨端会员权益识别。
- 完成任务沿用积分及日记记录规则；移动端功能通过侧栏入口引导。
- Command-N 新建棋盘，Command-Shift-N 添加任务，编辑器中 Command-S 保存、Esc 关闭。

Mac 资源目录中的背景图片为指向原始设计资源的相对符号链接，保留原图并避免复制。Mac 使用 2× 资源声明，iOS 的 3× 声明不变。

## iCloud 签名配置

Bundle ID 为 `com.bingoday.app.mac`，Team 为现有项目团队。

主应用的 `Mac Team Provisioning Profile: com.bingoday.app.mac` 已关联：

- App Group：`group.com.bingoday.app`
- iCloud CloudKit 容器：`iCloud.com.bingoday.app.coredata`
- iCloud Key-Value Store：现有 `com.bingoday.app` 标识

小组件 Bundle ID 为 `com.bingoday.app.mac.widget`。已注册专用 App ID，并将 `Bingodays Mac Widget Development 2026` 描述文件关联到同一个 App Group；Debug 构建显式使用此描述文件。扩展只读取快照，不直接访问 CloudKit。Release 的 Mac App Store 分发描述文件需在发布前单独配置。

缺少 iCloud entitlement 时，Mac 设置会禁用同步开关。真实双端同步、账号切换、离线后合并和通知权限仍需在有效签名构建中进行设备验收。

## 自动化验证

```sh
xcodebuild -project BingoADHD.xcodeproj -scheme BingodaysMacTests \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO test
```

该独立测试 Target 以共享代码和内存仓库验证数据兼容、隐藏格子、Bingo 判定、定时可用性、每日重置、任务编辑、积分和撤销持久化，不启动主应用。

普通构建可复用 Xcode 默认 DerivedData。与本 checkout 的 iOS 编译并行时，Mac 构建和测试统一复用固定目录 `~/Library/Developer/Xcode/DerivedData/BingodaysMac-BingoADHD2`，通过 `-derivedDataPath` 指定；不要并发运行共用该目录的构建。

2026-10-26 验证结果：Mac 无签名构建通过，8 项 Mac 测试通过，现有 iOS Simulator 构建通过。实际窗口已验证任务添加、保存、完成、撤销完成、重启持久化、主题与背景切换，以及移动端引导入口。

桌面小组件更新：应用与嵌入的 WidgetKit 扩展均通过无签名构建，12 项 Mac 测试通过（含桌面快照、深链接和定时展示边界）。随后完成本机 Mac 设备注册及主应用、小组件开发签名；两份嵌入描述文件均包含 `group.com.bingoday.app`。签名版完整构建与 `codesign --verify --deep --strict` 通过，应用已安装到 `~/Applications/BingodaysMac.app` 并启动，WidgetKit 扩展已由系统登记，共享棋盘快照已写入 App Group。桌面手动添加与点击唤起仍待 UI 验收。
