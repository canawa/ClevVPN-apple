# Frameworks

Сюда кладётся `Libbox.xcframework` — ядро sing-box для iOS.

Собрать на Mac (один раз):

```bash
./scripts/bootstrap-ios.sh
```

или только ядро:

```bash
brew install go
./scripts/build-libbox.sh
```

Без этого файла схема **ClevVPN** не соберётся с рабочим туннелем.
`Libbox.xcframework` в git не коммитится (тяжёлый бинарник) — его собирает bootstrap.
