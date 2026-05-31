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

## Progress Log

- Phase 1 guardrails are in place for unchanged visibility refreshes, reminder sync debounce, and cell schedule date formatting.
- `BoardEngine` now owns shared board cache expansion and visible-cell projection for the app, widget intent, and template import paths.
- `BoardEngine` now owns Bingo line detection, board score baselines, and full-board completion checks used by both the app and widget task toggle path.
- Widget timeline reloads can now be batched by persistence callers, so multi-step board saves can write named boards, active-board mirrors, countdown state, and widget selection before issuing one refresh.
