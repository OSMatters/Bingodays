# Sticker 盲盒：分支、Worktree 与发版协作规范

状态：已启用  
建立日期：2026-09-02  
盲盒基线：`9a9d625`（`release: prepare 4.2.0`）  
盲盒长期分支：`codex/sticker-blind-box`

## 1. 当前仓库的特殊情况

当前实际发布开发线是 `codex/optimization-checkpoint`。本地 `main`、`origin/main` 和该发布线不是可以安全直接合并的同一条历史：`origin/main` 与当前发布线来自不同根提交，不能使用普通 merge、rebase 或 pull 把它们拼在一起。

在单独完成仓库历史整理前：

- `codex/optimization-checkpoint` 作为常规版本的事实发布线。
- `codex/sticker-blind-box` 作为盲盒功能的长期集成线。
- 不从 `origin/main` 创建 release、hotfix 或盲盒分支。
- 不向 `main`/`origin/main` 强推，不使用 `--allow-unrelated-histories`。

这条限制是为了避免把两套完整工程历史强行混合。未来如果要恢复标准 `main` 工作流，应把它作为一次独立的仓库治理任务：先备份所有分支和标签，再明确哪条历史是唯一产品真相，最后在 GitHub 侧切换默认分支。不能和盲盒开发同时处理。

## 2. 两个固定工作目录

| 用途 | 路径 | 固定分支 |
| --- | --- | --- |
| 常规版本、紧急修复、App Store 发版 | `/Users/m98/Desktop/BingoADHD 2` | `codex/optimization-checkpoint` |
| Sticker 盲盒长期开发 | `/Users/m98/Desktop/BingoADHD BlindBox` | `codex/sticker-blind-box` |

两个目录通过 Git worktree 共用对象数据库，但拥有独立工作区和分支。任何任务开始前都必须检查当前目录与分支，禁止在常规版本目录实现盲盒，也禁止在盲盒目录打包不含盲盒的常规版本。

检查命令：

```bash
pwd
git branch --show-current
git status --short
```

## 3. 常规版本发布流程

常规版本继续在 `/Users/m98/Desktop/BingoADHD 2` 完成。当前目录已有大量未提交修改，第一次继续发版前必须先按功能归类、测试和提交，不能用一个笼统提交全部打包。

推荐流程：

1. 在 `codex/optimization-checkpoint` 上完成与盲盒无关的当前修改。
2. 按独立功能拆分提交，并完成构建与测试。
3. 准备发布时创建短期分支 `codex/release-X.Y.Z`，只接受发布修复。
4. App Store 归档必须来自已经提交的 release commit，不能从脏工作区归档。
5. 发布完成后创建 `vX.Y.Z` annotated tag。
6. 把 release 分支合回 `codex/optimization-checkpoint` 并推送。
7. 再把更新后的发布线合入 `codex/sticker-blind-box`。

紧急修复使用 `codex/hotfix-X.Y.Z`，从最近线上 tag 创建；修复发布后同时合回常规发布线和盲盒分支。

## 4. 盲盒开发流程

盲盒开发只在 `/Users/m98/Desktop/BingoADHD BlindBox` 进行，并遵循 [`sticker-blind-box-development-plan.md`](./sticker-blind-box-development-plan.md) 的第 0–9 轮。

每轮规则：

1. 开始前确认盲盒 worktree 干净，并同步最新远端盲盒分支。
2. 一轮只完成计划中声明的范围，不顺手加入常规功能。
3. 规则、迁移、CloudKit 事务和 UI 分开提交；资产变化单独提交。
4. 自动化测试和本轮退出条件通过后，才推送该轮检查点。
5. 每轮结束记录测试证据、开关状态和回退方法。
6. 未完成轮次不进入发布线，也不允许为了“先看看”而合入常规版本。

建议提交前缀：

- `docs(blindbox): ...`
- `test(blindbox): ...`
- `feat(blindbox): ...`
- `fix(blindbox): ...`
- `chore(blindbox): ...`

不要求为每轮永久保留一个远端子分支；长期集成分支上的小提交和清晰检查点更容易维护。只有第 4 轮统一积分钱包、第 5 轮 CloudKit 开盒事务、第 7 轮发布后台等高风险工作，才临时创建 `codex/blindbox-rN-*`，验证后合回盲盒分支并删除临时分支。

## 5. 常规发布线同步到盲盒

同步方向固定为：

```text
codex/optimization-checkpoint  ───────▶  codex/sticker-blind-box
          常规发布线                         盲盒长期线
```

盲盒未完成前禁止反向合并整条盲盒分支。同步应在以下时间发生：

- 每个常规版本发布并打 tag 后。
- 发布线出现与盲盒相关代码区域的重大重构后。
- 盲盒进入第 4、5、7、8 轮之前。
- 最终合并前。

长期远端分支同步使用 merge，不对已经推送的盲盒历史反复 rebase 或 force-push。发生冲突时在盲盒 worktree 解决并重新执行该轮全部测试。

如果盲盒开发中发现一个线上也需要的通用修复：先从常规发布线创建独立 fix/hotfix 分支完成并发布，再由发布线合入盲盒。不要把带有盲盒依赖的提交 cherry-pick 到常规发布线。

## 6. 最终合并与生产灰度

只有满足以下条件，才允许把盲盒合入常规发布线：

- PRD 验收项完成。
- 开发计划第 0–8 轮退出条件全部通过。
- 最新常规发布线已经合入盲盒，且没有未解决冲突。
- CloudKit development、TestFlight、迁移、跨设备、断网和杀进程恢复测试通过。
- 生产 Manifest、回滚和 `emergencyStopBlindBox` 已验证。
- 所有盲盒功能开关在生产默认关闭。

最终流程：

1. 冻结盲盒功能范围。
2. 将最新 `codex/optimization-checkpoint` 合入盲盒分支。
3. 执行完整构建、自动化测试和 TestFlight 验收。
4. 从常规发布线创建最终 release 分支。
5. 在 release 分支中合入 `codex/sticker-blind-box`，不 squash 掉关键迁移和事务检查点。
6. 功能开关关闭状态下归档并提交审核。
7. 审核通过后按开发计划第 9 轮远程灰度。
8. 稳定后将 release 结果合回常规发布线并打 tag。

## 7. 禁止事项

- 不在脏工作区创建 release tag 或 App Store archive。
- 不把未提交文件通过切换分支“带到”另一个功能。
- 不直接合并当前 `origin/main`。
- 不使用 `git reset --hard`、强推或清理未跟踪文件来整理当前工作区。
- 不把 CloudKit production schema/Manifest 变更与未验证的客户端代码同时上线。
- 不因为盲盒分支存在就省略运行时功能开关和远程紧急停止。

## 8. 每次任务的固定开场检查

后续任何 Codex 或人工开发任务开始时，先声明任务属于哪条线：

- “这是常规版本任务” → 使用 `/Users/m98/Desktop/BingoADHD 2`。
- “这是盲盒任务” → 使用 `/Users/m98/Desktop/BingoADHD BlindBox`。

如果请求同时包含两条线，先拆成两个独立提交/任务，再按“常规发布线先完成，盲盒线随后同步”的顺序执行。

