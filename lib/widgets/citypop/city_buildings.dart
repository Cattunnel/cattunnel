part of 'city_world.dart';

// Buildings of the «City pop» street: the far shore across the water and the
// facades of the left side of the street. Tokyo of the 80s: narrow
// multi-tenant «zakkyo» towers with a column of signs, ribbon-window
// offices with set-back top floors, apartment blocks with balconies,
// outdoor stairs and wall air conditioners, low tiled-roof houses between
// the tall ones, water tanks, antennas and billboards on the roofs.
//
// Everything is generated once in [_build] (geometry only, no colours), so
// the static layers and the per-frame lit layers read the same lists.

// ---------------------------------------------------------------- far shore
/// A lit or dark window of a far building, in pixels relative to the point
/// (left edge, waterline) of the building; y grows downwards (negative up).
class _Win {
  final Rect r;

  /// 0 plain window, 1 segment of a ribbon window, 2 shop window.
  final int k;
  final int row, col;
  const _Win(this.r, this.k, this.row, this.col);
}

class _FarSign {
  final Rect r;
  final int ci; // neon colour
  final int pc; // 0 or 1: which of the two paint colours of the building
  const _FarSign(this.r, this.ci, this.pc);
}

/// Roof and wall equipment of a far building.
/// kind 0 water tank, 1 antenna, 2 box (air conditioner, machine room),
/// 3 billboard frame (the lit face is a [_FarSign]), 4 wall air conditioner,
/// 5 outdoor stair, 6 balcony rail.
class _Deco {
  final int kind;
  final Rect r;
  const _Deco(this.kind, this.r);
}

class _Far {
  final double x, w, h;
  final int type; // 0 zakkyo, 1 office, 2 apartments, 3 low tiled house, 4 tower
  final bool tower, beacon, dk;
  final int id;
  final double ph, tint, pos;
  final List<Rect> body = [];
  final List<_Win> wins = [];
  final List<_FarSign> signs = [];
  final List<_Deco> decos = [];
  final List<double> paintA, paintB;

  /// Height of the wall under the tiled roof (type 3 only).
  double wall = 0;
  _Far(
    this.x,
    this.w,
    this.h,
    this.type,
    this.beacon,
    this.dk,
    this.id,
    this.ph,
    this.tint,
    this.pos,
    this.paintA,
    this.paintB,
  ) : tower = type == 4;
}

extension _FarGen on CityWorld {
  void _buildFar(math.Random r) {
    final w = _size.width, h = _size.height, u = _u;
    _far.clear();
    var x = -10 * u;
    var id = 0;
    var prev = -1;
    while (x < w + 10 * u) {
      final inBay = x > 0.60 * w;
      final centre = ((x + 8 * u) / w - 0.46).abs() < 0.2;
      var type = 0;
      for (var tries = 0; tries < 4; tries++) {
        final p = r.nextDouble();
        type = p < 0.14 && !inBay
            ? 4
            : p < 0.28
            ? 3
            : p < 0.58
            ? 0
            : p < 0.79
            ? 1
            : 2;
        if (type != prev || type == 3) break;
      }
      prev = type;
      var bw = 0.0, bh = 0.0;
      switch (type) {
        case 0:
          bw = (8 + r.nextDouble() * 5) * u;
          bh = (36 + r.nextDouble() * 34) * u;
        case 1:
          bw = (16 + r.nextDouble() * 14) * u;
          bh = (30 + r.nextDouble() * 34) * u;
        case 2:
          bw = (12 + r.nextDouble() * 8) * u;
          bh = (28 + r.nextDouble() * 26) * u;
        case 3:
          bw = (9 + r.nextDouble() * 7) * u;
          bh = (10 + r.nextDouble() * 5) * u;
        default:
          bw = (18 + r.nextDouble() * 10) * u;
          bh = (95 + r.nextDouble() * 80) * u * (h / 800);
      }
      if (type != 3) bh *= (inBay ? 0.6 : 1) * (centre && type != 4 ? 1.35 : 1);
      bh = math.min(bh, 0.18 * h);
      final pa = _paint[r.nextInt(_paint.length)];
      var pb = _paint[r.nextInt(_paint.length)];
      if (identical(pa, pb)) pb = const [226.0, 214.0, 190.0];
      final b = _Far(
        x,
        bw,
        bh,
        type,
        type == 4 || (type == 1 && bh > 60 * u),
        r.nextDouble() < 0.45,
        id,
        r.nextDouble(),
        r.nextDouble(),
        0.15 + 0.5 * (x / w),
        pa,
        pb,
      );
      _genFar(b, r);
      _far.add(b);
      id++;
      x += bw + (r.nextDouble() < 0.3 ? 3 * u : 0.5 * u);
    }
  }

  void _genFar(_Far b, math.Random r) {
    final u = _u, w = b.w, h = b.h;
    switch (b.type) {
      case 0:
        b.body.add(Rect.fromLTWH(0, -h, w, h));
        final fh = 5 * u, n = ((h - 3.5 * u) / fh).floor();
        final signLeft = r.nextBool(), sw = w * 0.36, sx = signLeft ? w * 0.05 : w * 0.59;
        b.wins.add(_Win(Rect.fromLTWH(w * 0.08, -2.6 * u, w * 0.84, 1.9 * u), 2, 0, 0));
        for (var i = 0; i < n; i++) {
          final top = -(3.5 * u + (i + 1) * fh);
          final wx = signLeft ? w * 0.46 : w * 0.07, ww = w * 0.42;
          b.wins.add(_Win(Rect.fromLTWH(wx, top + fh * 0.22, ww, fh * 0.5), 0, i, 0));
          if (r.nextDouble() < 0.85) {
            b.signs.add(
              _FarSign(Rect.fromLTWH(sx, top + 0.5 * u, sw, fh - 1.1 * u), r.nextInt(_neon.length), i.isEven ? 0 : 1),
            );
          }
          if (r.nextDouble() < 0.3) {
            b.decos.add(_Deco(4, Rect.fromLTWH(wx + ww * 0.15, top + fh * 0.74, 1.8 * u, 1.0 * u)));
          }
        }
        _roofGen(b, r, w * 0.9);
      case 1 || 4:
        final fh = 4 * u, n = ((h - 2 * u) / fh).floor();
        final setback = h > 44 * u && r.nextDouble() < (b.type == 4 ? 0.9 : 0.6);
        final low = setback ? (n * (0.62 + 0.15 * r.nextDouble())).floor() : n;
        final ins = w * 0.17, lowH = 2 * u + low * fh;
        if (setback) {
          b.body.add(Rect.fromLTWH(0, -lowH, w, lowH));
          b.body.add(Rect.fromLTWH(ins, -h, w - 2 * ins, h - lowH + 1));
        } else {
          b.body.add(Rect.fromLTWH(0, -h, w, h));
        }
        b.wins.add(_Win(Rect.fromLTWH(w * 0.06, -2.0 * u, w * 0.88, 1.4 * u), 2, 0, 0));
        for (var i = 0; i < n; i++) {
          final top = -(2 * u + (i + 1) * fh);
          final x0 = i < low ? w * 0.05 : ins + w * 0.04, x1 = i < low ? w * 0.95 : w - ins - w * 0.04;
          final segs = math.max(2, ((x1 - x0) / (3.6 * u)).round()), sw = (x1 - x0) / segs;
          for (var j = 0; j < segs; j++) {
            b.wins.add(_Win(Rect.fromLTWH(x0 + j * sw + 0.3 * u, top + fh * 0.2, sw - 0.6 * u, fh * 0.52), 1, i, j));
          }
        }
        if (r.nextDouble() < 0.5) {
          // a vertical sign hung on the corner, above the shops
          b.signs.add(
            _FarSign(
              Rect.fromLTWH(-1.4 * u, -h * (0.35 + 0.3 * r.nextDouble()), 1.5 * u, 11 * u),
              r.nextInt(_neon.length),
              0,
            ),
          );
        }
        _roofGen(b, r, setback ? w - 2 * ins : w * 0.9, left: setback ? ins : w * 0.05);
      case 2:
        b.body.add(Rect.fromLTWH(0, -h, w, h));
        final fh = 4.4 * u, n = ((h - 2.5 * u) / fh).floor();
        final stairLeft = r.nextBool(), sW = 2.2 * u;
        final x0 = stairLeft ? sW + 1 * u : 1 * u, x1 = stairLeft ? w - 1 * u : w - sW - 1 * u;
        b.decos.add(_Deco(5, Rect.fromLTWH(stairLeft ? 0 : w - sW, -h, sW, h)));
        b.wins.add(_Win(Rect.fromLTWH(x0, -2.3 * u, x1 - x0, 1.6 * u), 2, 0, 0));
        final cnt = math.max(2, ((x1 - x0) / (4.4 * u)).round()), cw = (x1 - x0) / cnt;
        for (var i = 0; i < n; i++) {
          final top = -(2.5 * u + (i + 1) * fh);
          b.decos.add(_Deco(6, Rect.fromLTWH(x0, top + fh * 0.58, x1 - x0, fh * 0.4)));
          for (var j = 0; j < cnt; j++) {
            b.wins.add(_Win(Rect.fromLTWH(x0 + j * cw + cw * 0.18, top + fh * 0.12, cw * 0.64, fh * 0.46), 0, i, j));
          }
          if (r.nextDouble() < 0.4) {
            b.decos.add(
              _Deco(4, Rect.fromLTWH(x0 + r.nextInt(cnt) * cw + cw * 0.25, top + fh * 0.64, 1.6 * u, 0.9 * u)),
            );
          }
        }
        _roofGen(b, r, w * 0.9);
      default:
        b.wall = h * 0.58;
        b.body.add(Rect.fromLTWH(0, -b.wall, w, b.wall));
        b.wins.add(_Win(Rect.fromLTWH(w * 0.12, -b.wall * 0.8, w * 0.28, b.wall * 0.45), 0, 0, 0));
        b.wins.add(_Win(Rect.fromLTWH(w * 0.6, -b.wall * 0.8, w * 0.28, b.wall * 0.45), 0, 0, 1));
        b.wins.add(_Win(Rect.fromLTWH(w * 0.2, -b.wall * 0.34, w * 0.6, b.wall * 0.28), 2, 1, 0));
    }
  }

  /// Roof equipment: a water tank, a billboard, an antenna or boxes.
  void _roofGen(_Far b, math.Random r, double span, {double left = 0}) {
    final u = _u, top = -b.h;
    final pick = r.nextDouble();
    if (pick < 0.3) {
      b.decos.add(_Deco(0, Rect.fromLTWH(left + span * 0.15, top - 5.2 * u, 3.6 * u, 4.2 * u)));
      b.decos.add(_Deco(2, Rect.fromLTWH(left + span * 0.62, top - 2.4 * u, 4 * u, 2.4 * u)));
    } else if (pick < 0.6) {
      final face = Rect.fromLTWH(left + span * 0.08, top - 7.4 * u, span * 0.7, 4.6 * u);
      b.decos.add(_Deco(3, face));
      b.signs.add(_FarSign(face.deflate(0.5 * u), r.nextInt(_neon.length), 1));
    } else if (pick < 0.8) {
      b.decos.add(_Deco(1, Rect.fromLTWH(left + span * (0.3 + 0.4 * r.nextDouble()), top - 10 * u, 0.9 * u, 10 * u)));
      b.decos.add(_Deco(2, Rect.fromLTWH(left + span * 0.1, top - 2.6 * u, 4.4 * u, 2.6 * u)));
    } else {
      b.decos.add(_Deco(2, Rect.fromLTWH(left + span * 0.1, top - 2.6 * u, 5 * u, 2.6 * u)));
      b.decos.add(_Deco(0, Rect.fromLTWH(left + span * 0.55, top - 5.2 * u, 3.6 * u, 4.2 * u)));
      b.decos.add(_Deco(1, Rect.fromLTWH(left + span * 0.9, top - 8 * u, 0.8 * u, 8 * u)));
    }
  }

  Color _farBase(_Far b) {
    final f = 0.86 + 0.26 * b.tint;
    final base = switch (b.type) {
      0 => _p3([200, 160, 150], [128, 62, 102], [28, 14, 54], _tod),
      1 || 4 => _p3([158, 172, 198], [92, 64, 128], [22, 16, 60], _tod),
      2 => _p3([218, 198, 168], [130, 72, 112], [30, 16, 56], _tod),
      _ => _p3([150, 124, 120], [96, 52, 90], [22, 12, 46], _tod),
    };
    final col = _mixc(
      [base[0] * f, base[1] * f, base[2] * f],
      _hz,
      0.15 + 0.12 * (1 - math.min(1, b.h / (90 * _u))) + b.tint * 0.05,
    );

    return _c(col);
  }

  void _paintFarStatic(Canvas canvas) {
    final hy = _hy, u = _u;
    final metal = _c(_p3([104, 98, 110], [62, 38, 78], [18, 12, 38], _tod));
    final tile = _c(_p3([84, 92, 112], [64, 40, 82], [20, 14, 40], _tod));
    final pane = _c(_mixc(_p3([120, 168, 178], [58, 40, 96], [14, 12, 40], _tod), _hz, 0.2), 0.62);
    for (final b in _far) {
      final base = _farBase(b);
      final fill = Paint()..color = base;
      for (var i = 0; i < b.body.length; i++) {
        final rr = b.body[i].shift(Offset(b.x, hy));
        canvas.drawRect(i == 0 ? Rect.fromLTRB(rr.left, rr.top, rr.right, rr.bottom + 1) : rr, fill);
      }
      if (b.type == 3) {
        // tiled roof: a trapezoid, a ridge and rows of tiles
        final top = hy - b.h, eave = hy - b.wall;
        canvas.drawPath(
          Path()
            ..moveTo(b.x - 0.8 * u, eave + 0.4 * u)
            ..lineTo(b.x + b.w + 0.8 * u, eave + 0.4 * u)
            ..lineTo(b.x + b.w * 0.82, top)
            ..lineTo(b.x + b.w * 0.18, top)
            ..close(),
          Paint()..color = tile,
        );
        final line = Paint()
          ..color = _c(_p3([50, 56, 74], [40, 22, 56], [10, 8, 28], _tod), 0.7)
          ..strokeWidth = math.max(0.6, 0.35 * u);
        for (var i = 1; i < 4; i++) {
          final t = i / 4;
          canvas.drawLine(
            Offset(_mix(b.x - 0.8 * u, b.x + b.w * 0.18, t), _mix(eave + 0.4 * u, top, t)),
            Offset(_mix(b.x + b.w + 0.8 * u, b.x + b.w * 0.82, t), _mix(eave + 0.4 * u, top, t)),
            line,
          );
        }
      }
      if (_dayK > 0.05 && b.type != 3) {
        canvas.drawRect(
          Rect.fromLTWH(b.x + b.w * 0.74, hy - b.h, b.w * 0.26, b.h + 1),
          Paint()..color = _c([255, 226, 180], 0.30 * _dayK),
        );
      }
      // dark glass of the windows (the lit ones are drawn per frame)
      final pp = Paint()..color = pane;
      for (final wn in b.wins) {
        canvas.drawRect(wn.r.shift(Offset(b.x, hy)), pp);
      }
      // painted signs: a column of boards, in two colours of the building
      for (final s in b.signs) {
        final col = s.pc == 0 ? b.paintA : b.paintB;
        canvas.drawRect(s.r.shift(Offset(b.x, hy)), Paint()..color = _c(_mixc(col, _hz, 0.15)));
      }
      for (final d in b.decos) {
        final rr = d.r.shift(Offset(b.x, hy));
        switch (d.kind) {
          case 0: // water tank: drum on legs, conical lid
            canvas.drawRect(
              Rect.fromLTWH(rr.left, rr.top + rr.height * 0.18, rr.width, rr.height * 0.6),
              Paint()..color = metal,
            );
            canvas.drawPath(
              Path()
                ..moveTo(rr.left - 0.3 * u, rr.top + rr.height * 0.2)
                ..lineTo(rr.center.dx, rr.top - 0.2 * u)
                ..lineTo(rr.right + 0.3 * u, rr.top + rr.height * 0.2)
                ..close(),
              Paint()..color = metal,
            );
            final leg = Paint()
              ..color = metal
              ..strokeWidth = math.max(0.7, 0.4 * u);
            canvas.drawLine(
              Offset(rr.left + 0.4 * u, rr.bottom - rr.height * 0.22),
              Offset(rr.left + 0.2 * u, rr.bottom),
              leg,
            );
            canvas.drawLine(
              Offset(rr.right - 0.4 * u, rr.bottom - rr.height * 0.22),
              Offset(rr.right - 0.2 * u, rr.bottom),
              leg,
            );
          case 1: // antenna with two cross bars
            canvas.drawRect(rr, Paint()..color = metal);
            for (final t in const [0.25, 0.5]) {
              canvas.drawRect(
                Rect.fromCenter(
                  center: Offset(rr.center.dx, rr.top + rr.height * t),
                  width: 4 * u,
                  height: math.max(0.7, 0.4 * u),
                ),
                Paint()..color = metal,
              );
            }
          case 2:
            canvas.drawRect(rr, Paint()..color = metal);
            canvas.drawRect(
              Rect.fromLTWH(rr.left + rr.width * 0.15, rr.top + rr.height * 0.25, rr.width * 0.3, rr.height * 0.45),
              Paint()..color = _c(const [20, 16, 34], 0.35),
            );
          case 3: // billboard: frame and legs; the lit face is a sign
            final frame = Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(0.8, 0.5 * u)
              ..color = metal;
            canvas.drawRect(rr, Paint()..color = _c(_mixc(b.paintB, [14, 8, 34], _neonK * 0.8)));
            canvas.drawRect(rr, frame);
            canvas.drawLine(
              Offset(rr.left + rr.width * 0.25, rr.bottom),
              Offset(rr.left + rr.width * 0.25, rr.bottom + 3 * u),
              frame,
            );
            canvas.drawLine(
              Offset(rr.right - rr.width * 0.25, rr.bottom),
              Offset(rr.right - rr.width * 0.25, rr.bottom + 3 * u),
              frame,
            );
          case 4: // wall air conditioner
            canvas.drawRect(rr, Paint()..color = _c(_p3([226, 224, 230], [150, 110, 150], [60, 50, 90], _tod)));
            canvas.drawRect(
              Rect.fromLTWH(rr.left + rr.width * 0.15, rr.top + rr.height * 0.3, rr.width * 0.7, rr.height * 0.45),
              Paint()..color = _c(const [40, 36, 56], 0.5),
            );
          case 5: // outdoor stair: dark strip with a zigzag
            canvas.drawRect(rr, Paint()..color = _c(_p3([120, 108, 120], [70, 40, 84], [16, 10, 36], _tod), 0.75));
            final zig = Paint()
              ..color = metal
              ..strokeWidth = math.max(0.6, 0.35 * u);
            final fh = 4.4 * u;
            for (var y = rr.bottom - fh; y > rr.top; y -= fh) {
              canvas.drawLine(Offset(rr.left, y + fh), Offset(rr.right, y), zig);
            }
          default: // balcony rail: a band with a top bar
            canvas.drawRect(rr, Paint()..color = _c(_p3([236, 232, 226], [180, 130, 170], [60, 48, 96], _tod), 0.55));
            canvas.drawRect(Rect.fromLTWH(rr.left, rr.top, rr.width, math.max(0.7, 0.45 * u)), Paint()..color = metal);
        }
      }
      if (b.type == 4 || (b.type == 1 && b.beacon)) {
        // mast on the roof
        final top = b.body.last.shift(Offset(b.x, hy));
        canvas.drawRect(Rect.fromLTWH(top.center.dx - 0.5 * u, top.top - 9 * u, 1 * u, 9 * u), Paint()..color = metal);
      }
    }
  }

  /// Lit windows and neon signs of the far shore, with the beacons. The
  /// rectangles are kept for the reflection in the water.
  void _paintFarLit(Canvas canvas) {
    final hy = _hy, u = _u;
    for (final l in _litWin) {
      l.clear();
    }
    for (final l in _litSign) {
      l.clear();
    }
    final dens = _mix(0.03, 0.06, _night);
    final warm = _sm(0.15, 0.7, _tod);
    for (final b in _far) {
      final lit = _lit(b.dk, b.pos);
      final d = dens + 0.62 * lit * warm;
      final off = Offset(b.x, hy);
      for (final wn in b.wins) {
        final rr = _ih(b.id * 977 + wn.col, wn.row + 11), per = 18 + _ih(wn.col, wn.row + b.id) * 50;
        final on = wn.k == 2
            ? _ih(b.id, 41 + wn.row) < 0.9 * lit * warm
            : _ih(b.id * 131 + wn.col * 7 + wn.row, (_time / per + rr * 9).floor()) < d;
        if (debugForceFarWindows ?? on) _litWin[(rr * 4).floor() % 4].add(wn.r.shift(off));
      }
      final nk = _neonK;
      if (nk > 0.05) {
        for (var i = 0; i < b.signs.length; i++) {
          final g = _signGate(b.dk, b.pos, 500 + b.id * 7 + i);
          if (nk * g > 0.12 + 0.7 * _ih(b.id, i + 90))
            _litSign[b.signs[i].ci % _litSign.length].add(b.signs[i].r.shift(off));
        }
      }
    }
    for (var i = 0; i < 4; i++) {
      if (_litWin[i].isEmpty) continue;
      canvas.drawPath(_rectsPath(_litWin[i]), Paint()..color = _c(_winColors[i], 0.92));
    }
    for (var i = 0; i < _litSign.length; i++) {
      if (_litSign[i].isEmpty) continue;
      final path = _rectsPath(_litSign[i]);
      canvas.drawPath(
        path,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = _c(_neon[i], 0.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.4 * u),
      );
      canvas.drawPath(path, Paint()..color = _c(_mixc(_neon[i], [255, 255, 255], 0.35), 0.92));
    }
    final vis = (0.25 + 0.75 * _sm(0.25, 0.7, _tod)) * (1 - _p.fault * 0.5);
    for (final b in _far) {
      if (!b.beacon) continue;
      final on = ((_time * 1.0 + b.ph * 3) % 1) < 0.34;
      if (!on) continue;
      final top = b.body.last.shift(Offset(b.x, hy));
      final c = Offset(top.center.dx, top.top - 9 * u);
      _glow(canvas, c, 10 * u, const [255, 30, 30], 0.8 * vis);
      canvas.drawRect(
        Rect.fromCenter(center: c, width: 2 * u, height: 2 * u),
        Paint()..color = _c(const [255, 90, 90], vis),
      );
    }
  }

  Path _rectsPath(List<Rect> rects) {
    final p = Path();
    for (final r in rects) {
      p.addRect(r);
    }

    return p;
  }

  /// The far shore mirrored in the water: silhouettes, lit windows and signs
  /// under the buildings that really stand there. Windows sway on the
  /// ripples, stretch vertically, and fade away from the waterline. The
  /// moon and the sun glitter stay in the shader.
  void _paintReflection(Canvas canvas) {
    final hy = _hy, u = _u, h = _size.height;
    final reach = 0.15 * h;
    final xq = _vpx + 1.8 * _k * ((h - hy) / (6 * _k));
    canvas.save();
    canvas.clipPath(
      Path()
        ..moveTo(_vpx, hy)
        ..lineTo(_size.width, hy)
        ..lineTo(_size.width, h)
        ..lineTo(xq, h)
        ..close(),
    );
    Paint fade(Color c, double a, {bool plus = false}) => Paint()
      ..blendMode = plus ? BlendMode.plus : BlendMode.srcOver
      ..shader = ui.Gradient.linear(Offset(0, hy), Offset(0, hy + reach), [
        c.withValues(alpha: c.a * a),
        c.withValues(alpha: 0),
      ]);
    final sil = Path();
    for (final b in _far) {
      if (b.x + b.w < _vpx) continue;
      for (final rr in b.body) {
        final a = rr.shift(Offset(b.x, hy));
        // slices, each swaying a little on the ripples
        final n = math.max(1, (a.height / (4 * u)).ceil());
        for (var i = 0; i < n; i++) {
          final y0 = hy + (hy - a.bottom + a.height * i / n) * 1.05;
          final y1 = hy + (hy - a.bottom + a.height * (i + 1) / n) * 1.05 + 0.5;
          final dx = math.sin(y0 / u * 0.55 + _time * 1.2 + a.left * 0.05) * 0.9 * u;
          sil.addRect(Rect.fromLTRB(a.left + dx, y0, a.right + dx, y1));
        }
      }
      if (b.type == 3) {
        sil.addRect(Rect.fromLTRB(b.x, hy + b.wall, b.x + b.w, hy + b.h * 1.05));
      }
    }
    canvas.drawPath(
      sil,
      fade(_c(_mixc(_p3([70, 80, 100], [60, 30, 80], [10, 6, 30], _tod), const [10, 6, 30], 0.3)), 0.36),
    );
    final dayLit = _sm(0.0, 0.3, _tod);
    Path mirror(List<Rect> rects, double sway) {
      final p = Path();
      for (final r in rects) {
        if (r.right < _vpx) continue;
        final top = hy + (hy - r.bottom) * 1.0, bot = hy + (hy - r.top) * 1.45;
        final dx = math.sin((top + bot) * 0.5 / u * 0.55 + _time * 1.7 + r.left * 0.06) * 1.3 * u * (0.4 + 0.6 * sway);
        final inset = r.width * 0.18;
        p.addRect(Rect.fromLTRB(r.left + dx + inset, top, r.right + dx - inset, bot));
      }

      return p;
    }

    final lampK = (0.12 + 0.88 * _p.alive) * (1 - 0.5 * _p.fault);
    for (var i = 0; i < 4; i++) {
      if (_litWin[i].isEmpty) continue;
      canvas.drawPath(mirror(_litWin[i], 1), fade(_c(_winColors[i]), 0.30 * dayLit * (0.4 + 0.6 * lampK), plus: true));
    }
    for (var i = 0; i < _litSign.length; i++) {
      if (_litSign[i].isEmpty) continue;
      canvas.drawPath(mirror(_litSign[i], 1), fade(_c(_neon[i]), 0.42, plus: true));
    }
    canvas.restore();
  }
}

// ------------------------------------------------------------ street facades
/// A window of a street facade, in street coordinates: depth range sa..sb
/// (metres from the camera), height z0..z1, in the wall plane x.
class _FWin {
  final double sa, sb, z0, z1, x;
  final int k; // 0 plain, 1 ribbon segment, 2 balcony door
  final int row, col;
  const _FWin(this.sa, this.sb, this.z0, this.z1, this.x, this.k, this.row, this.col);
}

/// Things on a facade. kind: 0 wall air conditioner, 1 balcony rail,
/// 2 outdoor stair, 3 sign board (vertical word), 4 band under ribbon windows,
/// 5 roof water tank, 6 roof antenna, 7 roof box, 8 roof billboard.
class _FBox {
  final double sa, sb, z0, z1, x;
  final int kind, ci;
  final String text;
  const _FBox(this.sa, this.sb, this.z0, this.z1, this.x, this.kind, this.ci, [this.text = '']);
}

class _Fac {
  final double s0, s1;
  final int idx, kind; // 0 zakkyo, 1 office, 2 low tiled house, 3 apartments
  final bool dk, shop;
  final double pos, col;
  final List<double> awn;
  final String word;
  final List<double> wordNeon, board;

  /// Height of the walls, where the set-back starts (zLow == zTop: none),
  /// and the extra height of a tiled roof.
  final double zTop, zLow, roof;
  final double setX;
  final List<_FWin> wins = [];
  final List<_FBox> boxes = [];
  _Fac(
    this.s0,
    this.s1,
    this.zTop,
    this.zLow,
    this.roof,
    this.setX,
    this.idx,
    this.kind,
    this.dk,
    this.shop,
    this.pos,
    this.col,
    this.awn,
    this.word,
    this.wordNeon,
    this.board,
  );

  double get z => zTop + roof;
}

extension _FacGen on CityWorld {
  void _buildFac(math.Random r) {
    _fac.clear();
    var s = 1.55;
    var idx = 0;
    var prev = -1;
    const words = citySignHorizontal;
    while (s < 34) {
      final ls = math.max(2.2, s * (0.3 + r.nextDouble() * 0.3));
      var kind = 0;
      for (var t = 0; t < 4; t++) {
        final p = r.nextDouble();
        kind = p < 0.36 ? 0 : (p < 0.6 ? 1 : (p < 0.76 ? 2 : 3));
        if (kind != prev || kind == 2) break;
      }
      // The first lots are fixed so that every kind is always on the street;
      // a low tiled-roof house comes again further on.
      if (idx < 4) kind = const [3, 0, 1, 2][idx];
      if (idx == 7) kind = 2;
      prev = kind;
      final zTop = switch (kind) {
        0 => 26 + r.nextDouble() * 34,
        1 => 32 + r.nextDouble() * 30,
        2 => 7.4,
        _ => 24 + r.nextDouble() * 22,
      };
      final stepped = (kind == 1 || kind == 3) && zTop > 34 && r.nextDouble() < 0.6;
      final zLow = stepped ? 3.4 * (zTop * (0.55 + 0.2 * r.nextDouble()) / 3.4).floorToDouble() : zTop;
      final f = _Fac(
        s,
        s + ls,
        zTop,
        zLow,
        kind == 2 ? 2.4 : 0,
        stepped ? -1.5 : 0,
        idx,
        kind,
        r.nextDouble() < 0.4,
        kind != 1 && r.nextDouble() < 0.92,
        0.05 + 0.6 * math.min(1, s / 26),
        r.nextDouble(),
        _paint[r.nextInt(_paint.length)],
        words[r.nextInt(words.length)],
        _neon[r.nextInt(_neon.length)],
        _paint[r.nextInt(_paint.length)],
      );
      _genFac(f, r);
      _fac.add(f);
      s += ls;
      idx++;
    }
  }

  void _genFac(_Fac f, math.Random r) {
    const xf = -6.6;
    final l = f.s1 - f.s0;
    final signRight = r.nextBool();
    final far = f.s0 > 12;
    switch (f.kind) {
      case 0: // zakkyo: a column of signs, one window and an air conditioner per floor
        var fl = 0;
        for (var z0 = 5.4; z0 + 3.3 <= f.zTop; z0 += 3.3, fl++) {
          final x = z0 > f.zLow ? xf + f.setX : xf;
          final wa = signRight ? f.s0 + l * 0.1 : f.s0 + l * 0.42, wb = signRight ? f.s0 + l * 0.5 : f.s0 + l * 0.9;
          f.wins.add(_FWin(wa, wb, z0 + 0.8, z0 + 2.6, x, 0, fl, 0));
          if (r.nextDouble() < 0.3)
            f.boxes.add(
              _FBox(wa + (wb - wa) * 0.1, wa + (wb - wa) * 0.1 + math.min(0.8, l * 0.28), z0 + 0.3, z0 + 0.8, x, 0, 0),
            );
          if (r.nextDouble() < 0.82) {
            final sa = signRight ? f.s0 + l * 0.58 : f.s0 + l * 0.08,
                sb = signRight ? f.s0 + l * 0.92 : f.s0 + l * 0.34;
            f.boxes.add(
              _FBox(
                sa,
                sb,
                z0 + 0.3,
                z0 + 3.0,
                x,
                3,
                r.nextInt(_neon.length),
                citySignVertical[(f.idx * 5 + fl * 3) % citySignVertical.length],
              ),
            );
          }
        }
        if (r.nextDouble() < 0.4) f.boxes.add(_FBox(f.s1 - l * 0.12, f.s1, 4.4, f.zTop, xf, 2, 0));
      case 1: // ribbon-window office
        var fl = 0;
        for (var z0 = 5.0; z0 + 3.6 <= f.zTop; z0 += 3.6, fl++) {
          final x = z0 > f.zLow ? xf + f.setX : xf;
          final segs = math.max(2, (l / 1.5).round()), sw = l / segs;
          final inset = z0 > f.zLow ? l * 0.04 : l * 0.02;
          for (var c = 0; c < segs; c++) {
            f.wins.add(
              _FWin(
                f.s0 + c * sw + (c == 0 ? inset : 0.04),
                f.s0 + (c + 1) * sw - (c == segs - 1 ? inset : 0.04),
                z0 + 1.0,
                z0 + 2.5,
                x,
                1,
                fl,
                c,
              ),
            );
          }
          f.boxes.add(_FBox(f.s0, f.s1, z0, z0 + 1.0, x, 4, 0));
        }
        if (r.nextDouble() < 0.5) {
          final x = xf + (f.zLow < f.zTop ? f.setX : 0);
          f.boxes.add(
            _FBox(
              f.s1 - l * 0.22,
              f.s1 - l * 0.04,
              5.2,
              5.2 + 3.0 * math.min(6, ((f.zTop - 6) / 3.6).floor()),
              x,
              3,
              r.nextInt(_neon.length),
              citySignVertical[f.idx % citySignVertical.length],
            ),
          );
        }
      case 2: // low house with a tiled roof: a window with a lattice and a sign above the shop
        f.wins.add(_FWin(f.s0 + l * 0.15, f.s0 + l * 0.5, 4.7, 6.3, xf, 0, 0, 0));
        f.wins.add(_FWin(f.s0 + l * 0.6, f.s0 + l * 0.85, 4.7, 6.3, xf, 0, 0, 1));
      default: // apartments: balconies with rails, sliding doors, air conditioners
        var fl = 0;
        for (var z0 = 5.0; z0 + 3.3 <= f.zTop; z0 += 3.3, fl++) {
          final x = z0 > f.zLow ? xf + f.setX : xf;
          f.boxes.add(_FBox(f.s0 + l * 0.04, f.s1 - l * 0.04, z0, z0 + 1.05, x, 1, 0));
          f.wins.add(_FWin(f.s0 + l * 0.1, f.s0 + l * 0.55, z0 + 0.15, z0 + 2.5, x, 2, fl, 0));
          f.wins.add(_FWin(f.s0 + l * 0.64, f.s0 + l * 0.9, z0 + 1.2, z0 + 2.4, x, 0, fl, 1));
          if (r.nextDouble() < 0.4)
            f.boxes.add(_FBox(f.s0 + l * 0.6, f.s0 + l * 0.6 + math.min(0.9, l * 0.25), z0 + 0.1, z0 + 0.75, x, 0, 0));
        }
        if (r.nextDouble() < 0.4) f.boxes.add(_FBox(f.s1 - l * 0.1, f.s1, 4.4, f.zTop, xf, 2, 0));
    }
    // roof equipment (visible only on the far, lower-seen buildings)
    if (f.kind != 2 && (far || r.nextDouble() < 0.5)) {
      final x = xf + (f.zLow < f.zTop ? f.setX : 0);
      final p = r.nextDouble();
      if (p < 0.35) {
        f.boxes.add(_FBox(f.s0 + l * 0.15, f.s0 + l * 0.15 + math.min(2.2, l * 0.4), f.zTop, f.zTop + 3.2, x, 5, 0));
      } else if (p < 0.65) {
        f.boxes.add(_FBox(f.s0 + l * 0.1, f.s1 - l * 0.1, f.zTop + 0.8, f.zTop + 4.8, x, 8, r.nextInt(_neon.length)));
      } else {
        f.boxes.add(_FBox(f.s0 + l * 0.5, f.s0 + l * 0.5 + 0.35, f.zTop, f.zTop + 7, x, 6, 0));
        f.boxes.add(_FBox(f.s0 + l * 0.1, f.s0 + l * 0.4, f.zTop, f.zTop + 1.8, x, 7, 0));
      }
    }
  }

  List<Offset> _qsz(double x, double sa, double sb, double z0, double z1) => [
    _pt(x, z1, sa),
    _pt(x, z1, sb),
    _pt(x, z0, sb),
    _pt(x, z0, sa),
  ];

  List<double> _wallColor(_Fac f) {
    final a = switch (f.idx % 4) {
      0 => _p3([212, 188, 156], [124, 62, 112], [24, 14, 52], _tod),
      1 => _p3([168, 178, 196], [96, 60, 124], [20, 14, 56], _tod),
      2 => _p3([188, 112, 96], [120, 48, 94], [26, 12, 46], _tod),
      _ => _p3([136, 160, 148], [88, 66, 116], [18, 16, 52], _tod),
    };

    return f.kind == 1
        ? _mixc(a, _p3([160, 196, 214], [96, 70, 140], [18, 22, 64], _tod), 0.45)
        : _mixc(a, [a[0] * 0.8, a[1] * 0.8, a[2] * 0.8], f.col);
  }

  void _paintNearStatic(Canvas canvas) {
    const xf = -6.6;
    final hz = _hz;
    final list = _fac.toList()..sort((a, b) => a.s0.compareTo(b.s0));
    final metal = _c(_p3([70, 66, 82], [44, 26, 62], [12, 8, 30], _tod));
    final tile = _p3([84, 92, 112], [70, 42, 88], [22, 16, 44], _tod);
    // far to near, so that the near facades cover the far ones
    for (var i = list.length - 1; i >= 0; i--) {
      final f = list[i];
      if (_pt(xf, 0, f.s0).dx < -0.4 * _size.width && _pt(xf, 0, f.s1).dx < -0.4 * _size.width) continue;
      final wall = _wallColor(f);
      final haze = math.min(0.34, 0.04 + 0.55 * math.exp(-3.6 / math.max(f.s0, 0.1)));
      final col = _mixc(wall, hz, haze);
      final wallC = _c(col);
      final shade = _c(_mixc(col, const [20, 10, 40], 0.35));
      final pxm = _k / ((f.s0 + f.s1) / 2);
      // side face of a building that rises above its nearer neighbour
      if (i > 0 && list[i - 1].z < f.z) {
        final nb = list[i - 1];
        final zLo = nb.z, depth = 8.0;
        _quad(canvas, [
          _pt(xf, f.z, f.s0),
          _pt(xf - depth, f.z, f.s0),
          _pt(xf - depth, zLo, f.s0),
          _pt(xf, zLo, f.s0),
        ], shade);
        if (pxm > 1.6) {
          final wp = Paint()..color = _c(_mixc(col, const [10, 8, 30], 0.55));
          for (var z = zLo + 2.0; z + 1.4 < f.z - 1; z += 3.4) {
            for (var xx = xf - 1.4; xx > xf - depth + 0.6; xx -= 2.2) {
              final q = [
                _pt(xx, z + 1.2, f.s0),
                _pt(xx - 0.9, z + 1.2, f.s0),
                _pt(xx - 0.9, z, f.s0),
                _pt(xx, z, f.s0),
              ];
              canvas.drawPath(Path()..addPolygon(q, true), wp);
            }
          }
        }
      }
      // wall
      final zl = f.zLow;
      _quad(canvas, _qsz(xf, f.s0, f.s1, 0, zl), wallC);
      if (zl < f.zTop) {
        _quad(canvas, _qsz(xf + f.setX, f.s0, f.s1, zl, f.zTop), _c(_mixc(col, hz, 0.1)));
        // the underside of the ledge where the upper floors step back
        _quad(canvas, [
          _pt(xf, zl, f.s0),
          _pt(xf, zl, f.s1),
          _pt(xf + f.setX, zl, f.s1),
          _pt(xf + f.setX, zl, f.s0),
        ], shade);
      }
      if (f.kind == 2) {
        // tiled roof: a sloping plane rising away from the street, rows of tiles, an eave
        final z0 = f.zTop, z1 = f.zTop + f.roof;
        _quad(canvas, [
          _pt(xf, z0, f.s0),
          _pt(xf, z0, f.s1),
          _pt(xf - 3, z1, f.s1),
          _pt(xf - 3, z1, f.s0),
        ], _c(_mixc(tile, hz, haze)));
        if (pxm > 2.4) {
          final line = Paint()
            ..color = _c(_mixc(tile, const [10, 8, 28], 0.5), 0.7)
            ..strokeWidth = math.max(0.7, 0.045 * pxm);
          for (var t = 1; t < 5; t++) {
            final x = xf - 3 * t / 5, z = _mix(z0, z1, t / 5);
            canvas.drawLine(_pt(x, z, f.s0), _pt(x, z, f.s1), line);
          }
        }
        _quad(canvas, _qsz(xf + 0.3, f.s0 - 0.1, f.s1 + 0.1, z0 - 0.25, z0 + 0.1), shade);
      }
      if (_dayK > 0.05) {
        _quad(canvas, [
          _pt(xf, f.zTop, f.s0),
          _pt(xf, f.zTop, _mix(f.s0, f.s1, 0.07)),
          _pt(xf, 0, _mix(f.s0, f.s1, 0.07)),
          _pt(xf, 0, f.s0),
        ], _c([255, 220, 170], 0.28 * _dayK));
      }
      // floor lines
      if (f.kind != 2 && pxm > 2) {
        final fl = Paint()
          ..color = _c(const [20, 12, 44], 0.16)
          ..strokeWidth = math.max(0.6, 0.03 * pxm);
        for (var z = 5.0; z < f.zTop; z += f.kind == 1 ? 3.6 : 3.3) {
          final x = z > zl ? xf + f.setX : xf;
          canvas.drawLine(_pt(x, z, f.s0), _pt(x, z, f.s1), fl);
        }
      }
      if (pxm < 1.0 && f.s0 > 14) continue;
      // windows: opaque glass tinted from the wall, a sill under each
      final glassNight = _mixc(const [40, 56, 84], const [16, 14, 44], _night);
      final glass = _c(_mixc(_mixc(const [128, 176, 190], glassNight, _tod), col, 0.18));
      final sill = _c(_mixc(col, const [255, 255, 255], 0.35));
      final blind = _c(_mixc([236, 228, 206], col, 0.25 + 0.5 * _night));
      for (final w in f.wins) {
        // some windows have blinds or curtains drawn, so the wall is not one even grid
        final t = _ih(f.idx * 17 + w.col, w.row + 9);
        _quad(canvas, _qsz(w.x, w.sa, w.sb, w.z0, w.z1), t < 0.16 && w.k != 1 ? blind : glass);
        if (pxm > 3) {
          if (w.k != 1) _quad(canvas, _qsz(w.x, w.sa - 0.05, w.sb + 0.05, w.z0 - 0.12, w.z0), sill);
          if (w.k == 0) {
            _quad(canvas, _qsz(w.x, (w.sa + w.sb) / 2 - 0.02, (w.sa + w.sb) / 2 + 0.02, w.z0, w.z1), sill);
          }
        }
      }
      for (final b in f.boxes) {
        _paintFBoxStatic(canvas, f, b, col, metal, pxm);
      }
      if (f.shop) _paintShopStatic(canvas, f, xf);
    }
  }

  void _paintFBoxStatic(Canvas canvas, _Fac f, _FBox b, List<double> col, Color metal, double pxm) {
    final q = _qsz(b.x, b.sa, b.sb, b.z0, b.z1);
    switch (b.kind) {
      case 0: // wall air conditioner
        _quad(canvas, q, _c(_p3([226, 224, 230], [160, 120, 160], [64, 54, 96], _tod)));
        if (pxm > 4)
          _quad(
            canvas,
            _qsz(
              b.x,
              b.sa + (b.sb - b.sa) * 0.12,
              b.sb - (b.sb - b.sa) * 0.12,
              b.z0 + 0.12,
              b.z0 + (b.z1 - b.z0) * 0.55,
            ),
            _c(const [40, 36, 56], 0.5),
          );
      case 1: // balcony: a band, a top bar, bars
        _quad(canvas, q, _c(_mixc(col, const [255, 255, 255], 0.28), 0.9));
        _quad(canvas, _qsz(b.x, b.sa, b.sb, b.z1 - 0.07, b.z1), metal);
        if (pxm > 5) {
          final n = math.min(10, ((b.sb - b.sa) / 0.22).floor());
          final bar = Paint()
            ..color = metal
            ..strokeWidth = math.max(0.6, 0.025 * pxm);
          for (var i = 1; i < n; i++) {
            final s = _mix(b.sa, b.sb, i / n);
            canvas.drawLine(_pt(b.x, b.z0 + 0.1, s), _pt(b.x, b.z1, s), bar);
          }
        }
      case 2: // outdoor stair
        _quad(canvas, q, _c(_mixc(col, const [10, 8, 30], 0.35), 0.8));
        final zig = Paint()
          ..color = metal
          ..strokeWidth = math.max(0.7, 0.05 * pxm);
        for (var z = b.z0; z + 3.3 <= b.z1 + 0.01; z += 3.3) {
          canvas.drawLine(_pt(b.x, z, b.sa), _pt(b.x, z + 3.3, b.sb), zig);
          canvas.drawLine(_pt(b.x, z + 1.65, b.sa), _pt(b.x, z + 3.3, b.sb), zig);
        }
      case 3: // sign board (the letters are drawn per frame)
        final pc = _paint[(f.idx + b.ci) % _paint.length];
        _quad(canvas, q, _c(_mixc(pc, const [12, 8, 30], _neonK * 0.85)));
        if (pxm > 3) {
          final rim = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(0.6, 0.03 * pxm)
            ..color = _c(_mixc(const [240, 232, 214], _neon[b.ci], _neonK), 0.9);
          canvas.drawPath(Path()..addPolygon(q, true), rim);
        }
      case 4: // spandrel band under a ribbon window
        _quad(canvas, q, _c(_mixc(col, const [10, 8, 30], 0.22)));
      case 5: // roof water tank
        _quad(canvas, q, metal);
        _quad(canvas, [_pt(b.x, b.z1 + 0.8, (b.sa + b.sb) / 2), _pt(b.x, b.z1, b.sb), _pt(b.x, b.z1, b.sa)], metal);
      case 6: // antenna
        _quad(canvas, q, metal);
        for (final t in const [0.55, 0.8]) {
          final z = _mix(b.z0, b.z1, t);
          _quad(canvas, _qsz(b.x, b.sa - 0.5, b.sb + 0.5, z, z + 0.12), metal);
        }
      case 7:
        _quad(canvas, q, metal);
      default: // roof billboard: board in the paint colour, legs
        _quad(canvas, _qsz(b.x, b.sa, b.sb, b.z0 - 0.8, b.z0), metal);
        _quad(canvas, q, _c(_mixc(_paint[(f.idx * 3 + b.ci) % _paint.length], const [12, 8, 30], _neonK * 0.85)));
        if (pxm > 2) {
          canvas.drawPath(
            Path()..addPolygon(q, true),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(0.7, 0.05 * pxm)
              ..color = metal,
          );
        }
    }
  }

  void _paintShopStatic(Canvas canvas, _Fac f, double xf) {
    final s0 = f.s0 + (f.s1 - f.s0) * 0.06, s1 = f.s1 - (f.s1 - f.s0) * 0.06, dm = 2 / (f.s0 + f.s1);
    if (_k * dm * 1.2 < 0.7 * _u) return;
    final glass = _mixc([34, 84, 92], [255, 196, 120], _sm(0.2, 0.9, _tod) * 0.35);
    _quad(canvas, [_pt(xf, 2.7, s0), _pt(xf, 2.7, s1), _pt(xf, 0.4, s1), _pt(xf, 0.4, s0)], _c(glass, 0.96));
    if (_dayK > 0.05) {
      _quad(canvas, [
        _pt(xf, 2.7, s0),
        _pt(xf, 2.7, _mix(s0, s1, 0.35)),
        _pt(xf, 0.4, _mix(s0, s1, 0.2)),
        _pt(xf, 0.4, s0),
      ], _c([255, 244, 214], 0.22 * _dayK));
    }
    final xo = xf + 1.15;
    final awnDim = 1 - 0.65 * _night;
    for (var i = 0; i < 7; i++) {
      final a = _mix(s0, s1, i / 7), b = _mix(s0, s1, (i + 1) / 7);
      final c = i.isOdd ? const [236.0, 230.0, 214.0] : f.awn;
      _quad(canvas, [
        _pt(xf, 3.5, a),
        _pt(xf, 3.5, b),
        _pt(xo, 2.75, b),
        _pt(xo, 2.75, a),
      ], _c([c[0] * awnDim, c[1] * awnDim, c[2] * awnDim * (1 + 0.15 * _night)]));
    }
    // painted board above the awning (neon at night is drawn on top)
    _quad(canvas, [
      _pt(xf, 5.0, s0),
      _pt(xf, 5.0, s1),
      _pt(xf, 3.6, s1),
      _pt(xf, 3.6, s0),
    ], _c(_mixc(f.board, [14, 8, 36], _neonK)));
  }

  // ------------------------------------------------------ lit street facades
  void _paintNearLit(Canvas canvas) {
    const xf = -6.6;
    final paths = List.generate(4, (_) => Path());
    final dens2 = _mix(0.02, 0.05, _night);
    final warm = _sm(0.15, 0.7, _tod);
    for (final f in _fac) {
      if (_pt(xf, 0, f.s0).dx < -0.4 * _size.width || f.s0 > 20) continue;
      final lit = _lit(f.dk, f.pos);
      final d = dens2 + 0.60 * lit * warm;
      for (final w in f.wins) {
        final rr = _ih(f.idx * 53 + w.col, w.row + 3), per = 20 + _ih(w.col, w.row + f.idx) * 60;
        if (_ih(f.idx * 29 + w.col * 3 + w.row, (_time / per + rr * 7).floor()) < d + (w.k == 1 ? 0.08 * lit : 0)) {
          paths[(rr * 4).floor() % 4].addPolygon(_qsz(w.x, w.sa + 0.03, w.sb - 0.03, w.z0 + 0.06, w.z1 - 0.06), true);
        }
      }
    }
    for (var i = 0; i < 4; i++) {
      canvas.drawPath(paths[i], Paint()..color = _c(_winColors[i], 0.92));
    }
    // Neon of the sign boards and rooftop billboards, with the letters.
    for (final f in _fac) {
      if (_pt(xf, 0, f.s0).dx < -0.3 * _size.width) continue;
      final pxm = _k / ((f.s0 + f.s1) / 2);
      if (pxm < 1.2) continue;
      for (final b in f.boxes) {
        if (b.kind != 3 && b.kind != 8) continue;
        final nk = _neonK * _signGate(f.dk, f.pos, f.idx * 31 + (b.z0 * 3).round());
        final q = _qsz(b.x, b.sa, b.sb, b.z0, b.z1);
        if (b.kind == 8) {
          if (nk > 0.05) {
            canvas.drawPath(
              Path()..addPolygon(q, true),
              Paint()
                ..blendMode = BlendMode.plus
                ..color = _c(_neon[b.ci], 0.75 * nk),
            );
            _glow(
              canvas,
              Offset((q[0].dx + q[2].dx) / 2, (q[0].dy + q[2].dy) / 2),
              math.max(6, (b.sb - b.sa) * pxm * 1.4),
              _neon[b.ci],
              0.35 * nk,
            );
          }
          continue;
        }
        _wallText(canvas, b, q, nk, pxm);
      }
    }
  }

  /// A vertical word on a wall sign: the text is laid out on a flat board and
  /// mapped onto the wall by an affine transform, so that it is foreshortened
  /// like the wall itself.
  void _wallText(Canvas canvas, _FBox b, List<Offset> q, double nk, double pxm) {
    if (pxm * (b.z1 - b.z0) < 14) return;
    final wm = b.sb - b.sa, hm = b.z1 - b.z0;
    const scale = 60.0;
    final w0 = wm * scale * 1.4, h0 = hm * scale;
    final a = q[0], bb = q[1], d = q[3];
    final m = Float64List.fromList([
      (bb.dx - a.dx) / w0, (bb.dy - a.dy) / w0, 0, 0, //
      (d.dx - a.dx) / h0, (d.dy - a.dy) / h0, 0, 0, //
      0, 0, 1, 0, //
      a.dx, a.dy, 0, 1,
    ]);
    final chars = b.text.runes.map(String.fromCharCode).map((c) => c == 'ー' ? '｜' : c).toList();
    final fs = math.min(w0 * 0.78, h0 * 0.92 / math.max(1, chars.length));
    final top = (h0 - fs * chars.length) / 2;
    canvas.save();
    canvas.transform(m);
    for (var i = 0; i < chars.length; i++) {
      final on = nk;
      final off = _c(_mixc([244, 236, 214], _mixc(_neon[b.ci], [10, 6, 24], 0.82), _neonK));
      final tp = _tp(chars[i], fs, off);
      final pos = Offset((w0 - tp.width) / 2, top + i * fs);
      tp.paint(canvas, pos);
      if (on > 0.05) {
        final glow = Paint()
          ..blendMode = BlendMode.plus
          ..color = _c(_neon[b.ci], 0.5 * on)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(1.5, fs * 0.3));
        canvas.drawCircle(Offset(w0 / 2, top + (i + 0.5) * fs), fs * 0.5, glow);
        _tp(chars[i], fs, _c(_mixc(_neon[b.ci], [255, 255, 255], 0.45), 0.55 + 0.45 * on)).paint(canvas, pos);
      }
    }
    canvas.restore();
  }
}
