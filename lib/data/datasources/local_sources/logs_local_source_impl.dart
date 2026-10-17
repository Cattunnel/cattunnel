import 'dart:convert';
import 'dart:io';

import 'package:adguard_logger/adguard_logger.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/common/logging/sanitizer/engine_line_scrubber.dart';
import 'package:trusttunnel/data/datasources/app_state_logging_datasource.dart';
import 'package:trusttunnel/data/datasources/logs_local_source.dart';
import 'package:trusttunnel/feature/settings/logs_manager/model/export_file_type.dart';
import 'package:trusttunnel/feature/settings/logs_manager/model/export_logs_archive.dart';
import 'package:vpn_plugin/models/logs/log_platform_files.dart';
import 'package:vpn_plugin/vpn_plugin.dart';

final class LogsLocalSourceImpl implements LogsLocalSource {
  static const _logTempKey = '_logTempKey';

  /// Archives saved outside the app (Downloads...): the panic button deletes
  /// them too (deleteExportedArchives), app data alone doesn't cover them.
  static const _logExportedKey = '_logExportedKey';

  final FileLogAppender _logAppender;
  final AppStateLoggingDataSource _appStateLoggingDataSource;
  final FilePicker _filePicker;
  final VpnPlugin _vpnPlugin;
  final SharedPreferences _sharedPreferences;

  LogsLocalSourceImpl({
    required FileLogAppender logAppender,
    required AppStateLoggingDataSource appStateLoggingDataSource,
    required FilePicker filePicker,
    required VpnPlugin vpnPlugin,
    required SharedPreferences sharedPreferences,
  }) : _logAppender = logAppender,
       _appStateLoggingDataSource = appStateLoggingDataSource,
       _vpnPlugin = vpnPlugin,
       _sharedPreferences = sharedPreferences,
       _filePicker = filePicker;

  @override
  Future<ExportLogsArchive> createArchive() async {
    final logPaths = await _vpnPlugin.fetchLogsPath();
    final logFiles = <String, Uint8List>{};

    for (final group in LogPlatformFiles.platform(defaultTargetPlatform).value) {
      final regex = RegExp(r'.*' + group + r'(\.\d+)?\.log');
      final selectedPaths = logPaths.where(regex.hasMatch).toList();

      final lines = selectedPaths.isEmpty
          ? <String>[]
          : (await _vpnPlugin.exportLogsFor(selectedPaths)).map((r) => EngineLineScrubber.scrub(r.toString())).toList();

      logFiles['$group.log'] = utf8.encode(lines.join(Platform.lineTerminator));
    }

    final snapshot = await _appStateLoggingDataSource.collectSnapshot();
    logFiles['app_state.log'] = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
    );

    final archivedData = await _logAppender.archiveData(
      additionalFiles: logFiles,
    );

    return ExportLogsArchive(
      data: archivedData,
      name: _generateArchiveName(),
    );
  }

  @override
  Future<String?> pickFilePath({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    ExportFileType type = ExportFileType.any,
    List<String>? allowedExtensions,
    Uint8List? data,
  }) async {
    final path = await _filePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      initialDirectory: initialDirectory,
      type: _mapExportFileType(type),
      allowedExtensions: allowedExtensions,
      bytes: data,
    );
    if (path != null) {
      final exported = _sharedPreferences.getStringList(_logExportedKey) ?? const [];
      await _sharedPreferences.setStringList(_logExportedKey, [...exported, path]);
    }

    return path;
  }

  /// Deletes the archives this app saved outside its own data (best effort:
  /// a file the system no longer lets us touch stays).
  static Future<void> deleteExportedArchives(SharedPreferences prefs) async {
    for (final path in prefs.getStringList(_logExportedKey) ?? const <String>[]) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } on Object {
        // Moved, or no longer ours to delete.
      }
    }
    await prefs.remove(_logExportedKey);
  }

  @override
  Future<String> saveRawFile({
    required Uint8List data,
    required String path,
    bool temporary = true,
  }) async {
    final file = await File(path).create(recursive: true);
    await file.writeAsBytes(data, mode: FileMode.writeOnly, flush: true);
    if (!temporary) {
      return path;
    }

    final tempLogs = _sharedPreferences.getStringList(_logTempKey);
    await _sharedPreferences.setStringList(_logTempKey, [...?tempLogs, path]);

    return path;
  }

  @override
  Future<void> deleteLogs() => Future.wait([
    clearTempFiles(),
    _logAppender.clearAllLogs(),
    _vpnPlugin.clearLogs(),
  ]);

  @override
  Future<void> clearTempFiles() async {
    final tempFiles = _sharedPreferences.getStringList(_logTempKey)?.map((path) => File(path)) ?? [];

    for (final file in tempFiles) {
      if (await file.exists()) {
        await file.delete();
      }
    }

    await _sharedPreferences.remove(_logTempKey);

    if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
      // This method is not available on desktop platforms (only Android and iOS)
      await _filePicker.clearTemporaryFiles();
    }
  }

  String _generateArchiveName() {
    final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:\-]'), '').replaceAll(RegExp(r'\..*'), '');

    return 'trusttunnel_${defaultTargetPlatform.name}_logs_$timestamp.zip';
  }

  FileType _mapExportFileType(ExportFileType type) => switch (type) {
    ExportFileType.any => FileType.any,
    ExportFileType.custom => FileType.custom,
  };
}
