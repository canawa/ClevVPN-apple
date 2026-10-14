import SwiftUI
import ClevVPNKit

/// Маршрутизация по приложениям — вкладка 1:1 с `MacAppsView`.
/// На iOS список установленных приложений недоступен (Apple не даёт
/// process-based routing в consumer Packet Tunnel), поэтому при включённом
/// режиме показываем пустой список с тем же UI, что на Mac.
struct AppsTabView: View {
    @EnvironmentObject private var state: AppState
    @State private var search = ""

    var body: some View {
        VStack(spacing: 12) {
            modePicker
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            if state.appRoutingMode != .off {
                TextField("Search apps", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 20)

                ScrollView {
                    LazyVStack(spacing: 6) {
                        // На iOS установленных приложений нет — список пустой.
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            } else {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.stroke)
                    Text("Choose a mode to route traffic by app")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
            }
        }
        .onChange(of: state.appRoutingMode) { _ in
            Task { await state.reconnectIfConnected() }
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App routing")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)

            ClevSegmentedPicker(selection: $state.appRoutingMode, options: [
                (.off, "Off"),
                (.bypassSelected, "Bypass VPN"),
                (.onlySelected, "Only via VPN")
            ])

            Text(modeHint)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private var modeHint: LocalizedStringKey {
        switch state.appRoutingMode {
        case .off:
            return "All traffic follows the mode from the «Rules» tab"
        case .bypassSelected:
            return "Selected apps go direct; everything else — via VPN"
        case .onlySelected:
            return "Only selected apps use VPN; everything else goes direct"
        }
    }
}
