import SwiftUI
import ClevVPNKit

/// Главный экран iOS — 1:1 с `MacHomeView`: кнопка, карточка подписки и список
/// серверов. Настройки, приложения, правила и язык — в шестерёнке.
struct ConnectView: View {
    @EnvironmentObject private var state: AppState

    @State private var filter: HomeFilter = .all
    /// CLEV_SCREEN=settings (или имя вкладки настроек) — сразу открыть настройки
    /// (для скриншотов из скриптов).
    @State private var showSettings: Bool = {
        #if DEBUG
        let screen = ProcessInfo.processInfo.environment["CLEV_SCREEN"] ?? ""
        return screen == "settings" || SettingsTab(rawValue: screen) != nil
        #else
        return false
        #endif
    }()

    var body: some View {
        mainStack
            .background(Theme.background.ignoresSafeArea())
            .background(StatusGlow(status: glowStatus).ignoresSafeArea())
            .overlay(alignment: .top) {
                if let toast = state.toast {
                    ToastView(toast: toast)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.toast)
            .sheet(isPresented: $showSettings) {
                SettingsSheet().environmentObject(state)
            }
            .onChangeCompat(of: state.settingsDismissTick) { _ in
                showSettings = false
            }
    }

    private var glowStatus: StatusGlow.Status {
        switch state.vpn.state {
        case .connected: return .on
        case .connecting, .disconnecting: return .busy
        case .disconnected, .invalid: return .off
        }
    }

    private var mainStack: some View {
        VStack(spacing: 12) {
            topBar

            ConnectButton(state: buttonState, size: 150, connectedAt: state.vpn.connectedAt, isPinging: state.isPinging) {
                // Пока идёт пинг (и VPN выключен) — нажатие отменяет пинг
                if state.isPinging && state.vpn.state == .disconnected {
                    state.cancelPing()
                } else {
                    Task { await state.toggleConnection() }
                }
            }
            .padding(.top, 2)

            // Только ошибка (текст статуса убран — состояние видно по кнопке)
            if let error = state.vpn.lastError, !AppState.demoMode {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(Theme.red)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Announce + трафик/дата — одна карточка, разделённые линией
            VStack(spacing: 0) {
                if let announce = state.subscription?.announce,
                   !announce.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    AnnounceText(text: announce)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    Divider().overlay(Theme.stroke)
                }
                infoBar
            }
            .card()
            .padding(.horizontal, 20)

            HomeFilterChips(filter: $filter,
                            order: state.filterOrder,
                            onReorder: { state.filterOrder = $0 })

            ScrollView {
                LazyVStack(spacing: 6) {
                    if filteredServers.isEmpty {
                        Text("No servers here yet")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                            .padding(.top, 24)
                    }
                    ForEach(filteredServers) { server in
                        QuickServerRow(
                            server: server,
                            isSelected: state.selectedServer?.id == server.id,
                            isFavorite: state.favorites.contains(server.id),
                            ping: state.pings[server.id],
                            isPinging: state.pingingServerIDs.contains(server.id)
                        ) {
                            Task { await state.select(server: server) }
                        }
                        .contextMenu {
                            Button {
                                state.pingOne(server)
                            } label: {
                                Label("Ping this server", systemImage: "bolt.horizontal")
                            }
                            Button {
                                state.toggleFavorite(server)
                            } label: {
                                if state.favorites.contains(server.id) {
                                    Label("Remove from My", systemImage: "star.slash")
                                } else {
                                    Label("Add to My", systemImage: "star")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .task {
            await state.vpn.refresh()
            state.startAutoRefresh()
            if state.pings.isEmpty {
                state.pingAll()
            }
            #if DEBUG
            if ProcessInfo.processInfo.environment["CLEV_AUTOCONNECT"] == "1",
               state.vpn.state == .disconnected {
                await state.toggleConnection()
            }
            #endif
        }
    }

    /// Строка трафика и даты с иконками пинга (слева) и обновления (справа).
    private var infoBar: some View {
        HStack(spacing: 10) {
            Button {
                state.pingAll()
            } label: {
                if state.isPinging {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .foregroundColor(Theme.yellow)
                }
            }
            .buttonStyle(.plain)
            .disabled(state.isPinging)

            if let info = state.subscription?.userInfo {
                if let used = info.usedBytes {
                    Label {
                        if let total = info.totalBytes, total > 0 {
                            Text(verbatim: "\(format(used)) / \(format(total))")
                        } else {
                            Text(verbatim: format(used))
                        }
                    } icon: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                if let expires = info.expiresAt {
                    Label {
                        Text(expires, style: .date)
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                }
            } else {
                Spacer()
            }

            Button {
                Task { await state.refreshSubscription() }
            } label: {
                if state.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundColor(Theme.yellow)
                }
            }
            .buttonStyle(.plain)
            .disabled(state.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }

    /// Верхняя панель: логотип по центру, шестерёнка в углу.
    private var topBar: some View {
        ZStack {
            ClevLogoFull(logoHeight: 20)
            HStack {
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    /// Серверы выбранной вкладки; избранные закрепляются сверху.
    private var filteredServers: [Server] {
        filter.apply(to: state.servers).sorted { a, b in
            let aFav = state.favorites.contains(a.id)
            let bFav = state.favorites.contains(b.id)
            return aFav && !bFav
        }
    }

    private var buttonState: ConnectButton.Status {
        switch state.vpn.state {
        case .connected: return .on
        case .connecting, .disconnecting: return .busy
        case .disconnected, .invalid: return .off
        }
    }
}

/// Выбор серверов для вкладки «Мои» — 1:1 с `MacMineEditor`.
struct MineEditorSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [Server] {
        guard !search.isEmpty else { return state.servers }
        return state.servers.filter { $0.rawName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("My servers")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            TextField("Search servers", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filtered) { server in
                        Button {
                            state.toggleFavorite(server)
                        } label: {
                            HStack(spacing: 10) {
                                Text(server.flagEmoji ?? "🌐")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(server.name)
                                        .font(.subheadline)
                                        .foregroundColor(Theme.textPrimary)
                                        .lineLimit(1)
                                    if let desc = server.descriptionText, !desc.isEmpty {
                                        Text(desc)
                                            .font(.caption2)
                                            .foregroundColor(Theme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: state.favorites.contains(server.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(state.favorites.contains(server.id)
                                                     ? Theme.yellow : Theme.stroke)
                            }
                            .padding(10)
                            .card()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .background(Theme.background)
    }
}
