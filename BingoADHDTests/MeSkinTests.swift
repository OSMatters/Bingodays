import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Bingodays

@MainActor
struct MeSkinTests {
    @Test(arguments: [nil, "normal", "halloween", "autumn", "unknown"] as [String?])
    func autumnIntroductionAppliesToEveryPreviousSelection(previousSelection: String?) {
        let suiteName = "MeSkinTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        if let previousSelection {
            defaults.set(previousSelection, forKey: AppSettings.meSkinKey)
        }

        MeSkinMigration.applyIfNeeded(defaults: defaults)

        #expect(defaults.string(forKey: AppSettings.meSkinKey) == "autumn")
        #expect(defaults.bool(forKey: MeSkinMigration.completionKey))
    }

    @Test(arguments: MeSkin.allCases)
    func laterLaunchPreservesUserSelection(selection: MeSkin) {
        let suiteName = "MeSkinTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        MeSkinMigration.applyIfNeeded(defaults: defaults)
        defaults.set(selection.rawValue, forKey: AppSettings.meSkinKey)

        MeSkinMigration.applyIfNeeded(defaults: defaults)

        #expect(defaults.string(forKey: AppSettings.meSkinKey) == selection.rawValue)
    }

    @Test(arguments: MeSkin.allCases)
    func allThemeStateResourcesAreBundled(skin: MeSkin) {
        #expect(UIImage(named: skin.backgroundImageName) != nil)
        #expect(UIImage(named: skin.crownArrowImageName) != nil)
        #expect(UIImage(named: skin.pickerImageName) != nil)
        for isPremium in [false, true] {
            for hasReviewed in [false, true] {
                let name = skin.characterImageName(isPremiumMember: isPremium, hasReviewedApp: hasReviewed)
                #expect(UIImage(named: name) != nil, "Missing Me resource: \(name)")
            }
        }
        #expect(UIImage(named: "MeAutumnBooks") != nil)
    }

    @Test(arguments: [CGSize(width: 320, height: 480), CGSize(width: 393, height: 730),
                      CGSize(width: 768, height: 950), CGSize(width: 1100, height: 700)])
    func autumnActionsFitAvailableRegion(size: CGSize) {
        let layout = MeSceneLayout.resolve(
            skin: .autumn, availableSize: size,
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 83, trailing: 0),
            isPadLayout: size.width > 600, bottomInset: 0
        )
        let bounds = CGRect(origin: .zero, size: size)
        #expect(bounds.contains(layout.pickerFrame))
        #expect(bounds.contains(layout.reviewFrame))
        #expect(bounds.contains(layout.diaryButtonFrame))
        #expect(layout.diaryArtworkFrame.maxY <= layout.diaryButtonFrame.minY + 12 * layout.scale)
    }
}
