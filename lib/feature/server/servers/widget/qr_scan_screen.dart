import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/utils/qr_import.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';
import 'package:trusttunnel/data/repository/deep_link_repository.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';

/// Scans a QR code and pops with what it holds: a [ServerData] for a `tt://`
/// server link, a [SubscriptionData] for a subscription share link, a
/// [QrImportSubscriptionCode] for a one-time code, or `null` if the user
/// backs out.
class QrScanScreen extends StatefulWidget {
  final DeepLinkRepository repository;

  const QrScanScreen({
    super.key,
    required this.repository,
  });

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController();
  bool _handling = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: CustomAppBar(
      title: context.ln.scanQrCode,
      leadingIconType: AppBarLeadingIconType.back,
      onBackPressed: () => Navigator.of(context).maybePop(),
      actions: [
        IconButton(
          tooltip: context.ln.scanFromGallery,
          icon: const Icon(Icons.photo_library_outlined),
          onPressed: _pickFromGallery,
        ),
      ],
    ),
    body: MobileScanner(
      controller: _controller,
      onDetect: _onDetect,
    ),
  );

  Future<void> _onDetect(BarcodeCapture capture) async {
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) {
      return;
    }

    await _handleRaw(raw);
  }

  /// Handles both a live scan and a QR code found on a picked image.
  ///
  /// Returns `true` when [raw] was a link the app can import.
  Future<bool> _handleRaw(String raw) async {
    if (_handling) {
      return false;
    }

    final parsed = QrImport.tryParse(raw);
    if (parsed == null) {
      return false;
    }

    _handling = true;
    await _controller.stop();

    switch (parsed) {
      case QrImportServerLink(:final link):
        try {
          final server = await widget.repository.parseDataFromLink(deepLink: link);

          if (mounted) {
            Navigator.of(context).pop(server);
          }
        } catch (_) {
          if (!mounted) {
            return true;
          }

          context.showInfoSnackBar(message: context.ln.importLinkInvalidError);
          _handling = false;
          await _controller.start();
        }
      case QrImportSubscriptionLink(:final subscription):
        if (mounted) {
          Navigator.of(context).pop(subscription);
        }
      case QrImportSubscriptionCode():
        if (mounted) {
          Navigator.of(context).pop(parsed);
        }
    }

    return true;
  }

  Future<void> _pickFromGallery() async {
    if (_handling) {
      return;
    }

    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.firstOrNull?.path;
    if (path == null) {
      return;
    }

    BarcodeCapture? capture;
    try {
      capture = await _controller.analyzeImage(path);
    } on Object {
      capture = null;
    }

    if (!mounted) {
      return;
    }

    final raw = capture?.barcodes.firstOrNull?.rawValue;
    if (raw == null) {
      context.showInfoSnackBar(message: context.ln.qrNoCodeInImage);

      return;
    }

    if (!await _handleRaw(raw) && mounted) {
      context.showInfoSnackBar(message: context.ln.importLinkInvalidError);
    }
  }
}
