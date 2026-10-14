# ClevVPN — клиенты для macOS и iOS

Один проект, две платформы. Интерфейс совпадает с Android / Windows.

## iOS с рабочим VPN (для заказчика)

Нужны: **Mac**, **Xcode 15+**, **платный Apple Developer**.

```bash
cd ClevVPN
chmod +x scripts/*.sh
./scripts/bootstrap-ios.sh
```

Скрипт сам:

1. поставит Go / XcodeGen при необходимости;
2. соберёт `Frameworks/Libbox.xcframework` (первый раз **10–30 минут**);
3. сгенерирует `ClevVPN.xcodeproj` с подключённым ядром;
4. откроет проект.

Дальше в Xcode:

1. Схема **ClevVPN** (не Preview).
2. Signing → ваш Team для таргетов **ClevVPN** и **PacketTunnel**.
3. В [Apple Developer](https://developer.apple.com/account/resources/identifiers/list):
   - App ID `com.clevvpn.ios` — capability **Network Extensions** (Packet Tunnel) + **App Groups**;
   - App ID `com.clevvpn.ios.tunnel` — то же;
   - App Group: `group.com.clevvpn.ios`.
4. Run на **физическом iPhone** (системный VPN в симуляторе не поднимается).

После этого: активация ключом → выбор сервера → Connect поднимает реальный туннель sing-box.

Повторные сборки ядро не пересобирают (уже лежит в `Frameworks/`).

### Если App Group / Bundle ID заняты

Смените в коде и entitlements на свои:

- `group.com.clevvpn.ios` → `SharedStore.appGroupID`, `*.entitlements`, `project.yml`
- `com.clevvpn.ios` / `com.clevvpn.ios.tunnel` → `project.yml`, затем снова `xcodegen generate`

## Остальные схемы

| Схема | Что даёт | Аккаунт |
|---|---|---|
| **ClevVPN** | UI + Packet Tunnel + Libbox | платный Developer |
| **ClevVPNPreview** | только UI (demo-подписка) | бесплатный Apple ID |
| **ClevVPNMac** | macOS-клиент (`brew install sing-box`) | не нужен платный |

```bash
# только перегенерация проекта (ядро уже собрано)
xcodegen generate
open ClevVPN.xcodeproj
```

Тесты:

```bash
xcodebuild -project ClevVPN.xcodeproj -scheme ClevVPN \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Что внутри

- `ClevVPN/` — экраны iOS и общая тема
- `ClevVPNMac/` — macOS UI, туннель через root sing-box
- `ClevVPNKit/` — подписка, конфиг, пинг, хранилище
- `PacketTunnel/` — Network Extension + мост к Libbox
- `Frameworks/Libbox.xcframework` — ядро (после bootstrap)
- `scripts/bootstrap-ios.sh` — полная подготовка iOS

## App Store (позже)

1. `PrivacyInfo.xcprivacy` (UserDefaults).
2. Проверить `ITSAppUsesNonExemptEncryption` — для VPN обычно не `false`.
3. Аккаунт-организация: App Review 5.4 принимает VPN только от Organization.

Mac App Store в текущем виде (root sing-box) не подойдёт — раздача через Developer ID + DMG.

## Данные

Демо-ключ активации: `demo` (подписка из бандла). Реальный ключ хранится в Keychain.
