import Combine
import UIKit

@MainActor
final class RewardEditorInputSession: ObservableObject {
    enum Field {
        case title, points, emoji
    }

    struct SaveInput {
        let title: String
        let pointsText: String

        var requiredPoints: Int? {
            guard let value = Int(pointsText), (1...9_999).contains(value) else { return nil }
            return value
        }
    }

    private final class Registration {
        weak var textField: UITextField?
        let field: Field

        init(_ textField: UITextField, field: Field) {
            self.textField = textField
            self.field = field
        }
    }

    private var registrations: [ObjectIdentifier: Registration] = [:]

    func register(_ textField: UITextField, field: Field) {
        registrations = registrations.filter { $0.value.textField != nil }
        registrations[ObjectIdentifier(textField)] = Registration(textField, field: field)
    }

    func unregister(_ textField: UITextField) {
        registrations.removeValue(forKey: ObjectIdentifier(textField))
    }

    /// Read UIKit's actual text before ending editing can update/rebuild the
    /// SwiftUI tree. Saving must not depend on a later binding update.
    func prepareSave(fallbackTitle: String, fallbackPoints: String) -> SaveInput {
        let fields = Array(registrations.values)
        fields.compactMap(\.textField).forEach { $0.unmarkText() }
        let title = fields.first { $0.field == .title }?.textField?.text ?? fallbackTitle
        let points = fields.first { $0.field == .points }?.textField?.text ?? fallbackPoints
        let input = SaveInput(
            title: String(title.prefix(AppSettings.maxRewardTitleLength))
                .trimmingCharacters(in: .whitespacesAndNewlines),
            pointsText: String(points.compactMap { $0.wholeNumberValue.map(String.init) }.joined().prefix(4))
        )
        endEditing()
        return input
    }

    func endEditing() {
        let fields = registrations.values.compactMap(\.textField)
        for textField in fields {
            textField.unmarkText()
            textField.sendActions(for: .editingChanged)
            textField.resignFirstResponder()
        }
    }
}
