import CloudKit
import CoreData
import XCTest
@testable import Bingodays

final class NativeICloudPersistenceTests: XCTestCase {
    func testSecondarySnapshotRoundTripsCompletionHistoryWithoutChangingTaskHistorySchema() throws {
        let snapshot = NativeICloudSecondaryStateSnapshot(
            taskLibrary: MyTasksLibrary(),
            taskHistory: [],
            taskCompletionHistory: [
                TaskCompletionHistoryRecord(
                    key: "focus",
                    completionCount: 12,
                    lastArchivedAt: Date(timeIntervalSince1970: 1_800_000_000)
                )
            ]
        )

        let decoded = try JSONDecoder().decode(
            NativeICloudSecondaryStateSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        XCTAssertEqual(decoded.schemaVersion, NativeICloudSecondaryStateSnapshot.schemaVersion)
        XCTAssertEqual(decoded.taskCompletionHistory, snapshot.taskCompletionHistory)
    }

    func testManualSyncWaitConfirmsOnlyAFinishedExpectedCloudEvent() async throws {
        let runtime = NativeICloudRuntime()
        let checkpoint = await runtime.cloudActivityCheckpoint()
        let setupEvent = NativeICloudMirroringEvent(
            kind: .setup,
            isFinished: true,
            succeeded: true,
            occurredAt: Date(timeIntervalSince1970: 1_800_000_000),
            errorDescription: nil
        )
        await runtime.handleCloudKitEvent(setupEvent)

        let timeoutResult = try await runtime.waitForFinishedCloudActivity(
            after: checkpoint,
            expectedKinds: [.importData],
            timeout: 0
        )
        XCTAssertNil(timeoutResult)

        let exportEvent = NativeICloudMirroringEvent(
            kind: .exportData,
            isFinished: true,
            succeeded: true,
            occurredAt: Date(timeIntervalSince1970: 1_800_000_001),
            errorDescription: nil
        )
        await runtime.handleCloudKitEvent(exportEvent)

        let confirmed = try await runtime.waitForFinishedCloudActivity(
            after: checkpoint,
            expectedKinds: [.exportData],
            timeout: 0
        )
        XCTAssertEqual(confirmed, exportEvent)
    }

    func testManualSyncWaitSurfacesFinishedCloudFailure() async {
        let runtime = NativeICloudRuntime()
        let checkpoint = await runtime.cloudActivityCheckpoint()
        let failedEvent = NativeICloudMirroringEvent(
            kind: .exportData,
            isFinished: true,
            succeeded: false,
            occurredAt: Date(timeIntervalSince1970: 1_800_000_000),
            errorDescription: "Network unavailable"
        )
        await runtime.handleCloudKitEvent(failedEvent)

        do {
            _ = try await runtime.waitForFinishedCloudActivity(
                after: checkpoint,
                expectedKinds: [.exportData],
                timeout: 0
            )
            XCTFail("Expected the finished CloudKit failure to be surfaced.")
        } catch let error as NativeICloudMirroringFailure {
            XCTAssertEqual(error.event, failedEvent)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCloudModelMeetsCoreDataCloudKitBaselineRules() throws {
        let model = NativeICloudConfiguration.makeManagedObjectModel()
        let entity = try XCTUnwrap(model.entitiesByName[NativeCloudStateEnvelope.entityName])

        XCTAssertTrue(entity.uniquenessConstraints.isEmpty)
        XCTAssertTrue(entity.relationshipsByName.isEmpty)
        XCTAssertFalse(entity.attributesByName.isEmpty)

        for attribute in entity.attributesByName.values {
            XCTAssertTrue(
                attribute.isOptional || attribute.defaultValue != nil,
                "\(attribute.name) must be optional or have a default value for CloudKit mirroring."
            )
        }
    }

    func testInMemoryContainerCanPersistAndFetchAnEnvelope() async throws {
        let controller = try NativeICloudPersistenceController(mode: .inMemory)
        try await controller.load()

        let commitID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let payload = Data("native-cloud-test".utf8)

        try await controller.container.performBackgroundTask { context in
            let envelope = NativeCloudStateEnvelope(context: context)
            envelope.domain = "primaryState"
            envelope.payload = payload
            envelope.modifiedAt = timestamp
            envelope.commitID = commitID
            envelope.schemaVersion = 1
            try context.save()
        }

        let viewContext = controller.container.viewContext
        let fetched = try await viewContext.perform {
            let request = NativeCloudStateEnvelope.fetchRequest()
            return try viewContext.fetch(request)
        }

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.domain, "primaryState")
        XCTAssertEqual(fetched.first?.payload, payload)
        XCTAssertEqual(fetched.first?.modifiedAt, timestamp)
        XCTAssertEqual(fetched.first?.commitID, commitID)
        XCTAssertEqual(fetched.first?.schemaVersion, 1)
    }

    func testSecondaryStateKeepsNewestCompleteCommit() async throws {
        let controller = try NativeICloudPersistenceController(mode: .inMemory)
        let store = NativeICloudSyncStore(controller: controller)
        try await store.load()

        let olderStamp = NativeICloudCommitStamp(
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
            commitID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        let newerStamp = NativeICloudCommitStamp(
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_100),
            commitID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )

        let winningValue = try await store.saveLatest(
            domain: .secondaryState,
            payload: Data("newer".utf8),
            stamp: newerStamp
        )
        let conflictValue = try await store.saveLatest(
            domain: .secondaryState,
            payload: Data("older".utf8),
            stamp: olderStamp
        )

        XCTAssertTrue(
            NativeICloudSaveConflictResolver.submittedValueWasPersisted(
                payload: Data("newer".utf8),
                stamp: newerStamp,
                savedValue: winningValue
            )
        )
        XCTAssertFalse(
            NativeICloudSaveConflictResolver.submittedValueWasPersisted(
                payload: Data("older".utf8),
                stamp: olderStamp,
                savedValue: conflictValue
            )
        )

        let latestValue = try await store.latestValue(for: .secondaryState)
        let latest = try XCTUnwrap(latestValue)
        XCTAssertEqual(latest.payload, Data("newer".utf8))
        XCTAssertEqual(latest.stamp, newerStamp)
    }

    func testPrimaryHistoryUsesNewerUserCommitEvenWhenItsLifetimeTotalIsLower() async throws {
        let controller = try NativeICloudPersistenceController(mode: .inMemory)
        let store = NativeICloudSyncStore(controller: controller)
        try await store.load()

        let olderHigherPointsStamp = NativeICloudCommitStamp(
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
            commitID: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        )
        let newerUserActionStamp = NativeICloudCommitStamp(
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_100),
            commitID: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        )
        let olderHigherPointsPayload = try JSONEncoder().encode(
            primarySnapshot(totalPoints: 346, lifetimePoints: 768)
        )
        let newerUserActionPayload = try JSONEncoder().encode(
            primarySnapshot(totalPoints: 337, lifetimePoints: 759)
        )

        _ = try await store.saveLatest(
            domain: .primaryState,
            payload: olderHigherPointsPayload,
            stamp: olderHigherPointsStamp
        )
        _ = try await store.saveLatest(
            domain: .primaryState,
            payload: newerUserActionPayload,
            stamp: newerUserActionStamp
        )

        let latestValue = try await store.latestValue(for: .primaryState)
        let latest = try XCTUnwrap(latestValue)
        XCTAssertEqual(latest.payload, newerUserActionPayload)
        XCTAssertEqual(latest.stamp, newerUserActionStamp)
    }

    func testPrimaryHistoryUsesLatestCommitWhenLifetimeProgressMatches() async throws {
        let controller = try NativeICloudPersistenceController(mode: .inMemory)
        let store = NativeICloudSyncStore(controller: controller)
        try await store.load()

        let olderStamp = NativeICloudCommitStamp(
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
            commitID: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
        )
        let newerStamp = NativeICloudCommitStamp(
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_100),
            commitID: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        )
        let olderPayload = try JSONEncoder().encode(
            primarySnapshot(totalPoints: 346, lifetimePoints: 768)
        )
        let newerPayload = try JSONEncoder().encode(
            primarySnapshot(totalPoints: 345, lifetimePoints: 768)
        )

        _ = try await store.saveLatest(
            domain: .primaryState,
            payload: olderPayload,
            stamp: olderStamp
        )
        _ = try await store.saveLatest(
            domain: .primaryState,
            payload: newerPayload,
            stamp: newerStamp
        )

        let latestValue = try await store.latestValue(for: .primaryState)
        let latest = try XCTUnwrap(latestValue)
        XCTAssertEqual(latest.payload, newerPayload)
        XCTAssertEqual(latest.stamp, newerStamp)
    }

    func testPrimaryHistoryKeepsBoundedSupersededCommits() async throws {
        let controller = try NativeICloudPersistenceController(mode: .inMemory)
        let store = NativeICloudSyncStore(controller: controller)
        try await store.load()

        for index in 0...NativeICloudSyncStore.primaryHistoryLimit {
            let stamp = NativeICloudCommitStamp(
                modifiedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)),
                commitID: UUID()
            )
            let payload = try JSONEncoder().encode(
                primarySnapshot(totalPoints: 300 - index, lifetimePoints: 768)
            )
            _ = try await store.saveLatest(
                domain: .primaryState,
                payload: payload,
                stamp: stamp
            )
        }

        let container = controller.container
        let primaryRecordCount = try await container.performBackgroundTask { context in
            let request = NativeCloudStateEnvelope.fetchRequest()
            request.predicate = NSPredicate(
                format: "domain == %@",
                NativeICloudDomain.primaryState.rawValue
            )
            return try context.fetch(request).count
        }
        XCTAssertEqual(primaryRecordCount, NativeICloudSyncStore.primaryHistoryLimit)

        let latestValue = try await store.latestValue(for: .primaryState)
        let latest = try XCTUnwrap(latestValue)
        XCTAssertEqual(
            latest.stamp.modifiedAt,
            Date(timeIntervalSince1970: 1_800_000_000 + Double(NativeICloudSyncStore.primaryHistoryLimit))
        )
    }

    func testPrimaryHistoryDoesNotCreateADuplicateCommitForIdenticalPayload() async throws {
        let controller = try NativeICloudPersistenceController(mode: .inMemory)
        let store = NativeICloudSyncStore(controller: controller)
        try await store.load()
        let payload = try JSONEncoder().encode(primarySnapshot(totalPoints: 343, lifetimePoints: 994))
        let firstStamp = NativeICloudCommitStamp(
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
            commitID: UUID()
        )
        let secondStamp = NativeICloudCommitStamp(
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_001),
            commitID: UUID()
        )

        let first = try await store.saveLatest(
            domain: .primaryState,
            payload: payload,
            stamp: firstStamp
        )
        let second = try await store.saveLatest(
            domain: .primaryState,
            payload: payload,
            stamp: secondStamp
        )

        XCTAssertEqual(second, first)
        let count = try await controller.container.performBackgroundTask { context in
            let request = NativeCloudStateEnvelope.fetchRequest()
            request.predicate = NSPredicate(
                format: "domain == %@",
                NativeICloudDomain.primaryState.rawValue
            )
            return try context.fetch(request).count
        }
        XCTAssertEqual(count, 1)
    }

    func testPrimaryHistoryDoesNotCreateADuplicateCommitForDeviceLocalRewardLedger() async throws {
        let controller = try NativeICloudPersistenceController(mode: .inMemory)
        let store = NativeICloudSyncStore(controller: controller)
        try await store.load()

        let firstPayload = try JSONEncoder().encode(
            primarySnapshot(
                totalPoints: 343,
                lifetimePoints: 994,
                dailyRewardState: DailyRewardState(dateKey: "2026-07-21")
            )
        )
        let secondPayload = try JSONEncoder().encode(
            primarySnapshot(
                totalPoints: 343,
                lifetimePoints: 994,
                dailyRewardState: DailyRewardState(
                    dateKey: "2026-07-21",
                    rewardedCellIDs: [UUID()],
                    peakCompletedLineCount: 3,
                    fullBoardRewardGranted: true
                )
            )
        )

        let first = try await store.saveLatest(
            domain: .primaryState,
            payload: firstPayload,
            stamp: NativeICloudCommitStamp(
                modifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
                commitID: UUID()
            )
        )
        let second = try await store.saveLatest(
            domain: .primaryState,
            payload: secondPayload,
            stamp: NativeICloudCommitStamp(
                modifiedAt: Date(timeIntervalSince1970: 1_800_000_001),
                commitID: UUID()
            )
        )

        XCTAssertEqual(second, first)
    }

    func testInitialMigrationRestoresRemoteOverFreshEmptyInstall() {
        let remoteStamp = NativeICloudCommitStamp(
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
            commitID: UUID()
        )

        XCTAssertEqual(
            NativeICloudInitialMigrationPlanner.decide(
                localHasMeaningfulData: false,
                localModifiedAt: Date(timeIntervalSince1970: 1_900_000_000),
                remoteStamp: remoteStamp
            ),
            .applyRemote
        )
    }

    func testFirstAssociationRestoresExistingCloudEvenWhenLocalWriteIsNewer() {
        let remoteStamp = NativeICloudCommitStamp(
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
            commitID: UUID()
        )

        XCTAssertEqual(
            NativeICloudInitialMigrationPlanner.decide(
                localHasMeaningfulData: true,
                localModifiedAt: Date(timeIntervalSince1970: 1_900_000_000),
                remoteStamp: remoteStamp,
                isAccountBindingConfirmed: false
            ),
            .applyRemote
        )
    }

    func testStarterGuideSeedDefersWhenCloudHasNoAccountData() {
        XCTAssertEqual(
            NativeICloudInitialMigrationPlanner.decide(
                localHasMeaningfulData: true,
                localIsSystemStarterGuideSeedData: true,
                localModifiedAt: Date(),
                remoteStamp: nil
            ),
            .deferUpload
        )
    }

    func testStarterGuideSeedCannotReplaceExistingAccountState() {
        let seed = starterGuideSnapshot()
        let account = NativeICloudPrimaryStateSnapshot(
            boards: [
                BingoBoardStore.NamedBoard(
                    name: "Saved board",
                    board: SavedBoard(
                        gridSize: 3,
                        cells: [[BingoCell(text: "Keep me")]],
                        completedLines: []
                    )
                )
            ],
            points: PointsPersistenceSnapshot(
                totalPoints: 343,
                lifetimePoints: 994,
                dailyRewardState: nil
            ),
            diaryEntries: [:],
            timeoutPayload: [:],
            customRewards: [],
            redemptionHistory: [],
            stickerInventory: [:],
            stickerPlacements: []
        )

        XCTAssertTrue(seed.isSystemStarterGuideSeedData)
        XCTAssertTrue(
            NativeICloudPrimaryExportGuard.blocksAutomaticUpload(local: seed, remote: account)
        )

        let merged = NativeICloudPrimaryStateMerger.merged(
            local: account,
            incoming: seed,
            localHasNewerUserChange: false
        )
        XCTAssertEqual(merged.points.totalPoints, 343)
        XCTAssertEqual(merged.points.lifetimePoints, 994)
        XCTAssertEqual(merged.boards, account.boards)
    }

    func testStarterGuideSeedIsRemovedWhenItPredatesExistingAccountHistory() throws {
        let seed = starterGuideSnapshot()
        let seedBoardID = try XCTUnwrap(seed.boards.first?.id)
        let account = accountSnapshot()

        let resolved = try XCTUnwrap(
            NativeICloudPrimaryHistoryResolver.resolve(primaryHistory([seed, account]))
        )

        XCTAssertEqual(resolved.boards, account.boards)
        XCTAssertTrue(resolved.effectiveDeletedBoardIDs.contains(seedBoardID))
        XCTAssertEqual(resolved.points.totalPoints, account.points.totalPoints)
    }

    func testThreeReinstallStarterGuideSnapshotsResolveToOneBoard() throws {
        let first = starterGuideSnapshot()
        let second = starterGuideSnapshot()
        let third = starterGuideSnapshot()
        let allIDs = Set((first.boards + second.boards + third.boards).map(\.id))

        let resolved = try XCTUnwrap(
            NativeICloudPrimaryHistoryResolver.resolve(primaryHistory([first, second, third]))
        )

        XCTAssertEqual(resolved.boards.count, 1)
        XCTAssertEqual(resolved.effectiveDeletedBoardIDs, allIDs.subtracting([resolved.boards[0].id]))
    }

    func testMixedAccountSnapshotsRemoveEveryPristineReinstallBoard() throws {
        let account = accountSnapshot()
        let accountBoard = try XCTUnwrap(account.boards.first)
        let firstSeed = try XCTUnwrap(starterGuideSnapshot().boards.first)
        let secondSeed = try XCTUnwrap(starterGuideSnapshot().boards.first)
        let firstMixed = primarySnapshot(boards: [accountBoard, firstSeed])
        let secondMixed = primarySnapshot(boards: [accountBoard, firstSeed, secondSeed])

        let resolved = try XCTUnwrap(
            NativeICloudPrimaryHistoryResolver.resolve(primaryHistory([firstMixed, secondMixed]))
        )

        XCTAssertEqual(resolved.boards.map(\.id), [accountBoard.id])
        XCTAssertTrue(resolved.effectiveDeletedBoardIDs.isSuperset(of: [firstSeed.id, secondSeed.id]))
    }

    func testEditedStarterGuideBoardIsPreservedBesideAccountBoard() throws {
        let account = accountSnapshot()
        let accountBoard = try XCTUnwrap(account.boards.first)
        var editedSeed = try XCTUnwrap(starterGuideSnapshot().boards.first)
        var cells = BoardEngine.expandedBoardCache(from: editedSeed.board)
        cells[0][0].text = "My own task"
        editedSeed.board = SavedBoard(
            gridSize: 3,
            cells: Array(cells.prefix(3)).map { Array($0.prefix(3)) },
            completedLines: [],
            fullBoardCells: cells
        )
        editedSeed.origin = .starterGuide
        let mixed = primarySnapshot(boards: [accountBoard, editedSeed])

        let normalized = NativeICloudPrimaryStateMerger.removingRedundantStarterGuideBoards(
            from: mixed
        )

        XCTAssertEqual(Set(normalized.boards.map(\.id)), [accountBoard.id, editedSeed.id])
        XCTAssertFalse(normalized.effectiveDeletedBoardIDs.contains(editedSeed.id))
    }

    func testStarterGuideBoardWithChangedRulesIsPreserved() throws {
        let accountBoard = try XCTUnwrap(accountSnapshot().boards.first)
        var customizedSeed = try XCTUnwrap(starterGuideSnapshot().boards.first)
        customizedSeed.taskResetMode = .keepTaskStatus
        customizedSeed.origin = .starterGuide
        let customizedSnapshot = primarySnapshot(boards: [customizedSeed])

        let normalized = BingoBoardStore.snapshotByRemovingRedundantStarterGuideBoards(
            BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: accountBoard.id,
                boards: [accountBoard, customizedSeed]
            )
        )

        XCTAssertEqual(Set(normalized.boards.map(\.id)), [accountBoard.id, customizedSeed.id])
        XCTAssertFalse(normalized.effectiveDeletedBoardIDs.contains(customizedSeed.id))
        XCTAssertFalse(customizedSnapshot.isSystemStarterGuideSeedData)
    }

    func testCompletedStarterGuideBoardIsNeverAutoRemoved() throws {
        let accountBoard = try XCTUnwrap(accountSnapshot().boards.first)
        var completedSeed = try XCTUnwrap(starterGuideSnapshot().boards.first)
        var cells = BoardEngine.expandedBoardCache(from: completedSeed.board)
        cells[0][0].isCompleted = true
        cells[0][0].completionStreakCount = 1
        cells[0][0].lastCompletedAt = .now
        completedSeed.board = SavedBoard(
            gridSize: 3,
            cells: Array(cells.prefix(3)).map { Array($0.prefix(3)) },
            completedLines: [],
            fullBoardCells: cells
        )

        let normalized = BingoBoardStore.snapshotByRemovingRedundantStarterGuideBoards(
            BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: accountBoard.id,
                boards: [accountBoard, completedSeed]
            )
        )

        XCTAssertEqual(Set(normalized.boards.map(\.id)), [accountBoard.id, completedSeed.id])
        XCTAssertFalse(normalized.effectiveDeletedBoardIDs.contains(completedSeed.id))
    }

    func testFreshMirrorDoesNotTrustAStaleAppGroupImportMarker() {
        XCTAssertFalse(
            NativeICloudInitialImportReadiness.isReady(
                storeHasPrimarySnapshot: false,
                observedImportForCurrentStore: false
            )
        )
        XCTAssertTrue(
            NativeICloudInitialImportReadiness.isReady(
                storeHasPrimarySnapshot: true,
                observedImportForCurrentStore: false
            )
        )
        XCTAssertTrue(
            NativeICloudInitialImportReadiness.isReady(
                storeHasPrimarySnapshot: false,
                observedImportForCurrentStore: true
            )
        )
    }

    func testPrimaryHistoryDoesNotLetAnEmptyReinstallCommitEraseAccountData() {
        let meaningful = NativeICloudPrimaryStateSnapshot(
            boards: [
                BingoBoardStore.NamedBoard(
                    name: "Saved board",
                    board: SavedBoard(
                        gridSize: 3,
                        cells: [[BingoCell(text: "Keep me")]],
                        completedLines: []
                    )
                )
            ],
            points: PointsPersistenceSnapshot(
                totalPoints: 343,
                lifetimePoints: 994,
                dailyRewardState: nil
            ),
            diaryEntries: [:],
            timeoutPayload: [:],
            customRewards: [],
            redemptionHistory: [],
            stickerInventory: [:],
            stickerPlacements: []
        )
        let emptyReinstall = primarySnapshot(totalPoints: 0, lifetimePoints: 0)

        let resolved = NativeICloudPrimaryHistoryResolver.resolve(
            primaryHistory([meaningful, emptyReinstall])
        )

        XCTAssertEqual(resolved?.points.totalPoints, 343)
        XCTAssertEqual(resolved?.points.lifetimePoints, 994)
        XCTAssertTrue(resolved?.hasMeaningfulUserData == true)
    }

    func testInitialMigrationUploadsMeaningfulNewerLocalData() {
        let remoteStamp = NativeICloudCommitStamp(
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
            commitID: UUID()
        )

        XCTAssertEqual(
            NativeICloudInitialMigrationPlanner.decide(
                localHasMeaningfulData: true,
                localModifiedAt: Date(timeIntervalSince1970: 1_800_000_001),
                remoteStamp: remoteStamp
            ),
            .uploadLocal
        )
    }

    func testInitialMigrationUploadsMeaningfulLocalDataOverANewerEmptyCloudSeed() {
        let remoteStamp = NativeICloudCommitStamp(
            modifiedAt: Date(timeIntervalSince1970: 1_900_000_000),
            commitID: UUID()
        )

        XCTAssertEqual(
            NativeICloudInitialMigrationPlanner.decide(
                localHasMeaningfulData: true,
                localModifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
                remoteStamp: remoteStamp,
                remoteHasMeaningfulData: false
            ),
            .uploadLocal
        )
    }

    func testEmptyLocalStateCannotBeExportedOverMeaningfulCloudState() {
        let local = primarySnapshot(totalPoints: 0, lifetimePoints: 0)
        let remote = NativeICloudPrimaryStateSnapshot(
            boards: [
                BingoBoardStore.NamedBoard(
                    name: "Saved board",
                    board: SavedBoard(
                        gridSize: 3,
                        cells: [[BingoCell(text: "Keep me")]],
                        completedLines: []
                    )
                )
            ],
            points: PointsPersistenceSnapshot(
                totalPoints: 343,
                lifetimePoints: 994,
                dailyRewardState: nil
            ),
            diaryEntries: [:],
            timeoutPayload: [:],
            customRewards: [],
            redemptionHistory: [],
            stickerInventory: [:],
            stickerPlacements: []
        )

        XCTAssertTrue(
            NativeICloudPrimaryExportGuard.blocksAutomaticUpload(
                local: local,
                remote: remote
            )
        )
    }

    func testMeaningfulLocalChangeIsNotBlockedByTheEmptySeedGuard() {
        let local = NativeICloudPrimaryStateSnapshot(
            boards: [
                BingoBoardStore.NamedBoard(
                    name: "Today",
                    board: SavedBoard(
                        gridSize: 3,
                        cells: [[BingoCell(text: "A real task")]],
                        completedLines: []
                    )
                )
            ],
            points: PointsPersistenceSnapshot(
                totalPoints: 344,
                lifetimePoints: 995,
                dailyRewardState: nil
            ),
            diaryEntries: [:],
            timeoutPayload: [:],
            customRewards: [],
            redemptionHistory: [],
            stickerInventory: [:],
            stickerPlacements: []
        )
        let remote = primarySnapshot(totalPoints: 343, lifetimePoints: 994)

        XCTAssertFalse(
            NativeICloudPrimaryExportGuard.blocksAutomaticUpload(
                local: local,
                remote: remote
            )
        )
    }

    func testAccountSwitchNeverAllowsAnImplicitCrossAccountCopy() {
        XCTAssertFalse(
            NativeICloudAccountChangePlanner.allows(
                .copyLocalDataToEmptyCurrentAccount,
                localHasMeaningfulData: true,
                remoteDataAvailability: .present
            )
        )
        XCTAssertFalse(
            NativeICloudAccountChangePlanner.allows(
                .copyLocalDataToEmptyCurrentAccount,
                localHasMeaningfulData: true,
                remoteDataAvailability: .unknown
            )
        )
        XCTAssertFalse(
            NativeICloudAccountChangePlanner.allows(
                .copyLocalDataToEmptyCurrentAccount,
                localHasMeaningfulData: false,
                remoteDataAvailability: .empty
            )
        )
    }

    func testAccountSwitchAllowsOnlyExplicitSafeChoices() {
        XCTAssertTrue(
            NativeICloudAccountChangePlanner.allows(
                .keepLocalOnly,
                localHasMeaningfulData: false,
                remoteDataAvailability: .unknown
            )
        )
        XCTAssertTrue(
            NativeICloudAccountChangePlanner.allows(
                .useCurrentAccountCloud,
                localHasMeaningfulData: true,
                remoteDataAvailability: .present
            )
        )
        XCTAssertTrue(
            NativeICloudAccountChangePlanner.allows(
                .copyLocalDataToEmptyCurrentAccount,
                localHasMeaningfulData: true,
                remoteDataAvailability: .empty
            )
        )
    }

    func testPrimaryConflictDoesNotLetOlderHigherPointsUndoANewerTap() throws {
        let olderHigherPoints = NativeICloudEnvelopeValue(
            domain: .primaryState,
            payload: try JSONEncoder().encode(
                primarySnapshot(totalPoints: 356, lifetimePoints: 792)
            ),
            stamp: NativeICloudCommitStamp(
                modifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
                commitID: UUID()
            ),
            schemaVersion: 1
        )
        let newerTap = NativeICloudEnvelopeValue(
            domain: .primaryState,
            payload: try JSONEncoder().encode(
                primarySnapshot(totalPoints: 346, lifetimePoints: 781)
            ),
            stamp: NativeICloudCommitStamp(
                modifiedAt: Date(timeIntervalSince1970: 1_800_000_001),
                commitID: UUID()
            ),
            schemaVersion: 1
        )

        XCTAssertTrue(
            NativeICloudPrimaryConflictResolver.prefers(newerTap, over: olderHigherPoints)
        )
        XCTAssertFalse(
            NativeICloudPrimaryConflictResolver.prefers(olderHigherPoints, over: newerTap)
        )
    }

    func testPrimaryConflictProtectsLocalTapDuringExportDebounce() {
        let incomingStamp = NativeICloudCommitStamp(
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
            commitID: UUID()
        )

        XCTAssertTrue(
            NativeICloudPrimaryConflictResolver.localChangeIsNewer(
                modifiedAt: Date(timeIntervalSince1970: 1_800_000_001),
                than: incomingStamp
            )
        )
        XCTAssertFalse(
            NativeICloudPrimaryConflictResolver.localChangeIsNewer(
                modifiedAt: Date(timeIntervalSince1970: 1_799_999_999),
                than: incomingStamp
            )
        )
    }

    func testHandledPrimaryResolutionSuppressesDuplicateProjectionForSameCommit() {
        let handledStamp = NativeICloudCommitStamp(
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_001),
            commitID: UUID()
        )
        let resolved = primarySnapshot(totalPoints: 400, lifetimePoints: 901)

        XCTAssertTrue(
            NativeICloudPrimaryHandledStateResolver.contains(
                latestStamp: handledStamp,
                latestSchemaVersion: NativeICloudPrimaryEnvelopeSchema.logicalCommitVersion,
                resolvedState: resolved,
                handledStamp: handledStamp,
                handledSchemaVersion: NativeICloudPrimaryEnvelopeSchema.logicalCommitVersion,
                handledState: resolved
            )
        )
    }

    func testHandledPrimaryResolutionAllowsChangedOrNewerCloudState() {
        let handledStamp = NativeICloudCommitStamp(
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_001),
            commitID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        let newerStamp = NativeICloudCommitStamp(
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_002),
            commitID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )
        let handled = primarySnapshot(totalPoints: 400, lifetimePoints: 901)
        let changed = primarySnapshot(totalPoints: 401, lifetimePoints: 902)

        XCTAssertFalse(
            NativeICloudPrimaryHandledStateResolver.contains(
                latestStamp: handledStamp,
                latestSchemaVersion: NativeICloudPrimaryEnvelopeSchema.logicalCommitVersion,
                resolvedState: changed,
                handledStamp: handledStamp,
                handledSchemaVersion: NativeICloudPrimaryEnvelopeSchema.logicalCommitVersion,
                handledState: handled
            )
        )
        XCTAssertFalse(
            NativeICloudPrimaryHandledStateResolver.contains(
                latestStamp: newerStamp,
                latestSchemaVersion: NativeICloudPrimaryEnvelopeSchema.logicalCommitVersion,
                resolvedState: handled,
                handledStamp: handledStamp,
                handledSchemaVersion: NativeICloudPrimaryEnvelopeSchema.logicalCommitVersion,
                handledState: handled
            )
        )
    }

    func testPrimaryMergePreservesTodayCompletionAgainstDelayedDeviceReset() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let boardID = UUID()
        let resetAt = now.addingTimeInterval(-3_600)
        let first = BingoCell(text: "One", isCompleted: true, lastCompletedAt: now.addingTimeInterval(-30))
        let second = BingoCell(text: "Two", isCompleted: true, lastCompletedAt: now.addingTimeInterval(-20))
        let third = BingoCell(text: "Three", isCompleted: true, lastCompletedAt: now.addingTimeInterval(-10))
        let fourth = BingoCell(text: "Four", isCompleted: true, lastCompletedAt: now)
        let completedCells = [[first, second], [third, fourth]]
        let clearedCells = [[
            BingoCell(id: first.id, text: "One"),
            BingoCell(id: second.id, text: "Two")
        ], [
            BingoCell(id: third.id, text: "Three"),
            BingoCell(id: fourth.id, text: "Four")
        ]]
        let localBoard = BingoBoardStore.NamedBoard(
            id: boardID,
            name: "Today",
            board: SavedBoard(
                gridSize: 2,
                cells: completedCells,
                completedLines: [.row(0), .row(1)],
                fullBoardCells: completedCells
            ),
            lastTaskResetAppliedAt: resetAt,
            updatedAt: now
        )
        let delayedResetBoard = BingoBoardStore.NamedBoard(
            id: boardID,
            name: "Today",
            board: SavedBoard(
                gridSize: 2,
                cells: clearedCells,
                completedLines: [],
                fullBoardCells: clearedCells
            ),
            lastTaskResetAppliedAt: now.addingTimeInterval(60),
            updatedAt: now.addingTimeInterval(60)
        )

        let local = NativeICloudPrimaryStateSnapshot(
            boards: [localBoard],
            points: PointsPersistenceSnapshot(
                totalPoints: 377,
                lifetimePoints: 816,
                dailyRewardState: DailyRewardState(dateKey: PointsStore.dateKey(for: now))
            ),
            diaryEntries: [:],
            timeoutPayload: [:],
            customRewards: [],
            redemptionHistory: [],
            stickerInventory: [:],
            stickerPlacements: []
        )
        let incoming = NativeICloudPrimaryStateSnapshot(
            boards: [delayedResetBoard],
            points: PointsPersistenceSnapshot(
                totalPoints: 346,
                lifetimePoints: 768,
                dailyRewardState: DailyRewardState(dateKey: PointsStore.dateKey(for: now))
            ),
            diaryEntries: [:],
            timeoutPayload: [:],
            customRewards: [],
            redemptionHistory: [],
            stickerInventory: [:],
            stickerPlacements: []
        )

        let merged = NativeICloudPrimaryStateMerger.merged(
            local: local,
            incoming: incoming,
            localHasNewerUserChange: false,
            referenceDate: now
        )

        XCTAssertEqual(merged.boards.first?.board, localBoard.board)
        XCTAssertEqual(merged.points.totalPoints, 377)
        XCTAssertEqual(merged.points.lifetimePoints, 816)
    }

    func testPrimaryMergeDoesNotResurrectBoardRemovedByAnotherDevice() {
        let now = Date(timeIntervalSince1970: 1_774_176_000)
        let deletedBoard = BingoBoardStore.NamedBoard(
            name: "A",
            board: SavedBoard(gridSize: 1, cells: [[BingoCell(text: "A")]], completedLines: []),
            updatedAt: now
        )
        let retainedBoard = BingoBoardStore.NamedBoard(
            name: "B",
            board: SavedBoard(gridSize: 1, cells: [[BingoCell(text: "B")]], completedLines: []),
            updatedAt: now
        )
        let oldCloud = primarySnapshot(
            boards: [deletedBoard, retainedBoard],
            deletedBoardIDs: []
        )
        let deletion = primarySnapshot(
            boards: [retainedBoard],
            deletedBoardIDs: [deletedBoard.id]
        )

        let merged = NativeICloudPrimaryStateMerger.merged(
            local: oldCloud,
            incoming: deletion,
            localHasNewerUserChange: false,
            referenceDate: now
        )

        XCTAssertEqual(merged.boards.map(\.id), [retainedBoard.id])
        XCTAssertEqual(merged.effectiveDeletedBoardIDs, [deletedBoard.id])
    }

    func testNewerBoardOrderWinsWithoutDiscardingIncomingTaskProgress() {
        let now = Date(timeIntervalSince1970: 1_774_176_000)
        let boardA = BingoBoardStore.NamedBoard(
            name: "A",
            board: SavedBoard(gridSize: 1, cells: [[BingoCell(text: "A")]], completedLines: []),
            updatedAt: now
        )
        let boardB = BingoBoardStore.NamedBoard(
            name: "B",
            board: SavedBoard(gridSize: 1, cells: [[BingoCell(text: "B")]], completedLines: []),
            updatedAt: now
        )
        var incomingBoardB = boardB
        incomingBoardB.board = SavedBoard(
            gridSize: 1,
            cells: [[BingoCell(text: "B", isCompleted: true)]],
            completedLines: []
        )
        incomingBoardB.updatedAt = now.addingTimeInterval(60)

        let local = primarySnapshot(
            boards: [boardB, boardA],
            protectedBoardID: boardA.id,
            boardOrderModifiedAt: now.addingTimeInterval(120)
        )
        let incoming = primarySnapshot(
            boards: [boardA, incomingBoardB],
            protectedBoardID: boardA.id,
            boardOrderModifiedAt: now.addingTimeInterval(30)
        )

        let merged = NativeICloudPrimaryStateMerger.merged(
            local: local,
            incoming: incoming,
            localHasNewerUserChange: false,
            referenceDate: now.addingTimeInterval(180)
        )

        XCTAssertEqual(merged.boards.map(\.id), [boardB.id, boardA.id])
        XCTAssertTrue(merged.boards[0].board.cells[0][0].isCompleted)
        XCTAssertEqual(merged.boardOrderModifiedAt, now.addingTimeInterval(120))
        XCTAssertEqual(merged.effectiveProtectedBoardID, boardA.id)
    }

    func testPrimaryHistoryKeepsConsecutiveBoardDeletionsAgainstOlderSnapshots() throws {
        let now = Date(timeIntervalSince1970: 1_774_176_000)
        let emptyBoard = SavedBoard(gridSize: 1, cells: [[BingoCell()]], completedLines: [])
        let boardA = BingoBoardStore.NamedBoard(name: "A", board: emptyBoard, updatedAt: now)
        let boardB = BingoBoardStore.NamedBoard(name: "B", board: emptyBoard, updatedAt: now)
        let boardC = BingoBoardStore.NamedBoard(name: "C", board: emptyBoard, updatedAt: now)
        let baseline = primarySnapshot(boards: [boardA, boardB, boardC])
        let afterDeletingA = primarySnapshot(
            boards: [boardB, boardC],
            deletedBoardIDs: [boardA.id]
        )
        let staleSnapshot = primarySnapshot(boards: [boardA, boardB, boardC])
        let afterDeletingB = primarySnapshot(
            boards: [boardC],
            deletedBoardIDs: [boardA.id, boardB.id]
        )

        let resolved = try XCTUnwrap(NativeICloudPrimaryHistoryResolver.resolve(primaryHistory([
            baseline,
            afterDeletingA,
            staleSnapshot,
            afterDeletingB
        ])))

        XCTAssertEqual(resolved.boards.map(\.id), [boardC.id])
        XCTAssertEqual(resolved.effectiveDeletedBoardIDs, [boardA.id, boardB.id])
    }

    func testPrimarySnapshotDecodesLegacyDataWithoutDeletionTombstones() throws {
        let snapshot = primarySnapshot(boards: [])
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "deletedBoardIDs")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            NativeICloudPrimaryStateSnapshot.self,
            from: legacyData
        )

        XCTAssertTrue(decoded.effectiveDeletedBoardIDs.isEmpty)
    }

    func testLegacyNamedBoardWithoutOriginDecodesAsUserBoard() throws {
        let board = try XCTUnwrap(accountSnapshot().boards.first)
        let encoded = try JSONEncoder().encode(board)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "origin")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            BingoBoardStore.NamedBoard.self,
            from: legacyData
        )

        XCTAssertEqual(decoded.origin, .user)
        XCTAssertEqual(decoded.id, board.id)
        XCTAssertEqual(decoded.board, board.board)
    }

    func testPrimaryHistoryPreservesAnotherDevicesTapAgainstLaterMidnightReset() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 12))
        )
        let boardID = UUID()
        let cellID = UUID()
        let resetAt = day.addingTimeInterval(-3_600)

        func board(completed: Bool, reset: Date, updatedAt: Date) -> BingoBoardStore.NamedBoard {
            let cell = BingoCell(
                id: cellID,
                text: "Task",
                isCompleted: completed,
                lastCompletedAt: completed ? updatedAt : nil
            )
            let cells = [[cell]]
            return BingoBoardStore.NamedBoard(
                id: boardID,
                name: "Today",
                board: SavedBoard(
                    gridSize: 1,
                    cells: cells,
                    completedLines: [],
                    fullBoardCells: cells
                ),
                lastTaskResetAppliedAt: reset,
                updatedAt: updatedAt
            )
        }

        func snapshot(
            board: BingoBoardStore.NamedBoard,
            total: Int,
            lifetime: Int
        ) -> NativeICloudPrimaryStateSnapshot {
            NativeICloudPrimaryStateSnapshot(
                boards: [board],
                points: PointsPersistenceSnapshot(
                    totalPoints: total,
                    lifetimePoints: lifetime,
                    dailyRewardState: DailyRewardState(dateKey: PointsStore.dateKey(for: day))
                ),
                diaryEntries: [:],
                timeoutPayload: [:],
                customRewards: [],
                redemptionHistory: [],
                stickerInventory: [:],
                stickerPlacements: []
            )
        }

        let baseline = snapshot(
            board: board(completed: false, reset: resetAt, updatedAt: day),
            total: 388,
            lifetime: 829
        )
        let iPadTap = snapshot(
            board: board(
                completed: true,
                reset: resetAt,
                updatedAt: day.addingTimeInterval(27)
            ),
            total: 389,
            lifetime: 830
        )
        let delayedPhoneReset = snapshot(
            board: board(
                completed: false,
                reset: day.addingTimeInterval(34),
                updatedAt: day.addingTimeInterval(34)
            ),
            total: 388,
            lifetime: 829
        )

        let resolved = try XCTUnwrap(
            NativeICloudPrimaryHistoryResolver.resolve(
                primaryHistory([baseline, iPadTap, delayedPhoneReset]),
                referenceDate: day,
                calendar: calendar
            )
        )

        XCTAssertTrue(resolved.boards[0].board.cells[0][0].isCompleted)
        XCTAssertEqual(resolved.points.totalPoints, 389)
        XCTAssertEqual(resolved.points.lifetimePoints, 830)
    }

    func testPrimaryHistoryStillAllowsExplicitUndoAfterCompletion() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let boardID = UUID()
        let cellID = UUID()
        let completedCell = BingoCell(
            id: cellID,
            text: "Task",
            isCompleted: true,
            lastCompletedAt: now
        )
        let undoneCell = BingoCell(id: cellID, text: "Task")

        func snapshot(cell: BingoCell, total: Int, updatedAt: Date) -> NativeICloudPrimaryStateSnapshot {
            let cells = [[cell]]
            let board = BingoBoardStore.NamedBoard(
                id: boardID,
                name: "Today",
                board: SavedBoard(
                    gridSize: 1,
                    cells: cells,
                    completedLines: [],
                    fullBoardCells: cells
                ),
                lastTaskResetAppliedAt: now.addingTimeInterval(-60),
                updatedAt: updatedAt
            )
            return NativeICloudPrimaryStateSnapshot(
                boards: [board],
                points: PointsPersistenceSnapshot(
                    totalPoints: total,
                    lifetimePoints: 830,
                    dailyRewardState: nil
                ),
                diaryEntries: [:],
                timeoutPayload: [:],
                customRewards: [],
                redemptionHistory: [],
                stickerInventory: [:],
                stickerPlacements: []
            )
        }

        let resolved = try XCTUnwrap(
            NativeICloudPrimaryHistoryResolver.resolve(primaryHistory([
                snapshot(cell: completedCell, total: 389, updatedAt: now),
                snapshot(cell: undoneCell, total: 388, updatedAt: now.addingTimeInterval(1))
            ]), referenceDate: now)
        )

        XCTAssertFalse(resolved.boards[0].board.cells[0][0].isCompleted)
        XCTAssertEqual(resolved.points.totalPoints, 388)
        XCTAssertEqual(resolved.points.lifetimePoints, 830)
    }

    func testCloudKitPartialFailureFormatterIncludesNestedCause() {
        let nested = NSError(
            domain: CKErrorDomain,
            code: CKError.serverRejectedRequest.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Server Rejected Request"]
        )
        let outer = NSError(
            domain: CKErrorDomain,
            code: CKError.partialFailure.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Partial Failure",
                CKPartialErrorsByItemIDKey: ["record-zone": nested]
            ]
        )

        let description = NativeICloudErrorFormatter.describe(outer)

        XCTAssertTrue(description.contains("CKErrorDomain 2"))
        XCTAssertTrue(description.contains("CKErrorDomain 15"))
        XCTAssertTrue(description.contains("Server Rejected Request"))
    }

    private func primaryHistory(
        _ snapshots: [NativeICloudPrimaryStateSnapshot]
    ) -> [(NativeICloudEnvelopeValue, NativeICloudPrimaryStateSnapshot)] {
        snapshots.enumerated().map { index, snapshot in
            let stamp = NativeICloudCommitStamp(
                modifiedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)),
                commitID: UUID()
            )
            return (
                NativeICloudEnvelopeValue(
                    domain: .primaryState,
                    payload: Data(),
                    stamp: stamp,
                    schemaVersion: NativeICloudPrimaryEnvelopeSchema.logicalCommitVersion
                ),
                snapshot
            )
        }
    }

    private func primarySnapshot(
        boards: [BingoBoardStore.NamedBoard],
        deletedBoardIDs: Set<UUID> = [],
        protectedBoardID: UUID? = nil,
        boardOrderModifiedAt: Date? = nil
    ) -> NativeICloudPrimaryStateSnapshot {
        NativeICloudPrimaryStateSnapshot(
            boards: boards,
            deletedBoardIDs: deletedBoardIDs,
            protectedBoardID: protectedBoardID,
            boardOrderModifiedAt: boardOrderModifiedAt,
            points: PointsPersistenceSnapshot(
                totalPoints: 0,
                lifetimePoints: 0,
                dailyRewardState: nil
            ),
            diaryEntries: [:],
            timeoutPayload: [:],
            customRewards: [],
            redemptionHistory: [],
            stickerInventory: [:],
            stickerPlacements: []
        )
    }

    private func primarySnapshot(
        totalPoints: Int,
        lifetimePoints: Int,
        dailyRewardState: DailyRewardState? = nil
    ) -> NativeICloudPrimaryStateSnapshot {
        NativeICloudPrimaryStateSnapshot(
            boards: [],
            points: PointsPersistenceSnapshot(
                totalPoints: totalPoints,
                lifetimePoints: lifetimePoints,
                dailyRewardState: dailyRewardState
            ),
            diaryEntries: [:],
            timeoutPayload: [:],
            customRewards: [],
            redemptionHistory: [],
            stickerInventory: [:],
            stickerPlacements: []
        )
    }

    private func starterGuideSnapshot() -> NativeICloudPrimaryStateSnapshot {
        let cells = [FirstStepGuideStore.seedTasks.map { BingoCell(text: $0) }]
        return NativeICloudPrimaryStateSnapshot(
            boards: [
                BingoBoardStore.NamedBoard(
                    name: L10n.boardDefaultName(1),
                    board: SavedBoard(
                        gridSize: 3,
                        cells: cells,
                        completedLines: [],
                        fullBoardCells: cells
                    )
                )
            ],
            points: PointsPersistenceSnapshot(
                totalPoints: 0,
                lifetimePoints: 0,
                dailyRewardState: nil
            ),
            diaryEntries: [:],
            timeoutPayload: [:],
            customRewards: [],
            redemptionHistory: [],
            stickerInventory: [:],
            stickerPlacements: []
        )
    }

    private func accountSnapshot() -> NativeICloudPrimaryStateSnapshot {
        NativeICloudPrimaryStateSnapshot(
            boards: [
                BingoBoardStore.NamedBoard(
                    name: "Saved board",
                    board: SavedBoard(
                        gridSize: 3,
                        cells: [[BingoCell(text: "Keep me")]],
                        completedLines: []
                    )
                )
            ],
            points: PointsPersistenceSnapshot(
                totalPoints: 343,
                lifetimePoints: 994,
                dailyRewardState: nil
            ),
            diaryEntries: [:],
            timeoutPayload: [:],
            customRewards: [],
            redemptionHistory: [],
            stickerInventory: [:],
            stickerPlacements: []
        )
    }
}
