import SwiftUI

/// Boxed text field with a small inline label, matching the design's form fields.
/// Error text is announced by VoiceOver as part of the field's value.
public struct NovaTextField: View {
    let label: String
    @Binding var text: String
    let prompt: String
    let error: String?
    let isSecure: Bool
    let contentType: UITextContentType?
    let keyboard: UIKeyboardType
    let autocapitalization: TextInputAutocapitalization

    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    public init(
        _ label: String,
        text: Binding<String>,
        prompt: String = "",
        error: String? = nil,
        isSecure: Bool = false,
        contentType: UITextContentType? = nil,
        keyboard: UIKeyboardType = .default,
        autocapitalization: TextInputAutocapitalization = .sentences
    ) {
        self.label = label
        _text = text
        self.prompt = prompt
        self.error = error
        self.isSecure = isSecure
        self.contentType = contentType
        self.keyboard = keyboard
        self.autocapitalization = autocapitalization
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(label)
                        .font(NovaFont.caption)
                        .foregroundStyle(NovaColor.textSecondary)
                        .accessibilityHidden(true) // spoken as the field's label instead
                    field
                        .accessibilityLabel(label)
                        .accessibilityHint(error ?? "")
                        .font(NovaFont.body)
                        .foregroundStyle(NovaColor.textPrimary)
                        .textContentType(contentType)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(autocapitalization)
                        .autocorrectionDisabled(isSecure || keyboard == .emailAddress)
                        .focused($isFocused)
                }
                if isSecure {
                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .foregroundStyle(NovaColor.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(minHeight: 56)
            .background(NovaColor.surface, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused || error != nil ? 1.2 : 0.8)
            }
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }

            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(NovaFont.caption)
                    .foregroundStyle(NovaColor.error)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: error)
        // Deliberately *not* `.accessibilityElement(children: .combine)`: combining would turn the
        // field into a static element — VoiceOver couldn't edit it and UI tests couldn't find it.
    }

    @ViewBuilder
    private var field: some View {
        if isSecure, !isRevealed {
            SecureField(prompt, text: $text)
        } else {
            TextField(prompt, text: $text)
        }
    }

    private var borderColor: Color {
        if error != nil {
            return NovaColor.error
        }
        return isFocused ? NovaColor.accent : NovaColor.border
    }
}
