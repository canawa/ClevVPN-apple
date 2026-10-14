import Foundation

/// Генератор конфигурации sing-box из выбранных серверов и настроек маршрутизации.
public struct SingBoxConfigBuilder {
    public var servers: [Server]
    public var routingMode: RoutingMode
    public var customRules: [RoutingRule]
    /// Правила по приложениям — работают только на macOS (process_path_regex).
    public var appRules: [AppRule]
    public var appRoutingMode: AppRoutingMode

    public init(servers: [Server], routingMode: RoutingMode, customRules: [RoutingRule],
                appRules: [AppRule] = [], appRoutingMode: AppRoutingMode = .off) {
        self.servers = servers
        self.routingMode = routingMode
        // Как в эталоне: свои правила доменов/IP работают только в режиме
        // «Свои правила»; в «Весь трафик через VPN» они игнорируются.
        self.customRules = routingMode == .custom ? customRules.filter(\.isEnabled) : []
        self.appRules = appRules
        self.appRoutingMode = appRules.isEmpty ? .off : appRoutingMode
    }

    public init(server: Server, routingMode: RoutingMode, customRules: [RoutingRule]) {
        self.init(servers: [server], routingMode: routingMode, customRules: customRules)
    }

    /// Полный конфиг для туннеля (TUN + DNS + маршрутизация).
    public func buildTunnelConfig() -> [String: Any] {
        [
            "log": ["level": "warn", "timestamp": true],
            "dns": buildDNS(),
            "inbounds": [buildTUNInbound()],
            "outbounds": buildOutbounds(),
            "route": buildRoute(),
            "experimental": [
                "cache_file": ["enabled": true, "path": "cache.db"]
            ]
        ]
    }

    private func buildOutbounds() -> [[String: Any]] {
        var outbounds: [[String: Any]] = []
        if let server = servers.first {
            outbounds.append(Self.outbound(for: server, tag: "proxy"))
        }
        outbounds.append(["type": "direct", "tag": "direct"])
        return outbounds
    }

    /// JSON-строка конфига (стабильный порядок ключей — удобно для тестов и диффов).
    public func buildTunnelConfigJSON() throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: buildTunnelConfig(),
            options: [.prettyPrinted, .sortedKeys]
        )
        return String(decoding: data, as: UTF8.self)
    }

    /// Конфиг для батч-пинга: все серверы как outbound'ы + Clash API, без TUN.
    /// Запускается внутри приложения, меряет реальную задержку через каждый протокол.
    public static func buildPingConfig(servers: [Server], clashPort: Int) -> [String: Any] {
        var outbounds: [[String: Any]] = servers.enumerated().map { index, server in
            outbound(for: server, tag: "ping-\(index)")
        }
        outbounds.append(["type": "direct", "tag": "direct"])
        return [
            "log": ["level": "error"],
            // Резолвер для доменных адресов серверов (напрямую, без прокси)
            "dns": [
                "servers": [["type": "udp", "tag": "dns-direct", "server": "198.51.100.11"]]
            ],
            "outbounds": outbounds,
            "route": [
                "default_domain_resolver": ["server": "dns-direct"]
            ],
            "experimental": [
                "clash_api": [
                    "external_controller": "127.0.0.1:\(clashPort)"
                ]
            ]
        ]
    }

    /// Тег outbound'а сервера в ping-конфиге по его индексу.
    public static func pingTag(index: Int) -> String { "ping-\(index)" }

    // MARK: - DNS

    private func buildDNS() -> [String: Any] {
        // dns-direct всегда присутствует: он же bootstrap-резолвер для адресов
        // серверов, заданных доменом (route.default_domain_resolver).
        // detour не указываем: sing-box 1.12+ запрещает detour на «пустой»
        // direct-outbound (FATAL «detour to an empty direct outbound»).
        var servers: [[String: Any]] = [
            ["type": "https", "tag": "dns-remote", "server": "198.51.100.10", "detour": "proxy"],
            ["type": "udp", "tag": "dns-direct", "server": "198.51.100.11"]
        ]
        var rules: [[String: Any]] = []

        // Пользовательские direct-домены тоже резолвим напрямую
        let directDomains = customRules
            .filter { $0.matcher == .domainSuffix && $0.target == .direct }
            .map(\.value)
        if !directDomains.isEmpty {
            rules.append(["domain_suffix": directDomains, "server": "dns-direct"])
        }

        return [
            "servers": servers,
            "rules": rules,
            "final": "dns-remote",
            "strategy": "prefer_ipv4"
        ]
    }

    // MARK: - Inbound

    private func buildTUNInbound() -> [String: Any] {
        [
            "type": "tun",
            "tag": "tun-in",
            "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
            "mtu": 1500,
            "auto_route": true,
            // strict_route навешивает дополнительные правила файрвола и замедляет
            // подъём/снятие туннеля — для десктопа отключаем ради скорости.
            "strict_route": false,
            // Стабильность UDP (игры, звонки, QUIC) и меньше обрывов при NAT
            "endpoint_independent_nat": true,
            "udp_timeout": "5m",
            // system-стек быстрее, но на macOS НЕ пробрасывает process-инфо в ядро,
            // из-за чего маршрутизация по приложениям не работает. Когда она нужна —
            // используем gvisor (чуть медленнее, зато видит процессы соединений).
            "stack": appRoutingMode != .off ? "gvisor" : "system"
        ]
    }

    // MARK: - Route

    private func buildRoute() -> [String: Any] {
        var rules: [[String: Any]] = [
            ["action": "sniff"],
            ["protocol": "dns", "action": "hijack-dns"],
            ["ip_is_private": true, "outbound": "direct"]
        ]
        var ruleSets: [[String: Any]] = []

        // Правила по приложениям (macOS) — приоритетнее всего остального
        if appRoutingMode != .off {
            let regexes = appRules.map(\.processPathRegex)
            switch appRoutingMode {
            case .bypassSelected:
                rules.append(["process_path_regex": regexes, "outbound": "direct"])
            case .onlySelected:
                rules.append(["process_path_regex": regexes, "outbound": "proxy"])
            case .off:
                break
            }
        }

        // Пользовательские правила имеют высший приоритет
        for rule in customRules {
            let outbound = rule.target == .direct ? "direct" : "proxy"
            switch rule.matcher {
            case .domainSuffix:
                rules.append(["domain_suffix": [rule.value], "outbound": outbound])
            case .ipCIDR:
                rules.append(["ip_cidr": [rule.value], "outbound": outbound])
            }
        }

        // В режиме «только выбранные через VPN» всё остальное идёт напрямую
        let finalOutbound = appRoutingMode == .onlySelected ? "direct" : "proxy"
        var route: [String: Any] = [
            "rules": rules,
            "final": finalOutbound,
            // Адреса серверов (заданные доменом) резолвим напрямую, без прокси —
            // иначе циклическая зависимость (sing-box 1.12+ требует это явно).
            "default_domain_resolver": ["server": "dns-direct"],
            "auto_detect_interface": true
        ]
        if !ruleSets.isEmpty {
            route["rule_set"] = ruleSets
        }
        return route
    }

    // MARK: - Outbounds

    /// Outbound sing-box для любого поддерживаемого протокола.
    public static func outbound(for server: Server, tag: String) -> [String: Any] {
        var out: [String: Any] = [
            "tag": tag,
            "server": server.host,
            "server_port": server.port
        ]

        switch server.kind {
        case .vless(let config):
            out["type"] = "vless"
            out["uuid"] = config.uuid
            if let flow = config.flow, !flow.isEmpty, config.tls.security != .none {
                out["flow"] = flow
            }
            if let tls = tlsBlock(config.tls) { out["tls"] = tls }
            if let transport = transportBlock(config.transport) { out["transport"] = transport }

        case .trojan(let config):
            out["type"] = "trojan"
            out["password"] = config.password
            if let tls = tlsBlock(config.tls) { out["tls"] = tls }
            if let transport = transportBlock(config.transport) { out["transport"] = transport }

        case .hysteria2(let config):
            out["type"] = "hysteria2"
            out["password"] = config.password
            if let range = config.portRange, !range.isEmpty {
                out["server_ports"] = [range]
                out.removeValue(forKey: "server_port")
            }
            if let obfs = config.obfsPassword, !obfs.isEmpty {
                out["obfs"] = ["type": "salamander", "password": obfs]
            }
            var tls: [String: Any] = ["enabled": true, "alpn": ["h3"]]
            if let sni = config.serverName, !sni.isEmpty { tls["server_name"] = sni }
            if config.allowInsecure { tls["insecure"] = true }
            out["tls"] = tls

        case .shadowsocks(let config):
            out["type"] = "shadowsocks"
            out["method"] = config.method
            out["password"] = config.password
        }

        return out
    }

    private static func tlsBlock(_ config: TLSConfig) -> [String: Any]? {
        guard config.security != .none else { return nil }
        var tls: [String: Any] = ["enabled": true]
        if let sni = config.serverName, !sni.isEmpty { tls["server_name"] = sni }
        if !config.alpn.isEmpty { tls["alpn"] = config.alpn }
        if config.allowInsecure { tls["insecure"] = true }
        if let fp = config.fingerprint, !fp.isEmpty {
            tls["utls"] = ["enabled": true, "fingerprint": fp]
        }
        if config.security == .reality, let publicKey = config.realityPublicKey {
            var reality: [String: Any] = ["enabled": true, "public_key": publicKey]
            if let shortID = config.realityShortID { reality["short_id"] = shortID }
            tls["reality"] = reality
            // Reality требует uTLS — без отпечатка ставим chrome
            if tls["utls"] == nil {
                tls["utls"] = ["enabled": true, "fingerprint": "chrome"]
            }
        }
        return tls
    }

    private static func transportBlock(_ config: TransportConfig) -> [String: Any]? {
        switch config.type {
        case .tcp:
            return nil
        case .ws:
            var transport: [String: Any] = ["type": "ws"]
            if let path = config.path, !path.isEmpty {
                // Happ/v2rayN кладут early data в path: "/path?ed=2048"
                if let qIndex = path.firstIndex(of: "?") {
                    transport["path"] = String(path[..<qIndex])
                    if path[qIndex...].contains("ed=") {
                        transport["max_early_data"] = 2048
                        transport["early_data_header_name"] = "Sec-WebSocket-Protocol"
                    }
                } else {
                    transport["path"] = path
                }
            }
            if let host = config.host, !host.isEmpty {
                transport["headers"] = ["Host": host]
            }
            return transport
        case .grpc:
            var transport: [String: Any] = ["type": "grpc"]
            if let service = config.serviceName ?? config.path, !service.isEmpty {
                transport["service_name"] = service
            }
            return transport
        case .httpupgrade:
            var transport: [String: Any] = ["type": "httpupgrade"]
            if let path = config.path, !path.isEmpty { transport["path"] = path }
            if let host = config.host, !host.isEmpty { transport["host"] = host }
            return transport
        }
    }
}
