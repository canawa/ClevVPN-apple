import SwiftUI
import ClevVPNKit

/// Экран активации — 1:1 с `MacActivationView` (адаптация под UIKit pasteboard).
struct ActivationView: View {
    @EnvironmentObject private var state: AppState
    @State private var link = ""

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ClevLogo()
                .frame(width: 110)
            (Text("Clev").foregroundColor(Theme.textPrimary)
                + Text("VPN").foregroundColor(Theme.yellow))
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Fast and reliable access without borders")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)

            TextField("Paste your access key", text: $link)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .frame(maxWidth: 320)
                .onSubmit { activate() }

            Button {
                if link.isEmpty, let pasted = UIPasteboard.general.string {
                    link = pasted
                }
                activate()
            } label: {
                if state.isLoading {
                    ProgressView().controlSize(.small).tint(.black)
                } else {
                    Text(link.isEmpty ? "Paste from clipboard" : "Activate")
                        .fontWeight(.semibold)
                        .frame(maxWidth: 280)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.yellow)
            .foregroundColor(.black)
            .controlSize(.large)
            .disabled(state.isLoading)

            if let error = state.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(Theme.red)
            }
            Spacer()
            Text("The key is provided with your subscription")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 30)
    }

    private func activate() {
        guard !link.isEmpty else { return }
        Task { await state.activate(urlString: link) }
    }
}
