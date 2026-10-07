/// Plain CIDR arithmetic for the Russian IP lists (RuListsService): parse,
/// merge overlapping/adjacent networks, subtract, and turn ranges back into
/// the fewest CIDR blocks. IPv4 as int, IPv6 as BigInt.
library;

/// An inclusive address range of one family.
class _Range {
  final BigInt start;
  final BigInt end;

  const _Range(this.start, this.end);
}

class CidrSet {
  final int _bits;
  final List<_Range> _ranges;

  CidrSet._(this._bits, this._ranges);

  /// IPv4 networks from [lines]; anything that isn't a valid v4 CIDR (or a
  /// bare address, taken as /32) is skipped.
  factory CidrSet.v4(Iterable<String> lines) => CidrSet._(32, _merge(_parseAll(lines, 32)));

  /// IPv6 networks from [lines], same rules.
  factory CidrSet.v6(Iterable<String> lines) => CidrSet._(128, _merge(_parseAll(lines, 128)));

  /// This set without the addresses of [other] (same family).
  CidrSet subtract(CidrSet other) {
    assert(other._bits == _bits, 'different address families');
    final result = <_Range>[];
    var j = 0;
    for (final range in _ranges) {
      var start = range.start;
      while (j < other._ranges.length && other._ranges[j].end < start) {
        j++;
      }
      var k = j;
      var fullyRemoved = false;
      while (k < other._ranges.length && other._ranges[k].start <= range.end) {
        final cut = other._ranges[k];
        if (cut.start > start) result.add(_Range(start, cut.start - BigInt.one));
        if (cut.end >= range.end) {
          fullyRemoved = true;
          break;
        }
        start = cut.end + BigInt.one;
        k++;
      }
      if (!fullyRemoved) result.add(_Range(start, range.end));
    }

    return CidrSet._(_bits, result);
  }

  /// The fewest CIDR blocks that cover exactly this set.
  List<String> toCidrs() => [for (final range in _ranges) ..._summarize(range, _bits)];

  static List<_Range> _parseAll(Iterable<String> lines, int bits) {
    final ranges = <_Range>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final range = _parse(line, bits);
      if (range != null) ranges.add(range);
    }

    return ranges;
  }

  static _Range? _parse(String cidr, int bits) {
    final slash = cidr.indexOf('/');
    final address = slash < 0 ? cidr : cidr.substring(0, slash);
    final prefix = slash < 0 ? bits : int.tryParse(cidr.substring(slash + 1));
    if (prefix == null || prefix < 0 || prefix > bits) return null;
    final value = bits == 32 ? _parseV4(address) : _parseV6(address);
    if (value == null) return null;

    final hostBits = bits - prefix;
    final start = (value >> hostBits) << hostBits;

    return _Range(start, start + (BigInt.one << hostBits) - BigInt.one);
  }

  static BigInt? _parseV4(String address) {
    final parts = address.split('.');
    if (parts.length != 4) return null;
    var value = 0;
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255 || part.isEmpty || part.length > 3) return null;
      value = (value << 8) | octet;
    }

    return BigInt.from(value);
  }

  static BigInt? _parseV6(String address) {
    if (!address.contains(':') || address.contains('.')) return null;
    final halves = address.split('::');
    if (halves.length > 2) return null;
    List<String> groups(String s) => s.isEmpty ? <String>[] : s.split(':');
    final head = groups(halves[0]);
    final tail = halves.length == 2 ? groups(halves[1]) : <String>[];
    final missing = 8 - head.length - tail.length;
    if (halves.length == 1 ? missing != 0 : missing < 1) return null;

    var value = BigInt.zero;
    for (final group in [...head, for (var i = 0; i < missing; i++) '0', ...tail]) {
      final word = group.length <= 4 ? int.tryParse(group, radix: 16) : null;
      if (word == null) return null;
      value = (value << 16) | BigInt.from(word);
    }

    return value;
  }

  static List<_Range> _merge(List<_Range> ranges) {
    ranges.sort((a, b) => a.start.compareTo(b.start));
    final merged = <_Range>[];
    for (final range in ranges) {
      if (merged.isNotEmpty && range.start <= merged.last.end + BigInt.one) {
        if (range.end > merged.last.end) merged[merged.length - 1] = _Range(merged.last.start, range.end);
      } else {
        merged.add(range);
      }
    }

    return merged;
  }

  static List<String> _summarize(_Range range, int bits) {
    final result = <String>[];
    var start = range.start;
    while (start <= range.end) {
      // The largest aligned block starting at [start] that fits the range.
      var hostBits = start == BigInt.zero ? bits : _trailingZeros(start, bits);
      while (hostBits > 0 && start + (BigInt.one << hostBits) - BigInt.one > range.end) {
        hostBits--;
      }
      result.add('${_format(start, bits)}/${bits - hostBits}');
      start += BigInt.one << hostBits;
    }

    return result;
  }

  static int _trailingZeros(BigInt value, int bits) {
    var count = 0;
    while (count < bits && (value >> count) & BigInt.one == BigInt.zero) {
      count++;
    }

    return count;
  }

  static String _format(BigInt value, int bits) {
    if (bits == 32) {
      final v = value.toInt();

      return [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255].join('.');
    }
    final groups = [for (var i = 7; i >= 0; i--) ((value >> (16 * i)) & BigInt.from(0xffff)).toInt().toRadixString(16)];

    return groups.join(':');
  }
}

/// A CIDR's prefix length, or null if [cidr] has none.
int? cidrPrefixLength(String cidr) {
  final slash = cidr.indexOf('/');

  return slash < 0 ? null : int.tryParse(cidr.substring(slash + 1));
}

/// [cidrs] (one family, as [CidrSet.toCidrs] gives them) without
/// [addresses]. Only the networks that contain an address are recomputed -
/// a cheap integer check for the rest - so this stays fast on 20k lines.
List<String> cidrsWithout(List<String> cidrs, Iterable<String> addresses) {
  if (cidrs.isEmpty) return cidrs;
  final v6 = cidrs.first.contains(':');
  final cut = v6 ? CidrSet.v6(addresses) : CidrSet.v4(addresses);
  if (cut._ranges.isEmpty) return cidrs;

  final hits = <int>{};
  if (v6) {
    for (var i = 0; i < cidrs.length; i++) {
      final range = CidrSet._parse(cidrs[i], 128);
      if (range != null && cut._ranges.any((r) => r.start <= range.end && r.end >= range.start)) hits.add(i);
    }
  } else {
    final cuts = [for (final r in cut._ranges) (r.start.toInt(), r.end.toInt())];
    for (var i = 0; i < cidrs.length; i++) {
      final range = _v4Range(cidrs[i]);
      if (range != null && cuts.any((c) => c.$1 <= range.$2 && c.$2 >= range.$1)) hits.add(i);
    }
  }
  if (hits.isEmpty) return cidrs;

  final result = <String>[];
  for (var i = 0; i < cidrs.length; i++) {
    if (!hits.contains(i)) {
      result.add(cidrs[i]);
      continue;
    }
    final rest = v6 ? CidrSet.v6([cidrs[i]]) : CidrSet.v4([cidrs[i]]);
    result.addAll(rest.subtract(cut).toCidrs());
  }

  return result;
}

/// An `a.b.c.d/n` network as an inclusive int range, without BigInt.
(int, int)? _v4Range(String cidr) {
  final slash = cidr.indexOf('/');
  final prefix = slash < 0 ? 32 : int.tryParse(cidr.substring(slash + 1));
  if (prefix == null || prefix < 0 || prefix > 32) return null;
  final parts = (slash < 0 ? cidr : cidr.substring(0, slash)).split('.');
  if (parts.length != 4) return null;
  var value = 0;
  for (final part in parts) {
    final octet = int.tryParse(part);
    if (octet == null || octet < 0 || octet > 255) return null;
    value = (value << 8) | octet;
  }
  final size = 1 << (32 - prefix);
  final start = value & ~(size - 1) & 0xffffffff;

  return (start, start + size - 1);
}

/// Whether [address] (a bare IPv4/IPv6 address) is inside one of [cidrs].
bool cidrsContain(List<String> cidrs, String address) {
  if (!address.contains(':')) {
    final target = _v4Range(address);
    if (target == null) return false;

    return cidrs.any((cidr) {
      final range = _v4Range(cidr);

      return range != null && range.$1 <= target.$1 && target.$2 <= range.$2;
    });
  }
  final target = CidrSet._parse(address, 128);
  if (target == null) return false;

  return cidrs.any((cidr) {
    final range = cidr.contains(':') ? CidrSet._parse(cidr, 128) : null;

    return range != null && range.start <= target.start && target.end <= range.end;
  });
}

/// Number of addresses [set] covers (for the plausibility check of
/// downloaded lists).
BigInt cidrSetAddressCount(CidrSet set) =>
    set._ranges.fold(BigInt.zero, (sum, range) => sum + range.end - range.start + BigInt.one);
