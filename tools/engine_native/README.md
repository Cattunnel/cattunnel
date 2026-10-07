# Нативное ядро TrustTunnelClient: своя сборка и патчи (DPI2)

Начато 30.09.2026. Цель: anti-DPI 2 — ClientHello отправляется приёмами
byedpi (github.com/hufrea/byedpi, MIT), одной TLS-записью, серверу менять
ничего не нужно. Сейчас все платформы берут готовое ядро 1.1.7 (Android: AAR
из Maven + наш `tools/engine_patch` только для Kotlin; десктоп: CLI с релиза).

## Сборка (Linux, WSL, без sudo)
`build_linux.sh` — копия `~/tt-build/build.sh`. Нужны: conan 2.31.1
(официальный бинарник в `~/tt-build/conan`), Rust 1.95 (`~/.cargo`,
rustup-init --profile minimal), clang 19 + libstdc++ (libc++ нет). Закрытый
conan-remote AdGuard не нужен: `scripts/bootstrap_conan_deps.py` + повторный
экспорт NativeLibsCommon 8.1.52 (рецепт boringssl). Первая сборка ~17 мин
(зависимости в `~/tt-build/conan-home`), потом инкрементально.
Результат: `~/tt-build/TrustTunnelClient/build/trusttunnel/trusttunnel_client`.

## 0001-anti-dpi-desync.patch (к тегу v1.1.7)
- TOML endpoint `anti_dpi_mode` 0..3 (при `anti_dpi = true`), протянут до
  `TcpSocketConnectParameters` и пинговалки (`ping.cpp`, `locations_pinger`).
- 0 — как в апстриме (1 байт, пауза 25 мс); 1 — OOB после 3-го байта и
  байты 4–7 с TTL 1 (byedpi `-o3 -d7`); 2 — первые 7 байт с TTL 1; 3 — OOB +
  TTL 1 внутри SNI.
- Реализация: `desync_write` в `net/src/tcp_socket.cpp` (первый TLS-flight из
  `do_handshake`).
- Проверено nl → main:8443 (мимо ТСПУ): 30.09 режимы 0, 2, 3 — TLS проходит;
  30.09 вечером, после правки режима 1 — все четыре (`handshake complete`).
- **Почему чистый OOB (`-o1`) висел:** сервер TrustTunnel на tokio читает
  ClientHello кусками по 1024 байта (`tls_listener.rs`). Linux-чтение
  останавливается на OOB-метке и отдаёт 1 байт; tokio на epoll считает
  короткое чтение признаком пустого сокета и снимает готовность, а остаток
  ClientHello уже лежит в очереди, нового события не будет — сервер ждёт
  вечно. Воспроизведено локально (tokio 1.53, чтение после того, как пришло
  всё). Любой TTL-1 кусок после OOB спасает: его перепосылка приходит позже и
  будит сервер. Поэтому все OOB-режимы идут в паре с TTL 1 (так же были
  устроены прошедшие через ТСПУ стратегии ByeDPI, кроме `-o1` с авто-откатом
  на `-d1`).

## Android (30.09)
`build_android.sh` собирает `libtrusttunnel_android.so` (gradle upstream +
conan + cargo-ndk), `NATIVE_JNI=~/tt-build/jni tools/engine_patch/build.sh`
кладёт её в AAR вместо официальной (остальные ABI остаются официальными).
JNI-экспорты совпадают с официальной (14 функций). Первая сборка arm64
~25 мин, потом ~30 с.

**Проверено на Galaxy S22 (Android 16, домашний Wi-Fi Билайн) → «Германия 2»
.227:443, где обычный сплит режется:** режимы 1, 2, 3 и «авто» подключаются,
«обычный» — нет. tcpdump на телефоне: 1 = URG-пакет (3 байта + мусор), 4
байта с TTL 1, остальное, перепосылка; 2 = 7 байт с TTL 1; 3 = URG до
первого байта SNI, 2 байта с TTL 1.
**Грабли Android:** кусок с TTL 1 сразу за OOB-пакетом ядро придерживает
(TCP small queues) и отправляет уже после возврата TTL, а `SIOCOUTQNSD` SELinux
приложению не даёт. Лечение: перед каждым следующим куском ждать ACK
(`TCP_INFO.tcpi_unacked == 0`, как у sing-box), «отправлено» на Android — по
`tcpi_notsent_bytes`. +1 RTT на установку соединения.

## Клиент (сделано 30.09)
- `ServerData.antiDpiMode` (БД `servers.anti_dpi_mode`, миграция v9): 0 —
  обычный, 1..3, 4 — авто. В форме сервера под «Анти-DPI» — «Способ обхода».
- В движок уходит `anti_dpi_mode` только 1..3 (`ConfigurationCodec`); Linux
  helper пропускает ключ (`config_guard.cpp`). Апстрим-ядро ключ игнорирует и
  делает обычный сплит.
- `tt://`-тег 0x41 (1 байт, 1..4): подписка может задать режим; без тега
  остаётся выбор пользователя.
- «Авто»: `VpnScope._startAntiDpiAuto` + `AntiDpiAuto` — 1→2→3 (удачный
  первым), 6 с на попытку, один круг; удачный запоминается в
  SharedPreferences по «id сервера + тип сети» (wifi/mobile/ethernet,
  `connectivity_plus`); не прошёл ни один — VPN останавливается, Марсик
  показывает «Обход не сработал».

## Дальше
1. Пробы relay → main:443 режимами 1–3 (только по команде владельца, считать
пробы). 2. Бот: тег 0x41 в ссылках подписки. 3. Ядро: Android arm64 собрано (остальные ABI — `TT_ABIS`), Windows и
Linux-бандл — нет; там режимы 1–3 пока работают как обычный сплит. 4. Идея: в ядро же — правила «никогда
не мимо VPN» (исключения внутри `*.ru`).

## 1.5.0: block_quic (03.10)
- TOML endpoint `block_quic = true` → `VpnUpstreamConfig.block_quic` →
  `EndpointConnectionConfig` → `Tunnel::finalize_connect_action`: UDP на порт
  443 (кроме DNS) получает `VPN_CA_REJECT`, браузеры переходят на TCP внутри
  туннеля. Тест `TunnelTest.BlockQuic` (core/test/test_tunnel.cpp).
- Приложение: `ServerData.blockQuic` (БД v12), тег `tt://` 0x45, переключатель
  «Отключить QUIC» в «Для экспертов». AAR patch level 10.
