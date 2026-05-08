import 'dart:io';
import 'dart:typed_data';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:platform/platform.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class BarcodeService {
  static const String trackingBaseUrl =
      'https://semere-fashions-60efc.web.app/track.html';

  static String trackingUrlForOrder(String orderId) {
    final normalizedOrderId = orderId.trim().replaceAll(RegExp(r'\s+'), '');
    return Uri.parse(trackingBaseUrl)
        .replace(queryParameters: {'id': normalizedOrderId})
        .toString();
  }

  static Future<Uint8List> buildLabelPdf({
    required String orderId,
    String? customerName,
    String? status,
    String? branchName,
    String? createdAtLabel,
  }) async {
    final pdf = pw.Document();
    final normalizedOrderId = orderId.trim().replaceAll(RegExp(r'\s+'), '');
    final trackingUrl = trackingUrlForOrder(orderId);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a6,
        margin: const pw.EdgeInsets.all(18),
        build: (context) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.red700, width: 1.5),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            padding: const pw.EdgeInsets.all(12),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Semere Fashions',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text('Order ID: $normalizedOrderId'),
                if ((customerName ?? '').isNotEmpty)
                  pw.Text('Customer: $customerName'),
                if ((status ?? '').isNotEmpty) pw.Text('Status: $status'),
                if ((branchName ?? '').isNotEmpty) pw.Text('Branch: $branchName'),
                if ((createdAtLabel ?? '').isNotEmpty)
                  pw.Text('Date: $createdAtLabel'),
                pw.SizedBox(height: 12),
                pw.Center(
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: normalizedOrderId,
                    width: 220,
                    height: 60,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.Text(
                    normalizedOrderId,
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Center(
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: trackingUrl,
                    width: 100,
                    height: 100,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.UrlLink(
                    destination: trackingUrl,
                    child: pw.Text(
                      'Open tracking page',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.blue700,
                        decoration: pw.TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text(
                    trackingUrl,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 7),
                    maxLines: 2,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> printLabel({
    required String orderId,
    String? customerName,
    String? status,
    String? branchName,
    String? createdAtLabel,
  }) async {
    final pdfData = await buildLabelPdf(
      orderId: orderId,
      customerName: customerName,
      status: status,
      branchName: branchName,
      createdAtLabel: createdAtLabel,
    );
    await Printing.layoutPdf(onLayout: (_) async => pdfData);
  }

  static Future<void> shareLabel({
    required String orderId,
    String? customerName,
    String? status,
    String? branchName,
    String? createdAtLabel,
  }) async {
    final pdfData = await buildLabelPdf(
      orderId: orderId,
      customerName: customerName,
      status: status,
      branchName: branchName,
      createdAtLabel: createdAtLabel,
    );
    final dir = await getTemporaryDirectory();
    final normalizedOrderId = orderId.trim().replaceAll(RegExp(r'\s+'), '');
    final file = File('${dir.path}/order_$normalizedOrderId.pdf');
    await file.writeAsBytes(pdfData);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Order Label $normalizedOrderId',
    );
  }

  static Future<void> openTrackingUrl(String orderId) async {
    final trackingUrl = trackingUrlForOrder(orderId);
    final isAndroid = LocalPlatform().isAndroid;

    if (isAndroid) {
      try {
        final intent = AndroidIntent(
          action: 'android.intent.action.VIEW',
          data: trackingUrl,
          package: 'com.android.chrome',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
        );
        await intent.launch();
        return;
      } catch (e) {
        // Chrome not available, fall back to default
        await launchUrl(
          Uri.parse(trackingUrl),
          mode: LaunchMode.externalApplication,
        );
      }
    } else {
      // iOS/Web/Others
      await launchUrl(
        Uri.parse(trackingUrl),
        mode: LaunchMode.externalApplication,
      );
    }
  }
}
