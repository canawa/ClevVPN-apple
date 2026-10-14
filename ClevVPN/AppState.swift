import Foundation
import SwiftUI
import Combine
import ClevVPNKit

/// Общее состояние приложения: подписка, серверы, выбор, настройки.
@MainActor
final class AppState: ObservableObject {
    @Published var subscription: ClevVPNKit.Subscription?
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var selectedServerID: String? {
        didSet { SharedStore.selectedServerID = selectedServerID }
    }
    @Published var favorites: Set<String> {
        didSet { SharedStore.favoriteServerIDs = favorites }
    }
    @Published var folders: [ServerFolder] {
        didSet { SharedStore.folders = folders }
    }
    @Published var routingMode: RoutingMode {
        didSet { SharedStore.routingMode = routingMode }
    }
    @Published var customRules: [RoutingRule] {
        didSet { SharedStore.customRules = customRules }
    }
    /// Kill Switch: не выпускать трафик мимо VPN (защита от утечки реального IP).
    @Published var killSwitchEnabled: Bool {
        didSet {
            guard killSwitchEnabled != oldValue else { return }
            SharedStore.killSwitchEnabled = killSwitchEnabled
            // Применяем к активному туннелю переподключением с новыми параметрами.
            Task { await reconnectIfConnected() }
        }
    }
    /// Маршрутизация по приложениям (UI как на Mac; в consumer Packet Tunnel
    /// Apple не даёт process-based routing — в конфиг туннеля не передаём).
    @Published var appRules: [AppRule] {
        didSet { SharedStore.appRules = appRules }
    }
    @Published var appRoutingMode: AppRoutingMode {
        didSet { SharedStore.appRoutingMode = appRoutingMode }
    }
    /// Пользовательский порядок вкладок Home (перетаскиванием).
    @Published var filterOrder: [String] {
        didSet { SharedStore.filterOrder = filterOrder }
    }
    @Published var pings: [String: Int]
    @Published var isPinging = false

    let vpn = VPNManager.shared
    private var cancellables = Set<AnyCancellable>()

    #if DEBUG
    /// Demo только для Preview / сборки без Libbox, либо форс CLEV_DEMO=1.
    /// После bootstrap (Libbox подключён) схема ClevVPN ходит в реальный туннель.
    static let demoMode: Bool = {
        #if canImport(Libbox)
        return ProcessInfo.processInfo.environment["CLEV_DEMO"] == "1"
        #else
        return true
        #endif
    }()
    #else
    /// Release всегда с реальным туннелем (Libbox обязателен в схеме ClevVPN).
    static let demoMode = false
    #endif

    init() {
        subscription = SharedStore.cachedSubscription
        selectedServerID = SharedStore.selectedServerID
        favorites = SharedStore.favoriteServerIDs
        folders = SharedStore.folders
        routingMode = SharedStore.routingMode
        customRules = SharedStore.customRules
        killSwitchEnabled = SharedStore.killSwitchEnabled
        appRules = SharedStore.appRules
        appRoutingMode = SharedStore.appRoutingMode
        filterOrder = SharedStore.filterOrder
        pings = SharedStore.pingResults

        #if DEBUG
        // Demo-режим: без собранного ядра (или по CLEV_DEMO=1) всегда подставляем
        // preview-подписку из бандла (announce + все серверы) и «подключаемся»
        // понарошку — чтобы отсмотреть весь UI. Старый кэш не мешает.
        if Self.demoMode {
            let sub = Self.demoSubscription()
            KeychainStore.subscriptionURL = "demo"
            subscription = sub
            SharedStore.cachedSubscription = sub
            if selectedServerID == nil || !sub.servers.contains(where: { $0.id == selectedServerID }) {
                selectedServerID = sub.servers.first?.id
            }
        }
        #endif

        // Пробрасываем изменения VPN-статуса в состояние экрана — иначе SwiftUI
        // не наблюдает вложенный VPNManager и кнопка обновляется с задержкой.
        vpn.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var hasSubscription: Bool {
        KeychainStore.subscriptionURL != nil && subscription != nil
    }

    var servers: [Server] { subscription?.servers ?? [] }

    /// Выбранный сервер (или первый в списке, пока выбор не сделан).
    var selectedServer: Server? {
        guard let id = selectedServerID else { return servers.first }
        return servers.first { $0.id == id } ?? servers.first
    }

    // MARK: - Подписка

    func activate(urlString: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        #if DEBUG
        // Демо-режим для разработки: ключ "demo" загружает тестовые серверы без сети
        if urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "demo" {
            let sub = Self.demoSubscription()
            KeychainStore.subscriptionURL = "demo"
            subscription = sub
            SharedStore.cachedSubscription = sub
            selectedServerID = sub.servers.first?.id
            return true
        }
        #endif
        do {
            let sub = try await SubscriptionClient().fetch(from: urlString)
            KeychainStore.subscriptionURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            subscription = sub
            SharedStore.cachedSubscription = sub
            if selectedServerID == nil {
                selectedServerID = sub.servers.first?.id
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshSubscription() async {
        guard let url = KeychainStore.subscriptionURL else { return }
        #if DEBUG
        if url == "demo" { return }
        #endif
        isLoading = true
        defer { isLoading = false }
        do {
            let sub = try await SubscriptionClient().fetch(from: url)
            subscription = sub
            SharedStore.cachedSubscription = sub
            errorMessage = nil
        } catch {
            // Кэш остаётся рабочим — просто показываем, что обновить не вышло
            errorMessage = error.localizedDescription
        }
    }

    /// Тихое обновление без спиннера (как на Mac).
    private func silentRefresh() async {
        guard let url = KeychainStore.subscriptionURL else { return }
        #if DEBUG
        if url == "demo" { return }
        #endif
        if let sub = try? await SubscriptionClient().fetch(from: url) {
            subscription = sub
            SharedStore.cachedSubscription = sub
        }
    }

    /// Запускает автообновление: сразу при старте + по интервалу из Remnawave
    /// (profile-update-interval, часы; по умолчанию 1 час).
    func startAutoRefresh() {
        guard KeychainStore.subscriptionURL != nil else { return }
        Task {
            await silentRefresh()
            while !Task.isCancelled {
                let hours = max(1, subscription?.updateIntervalHours ?? 1)
                try? await Task.sleep(nanoseconds: UInt64(hours) * 3_600 * 1_000_000_000)
                if Task.isCancelled { break }
                await silentRefresh()
            }
        }
    }

    func logout() {
        if vpn.state != .disconnected { Task { await vpn.disconnect() } }
        KeychainStore.subscriptionURL = nil
        SharedStore.cachedSubscription = nil
        subscription = nil
        selectedServerID = nil
    }

    // MARK: - VPN

    func toggleConnection() async {
        #if DEBUG
        if Self.demoMode {
            if vpn.state == .connected || vpn.state == .connecting {
                vpn.stopDemo()
            } else {
                await vpn.startDemo()
            }
            return
        }
        #endif
        switch vpn.state {
        case .connected, .connecting:
            await vpn.disconnect()
        default:
            await startTunnel(reconnect: false)
        }
    }

    /// Запуск/перезапуск туннеля с выбранным сервером и правилами.
    func startTunnel(reconnect: Bool) async {
        guard let server = selectedServer else { return }
        if reconnect {
            await vpn.reconnect(servers: [server],
                                routingMode: routingMode, customRules: customRules,
                                killSwitch: killSwitchEnabled)
        } else {
            await vpn.connect(servers: [server],
                              routingMode: routingMode, customRules: customRules,
                              killSwitch: killSwitchEnabled)
        }
    }

    /// Если туннель активен — применяет изменения переподключением.
    func reconnectIfConnected() async {
        guard vpn.state == .connected else { return }
        await startTunnel(reconnect: true)
    }

    /// Смена сервера: если подключены — переподключаемся к новому.
    func select(server: Server) async {
        let changed = selectedServerID != server.id
        selectedServerID = server.id
        if changed, vpn.state == .connected {
            await startTunnel(reconnect: true)
        }
    }

    // MARK: - Пинг (как на Mac: фоновый прогон + пакетное применение результатов)

    @Published var pingingServerIDs: Set<String> = []
    private var pingTask: Task<Void, Never>?
    private var pendingPings: [String: Int] = [:]
    private var flushScheduled = false

    func pingAll() {
        guard !isPinging, !servers.isEmpty else { return }
        isPinging = true
        pingingServerIDs = Set(servers.map(\.id))
        let all = servers
        pingTask = Task.detached(priority: .utility) { [weak self] in
            await self?.runPingDetached(servers: all)
            await MainActor.run {
                self?.flushPings()
                self?.isPinging = false
                self?.pingingServerIDs = []
            }
        }
    }

    /// Пинг одного сервера (из контекстного меню).
    func pingOne(_ server: Server) {
        pingingServerIDs.insert(server.id)
        Task.detached(priority: .utility) { [weak self] in
            await self?.runPingDetached(servers: [server])
            await MainActor.run { self?.flushPings() }
        }
    }

    /// Прогон TCP-пинга вне главного потока; результаты складываются в буфер.
    nonisolated private func runPingDetached(servers: [Server]) async {
        await PingService.shared.ping(servers: servers) { [weak self] result in
            Task { @MainActor in self?.bufferPing(result) }
        }
    }

    /// Кладёт результат в буфер и планирует пакетное обновление UI (раз в ~150мс).
    private func bufferPing(_ result: PingResult) {
        guard pingingServerIDs.contains(result.serverID) else { return }
        pendingPings[result.serverID] = result.latencyMs ?? -1
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self?.flushPings()
        }
    }

    private func flushPings() {
        flushScheduled = false
        guard !pendingPings.isEmpty else { return }
        for (id, ms) in pendingPings {
            pings[id] = ms
            pingingServerIDs.remove(id)
        }
        pendingPings.removeAll()
    }

    /// Отмена пинга: незавершённые серверы остаются без значения.
    func cancelPing() {
        pingTask?.cancel()
        pingTask = nil
        pendingPings.removeAll()
        flushScheduled = false
        pingingServerIDs = []
        isPinging = false
    }

    // MARK: - Избранное и папки

    #if DEBUG
    private static func demoSubscription() -> ClevVPNKit.Subscription {
        // Реальная подписка (вкладки/серверы 1-в-1 как на Mac), секреты вычищены —
        // только для просмотра UI. Файл PreviewSubscription.json лежит в бандле.
        if let url = Bundle.main.url(forResource: "PreviewSubscription", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let sub = try? JSONDecoder().decode(ClevVPNKit.Subscription.self, from: data) {
            return sub
        }
        // Фолбэк на случай отсутствия ресурса — минимальная витрина.
        let links = """
        vless://11111111-1111-1111-1111-111111111111@10.0.0.1:443?type=tcp&security=reality&pbk=demo&fp=chrome&sni=yahoo.com&sid=01ab&flow=xtls-rprx-vision#Европа%20%7C%20%F0%9F%87%A9%F0%9F%87%AA%20%D0%A4%D1%80%D0%B0%D0%BD%D0%BA%D1%84%D1%83%D1%80%D1%82
        hysteria2://demo@10.0.0.3:8443?sni=hy.demo.com#Скорость%20%7C%20%F0%9F%87%AB%F0%9F%87%AE%20%D0%A5%D0%B5%D0%BB%D1%8C%D1%81%D0%B8%D0%BD%D0%BA%D0%B8
        """
        let servers = ShareLinkParser.parseSubscriptionContent(links)
        return ClevVPNKit.Subscription(
            servers: servers, title: "ClevVPN Demo",
            userInfo: SubscriptionUserInfo.parse("upload=1073741824; download=16106127360; total=107374182400; expire=1782000000"),
            announce: nil, supportURL: "https://t.me/clevvpn_support")
    }
    #endif

    func toggleFavorite(_ server: Server) {
        if favorites.contains(server.id) {
            favorites.remove(server.id)
        } else {
            favorites.insert(server.id)
        }
    }

    func addFolder(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        folders.append(ServerFolder(name: trimmed))
    }

    func toggle(server: Server, in folder: ServerFolder) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        if let position = folders[index].serverIDs.firstIndex(of: server.id) {
            folders[index].serverIDs.remove(at: position)
        } else {
            folders[index].serverIDs.append(server.id)
        }
    }
}
