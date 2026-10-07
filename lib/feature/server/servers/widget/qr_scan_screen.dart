import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/utils/deep_link_uri_normalizer.dart';
import 'package:trusttunnel/common/utils/subscription_share_link.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';
import 'package:trusttunnel/data/repository/deep_link_repository.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';

/// Scans a QR code and pops with what it holds: a [ServerData] for a `tt://`
/// server link, a [SubscriptionData] for a [SubscriptionShareLink], or `null`
/// if the user backs out.
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
    ),
    body: MobileScanner(
      controller: _controller,
      onDetect: _onDetect,
    ),
  );

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) {
      return;
    }

    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) {
      return;
    }

    final subscription = SubscriptionShareLink.tryDecode(raw);
    if (subscription != null) {
      _handling = true;
      await _controller.stop();
      if (mounted) {
        Navigator.of(context).pop(subscription);
      }

      return;
    }

    final normalized = DeepLinkUriNormalizer.normalize(raw);
    if (normalized == null) {
      return;
    }

    _handling = true;
    await _controller.stop();

    try {
      final server = await widget.repository.parseDataFromLink(deepLink: normalized);

      if (mounted) {
        Navigator.of(context).pop(server);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      context.showInfoSnackBar(message: context.ln.importLinkInvalidError);
      _handling = false;
      await _controller.start();
    }
  }
}
