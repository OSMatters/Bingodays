import SwiftUI
import UIKit
import XCTest
@testable import Bingodays

final class DecorativeAnimationTests: XCTestCase {
    @MainActor
    private final class Controls: ObservableObject {
        @Published var reduceMotion = true
        @Published var scenePhase = ScenePhase.active
        @Published var isVisible = true
        var samples: [TimeInterval?] = []
    }

    private struct Probe: View {
        @ObservedObject var controls: Controls

        var body: some View {
            Group {
                if controls.isVisible {
                    DecorativeAnimationTimeline(isEnabled: !controls.reduceMotion) { time in
                        Color.clear
                            .onChange(of: time, initial: true) { _, value in
                                controls.samples.append(value)
                            }
                    }
                }
            }
            .environment(\.scenePhase, controls.scenePhase)
        }
    }

    @MainActor
    func testVisualClockStopsAndRestartsWithEnablementSceneAndVisibility() async throws {
        let controls = Controls()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 160, height: 160))
        window.rootViewController = UIHostingController(rootView: Probe(controls: controls))
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }

        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(controls.samples.isEmpty)
        XCTAssertTrue(controls.samples.allSatisfy { $0 == nil })

        controls.reduceMotion = false
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(controls.samples.contains { ($0 ?? 0) > 0 })

        controls.reduceMotion = true
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(controls.samples.last ?? nil)
        let stoppedCount = controls.samples.count
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(controls.samples.count, stoppedCount)

        controls.scenePhase = .background
        controls.reduceMotion = false
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(controls.samples.last ?? nil)

        controls.scenePhase = .active
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNotNil(controls.samples.last ?? nil)

        controls.isVisible = false
        try await Task.sleep(for: .milliseconds(150))
        let hiddenCount = controls.samples.count
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(controls.samples.count, hiddenCount)

        controls.isVisible = true
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNotNil(controls.samples.last ?? nil)
        XCTAssertGreaterThan(controls.samples.count, hiddenCount)
    }
}
