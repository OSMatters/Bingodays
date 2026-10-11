import UIKit

/// Measures the same font/wrapping used by the cell; no character truncation.
enum BingoBoardTextFitter {
    static func font(size: CGFloat) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: .medium)
        if AppLanguage.current == .english, let outfit = UIFont(name: "Outfit", size: size) {
            let descriptor = outfit.fontDescriptor.addingAttributes([
                .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.medium.rawValue]
            ])
            return UIFont(descriptor: descriptor, size: size)
        }
        return font
    }

    static func fits(_ text: String, fontSize: CGFloat, in size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byCharWrapping
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: size.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font(size: fontSize), .paragraphStyle: paragraph],
            context: nil
        )
        return ceil(bounds.height) <= floor(size.height) && ceil(bounds.width) <= ceil(size.width)
    }

    static func image(for text: String, in size: CGSize, maximumFontSize: CGFloat? = nil, color: UIColor = UIColor(red: 41 / 255, green: 30 / 255, blue: 10 / 255, alpha: 1)) -> UIImage {
        let fontSize = fontSize(for: text, in: size, maximum: maximumFontSize ?? min(15, size.height * 0.45))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byCharWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(size: fontSize), .paragraphStyle: paragraph,
            .foregroundColor: color
        ]
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: size.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            (text as NSString).draw(
                with: CGRect(x: 0, y: max(0, (size.height - ceil(bounds.height)) / 2), width: size.width, height: ceil(bounds.height)),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil
            )
        }
    }

    static func fontSize(for text: String, in size: CGSize, maximum: CGFloat) -> CGFloat {
        var low: CGFloat = 0.5
        var high = maximum
        for _ in 0..<12 {
            let candidate = (low + high) / 2
            if fits(text, fontSize: candidate, in: size) { low = candidate } else { high = candidate }
        }
        return low
    }
}
