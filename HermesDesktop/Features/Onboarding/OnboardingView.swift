import SwiftUI

// MARK: - OnboardingView

/// The initial connection screen presented when no Hermes API credentials
/// have been configured yet.
///
/// The user enters their API URL and API key, taps **Connect**, and on
/// success the `onConnected` closure is called so the parent can
/// navigate to the main application.
struct OnboardingView: View {

    // MARK: State

    @State private var viewModel = OnboardingViewModel()

    // MARK: Callbacks

    /// Invoked after a successful health check, signalling the parent to
    /// navigate away from the onboarding flow.
    let onConnected: () -> Void

    // MARK: Body

    var body: some View {
        VStack(spacing: Space.xl) {

            // App icon
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.hkAccent)

            // Title
            Text("Hermes Desktop")
                .font(.hkHeading)
                .foregroundStyle(Color.hkInk)

            // Subtitle
            Text("Connect to your Hermes Agent on VPS")
                .font(.hkBody)
                .foregroundStyle(Color.hkMuted)

            // Form fields
            VStack(alignment: .leading, spacing: Space.md) {
                TextField("API URL (e.g. http://vps:8642)", text: $viewModel.apiURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.hkBody)

                SecureField("API Key", text: $viewModel.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.hkBody)
            }
            .frame(width: 320)

            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.hkCaption)
                    .foregroundStyle(Color.red)
                    .multilineTextAlignment(.center)
                    .frame(width: 320)
                    .onTapGesture {
                        viewModel.clearError()
                    }
            }

            // Connect button
            Button(action: { Task { await viewModel.connect() } }) {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Connect")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(viewModel.isLoading)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(Space.xxl)
        .frame(minWidth: 480, minHeight: 400)
        .background(Color.hkPaper)
        .onChange(of: viewModel.isConnected) { _, connected in
            if connected { onConnected() }
        }
    }
}

// MARK: - PrimaryButtonStyle

/// A simple filled-accent button style used by the onboarding connect
/// button and reusable across the application.
private struct PrimaryButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hkBodyEm)
            .foregroundStyle(Color.hkInk)
            .frame(minWidth: 160)
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.hkAccent)
                    .opacity(configuration.isPressed ? 0.7 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(onConnected: {
        print("Connected — navigate to main app")
    })
}
