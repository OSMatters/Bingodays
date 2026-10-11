import UIKit

/// A separate input context keeps reward emoji entry independent of title input.
final class RewardEmojiTextField: UITextField {
    override var textInputContextIdentifier: String? {
        "com.bingoday.reward-emoji"
    }

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" }
            ?? super.textInputMode
    }
}
