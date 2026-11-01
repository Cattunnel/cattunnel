import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

/// Only hardware vendor/product fields, never hostnames or serial numbers.
abstract final class DeviceModel {
  static const _biosKey = r'HARDWARE\DESCRIPTION\System\BIOS';

  static Future<String> read({
    String? os,
    Future<Map<Object?, Object?>> Function()? android,
    Future<String> Function(String)? file,
    String? Function(String key, String name)? registry,
  }) async {
    try {
      final platform = os ?? Platform.operatingSystem;
      final readFile = file ?? ((path) => File(path).readAsString());
      // The registry is read in-process: running reg.exe from a GUI app can flash a console window.
      final readRegistry = registry ?? _registryValue;
      late List<String> parts;
      if (platform == 'android') {
        final info =
            await (android ??
                (() async =>
                    await const MethodChannel('cattunnel/apps').invokeMapMethod<Object?, Object?>('deviceInfo') ??
                    const {}))();
        parts = [info['manufacturer']?.toString() ?? '', info['model']?.toString() ?? ''];
      } else if (platform == 'linux') {
        parts = [await readFile('/sys/class/dmi/id/sys_vendor'), await readFile('/sys/class/dmi/id/product_name')];
      } else if (platform == 'windows') {
        parts = [];
        for (final name in ['SystemManufacturer', 'SystemProductName']) {
          final value = readRegistry(_biosKey, name);
          if (value == null) return '';
          parts.add(value);
        }
      } else {
        return '';
      }
      // HTTP headers use printable ASCII; controls and non-ASCII cannot leak into them.
      final text = parts.join(' ').replaceAll(RegExp(r'[^\x20-\x7e]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      return text.length > 64 ? text.substring(0, 64) : text;
    } on Object {
      return '';
    }
  }

  /// HKLM string value, or null when it is missing or unreadable.
  static String? _registryValue(String key, String name) {
    final subKey = key.toNativeUtf16();
    final value = name.toNativeUtf16();
    final size = calloc<Uint32>()..value = 512;
    final data = wsalloc(256);
    try {
      final status = RegGetValue(HKEY_LOCAL_MACHINE, subKey, value, RRF_RT_REG_SZ, nullptr, data, size);
      return status == ERROR_SUCCESS ? data.toDartString() : null;
    } finally {
      free(subKey);
      free(value);
      free(size);
      free(data);
    }
  }
}
