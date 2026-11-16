import XCTest

@MainActor
final class CoreOperationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDownWithError() throws {
        if let app, (testRun?.totalFailureCount ?? 0) > 0 {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app?.terminate()
        app = nil
    }

    private func launch(_ scenario: String) throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("Bingodays Regression ") == true else {
            throw XCTSkip("Use scripts/run_regression.py: UI fixtures require its isolated simulator")
        }
        app = XCUIApplication(bundleIdentifier: "com.bingoday.app")
        app.launchArguments = ["-UITesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["BINGODAYS_UI_TEST_RUN"] = UUID().uuidString
        app.launchEnvironment["BINGODAYS_UI_TEST_SCENARIO"] = scenario
        app.launch()
        XCTAssertTrue(cell().waitForExistence(timeout: 20))
    }

    private func cell(_ coordinate: String = "0-0") -> XCUIElement {
        app.buttons["board.cell.\(coordinate)"]
    }

    private func relaunch() {
        app.terminate()
        app.launch()
        XCTAssertTrue(cell().waitForExistence(timeout: 20))
    }

    private func assertNoTimeout(for kind: String) {
        let complete = app.buttons["timeout.\(kind).complete"]
        let appears = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: complete)
        appears.isInverted = true
        wait(for: [appears], timeout: 3.2)
    }

    private func resolve(_ action: String, kind: String) {
        let button = app.buttons["timeout.\(kind).\(action)"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
        if action == "postpone" {
            let wheels = app.pickerWheels
            XCTAssertTrue(wheels.firstMatch.waitForExistence(timeout: 5))
            XCTAssertEqual(wheels.count, 2)
            wheels.element(boundBy: 1).adjust(toPickerWheelValue: "5m")
            app.buttons["timeout.delay.apply"].tap()
        }
        XCTAssertTrue(button.waitForNonExistence(timeout: 5))
        assertNoTimeout(for: kind)
        relaunch()
        assertNoTimeout(for: kind)
    }

    func testCreateTaskSaveSurvivesRelaunch() throws {
        try launch("tasks")
        cell("0-2").press(forDuration: 0.4)
        let field = app.textFields["task.editor.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Saved UI task")
        app.buttons["task.editor.save"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertEqual(cell("0-2").label, "Saved UI task")
        relaunch()
        XCTAssertEqual(cell("0-2").label, "Saved UI task")
    }

    func testCancelTaskDraftDoesNotPersist() throws {
        try launch("tasks")
        cell("0-2").press(forDuration: 0.4)
        let field = app.textFields["task.editor.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Cancelled UI draft")
        app.buttons["task.editor.cancel"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        relaunch()
        XCTAssertEqual(cell("0-2").label, "Empty tile")
    }

    func testCompleteAndUndoSurviveRelaunch() throws {
        try launch("tasks")
        cell().tap()
        XCTAssertTrue((cell().value as? String)?.hasPrefix("Completed") == true)
        relaunch()
        XCTAssertTrue((cell().value as? String)?.hasPrefix("Completed") == true)
        cell().tap()
        relaunch()
        XCTAssertTrue((cell().value as? String)?.hasPrefix("Not completed") == true)
    }

    func testTaskPostponeDoesNotReopen() throws {
        try launch("task-timeout")
        resolve("postpone", kind: "task")
        XCTAssertEqual(cell().label, "UI task")
        XCTAssertTrue((cell().value as? String)?.hasPrefix("Not completed") == true)
    }

    func testTaskCompleteDoesNotReopen() throws {
        try launch("task-timeout")
        resolve("complete", kind: "task")
        XCTAssertTrue((cell().value as? String)?.hasPrefix("Completed") == true)
    }

    func testTaskDeleteDoesNotReopen() throws {
        try launch("task-timeout")
        resolve("remove", kind: "task")
        XCTAssertEqual(cell().label, "Empty tile")
    }

    func testBoardPostponeDoesNotReopen() throws {
        try launch("board-timeout")
        resolve("postpone", kind: "board")
        XCTAssertTrue((cell().value as? String)?.hasPrefix("Not completed") == true)
    }

    func testBoardCompleteDoesNotReopen() throws {
        try launch("board-timeout")
        resolve("complete", kind: "board")
        XCTAssertTrue((cell().value as? String)?.hasPrefix("Completed") == true)
    }

    func testBoardCancelDoesNotReopen() throws {
        try launch("board-timeout")
        resolve("remove", kind: "board")
        XCTAssertTrue((cell().value as? String)?.hasPrefix("Not completed") == true)
    }
}
