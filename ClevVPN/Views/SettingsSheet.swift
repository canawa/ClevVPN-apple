import SwiftUI
import ClevVPNKit

/// Разделы, спрятанные под шестерёнкой — 1:1 с `MacSettingsSheet`.
struct SettingsSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    /// CLEV_SCREEN=apps|rules|subscription|language — открыть нужную вкладку сразу
    /// (для скриншотов из скриптов).
    @State private var tab: SettingsTab = {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["CLEV_SCREEN"],
           let tab = SettingsTab(rawValue: name) {
            return tab
        }
        #endif
        return .apps
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            ClevSegmentedTabs(selection: $tab)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            Divider().overlay(Theme.stroke)

            switch tab {
            case .apps: AppsTabView()
            case .rules: RulesTabView()
            case .subscription: SubscriptionTabView()
            case .language: LanguageTabView()
            }
        }
        .background(Theme.background)
    }
}
