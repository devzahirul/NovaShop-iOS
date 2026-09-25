import DesignSystem
import Domain
import SwiftUI

/// Modal auth flow: Sign in (02) → Create account (03) → Style preferences (04).
/// Presented only when an action needs an account; `onFinish` resumes the pending route.
public struct AuthFlowView: View {
    private enum Step: Hashable { case signUp, preferences }

    @State private var path: [Step] = []
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    private let onFinish: () -> Void

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    public var body: some View {
        NavigationStack(path: $path) {
            SignInView(viewModel: SignInViewModel(session: session), onCreateAccount: { path.append(.signUp) }, onSuccess: onFinish)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark").foregroundStyle(NovaColor.textPrimary)
                        }
                        .accessibilityLabel("Close")
                    }
                }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .signUp:
                        SignUpView(viewModel: SignUpViewModel(session: session)) { path.append(.preferences) }
                    case .preferences:
                        StylePreferencesView(viewModel: StylePreferencesViewModel(session: session), onFinish: onFinish)
                    }
                }
        }
        .tint(NovaColor.accent)
    }
}

struct AuthHeader: View {
    let title: String
    let subtitle: String
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if let imageURL {
                RemoteImage(imageURL)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title).font(NovaFont.title).foregroundStyle(NovaColor.textPrimary).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(NovaFont.body).foregroundStyle(NovaColor.textSecondary)
            }
        }
    }
}

// MARK: - Sign in (design 02)

struct SignInView: View {
    @State private var viewModel: SignInViewModel
    @Environment(SessionStore.self) private var session
    let onCreateAccount: () -> Void
    let onSuccess: () -> Void

    init(viewModel: @autoclosure @escaping () -> SignInViewModel, onCreateAccount: @escaping () -> Void, onSuccess: @escaping () -> Void) {
        _viewModel = State(wrappedValue: viewModel())
        self.onCreateAccount = onCreateAccount
        self.onSuccess = onSuccess
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                AuthHeader(
                    title: "Welcome Back",
                    subtitle: "Sign in to continue to NovaShop",
                    imageURL: URL(string: "https://images.unsplash.com/photo-1434389677669-e08b4cac3105?auto=format&fit=crop&q=75")
                )
                VStack(spacing: Spacing.md) {
                    NovaTextField(
                        "Email address", text: $viewModel.email, prompt: "name@email.com", error: viewModel.fieldErrors[.email],
                        contentType: .username, keyboard: .emailAddress, autocapitalization: .never
                    )
                    .accessibilityIdentifier("auth.email")
                    NovaTextField(
                        "Password", text: $viewModel.password, error: viewModel.fieldErrors[.password], isSecure: true,
                        contentType: .password
                    )
                    .accessibilityIdentifier("auth.password")
                    HStack {
                        Spacer()
                        Button("Forgot Password?") {}
                            .font(NovaFont.caption.weight(.medium))
                            .tint(NovaColor.accent)
                    }
                }
                if let error = viewModel.error {
                    InlineBanner(error.message, style: .error)
                }
                NovaButton("Sign In", isLoading: viewModel.isSubmitting) {
                    Task {
                        if await viewModel.signIn() {
                            onSuccess()
                        }
                    }
                }
                .accessibilityIdentifier("auth.signIn")

                if session.supportsSocialSignIn {
                    SocialSignInButtons(isDisabled: viewModel.isSubmitting) { provider in
                        Task {
                            if await viewModel.signIn(with: provider) {
                                onSuccess()
                            }
                        }
                    }
                }

                HStack(spacing: Spacing.xs) {
                    Text("Don't have an account?").foregroundStyle(NovaColor.textSecondary)
                    Button("Sign Up", action: onCreateAccount).fontWeight(.semibold).tint(NovaColor.accent)
                        .accessibilityIdentifier("auth.goToSignUp")
                }
                .font(NovaFont.callout)
                .frame(maxWidth: .infinity)
            }
            .padding(Spacing.screen)
        }
        .scrollDismissesKeyboard(.interactively)
        .novaScreenBackground()
        .navigationTitle("NovaShop")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SocialSignInButtons: View {
    let isDisabled: Bool
    let action: (SocialProvider) -> Void

    var body: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Rectangle().fill(NovaColor.border).frame(height: 0.5)
                Text("or continue with").font(NovaFont.caption).foregroundStyle(NovaColor.textSecondary).fixedSize()
                Rectangle().fill(NovaColor.border).frame(height: 0.5)
            }
            Button { action(.apple) } label: {
                Label("Continue with Apple", systemImage: "apple.logo")
            }
            .buttonStyle(.nova(.outline))
            Button { action(.google) } label: {
                Label("Continue with Google", systemImage: "g.circle.fill")
            }
            .buttonStyle(.nova(.outline))
        }
        .disabled(isDisabled)
    }
}

// MARK: - Sign up (design 03)

struct SignUpView: View {
    @State private var viewModel: SignUpViewModel
    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(viewModel: @autoclosure @escaping () -> SignUpViewModel, onSuccess: @escaping () -> Void) {
        _viewModel = State(wrappedValue: viewModel())
        self.onSuccess = onSuccess
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                AuthHeader(
                    title: "Create an Account",
                    subtitle: "Join NovaShop for a brighter you.",
                    imageURL: URL(string: "https://images.unsplash.com/photo-1496747611176-843222e1e57c?auto=format&fit=crop&q=75")
                )
                VStack(spacing: Spacing.md) {
                    NovaTextField(
                        "Full name",
                        text: $viewModel.name,
                        prompt: "Olivia Chen",
                        error: viewModel.fieldErrors[.name],
                        contentType: .name,
                        autocapitalization: .words
                    )
                    .accessibilityIdentifier("signup.name")
                    NovaTextField(
                        "Email address",
                        text: $viewModel.email,
                        prompt: "name@email.com",
                        error: viewModel.fieldErrors[.email],
                        contentType: .username,
                        keyboard: .emailAddress,
                        autocapitalization: .never
                    )
                    .accessibilityIdentifier("signup.email")
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        NovaTextField(
                            "Password",
                            text: $viewModel.password,
                            error: viewModel.fieldErrors[.password],
                            isSecure: true,
                            contentType: .newPassword
                        )
                        .accessibilityIdentifier("signup.password")
                        if !viewModel.password.isEmpty {
                            ProgressView(value: viewModel.passwordStrength)
                                .tint(viewModel.passwordStrength > 0.7 ? NovaColor.success : NovaColor.accent)
                                .accessibilityLabel("Password strength")
                        }
                    }
                }
                Toggle(isOn: $viewModel.acceptedTerms) {
                    Text("I agree to the Terms of Service and Privacy Policy")
                        .font(NovaFont.caption)
                        .foregroundStyle(NovaColor.textSecondary)
                }
                .toggleStyle(CheckboxToggleStyle())
                .accessibilityIdentifier("signup.terms")
                if let error = viewModel.error {
                    InlineBanner(error.message, style: .error)
                }
                NovaButton("Create Account", isLoading: viewModel.isSubmitting) {
                    Task {
                        if await viewModel.signUp() {
                            onSuccess()
                        }
                    }
                }
                .disabled(!viewModel.canSubmit)
                .accessibilityIdentifier("signup.submit")
                HStack(spacing: Spacing.xs) {
                    Text("Already have an account?").foregroundStyle(NovaColor.textSecondary)
                    Button("Sign In") { dismiss() }.fontWeight(.semibold).tint(NovaColor.accent)
                }
                .font(NovaFont.callout)
                .frame(maxWidth: .infinity)
            }
            .padding(Spacing.screen)
        }
        .scrollDismissesKeyboard(.interactively)
        .novaScreenBackground()
        .navigationTitle("NovaShop")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(configuration.isOn ? NovaColor.accent : NovaColor.textTertiary)
                    .font(.title3)
                configuration.label
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
    }
}

// MARK: - Preferences (design 04)

struct StylePreferencesView: View {
    @State private var viewModel: StylePreferencesViewModel
    let onFinish: () -> Void

    init(viewModel: @autoclosure @escaping () -> StylePreferencesViewModel, onFinish: @escaping () -> Void) {
        _viewModel = State(wrappedValue: viewModel())
        self.onFinish = onFinish
    }

    private static let images: [StylePreference: String] = [
        .casual: "1517841905240-472988babdf9", .chic: "1583846717393-dc2412c95ed7", .minimal: "1564584217132-2271feaeb3c5",
        .trendy: "1529139574466-a303027c1d8b", .classic: "1554412933-514a83d2f3c8", .boho: "1496747611176-843222e1e57c",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                ProgressView(value: 1, total: 1).tint(NovaColor.accent)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Tell us your style").font(NovaFont.title).accessibilityAddTraits(.isHeader)
                    Text("So we can personalize your experience.").font(NovaFont.body).foregroundStyle(NovaColor.textSecondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.lg), count: 3), spacing: Spacing.xl) {
                    ForEach(StylePreference.allCases) { style in
                        let isSelected = viewModel.selected.contains(style)
                        Button {
                            viewModel.toggle(style)
                        } label: {
                            VStack(spacing: Spacing.sm) {
                                RemoteImage(
                                    URL(string: "https://images.unsplash.com/photo-\(Self.images[style] ?? "")?auto=format&fit=crop&q=75")
                                )
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(Circle())
                                .overlay { Circle().strokeBorder(isSelected ? NovaColor.accent : .clear, lineWidth: 3) }
                                .overlay(alignment: .bottomTrailing) {
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(NovaColor.onAccent, NovaColor.accent)
                                    }
                                }
                                Text(style.title).font(NovaFont.callout).foregroundStyle(NovaColor.textPrimary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(style.title)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .sensoryFeedback(.selection, trigger: isSelected)
                    }
                }
            }
            .padding(Spacing.screen)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Spacing.sm) {
                NovaButton("Continue", isLoading: viewModel.isSaving) {
                    Task {
                        await viewModel.save()
                        onFinish()
                    }
                }
                .disabled(viewModel.selected.isEmpty)
                .accessibilityIdentifier("preferences.continue")
                Button("Skip for now", action: onFinish).font(NovaFont.callout).tint(NovaColor.accent).frame(minHeight: 44)
            }
            .padding(Spacing.screen)
            .background(.bar)
        }
        .novaScreenBackground()
        .navigationBarBackButtonHidden()
    }
}
