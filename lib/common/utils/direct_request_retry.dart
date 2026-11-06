import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// One fresh direct attempt after a transient network failure. The caller
/// owns and closes each attempt's client. Never use for a one-time POST.
Future<T> retryDirectRead<T>(
  Future<T> Function() attempt, {
  bool Function(Object error)? retryable,
}) async {
  try {
    return await attempt();
  } on Object catch (error) {
    final transient =
        error is SocketException ||
        error is TimeoutException ||
        error is http.ClientException ||
        error is HandshakeException ||
        (retryable?.call(error) ?? false);
    if (!transient) rethrow;
    return attempt();
  }
}
