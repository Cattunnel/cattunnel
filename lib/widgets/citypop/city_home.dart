import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/assets/font_families.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/widgets/citypop/city_scene.dart';
import 'package:trusttunnel/widgets/citypop/city_style.dart';

/// Short, decorative Japanese status next to the real (Russian) one.
String cityStatusJa(VpnState state) => switch (state) {
  VpnState.connected => '接続済',
  VpnState.connecting => '接続中',
  VpnState.disconnected => '未接続',
  _ => '接続失敗',
};

bool cityIsTrouble(VpnState state) => switch (state) {
  VpnState.waitingForRecovery || VpnState.recovering || VpnState.waitingForNetwork => true,
  _ => false,
};

/// The home in «City pop»: the live street scene fills the page, the status
/// stands on top of it, Marsik sits on the ledge above the cassette panel
/// (J-card with two keys: PLAY connects, STOP disconnects).
///
/// It only draws: connecting, the server list and the session timer stay in
/// CozyServersView, which passes the callbacks in.
class CityHomeBody extends StatelessWidget {
  final VpnState state;
  final String serverName;
  final String serverSub;
  final int? pingMs;
  final bool unreachable;
  final Duration? session;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onPickServer;
  final Widget? topActions;

  /// Wide window: the always-open server list shown under the cassette panel
  /// in the right column. Null keeps the phone layout even on a wide screen.
  final Widget? wideServers;

  /// Tests and screenshots: a fixed scene frame and time of day.
  final double? still;
  final double? timeOfDay;

  const CityHomeBody({
    super.key,
    required this.state,
    required this.serverName,
    required this.serverSub,
    required this.onPlay,
    required this.onStop,
    required this.onPickServer,
    this.pingMs,
    this.unreachable = false,
    this.session,
    this.topActions,
    this.wideServers,
    this.still,
    this.timeOfDay,
  });

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String formatSession(Duration d) => '${_two(d.inHours)}:${_two(d.inMinutes % 60)}:${_two(d.inSeconds % 60)}';

  @override
  Widget build(BuildContext context) {
    final night = context.isCityNight;
    final trouble = cityIsTrouble(state);
    final alive = switch (state) {
      VpnState.connected => 1.0,
      VpnState.connecting => 0.55,
      VpnState.disconnected => 0.0,
      _ => 0.55,
    };

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final panelH = (h * 0.31).clamp(222.0, 280.0);
        final catW = (w * (state == VpnState.disconnected ? 0.43 : 0.33)).clamp(110.0, 180.0);
        final wide = w >= 840 && wideServers != null;

        if (wide) {
          final scene = Stack(
            fit: StackFit.expand,
            children: [
              CityScene(
                alive: alive,
                fault: trouble ? 1 : 0,
                dark: night,
                still: still,
                timeOfDay: timeOfDay,
                planeNow: still != null,
              ),
              Positioned(
                left: 14,
                right: 14,
                top: MediaQuery.paddingOf(context).top + 6,
                child: _TopBar(actions: topActions, dark: _sceneIsDark(context, timeOfDay)),
              ),
              Positioned(
                left: 24,
                right: 48,
                top: MediaQuery.paddingOf(context).top + 76,
                child: _StatusBlock(
                  state: state,
                  session: session,
                  pingMs: pingMs,
                  unreachable: unreachable,
                  dark: _sceneIsDark(context, timeOfDay),
                ),
              ),
              Positioned(
                right: 16,
                top: MediaQuery.paddingOf(context).top + 90,
                child: _Tategaki(text: cityStatusJa(state)),
              ),
            ],
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: scene),
              SizedBox(
                width: (w * 0.38).clamp(320.0, 480.0),
                child: Column(
                  children: [
                    SizedBox(
                      height: panelH,
                      child: _CassettePanel(
                        state: state,
                        serverName: serverName,
                        serverSub: serverSub,
                        pingMs: pingMs,
                        onPlay: onPlay,
                        onStop: onStop,
                        onPickServer: onPickServer,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 8, 12, 12),
                        child: wideServers!,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            CityScene(
              alive: alive,
              fault: trouble ? 1 : 0,
              dark: night,
              still: still,
              timeOfDay: timeOfDay,
              planeNow: still != null,
            ),
            Positioned(
              left: 14,
              right: 14,
              top: MediaQuery.paddingOf(context).top + 6,
              child: _TopBar(actions: topActions, dark: _sceneIsDark(context, timeOfDay)),
            ),
            Positioned(
              left: 16,
              right: 40,
              top: MediaQuery.paddingOf(context).top + 62,
              child: _StatusBlock(
                state: state,
                session: session,
                pingMs: pingMs,
                unreachable: unreachable,
                dark: _sceneIsDark(context, timeOfDay),
              ),
            ),
            Positioned(
              right: 8,
              top: MediaQuery.paddingOf(context).top + 76,
              child: _Tategaki(text: cityStatusJa(state)),
            ),
            Positioned(
              right: 14,
              bottom: panelH - 6,
              child: _Marsik(state: state, width: catW, onTap: state == VpnState.disconnected ? onPlay : onStop),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: panelH,
              child: _CassettePanel(
                state: state,
                serverName: serverName,
                serverSub: serverSub,
                pingMs: pingMs,
                onPlay: onPlay,
                onStop: onStop,
                onPickServer: onPickServer,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Text over the scene: cream with a dark plate by night and at dusk, ink on
/// a cream plate by day, so it stays readable on any frame of the sky.
bool _sceneIsDark(BuildContext context, double? tod) {
  final t = tod ?? CityClock.todAt(DateTime.now());

  return t > 0.3;
}

class _TopBar extends StatelessWidget {
  final Widget? actions;
  final bool dark;

  const _TopBar({required this.dark, this.actions});

  @override
  Widget build(BuildContext context) {
    final plate = dark ? const Color(0x99140A28) : const Color(0xDBFFF6E6);
    final ink = dark ? const Color(0xFFFFF6E6) : CityColors.ink;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 5, 14, 5),
          decoration: BoxDecoration(
            color: plate,
            borderRadius: BorderRadius.circular(18),
            border: const Border(left: BorderSide(color: CityColors.red, width: 4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform(
                transform: Matrix4.skewX(-0.14),
                child: Text(
                  'CatTunnel',
                  style: TextStyle(fontFamily: FontFamilies.delaGothicOne, fontSize: 17, color: ink, height: 1.1),
                ),
              ),
              Text(
                'キャットトンネル · VPN',
                style: TextStyle(
                  fontFamily: FontFamilies.mPlus1p,
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                  letterSpacing: 0.6,
                  color: ink.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (actions != null) actions!,
      ],
    );
  }
}

class _StatusBlock extends StatelessWidget {
  final VpnState state;
  final Duration? session;
  final int? pingMs;
  final bool unreachable;
  final bool dark;

  const _StatusBlock({
    required this.state,
    required this.session,
    required this.pingMs,
    required this.unreachable,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    final ink = dark ? const Color(0xFFFFF6E6) : CityColors.ink;
    final trouble = cityIsTrouble(state);
    final title = trouble
        ? context.ln.connectionErrorDialogTitle
        : switch (state) {
            VpnState.connected => context.ln.trayStatusConnected,
            VpnState.disconnected => context.ln.trayStatusDisconnected,
            _ => context.ln.trayStatusConnecting,
          };
    final details = <String>[
      if (state == VpnState.connected && session != null)
        context.ln.cozySessionTime(CityHomeBody.formatSession(session!)),
      if (pingMs != null) context.ln.cozyPing(pingMs!),
      if (unreachable && state != VpnState.connected) context.ln.serverUnreachable,
    ];
    final sub = details.isNotEmpty
        ? details.join(' · ')
        : (state == VpnState.disconnected
              ? context.ln.cozyTapToConnect
              : (state == VpnState.connecting ? context.ln.diagProgressUsually : ''));
    final service = switch (state) {
      VpnState.connected => 'ON AIR',
      VpnState.connecting => 'TUNING',
      VpnState.disconnected => 'STANDBY',
      _ => 'NO SIGNAL',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _Service('SIDE A', ink),
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: ink.withValues(alpha: 0.6),
              ),
            ),
            _Service(service, ink),
          ],
        ),
        const SizedBox(height: 4),
        Transform(
          transform: Matrix4.skewX(-0.14),
          child: Text(
            title,
            maxLines: 2,
            style: TextStyle(
              fontFamily: FontFamilies.delaGothicOne,
              fontSize: trouble ? 22 : 31,
              height: 1.12,
              color: ink,
              shadows: dark
                  ? const [Shadow(color: Color(0xCCFF5078), blurRadius: 14)]
                  : const [Shadow(color: Color(0xE6FFF6E6), blurRadius: 10)],
            ),
          ),
        ),
        const SizedBox(height: 6),
        // One red and one cream band, like the paper strip on a record
        Container(width: 132, height: 4, color: CityColors.red),
        Container(width: 132, height: 3, margin: const EdgeInsets.only(top: 1.5), color: CityColors.cream),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: 9),
          Container(
            constraints: const BoxConstraints(maxWidth: 300),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xE6FFF6E6),
              borderRadius: BorderRadius.circular(14),
              border: const Border(left: BorderSide(color: CityColors.gold, width: 3)),
            ),
            child: Text(
              sub,
              style: const TextStyle(
                fontFamily: FontFamilies.mPlus1p,
                fontWeight: FontWeight.w500,
                fontSize: 14.5,
                height: 1.35,
                color: CityColors.ink,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Service extends StatelessWidget {
  final String text;
  final Color color;

  const _Service(this.text, this.color);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontFamily: FontFamilies.mPlus1p,
      fontWeight: FontWeight.w800,
      fontSize: 11,
      letterSpacing: 1.8,
      color: color,
    ),
  );
}

/// A vertical line of Japanese, one upright character under another.
class _Tategaki extends StatelessWidget {
  final String text;

  const _Tategaki({required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    decoration: BoxDecoration(color: const Color(0x8C140A28), borderRadius: BorderRadius.circular(10)),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final ch in text.runes)
          Text(
            String.fromCharCode(ch),
            style: const TextStyle(
              fontFamily: FontFamilies.mPlus1p,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              height: 1.2,
              color: Color(0xFFFFF6E6),
            ),
          ),
      ],
    ),
  );
}

class _Marsik extends StatelessWidget {
  final VpnState state;
  final double width;
  final VoidCallback onTap;

  const _Marsik({required this.state, required this.width, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final image = switch (state) {
      VpnState.connected => AssetImages.catShield,
      VpnState.connecting => AssetImages.catGear,
      VpnState.disconnected => AssetImages.catSleeping,
      _ => AssetImages.catAlert,
    };

    return Semantics(
      button: true,
      label: state == VpnState.disconnected ? context.ln.connect : context.ln.disconnect,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOut,
          child: Image.asset(image, key: ValueKey(image), width: width),
        ),
      ),
    );
  }
}

/// The J-card: a cassette, the current server as «track A1», and the deck
/// keys. PLAY is down while connected; the reels turn while connecting (fast)
/// and while connected (slow), and stand still when off or on error.
class _CassettePanel extends StatelessWidget {
  final VpnState state;
  final String serverName;
  final String serverSub;
  final int? pingMs;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onPickServer;

  const _CassettePanel({
    required this.state,
    required this.serverName,
    required this.serverSub,
    required this.pingMs,
    required this.onPlay,
    required this.onStop,
    required this.onPickServer,
  });

  @override
  Widget build(BuildContext context) {
    final night = context.isCityNight;
    final ink = night ? const Color(0xFFF7ECD6) : CityColors.ink;
    final soft = night ? const Color(0xFFC9B9D6) : const Color(0xFF5B4A5E);
    final paper = night ? CityColors.night : CityColors.cream;
    final trouble = cityIsTrouble(state);
    final playDown = state == VpnState.connected || state == VpnState.connecting;
    final stopDown = state == VpnState.disconnected || trouble;
    final playLabel = trouble ? context.ln.diagRetry : context.ln.connect;
    final stopLabel = state == VpnState.connecting ? context.ln.diagCancel : context.ln.disconnect;
    final led = switch (state) {
      VpnState.connected => const Color(0xFF2FE08A),
      VpnState.connecting => const Color(0xFFFFB02E),
      VpnState.disconnected => const Color(0xFF7A7389),
      _ => const Color(0xFFFF3B3B),
    };

    return Container(
      decoration: BoxDecoration(
        color: paper,
        border: Border(top: BorderSide(color: ink, width: 3)),
        boxShadow: const [BoxShadow(color: Color(0x40140828), blurRadius: 24, offset: Offset(0, -8))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(height: 4, color: CityColors.red),
            Container(
              height: 3,
              margin: const EdgeInsets.only(top: 1.5),
              color: night ? CityColors.gold : CityColors.cream.withValues(alpha: 0.0),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: onPickServer,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            _Cassette(state: state, ink: ink, night: night),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${context.ln.cozyServer.toUpperCase()} · SIDE A · 01',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: FontFamilies.mPlus1p,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 11,
                                      letterSpacing: 1.0,
                                      color: soft,
                                    ),
                                  ),
                                  Text(
                                    serverName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: FontFamilies.mPlus1p,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                      color: ink,
                                    ),
                                  ),
                                  Text(
                                    serverSub,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: FontFamilies.mPlus1p,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                      color: soft,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (pingMs != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Text(
                                  context.ln.cozyPing(pingMs!).replaceFirst(RegExp(r'^\D+'), ''),
                                  style: TextStyle(
                                    fontFamily: FontFamilies.mPlus1p,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: night ? const Color(0xFF5EF1E6) : const Color(0xFF0F6F63),
                                  ),
                                ),
                              ),
                            Icon(Icons.expand_more_rounded, color: soft, size: 22),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _Key(
                            label: 'PLAY',
                            caption: playLabel,
                            icon: _KeyIcon.play,
                            down: playDown,
                            half: state == VpnState.connecting,
                            led: led,
                            ink: ink,
                            night: night,
                            onTap: onPlay,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Key(
                            label: 'STOP',
                            caption: stopLabel,
                            icon: _KeyIcon.stop,
                            down: stopDown,
                            ink: ink,
                            night: night,
                            onTap: onStop,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _KeyIcon { play, stop }

/// A deck key: sinks 3 dp when pressed (120 ms, ease-out), hard shadow under it.
class _Key extends StatelessWidget {
  final String label;
  final String caption;
  final _KeyIcon icon;
  final bool down;
  final bool half;
  final Color? led;
  final Color ink;
  final bool night;
  final VoidCallback onTap;

  const _Key({
    required this.label,
    required this.caption,
    required this.icon,
    required this.down,
    required this.ink,
    required this.night,
    required this.onTap,
    this.half = false,
    this.led,
  });

  @override
  Widget build(BuildContext context) {
    final offset = down ? 3.0 : (half ? 1.5 : 0.0);
    final top = night ? const Color(0xFF3B2F66) : const Color(0xFFECE6D6);
    final bottom = night ? const Color(0xFF271D4D) : const Color(0xFFCDC5B0);
    final pressed = night ? const Color(0xFF1A1236) : const Color(0xFFB9B19C);

    return Semantics(
      button: true,
      label: caption,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          height: 64,
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                top: offset,
                bottom: 4 - offset,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    gradient: down
                        ? null
                        : LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [top, bottom],
                          ),
                    color: down ? pressed : null,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ink, width: 2),
                    boxShadow: [BoxShadow(color: ink, offset: Offset(0, 4 - offset))],
                  ),
                  child: Row(
                    children: [
                      CustomPaint(
                        size: const Size(22, 22),
                        painter: _KeyIconPainter(icon, icon == _KeyIcon.play ? CityColors.red : ink),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontFamily: FontFamilies.mPlus1p,
                                fontWeight: FontWeight.w800,
                                fontSize: 10.5,
                                letterSpacing: 1.8,
                                color: night ? const Color(0xFFC9B9D6) : const Color(0xFF5B4A5E),
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                caption,
                                maxLines: 1,
                                style: TextStyle(
                                  fontFamily: FontFamilies.mPlus1p,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                  height: 1.15,
                                  color: ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (led != null)
                Positioned(
                  right: 9,
                  top: 8 + offset,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: led,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: led!.withValues(alpha: 0.8), blurRadius: 6)],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyIconPainter extends CustomPainter {
  final _KeyIcon icon;
  final Color color;

  const _KeyIconPainter(this.icon, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    if (icon == _KeyIcon.play) {
      canvas.drawPath(
        Path()
          ..moveTo(size.width * 0.18, size.height * 0.08)
          ..lineTo(size.width * 0.9, size.height * 0.5)
          ..lineTo(size.width * 0.18, size.height * 0.92)
          ..close(),
        paint,
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * 0.14, size.height * 0.14, size.width * 0.72, size.height * 0.72),
          const Radius.circular(3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_KeyIconPainter old) => old.icon != icon || old.color != color;
}

/// The cassette: label strip, window with two reels. The reels turn fast
/// while connecting, slowly while connected, and stand still otherwise.
class _Cassette extends StatefulWidget {
  final VpnState state;
  final Color ink;
  final bool night;

  const _Cassette({required this.state, required this.ink, required this.night});

  @override
  State<_Cassette> createState() => _CassetteState();
}

class _CassetteState extends State<_Cassette> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(seconds: 1));
  bool _reduce = false;

  Duration? get _period => switch (widget.state) {
    // Slower than a real reel on purpose: the owner found 0.65 s / 3.2 s
    // per turn too fast (01.11).
    VpnState.connecting => const Duration(milliseconds: 1800),
    VpnState.connected => const Duration(milliseconds: 6000),
    _ => null,
  };

  void _sync() {
    final period = _period;
    if (period == null || _reduce) {
      _turn.stop();
    } else {
      _turn.duration = period;
      if (!_turn.isAnimating) _turn.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(_Cassette old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      _turn.duration = _period ?? _turn.duration;
      _sync();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: const Size(84, 56),
      painter: _CassettePainter(turn: _turn, ink: widget.ink, night: widget.night),
    ),
  );
}

class _CassettePainter extends CustomPainter {
  final Animation<double> turn;
  final Color ink;
  final bool night;

  _CassettePainter({required this.turn, required this.ink, required this.night}) : super(repaint: turn);

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10));
    canvas.drawRRect(body.shift(const Offset(2, 2)), Paint()..color = ink);
    canvas.drawRRect(body, Paint()..color = night ? const Color(0xFF2D2358) : const Color(0xFFEFE3C8));
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ink,
    );
    final label = RRect.fromRectAndRadius(Rect.fromLTWH(7, 5, size.width - 14, 17), const Radius.circular(4));
    canvas.drawRRect(label, Paint()..color = const Color(0xFFFFFAF0));
    canvas.drawRRect(
      label,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ink,
    );
    final tp = TextPainter(
      text: const TextSpan(
        text: 'A',
        style: TextStyle(fontFamily: FontFamilies.delaGothicOne, fontSize: 10, color: CityColors.red),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(11, 7));
    final win = RRect.fromRectAndRadius(
      Rect.fromLTWH(14, size.height - 27, size.width - 28, 21),
      const Radius.circular(10.5),
    );
    canvas.drawRRect(win, Paint()..color = const Color(0xFF17102B));
    for (final cx in [26.0, size.width - 26]) {
      final c = Offset(cx, size.height - 16.5);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(turn.value * 2 * math.pi);
      for (var i = 0; i < 6; i++) {
        canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: 6.5),
          i * math.pi / 3,
          math.pi / 5,
          true,
          Paint()..color = const Color(0xFFFFFAF0),
        );
      }
      canvas.drawCircle(Offset.zero, 2.2, Paint()..color = const Color(0xFF8D84A6));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CassettePainter old) => old.ink != ink || old.night != night;
}
