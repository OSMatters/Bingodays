import SwiftUI
import UIKit
import WidgetKit

struct BingoDynamicIslandIcon: View {
    var size: CGFloat = 24

    // Resize the bitmap itself: a view frame doesn't reduce ActivityKit's image payload.
    private var artwork: Image {
        guard let original = UIImage(named: "DynamicIslandIcon"),
              let thumbnail = original.preparingThumbnail(of: CGSize(width: size * 3, height: size * 3)),
              let pixels = thumbnail.cgImage else {
            return Image(systemName: "square.grid.3x3.fill")
        }
        return Image(uiImage: UIImage(cgImage: pixels, scale: 3, orientation: thumbnail.imageOrientation))
            .renderingMode(.original)
    }

    var body: some View {
        Group {
            if #available(iOS 18, *) {
                artwork.resizable().widgetAccentedRenderingMode(.fullColor)
            } else {
                artwork.resizable()
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .unredacted()
        .accessibilityLabel("Bingodays")
    }
}
