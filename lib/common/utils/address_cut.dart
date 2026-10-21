import 'dart:io';

/// Cuts the IP addresses out of a text.
///
/// The problem report leaves the phone in a chat, and the addresses in it
/// are the person's own: the gateway of their network, the address of their
/// phone on it, the address of the server they tried. None of that is the
/// admin's business, so all of it goes.
///
/// Only real addresses are cut. A version ("1.2.3.4" is one, "2026.10.21" is
/// not), a time ("21:29:00") and a MAC address ("aa:bb:cc:dd:ee:ff") stay:
/// the report is useless without them.
abstract final class AddressCut {
  static const replacement = '<address cut>';

  /// Four numbers with dots. Whether it is an address at all is decided
  /// afterwards.
  static final _ipv4 = RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}\b');

  /// Hex groups with colons. The lookbehind keeps it from starting in the
  /// middle of a dotted quad, the lookahead keeps it from matching a number
  /// without a colon.
  static final _ipv6 = RegExp(r'(?<![0-9A-Za-z:.])(?=[0-9A-Fa-f:]*:)[0-9A-Fa-f:]{2,}(?![0-9A-Za-z:])');

  /// The text with every address in it replaced.
  static String cut(String text) => text
      .replaceAllMapped(_ipv4, (m) => _isAddress(m[0]!) ? replacement : m[0]!)
      .replaceAllMapped(_ipv6, (m) => _isAddress(m[0]!) ? replacement : m[0]!);

  /// Whether the candidate really is an address the system would accept.
  static bool _isAddress(String candidate) => InternetAddress.tryParse(candidate) != null;
}
