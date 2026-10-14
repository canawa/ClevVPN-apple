import SwiftUI
import ClevVPNKit

@main
struct ClevVPNApp: App {
    @StateObject private var state = AppState()
    @AppStorage("appLanguage") private var appLanguage = "system"

    init() {
        #if canImport(Libbox)
        LibboxPingEngine.install()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
                .tint(Theme.yellow)
                // Смена языка без перезапуска: SwiftUI сам разрешает строки по
                // locale из окружения, поэтому пересобирать иерархию (.id) не
                // нужно — переключение мгновенное.
                .environment(\.locale, appLanguage == "system" ? .current : Locale(identifier: appLanguage))
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if state.hasSubscription {
                ConnectView()
            } else {
                ActivationView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: state.hasSubscription)
    }
}
