# CatTunnel для Linux (Arch) — установка и что внутри

Для второго администратора. Коротко: приложение работает от обычного пользователя; от root работают только
небольшой помощник `cattunnel-helper` (собирается из исходников прямо в PKGBUILD) и `trusttunnel_client` —
официальное ядро TrustTunnelClient с нашим патчем анти-DPI (`tools/engine_native/0001-anti-dpi-desync.patch`,
сборка `tools/engine_native/build_linux.sh`; хеш закреплён в PKGBUILD).

## 1. Проверить подпись

В релизе: готовый пакет `cattunnel-<ver>-1-x86_64.pkg.tar.zst` и то, из чего он собран — `PKGBUILD`,
`cattunnel.install`, `cattunnel-app-<ver>-x86_64.tar.gz`, `cattunnel-helper-src-<ver>.tar.gz`;
плюс `SHA256SUMS` и `SHA256SUMS.sig` на всё это.

```
# публичный ключ (Ed25519) - тот же, что проверяет обновления Android/Windows:
cat > cattunnel-release.pub.pem <<'EOF'
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAQdZxc2PNJDDKVsm06RVS26UU1dhUFLc9wjRw5zQvtFA=
-----END PUBLIC KEY-----
EOF
openssl pkeyutl -verify -pubin -inkey cattunnel-release.pub.pem -rawin -in SHA256SUMS \
    -sigfile <(base64 -d SHA256SUMS.sig)          # "Signature Verified Successfully"
sha256sum -c SHA256SUMS                            # все OK
```

Отпечаток ключа (sha256 от DER): `cec7226bb8218de67f02cf5992e3da7f54c3251d0ceade7e55c42cc7853a2f49`.
Сверь его с владельцем по другому каналу, не по тому, по которому пришёл архив.

`trusttunnel_client` makepkg проверит сам: его sha256 в `PKGBUILD` (тот же, что в `ENGINE_SHA256` репозитория).

## 2. Установить

Либо готовый пакет (собран тем же PKGBUILD в чистом контейнере Arch):
```
sudo pacman -U cattunnel-<ver>-1-x86_64.pkg.tar.zst
```
либо собрать самому из того же, что можно прочитать:
```
makepkg -si                                # собирает помощник (cmake/ninja/gcc), ставит пакет
```
Дальше, в обоих случаях:
```
sudo usermod -aG cattunnel "$USER"          # доступ к сокету помощника; перелогиниться
sudo systemctl enable --now cattunnel-helper
```

Сервис и группу пакет сам не включает — это решение администратора.

## 3. Что от root и что он может

| | |
|---|---|
| `/usr/lib/cattunnel/cattunnel-helper` | ~1000 строк C++17 + nlohmann/json, исходники в `cattunnel-helper-src-*.tar.gz` (`src/plugins/vpn_plugin/linux/helper/`, протокол — `HELPER.md`) |
| `/usr/lib/cattunnel/trusttunnel_client` | CLI TrustTunnelClient (Apache-2.0) + патч анти-DPI `tools/engine_native/0001-anti-dpi-desync.patch` (он же в `cattunnel-helper-src-*.tar.gz`), собран `tools/engine_native/build_linux.sh` |
| `cattunnel-helper.service` | `NoNewPrivileges`, `ProtectSystem=true`, `ProtectHome`, `PrivateTmp`, `DevicePolicy=closed` + только `/dev/net/tun`, урезанный `CapabilityBoundingSet`, `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK`; `systemd-analyze security`: 4.6 OK |

Помощник слушает `/run/cattunnel/helper.sock` (0660, группа `cattunnel`) и проверяет каждого клиента
через `SO_PEERCRED` (член группы или root). Что клиент может попросить:

- **start** — конфиг CLI в TOML. Помощник его разбирает и отказывает, если: ключ не из белого списка того,
  что пишет приложение; в значении есть путь к файлу; SOCKS-слушатель не на loopback; размеры больше лимитов.
  Принятый конфиг пишется в `/run/cattunnel/client.toml` (root, 0600), CLI запускается по абсолютному пути
  с чистым окружением. Одновременно — один CLI.
- **stop**, **state**, **logs** (последние записи CLI, без паролей на уровне info).
- **probe** / **relay** — TCP-соединение с числовым адресом, привязанное к физическому интерфейсу
  (`SO_BINDTODEVICE`): диагностика и замер задержки мимо туннеля.

Произвольных команд, путей и аргументов CLI помощник не принимает.

## 4. DNS (у тебя NetworkManager без systemd-resolved)

CLI сам умеет DNS только через `resolvectl`; без resolved он молча пропускает этот шаг, и запросы шли бы
мимо туннеля. Поэтому на время сеанса помощник:

1. сохраняет оригинальный `/etc/resolv.conf` в `/var/lib/cattunnel/resolv.conf.backup` (root, 0600, на диске —
   чтобы пережить падение и перезагрузку; существующий бэкап не перезаписывается);
2. кладёт `/run/NetworkManager/conf.d/90-cattunnel-dns.conf` с `dns=none` и делает `nmcli general reload conf`
   — NM перестаёт переписывать `resolv.conf`;
3. пишет `resolv.conf` с DNS туннеля (`46.243.231.30/31` — их перехватывает движок).

При отключении — всё в обратном порядке, NM снова ведёт DNS (`reload conf,dns-rc`). Профили NM не
меняются. Если помощник упал, при старте он возвращает DNS и убирает правила маршрутизации, оставшиеся
от CLI. Проверено на Debian 13 с тем же набором (NM без resolved): `resolv.conf` возвращается
байт в байт, в том числе после `kill -9` помощника.

**namcap** (проверено в контейнере Arch): ругается на ELF в `/opt` — так ставятся готовые сборки
приложений. Предупреждает, что у файлов Flutter-сборки и у `trusttunnel_client` нет полного
RELRO, а у `trusttunnel_client` ещё и PIE — так их собирают Flutter и сборка ядра TrustTunnel. У `cattunnel-helper`
(единственный наш бинарник от root) — PIE, full RELRO, stack protector, `_FORTIFY_SOURCE` из флагов Arch.

## 5. Удаление

`sudo pacman -R cattunnel` — сервис отключается перед удалением. Остаются группа `cattunnel` и
`/var/log/cattunnel/` (лог CLI, root 0640).

## 6. Пока нет

Kill switch, сплит по приложениям (нужна своя сборка ядра TrustTunnel), обновления внутри приложения.
Трея на Linux нет. Импорт «Из файла (.toml)» берёт из файла только сервер ([endpoint]), остальное —
из настроек приложения.
