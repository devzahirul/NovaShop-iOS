import SwiftUI
import UIKit

public extension View {
    /// Adds a "Done" button above the keyboard. Number pads have no return key, so without this
    /// there is no way to dismiss them and the form's primary button stays covered.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("keyboard.done")
            }
        }
    }
}

/// Ends editing in the key window (fields own their focus state internally).
@MainActor
public func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
