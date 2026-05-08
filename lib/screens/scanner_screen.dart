import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import 'order_details_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasDetected = false;

  Future<void> _handleCode(String code) async {
    final trimmedCode = code.trim();
    if (_hasDetected || trimmedCode.isEmpty) return;

    _hasDetected = true;

    if (trimmedCode.startsWith('http://') || trimmedCode.startsWith('https://')) {
      // URL detected -> Open in browser
      final uri = Uri.parse(trimmedCode.replaceAll(RegExp(r'\s+'), ''));
      var launched = false;
      try {
        launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        launched = false;
      }
      if (!launched && mounted) {
        _hasDetected = false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open tracking link')),
        );
        return;
      }
      if (mounted) Navigator.pop(context);
    } else {
      // Order ID detected -> Open in app
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => OrderDetailsScreen(orderId: trimmedCode),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                final code = barcode.rawValue;
                if (code != null && code.isNotEmpty) {
                  print('Scanned: $code');
                  _handleCode(code);
                  break;
                }
              }
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Point the camera at the order barcode.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
