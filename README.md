<p align="center">
  <img src="assets/icon/icon_square.png" width="128" alt="CatTunnel">
</p>

<h1 align="center">CatTunnel</h1>

<p align="center">
  Клиент для серверов <b>TrustTunnel</b> на Android, Windows и Linux — с устойчивостью к DPI, зашифрованными подписками и встроенной диагностикой.
  <br>
  <i>A TrustTunnel client for Android, Windows and Linux with DPI resistance, encrypted subscriptions and built-in diagnostics.</i>
</p>

<p align="center">
  <a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/Cattunnel/cattunnel?include_prereleases&label=release" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="License"></a>
  <img src="https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android&logoColor=white" alt="Android 8.0+">
  <img src="https://img.shields.io/badge/Windows-x64-0078D6?logo=windows&logoColor=white" alt="Windows x64">
  <img src="https://img.shields.io/badge/Linux-Arch%20%7C%20Debian-FCC624?logo=linux&logoColor=black" alt="Linux">
  <img src="https://img.shields.io/badge/Flutter-3.38.3-02569B?logo=flutter" alt="Flutter 3.38.3">
</p>

<p align="center">
  <a href="../../releases/latest"><b>Скачать</b></a> ·
  <a href="assets/readme/README.ru.md">Руководство пользователя</a> ·
  <a href="assets/readme/README.en.md">User guide (EN)</a> ·
  <a href="docs/how-it-works.md">Как это устроено</a> ·
  <a href="https://github.com/Cattunnel/cattunnel-router">Версия для роутеров</a>
</p>

---

CatTunnel — клиентское приложение: он подключается к серверу TrustTunnel, который у вас уже есть (свой или от администратора). Серверов и подписок проект не предоставляет.

В основе — открытый [TrustTunnel Flutter Client](https://github.com/TrustTunnel/TrustTunnelFlutterClient) от AdGuard (Apache-2.0). CatTunnel добавляет собственную сборку сетевого ядра с защитой от анализа трафика (DPI), подписки с шифрованием age, пошаговую диагностику подключения, строгую проверку сертификатов и русский интерфейс. В приложении живёт кот-помощник Марсик: он объясняет, что пошло не так.

> Аккаунт свежий — по соображениям безопасности. Проект ведётся уже около двух месяцев, и автор решил сделать его публичным без привязки к себе. Поэтому история разработки до публикации не перенесена: репозиторий начинается с уже готового кода.

## Возможности

**Подключение и серверы**
- Серверы вручную, по ссылке `tt://`, по QR-коду или из подписки; повторная ссылка на тот же сервер обновляет его (например, «порт 8443 → 9443»), а не создаёт дубль.
- Kill switch, автоподключение, кнопка в шторке Android — подключение без открытия приложения, одно уведомление вместо двух.
- Работающий VPN не переподключается, когда приложение открывают заново; смена сервера — одно подключение, а не два.
- Проверка и сортировка серверов по задержке, настройка MTU.
- Ключи **«Российский выход»** для тех, кто за границей: через Россию идут только российские сайты и приложения, остальное — напрямую.

**Подписки**
- Подписка сама обновляет список серверов; только `https://`, без перенаправлений; запасные адреса на случай блокировки первого.
- Шифрование ответа **age (X25519)** прямо на устройстве, бинарный и armor-формат.
- Подписка может задать для сервера способ анти-DPI, отпечаток TLS и выход.
- Обмен подпиской через QR-код и импорт сканером.

**Устойчивость к DPI**
- Своя сборка ядра TrustTunnelClient: ClientHello уходит приёмами из [ByeDPI](https://github.com/hufrea/byedpi) — «срочный» байт, кусок с TTL 1, разрыв внутри имени сервера. Способы 1–3, своя строка в синтаксисе ByeDPI и режим **«Авто»**, который запоминает удачный способ для сервера и сети.
- **Отпечаток TLS** для каждого сервера (по умолчанию — как у браузера устройства), **маскировка размеров** (HTTP/2 padding), **отключение QUIC**.
- Понятные причины отказа и бережные повторы, если фильтр временно «заморозил» адрес сервера. Подробно — [docs/anti-dpi.md](docs/anti-dpi.md).

**Раздельное туннелирование**
- Сайты, IP-адреса, сети и приложения мимо VPN; свой список редактируется.
- Российские сети и домены подтягиваются автоматически (runetfreedom, ipverse, hydraponique) и обновляются раз в сутки.
- Режим «Авто»: российские, китайские и узбекские сервисы и приложения производителя телефона — мимо VPN; российские — всегда, остальные можно вернуть в туннель.
- **Яндекс Браузер всегда остаётся в VPN**, хотя он российский: у очень многих это основной браузер, и иначе мимо туннеля уходил бы почти весь их трафик. Сайты Яндекса при этом всё равно идут напрямую по правилам доменов.
  *Владельцам VPN-серверов:* Яндекс Браузер не входит в список «мимо VPN» из-за массовости — просьба отнестись с пониманием.
- Скачанные списки проверяются на правдоподобие: правило вроде `0.0.0.0/0` («всё мимо VPN») отбрасывается, при подозрительной загрузке остаётся прошлая копия. Адрес самого VPN-сервера из списков всегда вычитается.

**Диагностика — кот Марсик**
- Если подключение зависло на 10 секунд, Марсик сам проверяет интернет, доступность сервера, TLS/SNI, ключи и подписку, говорит, что не так, и предлагает рабочий сервер.
- Если система вообще не дала создать VPN, говорит об этом прямо.
- На vivo, OPPO, realme, OnePlus и iQOO объясняет ложное «VPN не подключён» в системе.
- «Сообщить о проблеме»: отчёт для администратора без паролей и ключей.
- Марсика можно гладить: комплименты, счётчик, пасхалки, мурлыканье и иногда стихи.

**Безопасность и приватность**
- **Строгая проверка сертификата сервера** (включена по умолчанию на Android, Windows и Linux): только системные корневые сертификаты, без «Russian Trusted Root/Sub CA» и вручную установленных. Выключить можно только после трёх подтверждений.
- Проверка устройства и утечек, тревожная кнопка (стереть данные приложения), маскировка под «Калькулятор», блокировка приложения, защита экранов с ключами от скриншотов.
- Нет аналитики и рекламы, телеметрия ML Kit отключена; данные не попадают в облачные резервные копии; пароли, ключи и адреса подписок не пишутся в журнал.

**Компьютеры**
- **Linux:** пакеты Arch и Debian; приложение работает от пользователя, права root — только у помощника с белым списком команд и закалённым systemd-юнитом.
- **Windows:** установщик и обновления из приложения.

**Оформление и обновления**
- Тёмная тема и стиль **«Уютный»**: большая кнопка с Марсиком, таймер сеанса, пинг, выбор сервера снизу; окно «Что нового», обучение при первом запуске, русский и английский интерфейс.
- Android и Windows обновляются из приложения: `latest.json` подписан Ed25519, файлы сверяются по SHA-256, адрес обновлений задаётся только при сборке.

## Установка

Файлы — в [релизах](../../releases/latest).

| Файл | Платформа | Примечание |
| :--- | :--- | :--- |
| `cattunnel-<версия>-arm64.apk` | Android 8.0+, `arm64-v8a` | Основная сборка |
| `cattunnel-<версия>-universal.apk` | Android 8.0+, `arm64-v8a` + `armeabi-v7a` | Для старых 32-битных устройств |
| `cattunnel-<версия>-windows-setup.exe` | Windows 10/11 x64 | Установщик |
| `cattunnel_<версия>_amd64.deb` | Debian, Ubuntu | `sudo apt install ./cattunnel_<версия>_amd64.deb` |
| `cattunnel-<версия>-1-x86_64.pkg.tar.zst` | Arch Linux | `sudo pacman -U …`; рядом `PKGBUILD` для сборки из исходников |

**Windows:** установщик пока не подписан сертификатом разработчика, поэтому SmartScreen может показать «Windows защитила ваш компьютер» — «Подробнее» → «Выполнить в любом случае». По той же причине отдельные антивирусы с эвристикой иногда помечают установщик (результаты VirusTotal — в описании каждого релиза). Подлинность файла проверяется по `SHA256SUMS` (см. ниже). Обновления затем приходят из самого приложения.

На Linux приложение работает от обычного пользователя; права root нужны только небольшому помощнику `cattunnel-helper` (systemd, доступ по группе `cattunnel`) — см. [plugins/vpn_plugin/linux/HELPER.md](plugins/vpn_plugin/linux/HELPER.md).

Для роутеров (OpenWrt, Keenetic, ASUS Merlin) — отдельный репозиторий [cattunnel-router](https://github.com/Cattunnel/cattunnel-router).

### Проверка подлинности

Файлы релиза перечислены в `SHA256SUMS`, подписанном ключом Ed25519. Публичный ключ — [`linux/packaging/cattunnel-release.pub.pem`](linux/packaging/cattunnel-release.pub.pem):

```bash
openssl pkeyutl -verify -pubin -inkey cattunnel-release.pub.pem -rawin \
  -in SHA256SUMS -sigfile <(base64 -d SHA256SUMS.sig)
sha256sum -c SHA256SUMS --ignore-missing
```

Сертификат подписи Android-приложения: `CN=CatTunnel`, SHA-256 `42:6C:CE:9A:C6:62:B2:D1:41:01:E2:7F:0C:B6:7E:0C:AA:23:13:7B:CC:29:1C:6D:6A:06:EF:11:62:99:AF:B7`.

## Сборка из исходников

**Требования:** Flutter **3.38.3** (версия зафиксирована в `pubspec.yaml`), JDK 17, Android SDK (platform 36), NDK `29.0.14206865`, токен GitHub с правом `read:packages` — Android-движок TrustTunnel загружается из GitHub Packages.

```bash
export GPR_KEY=<токен с read:packages>
make init          # зависимости и генерация кода
flutter test
```

**Android**

```bash
# Основная сборка (arm64)
flutter build apk --release --split-per-abi --target-platform android-arm64

# Универсальная (arm64 + armv7), с тем же versionCode, что у arm64
flutter build apk --release --target-platform android-arm,android-arm64 --build-number=<versionCode arm64>

# Обновления из приложения: адрес latest.json и ключ, которым он подписан
flutter build apk ... \
  --dart-define=UPDATE_URL=https://github.com/Cattunnel/cattunnel/releases/latest/download/latest.json \
  --dart-define=UPDATE_PUBKEY=$(openssl pkey -pubin -in linux/packaging/cattunnel-release.pub.pem -outform DER | tail -c 32 | base64)

# Свой идентификатор приложения (форк, параллельная установка)
ORG_GRADLE_PROJECT_appId=org.example.myvpn flutter build apk ...
```

Релизная подпись берётся из `android/key.properties` и `android/keystore/` (оба пути в `.gitignore`). Без них сборка подписывается отладочным ключом — такой APK не встанет поверх официального.

**Windows и Linux:** установщик — [`windows/installer/`](windows/installer/), пакеты Arch и Debian — [`linux/packaging/`](linux/packaging/README.md).

**Сетевое ядро:** собственная сборка TrustTunnelClient с патчем [`tools/engine_native/0001-anti-dpi-desync.patch`](tools/engine_native/0001-anti-dpi-desync.patch) — [`tools/engine_native/`](tools/engine_native/README.md); патчи Android-движка — [`tools/engine_patch/`](tools/engine_patch/).

<details>
<summary>Заметки по сборке</summary>

- `--split-per-abi` прибавляет 2000 к `versionCode` для arm64, поэтому универсальной сборке номер передаётся явно.
- Библиотеки x86/x86_64 исключены из APK — на x86-эмуляторах приложение не запустится.
- `tools/update_engine.sh <версия>` меняет версию ядра сразу для всех платформ.
- `latest.json` для релиза: `tools/make_latest_json.sh https://github.com/Cattunnel/cattunnel/releases/download/v<версия> <arm64.apk> <universal.apk> notes.txt`, подпись — `tools/sign_latest_json.sh`.
- Изменения оригинального TrustTunnel переносятся по одному (cherry-pick): история этого репозитория начинается заново, общего предка с upstream нет.
</details>

## Структура

```text
lib/                      приложение (Flutter)
  feature/companion/      Марсик
  feature/vpn/domain/     диагностика, анти-DPI «Авто», отпечаток TLS
  feature/security/       проверки устройства и утечек, тревожная кнопка
  feature/subscriptions/  подписки, QR, импорт
plugins/vpn_plugin/       привязки к TrustTunnelClient (Pigeon); linux/helper — привилегированный помощник
packages/dage/            библиотека age с исправлениями совместимости
tools/engine_native/      сборка своего ядра и патч анти-DPI
tools/engine_patch/       патчи Android-движка
android/ ios/ macos/ windows/ linux/   платформенные части, установщик и пакеты
docs/                     устройство, анти-DPI, безопасность
test/                     тесты (flutter test)
```

## Безопасность

Нашли уязвимость — пожалуйста, не публикуйте её в Issues, а сообщите через [GitHub Security Advisories](../../security/advisories/new).

## Лицензия

CatTunnel распространяется по лицензии [Apache-2.0](LICENSE), как и оригинальный TrustTunnel Flutter Client © Adguard Software Ltd. Сторонний код и материалы сохраняют свои лицензии — см. [NOTICE](NOTICE) и `assets/licenses/` (они же на странице лицензий в приложении). Исключение: стихи Марсика защищены авторским правом и под Apache-2.0 не распространяются (подробно в NOTICE).

«TrustTunnel» и «AdGuard» — товарные знаки их владельцев. CatTunnel с ними не связан и лишь работает по протоколу TrustTunnel.

При разработке использовался ИИ-ассистент Claude.
