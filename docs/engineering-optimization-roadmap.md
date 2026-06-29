# Engineering Optimization Roadmap

## Diagnosis

The app is a SwiftUI iOS project with a working split between models, view models, services, and views, but several boundaries still leak:

- `ContentView` coordinates app lifecycle, presentation state, board switching, review prompts, update prompts, reminders, and persistence side effects.
- `BingoViewModel` owns board mutations, reward settlement, timeout detection, analytics triggers, and direct persistence calls.
- Store types are static global APIs, which makes logic hard to test and makes save paths fan out into board storage, diary storage, points storage, widget reloads, and notification sync.
- A one-second home ticker can invalidate board UI and trigger side effects even when the visible board state has not changed.
- There is no test target, so refactors currently rely on manual checks.

## Guiding Policies

- Avoid a rewrite. Move one boundary at a time and keep each step shippable.
- Keep product behavior stable while reducing side effects per user action.
- Prefer pure domain functions for board rules, timeout detection, rewards, and import/export transforms.
- Put persistence and external systems behind small protocols before deeper refactors.
- Add tests around pure logic before moving large ownership boundaries.

## Phased Plan

### Phase 1: Low-Risk Performance Guardrails

- Avoid publishing unchanged board state during ticker-driven refreshes.
- Debounce task reminder sync and skip notification scheduler work when the effective reminder set is unchanged.
- Cache hot-path date formatters and move repeated display formatting out of cell body computation where practical.
- Keep widget and notification work off the critical first-frame path.

### Phase 2: Testable Domain Core

- Add a unit test target for board reset, reward settlement, visibility windows, timeout detection, and template import.
- Extract `BoardEngine` pure functions from `BingoViewModel`:
  - bingo line calculation
  - board-full completion detection
  - visible-cell projection
  - expired task/board timeout detection
  - forced-task normalization
- Keep the current public `BingoViewModel` API while delegating calculations to the engine.

### Phase 3: Persistence Boundary

- Introduce protocols:
  - `BoardRepository`
  - `PointsRepository`
  - `DiaryRepository`
  - `TaskLibraryRepository`
  - `ReminderScheduler`
  - `WidgetTimelineReloader`
- Adapt current static stores behind default implementations.
- Inject repositories into `BingoViewModel`, `BoardManagementStore`, and account sync code.
- Make save operations return a commit result so UI coordinators can react without duplicating persistence calls.

### Phase 4: Unified Board Commit Path

- Create a `BoardStateCommitter` that persists active board state, named board mirrors, diary deltas, points, widget reloads, and reminders in one explicit place.
- Replace broad `.onChange(of: cells)` persistence with direct commits from board commands.
- Make reminder sync diff-aware so unchanged pending notifications are not removed and recreated.

### Phase 5: View Composition Cleanup

- Split `ContentView` coordination into focused stores:
  - `HomeLifecycleStore`
  - `HomePresentationStore`
  - `AppReviewPromptStore`
  - `LimitedOfferStore`
  - `ReminderSyncStore`
- Convert board cell rendering to a small `BingoCellPresentationState` so timer updates only affect text that actually changes.

## First Milestone Definition

Done means:

- Home ticker no longer publishes identical `cells`.
- Reminder sync calls are debounced from UI state cascades and skipped when reminder inputs are unchanged.
- The optimization roadmap is checked in.
- The project still builds for the `BingoADHD` scheme.

## Stabilization Stop Line

After the current persistence work, stop broad refactoring when these are done:

- Board mutations, named-board snapshot writes, active-board mirror writes, points, diary, reminders, and widget reloads each have one clear owner.
- Hot paths avoid duplicate WidgetKit reloads and unchanged UI publishes.
- The main board/domain rules are in pure helpers or injected repositories, so new feature work does not require touching unrelated storage code.

Remaining optimization should be treated as targeted fixes only, unless a measured performance issue or a specific feature forces a deeper change.

## Progress Log

- Phase 1 guardrails are in place for unchanged visibility refreshes, reminder sync debounce, and cell schedule date formatting.
- `BoardEngine` now owns shared board cache expansion and visible-cell projection for the app, widget intent, and template import paths.
- `BoardEngine` now owns Bingo line detection, board score baselines, and full-board completion checks used by both the app and widget task toggle path.
- `BoardEngine` now owns timeout and scheduled replacement candidate detection, so UI coordinators can react to domain events without duplicating scan rules.
- `BoardEngine` now owns expired task and board countdown resolution transforms, keeping timeout business mutations out of `BingoViewModel` UI event handling.
- `BingoViewModelPersistence` now depends on board, diary, and points repositories instead of binding directly to static stores, creating the first injectable persistence boundary.
- Widget timeline reloads can now be batched by persistence callers, so multi-step board saves can write named boards, active-board mirrors, countdown state, and widget selection before issuing one refresh.
- `BingoViewModelPersistence` now returns an explicit commit result for board, diary, points, and widget side effects, giving future coordinators a stable contract instead of relying on hidden static-store work.
- `BoardManagementStore` now uses an injected board-management repository for named-board snapshots, active-board mirrors, widget task sync, and widget panel selection instead of calling static stores from each workflow.
- `BoardStateCommitter` now centralizes active-board mirror writes, countdown persistence, optional widget panel selection, and widget timeline reload decisions for both ViewModel persistence and board-management flows.
- `BoardManagementStore` now commits named-board snapshots and active-board mirrors through one private helper, reducing duplicated save-and-mirror combinations across select, create, delete, and template import flows.
- Task-start reminder syncing now has an injectable scheduler boundary, moving reminder signatures and notification scheduling details out of `ContentView`.
- `BoardStateCommitter` now lives in its own source file, keeping active-board commit orchestration separate from ViewModel persistence details.
- `BoardResetRuleEngine` now centralizes cross-day/custom reset evaluation and reset snapshot transforms for both in-app resets and widget task toggles, removing duplicated reset rules from the app/widget boundary.
- `BingoDiaryStore` and `BingoTimeoutStore` now live in dedicated model files, shrinking `BingoModels.swift` and isolating persistence helpers from shared domain model definitions.
- Widget panel/task sync storage and widget task toggle mutation rules now live outside `WidgetBoardSwitchIntent.swift`, keeping AppIntent entrypoints separate from cross-process storage and board mutation side effects.
- `BingoADHDTests` now builds the first guardrail tests for board reset rules and widget task toggles, giving future refactors behavior checks beyond compilation.
- Named-board snapshot persistence now returns whether it actually wrote data and skips no-op writes, so board-management and widget-intent flows can avoid redundant WidgetKit reloads.
- Task-start reminder sync now diffs pending notification requests before deleting or scheduling, avoiding full notification teardown when reminder inputs are unchanged.
- `TaskStartReminderSyncStore` now owns reminder-sync signatures and debounce tasks, reducing `ContentView` state ownership while keeping the existing scheduler boundary intact.
- Home board-state observers now pass precise change metadata, so countdown-only or completed-line-only updates can persist board mirrors without triggering task reminder sync.
- `BoardManagementStore.persistBoardState` now skips unchanged board/countdown mirrors without touching `updatedAt`, preventing no-op snapshot writes from cascading into countdown schedule invalidation or reminder sync.
- `HomeBoardSnapshotSyncStore` now owns selected-board snapshot sync results, keeping countdown schedule invalidation and task-reminder sync policy out of `ContentView` helpers.
- `HomeLifecycleWorkStore` now owns the launch/foreground catch-up work plan, making lifecycle side-effect order explicit and testable before deeper timeout/reset extraction.
- `HomeTimeoutWorkStore` now owns countdown ticker work planning, so idle ticks can remain no-ops while live countdown ticks and full maintenance ticks have explicit, tested step order.
- Lifecycle catch-up and countdown ticker maintenance now share one timeout-processing executor in `ContentView`, reducing duplicate expired-countdown/task/replacement/other-board handling.
- `HomeTimeoutWorkStore` now also owns countdown maintenance scheduling and other-board expired-timeout selection, moving more timer-driven pure logic out of `ContentView`.
- `BoardManagementStore.selectBoard` now returns a structured selection result and rejects unknown board IDs, so `ContentView` only invalidates countdown scheduling or syncs task reminders after a real selection change.
- Board create/delete/template import/template replace flows now return the same board-management mutation result, and board rename skips unchanged names without triggering task-reminder sync.
- P2 cleanup narrowed board mutation results to non-optional selected boards, consolidated board side-effect application in `ContentView`, and removed an unused `WidgetKit` import from the home view.
- App Review prompt candidate selection now lives in `HomeAppReviewPromptStore` with explicit evaluation state and guardrail tests, leaving `ContentView` responsible only for UI presentation.
- App Review prompt presentation blocking now uses `AppReviewPromptPresentationState`, keeping overlay/timeout blocker rules testable while preserving debug bypass behavior.
- Limited Offer home-state cleanup, legacy migration, campaign seeding, and unlock checks now live in `LimitedOfferHomeRules`, with no-op state writes skipped in `ContentView`.
