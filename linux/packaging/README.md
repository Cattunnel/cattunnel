# CatTunnel для Linux: пакеты Arch и Debian

English: [README.en.md](README.en.md)

Документ для администратора, который ставит, проверяет или собирает пакет. Приложение работает от обычного пользователя. От root работают только небольшой помощник `cattunnel-helper` (его протокол описан в [HELPER.md](../../plugins/vpn_plugin/linux/HELPER.md)) и консольный клиент `trusttunnel_client`: ядро [TrustTunnelClient](https://github.com/TrustTunnel/TrustTunnelClient) версии из файла `ENGINE_VERSION` (сейчас 1.3.0-rc.1) с патчами CatTunnel, см. [tools/engine_native/README.md](../../tools/engine_native/README.md). Исходный код приложения: [Cattunnel/cattunnel](https://github.com/Cattunnel/cattunnel).

## 1. Проверить подпись

`build_release.sh` собирает в `build/arch/`: `PKGBUILD`, `cattunnel.install`, `cattunnel-app-<версия>-x86_64.tar.gz` (готовая сборка приложения), `cattunnel-helper-src-<версия>.tar.gz` (исходники помощника и файлы упаковки), `trusttunnel_client-v<ядро>-cattunnel-linux-x86_64.tar.gz` (наше ядро), а также `SHA256SUMS` и `SHA256SUMS.sig` на всё это. В готовые пакеты (`.pkg.tar.zst`, `.deb`) тот же ключ подписывает `SHA256SUMS`, когда они лежат в этой папке (`makepkg_in_docker.sh` добавляет в список пакет Arch и все `cattunnel_*_amd64.deb`).

```
# публичный ключ Ed25519 (файл linux/packaging/cattunnel-release.pub.pem), он же проверяет обновления Android и Windows:
openssl pkeyutl -verify -pubin -inkey cattunnel-release.pub.pem -rawin -in SHA256SUMS \
    -sigfile <(base64 -d SHA256SUMS.sig)          # "Signature Verified Successfully"
sha256sum -c SHA256SUMS                            # все OK
```

Отпечаток ключа (sha256 от DER): `d1c58a11338b4840ce26ff3a27796cfd600f768e4bd5092b92b948c32b38adbf`. Получить его из файла: `openssl pkey -pubin -in cattunnel-release.pub.pem -outform DER | sha256sum`. Сверьте отпечаток с автором релиза по другому каналу, не по тому, которым пришёл архив.

Хеш ядра записан в `PKGBUILD` (строка `sha256sums`): это хеш нашего архива `trusttunnel_client-v<ядро>-cattunnel-linux-x86_64.tar.gz`, а не официального архива TrustTunnel. Хеши официальных архивов лежат в файле `ENGINE_SHA256` в корне репозитория, пакет Linux по ним не собирается. `makepkg` проверяет хеш сам.

## 2. Установить

Файлы релиза называются так (список в [корневом README](../../README.md)): `cattunnel-linux.pkg.tar.zst` для Arch и `cattunnel-linux.deb` для Debian и Ubuntu.

Arch, готовый пакет:
```
sudo pacman -U cattunnel-linux.pkg.tar.zst
```
Arch, сборка из тех же исходников (собирает помощник через cmake, ninja и gcc, ставит пакет):
```
makepkg -si
```
Debian 13 и Ubuntu 24.04 и новее, amd64:
```
sudo apt install ./cattunnel-linux.deb
```
Дальше, в обоих случаях:
```
sudo usermod -aG cattunnel "$USER"          # доступ к сокету помощника; перелогиниться
sudo systemctl enable --now cattunnel-helper
```

Сервис и группу пакет сам не включает: это решение администратора. При обновлении пакета помощник перезапускается сразу, если VPN не поднят; если поднят, пакет напоминает перезапустить его после отключения (`sudo systemctl restart cattunnel-helper`).

Зависимости Arch: `gtk3`, `gstreamer`, `gst-plugins-base-libs`, `gst-plugins-good`, `zenity`, `xdg-utils`, `iproute2`, `systemd`; для сборки ещё `cmake`, `ninja`, `gcc`. Необязательные: `networkmanager` (DNS при выключенном systemd-resolved) и `systemd-resolved`. Зависимости Debian перечислены в `build_deb.sh` (поле `Depends`), рекомендуется `network-manager`.

## 3. Что работает от root и что оно может

| | |
|---|---|
| `/usr/lib/cattunnel/cattunnel-helper` | около 1150 строк C++17 в `.cpp`-файлах помощника; сторонние заголовки nlohmann/json и toml++. Исходники в `cattunnel-helper-src-*.tar.gz` (`src/plugins/vpn_plugin/linux/helper/`) |
| `/usr/lib/cattunnel/trusttunnel_client` | консольный клиент TrustTunnel (Apache-2.0) с патчами CatTunnel; сборка описана в [tools/engine_native/README.md](../../tools/engine_native/README.md) |
| `cattunnel-helper.service` | `NoNewPrivileges`, `ProtectSystem=true`, `ProtectHome`, `PrivateTmp`, `DevicePolicy=closed` и только `/dev/net/tun`, `CapabilityBoundingSet` из шести прав (`CAP_NET_ADMIN CAP_NET_RAW CAP_CHOWN CAP_FOWNER CAP_DAC_OVERRIDE CAP_KILL`), `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK`, `MemoryDenyWriteExecute`, `TasksMax=64` |

Помощник слушает `/run/cattunnel/helper.sock` (0660, группа `cattunnel`) и проверяет каждого клиента через `SO_PEERCRED`: допускаются root и члены группы. Что клиент может попросить:

- **start**: конфиг клиента в TOML. Помощник отказывает, если ключ не из белого списка того, что пишет приложение, если в значении путь к файлу, если SOCKS-слушатель не на loopback или если размеры больше лимитов. Принятый конфиг пишется в `/run/cattunnel/client.toml` (root, 0600), клиент запускается по абсолютному пути с чистым окружением. Одновременно работает один клиент.
- **stop**, **state**, **logs** (последние записи клиента, без паролей на уровне info).
- **probe** и **relay**: TCP-соединение с числовым адресом, привязанное к физическому интерфейсу (`SO_BINDTODEVICE`). Нужно для диагностики и замера задержки мимо туннеля.

Произвольных команд, путей и аргументов клиента помощник не принимает.

## 4. DNS

Клиент настраивает DNS только через `resolvectl`. Без systemd-resolved он пропускает этот шаг, и запросы шли бы мимо туннеля, поэтому на время сеанса помощник сам подменяет `/etc/resolv.conf` (при активном NetworkManager сначала ставит ему временный файл `dns=none`) и возвращает оригинал при отключении. Оригинал хранится в `/var/lib/cattunnel/resolv.conf.backup`; если помощник упал, при следующем старте он восстанавливает DNS и убирает правила маршрутизации, оставшиеся от клиента. Подробности и схема: [HELPER.md](../../plugins/vpn_plugin/linux/HELPER.md).

## 5. Как собирается пакет

```text
 Flutter-сборка (flutter build linux)         ядро trusttunnel_client (ENGINE_BIN, свой билд)
        |                                        |  проверка: в бинарнике есть строка "Anti-DPI mode"
        v                                        v
 cattunnel-app-<версия>-x86_64.tar.gz     trusttunnel_client-v<ядро>-cattunnel-linux-x86_64.tar.gz
        \                                       /
         \    git archive HEAD (исходники помощника, файлы упаковки)
          \            |          cattunnel-helper-src-<версия>.tar.gz
           v           v
        PKGBUILD из PKGBUILD.in (хеши вставлены), cattunnel.install
                       |
                       v
        SHA256SUMS  --подпись Ed25519-->  SHA256SUMS.sig
                       |
        makepkg_in_docker.sh -> cattunnel-<версия>-1-x86_64.pkg.tar.zst
        build_deb.sh         -> cattunnel_<версия>_amd64.deb
```

Рисунок 1. Что делают скрипты в `linux/packaging/` и какие файлы получаются.

- `build_release.sh <версия> <номер-сборки> [--skip-flutter-build]`: версия только из цифр и точек (она же `pkgver`). Скрипт отказывается работать, если упакованные пути не закоммичены: `git archive` берёт `HEAD`, и `PKGBUILD` называет коммит, из которого собран помощник. Путь к готовому ядру задаёт переменная `ENGINE_BIN`. Ключ подписи берётся из `UPDATE_SIGNING_KEY` (по умолчанию `android/keystore/update-signing.pem`); без него `SHA256SUMS` остаётся без подписи, скрипт печатает предупреждение.
- `build_deb.sh` запускается после `build_release.sh`: берёт из `build/arch/` сборку приложения и архив ядра, помощника собирает заново из закоммиченных исходников и пакует `.deb` (`dpkg-deb`, нужен `fakeroot`).
- `makepkg_in_docker.sh <ssh-хост>` собирает пакет Arch в контейнере `archlinux:latest` на хосте с Docker, сверяет, что сборка приложения в пакете побайтно совпадает с архивом, проверяет `pacman -U` и заново подписывает `SHA256SUMS`.

В пакет кладутся ещё `com.cattunnel.app.desktop` (обработчик ссылок `tt://`), правило `cattunnel.sysusers` для группы `cattunnel`, лицензии (`LICENSE`, `NOTICE`, лицензия клиента) и `HELPER.md` с этим файлом в `/usr/share/doc/cattunnel/`.

## 6. Удаление

`sudo pacman -R cattunnel` или удаление пакета Debian: перед удалением служба отключается (`pre_remove` в `cattunnel.install`, `prerm` в `.deb`). Скрипты не удаляют группу `cattunnel` и каталог `/var/log/cattunnel/` с журналом клиента.

## 7. Чего на Linux нет

- Обновления внутри приложения: приложение обновляет себя только на Android и Windows (проверка в `lib/feature/updates/domain/update_service.dart`). На Linux обновляется пакет.
- Импорт «Из файла (.toml)» берёт из файла только сервер (`[endpoint]`), остальное идёт из настроек приложения.

Раздельный туннель по программам и значок в трее на Linux есть, их описывает [корневой README](../../README.md).
