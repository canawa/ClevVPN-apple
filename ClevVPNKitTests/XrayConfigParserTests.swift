import XCTest
@testable import ClevVPNKit

final class XrayConfigParserTests: XCTestCase {

    /// Профили в формате, который реально отдаёт панель example.com (Remnawave/Happ).
    private let sample = """
    [
      {
        "remarks": "🇩🇪 Германия | Ультра⚡",
        "outbounds": [
          {
            "tag": "proxy",
            "protocol": "vless",
            "settings": { "vnext": [ { "address": "germ.example.com", "port": 7443,
              "users": [ { "id": "11111111-1111-1111-1111-111111111111", "encryption": "none", "flow": "xtls-rprx-vision" } ] } ] },
            "streamSettings": { "network": "tcp", "security": "tls",
              "tlsSettings": { "serverName": "germ.example.com", "fingerprint": "firefox", "alpn": ["h2","http/1.1"] } }
          },
          { "tag": "direct", "protocol": "freedom" }
        ]
      },
      {
        "remarks": "🇳🇱 Нидерланды 2 | Ультра⚡",
        "outbounds": [ {
          "tag": "proxy", "protocol": "hysteria",
          "settings": { "address": "dedik.example.com", "port": 9443, "version": 2 },
          "streamSettings": { "network": "hysteria",
            "hysteriaSettings": { "version": 2, "auth": "11111111-1111-1111-1111-111111111111" },
            "security": "tls", "tlsSettings": { "serverName": "dedik.example.com", "alpn": ["h3"] } }
        } ]
      },
      {
        "remarks": "🇷🇺 Youtube и Instagram",
        "outbounds": [ {
          "tag": "proxy", "protocol": "vless",
          "settings": { "vnext": [ { "address": "reality.example.com", "port": 443,
            "users": [ { "id": "uuid-reality", "flow": "xtls-rprx-vision" } ] } ] },
          "streamSettings": { "network": "tcp", "security": "reality",
            "realitySettings": { "serverName": "m.vk.com", "publicKey": "demoRealityPublicKey00000000000000000000000", "fingerprint": "chrome", "shortId": "ab12" } }
        } ]
      },
      {
        "remarks": "🇪🇺 Обход глушилок 13 | Моб. интернет",
        "outbounds": [ {
          "tag": "proxy", "protocol": "trojan",
          "settings": { "servers": [ { "address": "select.example.com", "port": 8443, "password": "demo-trojan-password-0000000000" } ] },
          "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "grpc" },
            "security": "tls", "tlsSettings": { "serverName": "select.example.com" } }
        } ]
      },
      {
        "remarks": "🇺🇸 xhttp server",
        "outbounds": [ {
          "tag": "proxy", "protocol": "vless",
          "settings": { "vnext": [ { "address": "xh.example.com", "port": 443, "users": [ { "id": "u" } ] } ] },
          "streamSettings": { "network": "xhttp", "security": "tls", "tlsSettings": { "serverName": "xh.example.com" } }
        } ]
      }
    ]
    """

    func testDetectsXrayFormat() {
        XCTAssertTrue(XrayConfigParser.looksLikeXrayJSON(sample))
        XCTAssertFalse(XrayConfigParser.looksLikeXrayJSON("vless://x@198.51.100.10:443#a"))
    }

    func testParsesAllSupportedProtocols() throws {
        let servers = XrayConfigParser.parse(sample)
        // 5 профилей, но xhttp не поддерживается — остаётся 4
        XCTAssertEqual(servers.count, 4)

        let germany = try XCTUnwrap(servers.first { $0.host == "germ.example.com" })
        XCTAssertEqual(germany.protocolType, .vless)
        XCTAssertEqual(germany.port, 7443)
        XCTAssertEqual(germany.countryCode, "DE")
        // «Ультра» → вкладка «Скорость» (категория считается по имени сервера)
        XCTAssertTrue(ServerCategory.speed.matches(germany.rawName))
        guard case .vless(let vlessConfig) = germany.kind else { return XCTFail() }
        XCTAssertEqual(vlessConfig.flow, "xtls-rprx-vision")
        XCTAssertEqual(vlessConfig.tls.security, .tls)
        XCTAssertEqual(vlessConfig.tls.fingerprint, "firefox")
    }

    func testHysteria2FromXray() throws {
        let servers = XrayConfigParser.parse(sample)
        let nl = try XCTUnwrap(servers.first { $0.host == "dedik.example.com" })
        XCTAssertEqual(nl.protocolType, .hysteria2)
        guard case .hysteria2(let config) = nl.kind else { return XCTFail() }
        XCTAssertEqual(config.password, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(config.serverName, "dedik.example.com")
    }

    func testRealityFromXray() throws {
        let servers = XrayConfigParser.parse(sample)
        let ru = try XCTUnwrap(servers.first { $0.host == "reality.example.com" })
        // «Youtube» → вкладка «Ютуб»
        XCTAssertTrue(ServerCategory.youtube.matches(ru.rawName))
        guard case .vless(let config) = ru.kind else { return XCTFail() }
        XCTAssertEqual(config.tls.security, .reality)
        XCTAssertEqual(config.tls.realityPublicKey, "demoRealityPublicKey00000000000000000000000")
        XCTAssertEqual(config.tls.serverName, "m.vk.com")
        XCTAssertEqual(config.tls.realityShortID, "ab12")
    }

    func testTrojanGrpcFromXray() throws {
        let servers = XrayConfigParser.parse(sample)
        let bypass = try XCTUnwrap(servers.first { $0.host == "select.example.com" })
        XCTAssertEqual(bypass.protocolType, .trojan)
        XCTAssertTrue(ServerCategory.bypass.matches(bypass.rawName))
        guard case .trojan(let config) = bypass.kind else { return XCTFail() }
        XCTAssertEqual(config.password, "demo-trojan-password-0000000000")
        XCTAssertEqual(config.transport.type, .grpc)
        XCTAssertEqual(config.transport.serviceName, "grpc")
    }

    /// Категории Home — те же маркеры, что в Android (ServerCategory.kt)
    /// и Windows (ServerCategoryHelper.cs).
    func testCategoryDetection() {
        XCTAssertTrue(ServerCategory.bypass.matches("Обход глушилок"))
        XCTAssertTrue(ServerCategory.youtube.matches("🇷🇺 Youtube"))
        XCTAssertTrue(ServerCategory.speed.matches("🇩🇪 Германия | Ультра⚡"))
        XCTAssertTrue(ServerCategory.gaming.matches("🇵🇱 Польша | Игровой🎮"))

        // «Авто» — отдельная метка; обход с «Авто» в имени остаётся обходом
        XCTAssertTrue(ServerCategory.auto.matches("🇪🇺 Авто | Европа | WIFI"))
        XCTAssertFalse(ServerCategory.auto.matches("🇪🇺 Авто | Обход глушилок | Моб. инет"))
        XCTAssertFalse(ServerCategory.auto.matches("🇩🇪 Автобан"))

        // Страна без тематики не попадает ни в одну вкладку, кроме «Все»
        XCTAssertTrue(ServerCategory.allCases.allSatisfy { !$0.matches("🇫🇮 Финляндия") })

        // Чипы Home не содержат «Авто»
        XCTAssertEqual(ServerCategory.homeFilters, [.bypass, .speed, .youtube, .gaming])
    }
}
