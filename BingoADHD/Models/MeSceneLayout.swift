import SwiftUI

struct MeSceneLayout {
    let scale: CGFloat
    let contentWidth: CGFloat
    let titleCenter: CGPoint
    let pickerFrame: CGRect
    let characterFrame: CGRect
    let streakFrame: CGRect
    let crownFrame: CGRect
    let reviewFrame: CGRect
    let diaryArtworkFrame: CGRect
    let diaryButtonFrame: CGRect
    let catCenter: CGPoint
    let backgroundVerticalOffset: CGFloat

    static func resolve(
        skin: MeSkin,
        availableSize size: CGSize,
        safeAreaInsets: EdgeInsets,
        isPadLayout: Bool,
        bottomInset: CGFloat
    ) -> Self {
        if skin == .autumn {
            let height = size.height + safeAreaInsets.top + safeAreaInsets.bottom
            let scale = min(size.width / 393, (height - bottomInset) / 849, 1.08)
            let origin = CGPoint(
                x: (size.width - 393 * scale) / 2,
                y: max(0, (height - 849 * scale) * 0.35) - safeAreaInsets.top
            )
            func frame(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
                CGRect(x: origin.x + x * scale, y: origin.y + y * scale,
                       width: width * scale, height: height * scale)
            }
            // Keep the artwork's full canvas at the original scene position.
            return Self(
                scale: scale,
                contentWidth: 393 * scale,
                titleCenter: CGPoint(x: size.width / 2, y: origin.y + 155 * scale),
                pickerFrame: CGRect(x: origin.x + 20 * scale,
                                    y: max(0, origin.y + 47 * scale), width: 76, height: 44),
                characterFrame: frame(-4, 289, 401, 401),
                streakFrame: frame(43, 239, 80, 98),
                crownFrame: frame(218, 223, 150, 150),
                reviewFrame: frame(27, 350, 128, 52),
                diaryArtworkFrame: frame(255, 520, 110, 123).offsetBy(dx: -15, dy: 0),
                diaryButtonFrame: frame(201, 634, 158, 65).offsetBy(dx: -15, dy: 0),
                catCenter: .zero,
                backgroundVerticalOffset: 0
            )
        }

        // Preserve the existing layouts for the two earlier themes.
        let width = min(size.width, isPadLayout ? 430 : 393)
        let scale = min(max(min(width / 393, (size.height - bottomInset) / 849),
                            isPadLayout ? 0.9 : 0.82), isPadLayout ? 1.08 : 1)
        let lift = isPadLayout ? max(0, (size.height - 849 * scale) * 0.18) : 0
        let portrait = isPadLayout && size.height > size.width
        let characterOffset: CGFloat = 16 + (isPadLayout ? 20 : 0) + (portrait ? 40 : 0)
        let centerX = size.width / 2
        func frame(centerX: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
            CGRect(x: centerX - width * scale / 2, y: y - height * scale / 2,
                   width: width * scale, height: height * scale)
        }
        return Self(
            scale: scale,
            contentWidth: width,
            titleCenter: CGPoint(x: centerX, y: 118 * scale + lift),
            pickerFrame: CGRect(x: centerX - width / 2 + 20,
                                y: 42 * scale + lift - 22, width: 76, height: 44),
            characterFrame: frame(centerX: centerX, y: 476 * scale + lift + characterOffset,
                                  width: isPadLayout ? 424 : 392, height: isPadLayout ? 424 : 392),
            streakFrame: frame(centerX: centerX - width / 2 + 96 * scale,
                               y: 266 * scale + lift + 16,
                               width: isPadLayout ? 108 : 96, height: isPadLayout ? 124 : 110),
            crownFrame: frame(centerX: centerX + width / 2 - 126 * scale,
                              y: 270 * scale + lift + 16,
                              width: isPadLayout ? 168 : 150, height: isPadLayout ? 168 : 150),
            reviewFrame: frame(centerX: centerX - width / 2 + 125 * scale + (portrait ? -60 : 0),
                               y: 383 * scale + lift + characterOffset,
                               width: isPadLayout ? 163 : 142, height: isPadLayout ? 80 : 70),
            diaryArtworkFrame: frame(centerX: centerX + width / 2 - 173 * scale,
                                     y: 557 * scale + lift + characterOffset,
                                     width: isPadLayout ? 108 : 94, height: isPadLayout ? 80 : 70),
            diaryButtonFrame: frame(centerX: centerX + width / 2 - 199 * scale,
                                    y: 623 * scale + lift + characterOffset,
                                    width: isPadLayout ? 205 : 178, height: isPadLayout ? 84 : 73),
            catCenter: CGPoint(x: centerX - width / 2 + 70 * scale,
                               y: 674 * scale + lift + characterOffset),
            backgroundVerticalOffset: isPadLayout && !portrait ? -60 : 0
        )
    }
}
