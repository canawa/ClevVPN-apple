import SwiftUI
import ClevVPNKit

/// Вкладка «Подписка» — общая карточка, одинаковая с macOS/Windows/Android.
struct SubscriptionTabView: View {
    @EnvironmentObject private var state: AppState
    @State private var showLogoutConfirm = false

    var body: some View {
        SubscriptionSettingsCard(
            title: state.subscription?.title,
            info: state.subscription?.userInfo,
            isLoading: state.isLoading,
            errorMessage: state.errorMessage,
            supportURL: state.subscription?.supportURL,
            onRefresh: { Task { await state.refreshSubscription() } },
            onDelete: { showLogoutConfirm = true }
        )
        .confirmationDialog(Text("Remove the access key from this device?"),
                            isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { state.logout() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Смена языка — 1:1 с `MacLanguageView`, применяется сразу, без перезапуска.
struct LanguageTabView: View {
    @AppStorage("appLanguage") private var appLanguage = "system"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Language")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)

                VStack(spacing: 0) {
                    row("system", Text("System"))
                    Divider().overlay(Theme.stroke)
                    row("ru", Text(verbatim: "Русский"))
                    Divider().overlay(Theme.stroke)
                    row("en", Text(verbatim: "English"))
                }
                .card()
            }
            .padding(20)
        }
    }

    private func row(_ code: String, _ title: Text) -> some View {
        Button {
            guard appLanguage != code else { return }
            // Меняем и AppleLanguages (для bundle-строк), и appLanguage (для
            // environment locale) — как на macOS.
            appLanguage = code
            if code == "system" {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([code], forKey: "AppleLanguages")
            }
        } label: {
            HStack {
                title.foregroundColor(Theme.textPrimary)
                Spacer()
                if appLanguage == code {
                    Image(systemName: "checkmark").foregroundColor(Theme.yellow)
                }
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
