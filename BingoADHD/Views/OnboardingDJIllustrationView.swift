import SwiftUI

struct OnboardingDJIllustrationView: View {
    private let artworkSize = CGSize(width: 1028, height: 1530)
    // The square crop is centered on the record's spindle hole in source pixels.
    private let recordBounds = CGRect(x: 643.5, y: 113.5, width: 340, height: 340)

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / artworkSize.width
            let record = CGRect(
                x: recordBounds.minX * scale,
                y: recordBounds.minY * scale,
                width: recordBounds.width * scale,
                height: recordBounds.height * scale
            )

            ZStack(alignment: .topLeading) {
                Image(decorative: "OnboardingJuanjuanDJ")
                    .resizable()
                    .interpolation(.high)
                    .mask {
                        Path { path in
                            path.addRect(CGRect(origin: .zero, size: geometry.size))
                            path.addRect(record)
                        }
                        .fill(style: FillStyle(eoFill: true))
                    }

                DecorativeAnimationTimeline { time in
                    let turn = (time ?? 0).truncatingRemainder(dividingBy: 6) / 6

                    Image(decorative: "OnboardingJuanjuanDJ")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .offset(x: -record.minX, y: -record.minY)
                        .frame(width: record.width, height: record.height, alignment: .topLeading)
                        .clipped()
                        .rotationEffect(.degrees(turn * 360))
                        .position(x: record.midX, y: record.midY)
                }
            }
        }
        .aspectRatio(artworkSize.width / artworkSize.height, contentMode: .fit)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
