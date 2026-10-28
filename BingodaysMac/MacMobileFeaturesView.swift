import SwiftUI
import CoreImage.CIFilterBuiltins

struct MacMobileFeaturesView: View {
    @Environment(\.dismiss) private var dismiss
    private let mobileURL = URL(string: "https://apps.apple.com/app/id6760203837")!
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "iphone").font(.system(size: 46)).foregroundStyle(.brown)
            Text("更多小惊喜，在移动端").font(.title2.bold())
            Text("Mac 陪你专注完成任务。\n在 iPhone 或 iPad 上体验 Bingo 日记、\n积分奖励、贴纸盲盒等更多功能。")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(5)
            if let qr = qrImage {
                Image(nsImage: qr).interpolation(.none).resizable().frame(width: 130, height: 130)
                Text("扫码打开 App Store").font(.caption).foregroundStyle(.secondary)
            }
            Link("在 App Store 查看 Bingodays", destination: mobileURL)
            Text("开启 iCloud 同步后，可在两端继续处理同一份任务。")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("继续完成任务") { dismiss() }.keyboardShortcut(.defaultAction)
        }.padding(36).frame(width: 440)
    }
    private var qrImage: NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(mobileURL.absoluteString.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 5, y: 5)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
