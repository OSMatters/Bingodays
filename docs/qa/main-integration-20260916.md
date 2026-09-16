# 本地主分支整合记录 — 2026-09-16

## 范围与历史

- 日常开发保存提交：ee45676（原基线 9a9d625）。
- 盲盒开发保存提交：2dc366d（原基线 f5023a5）。
- iPad 适配：2b368ea。
- 整合提交：3868b2f、317b783；编译修复及新流程说明：9a2f28a。
- 保留日常版本的系统 TabView、分享、棋盘滑动、新图标与同步改动；接入盲盒门户的入口来源识别、导航隐藏和返回逻辑。
- 工程配置保留两侧新增资源/源码；保留分享及盲盒统计方法、双方同步回归测试。
- iPad 使用画布布局计算并保留透明盲盒首页背景。
- 移除未使用的旧盲盒底栏包装组件；拆分拉绳坐标计算，修复完整构建中的类型推断超时。

## 验证

- Debug generic iOS Simulator 完整构建通过（arm64 / x86_64）。日志：/tmp/BingoMainIntegration-20260916-build-final.log。
- Release generic iOS 构建通过，CODE_SIGNING_ALLOWED=NO。日志：/tmp/BingoMainIntegration-20260916-release.log。不是签名归档，也未安装真机或上传。
- 全部资产目录中引用的图片文件均存在。
- 回归复跑：477 项 XCTest，475 项通过、2 项失败（3 条断言）；5 项 Swift Testing 测试通过。日志：/tmp/BingoMainIntegration-20260916-tests-rerun.log；结果：/tmp/BingoMainIntegration-20260916-tests-rerun.xcresult。
- 修正 4 个旧测试的初始化/券数预期，使其符合已有“新账户初始 3 张券”规则。每日赠券测试显式构造空钱包，继续验证日赠规则，不弱化断言。
- 模拟器手动检查通过：顶部积分入口进入自定义奖励；点击拉绳进入盲盒；免费券弹窗；MyBox 入口、三个主题与 Coming Soon；Zodiac 收藏页；返回积分页并恢复系统底栏；底部首页/积分切换。
- 模拟器下拉拖动未确认成功，不记为通过；连续动效、首次引导及所有设备布局还需专项真机验收。

## 已有阻止发布的缺陷（未掩盖失败测试）

1. B11：时钟回拨仍可能获得新的积分兑换资格。
2. B12：同一绝对时间跨时区仍可能重复领取日赠券。

这两项在 docs/designs/sticker-blind-box-regression-report-20260908.md 中已有记录；相关生产规则与盲盒分支一致，并非本次合并新增。此次仅整合代码，不擅自修改时间与时区政策。完整测试仍返回失败，不能宣称全部测试通过。
盲盒正式发布开关维持原状（Release 不启用盲盒），未做真实 iCloud、付费交易或真机验收；发布前必须解决上述问题并另行验收。

## 保全与远程

- 完整备份：/Users/m98/Desktop/BingoADHD-merge-backup-20260916-DJEENn，含两个工作目录及校验通过的 all-branches.bundle。
- 两份会与切换冲突的未跟踪需求/开发文档已移入该备份的 pre-switch-docs；其中 PRD 与分支版本不同，原文保留。
- 其余非应用的文档、素材改动不清理、不纳入功能提交。
- 用户明确确认仅整合本地 main；远程 main 是独立历史，不合并、不推送、不覆盖。旧分支保留。
- 后续唯一开发目录与规则见 docs/main-development-workflow.md。
