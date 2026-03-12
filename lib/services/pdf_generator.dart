import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfGenerator {
  static Future<Uint8List> generateSalesReport(
    List<Map<String, dynamic>> orders,
    double totalRevenue,
    int totalOrders,
    double avgOrderValue,
    List<Map<String, dynamic>> dailyData,
  ) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text('Sales Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 20),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatCard('Total Orders', totalOrders.toString()),
              _buildStatCard('Revenue', 'ETB ${totalRevenue.toStringAsFixed(2)}'),
              _buildStatCard('Avg Order', 'ETB ${avgOrderValue.toStringAsFixed(2)}'),
            ],
          ),
          pw.SizedBox(height: 30),
          pw.Text('Daily Sales (Last 7 days)', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.Table.fromTextArray(
            data: [
              ['Date', 'Amount (ETB)'],
              ...dailyData.map((d) => [d['date'], 'ETB ${d['amount']}']),
            ],
            border: pw.TableBorder.all(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 30),
          pw.Text('Generated on ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<Uint8List> generateProductsReport(
    List<Map<String, dynamic>> products,
    List<Map<String, dynamic>> topProducts,
  ) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text('Products Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 20),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatCard('Total Products', products.length.toString()),
              _buildStatCard('Low Stock', products.where((p) => (p['stock'] ?? 0) < (p['minimumLevel'] ?? 5)).length.toString()),
            ],
          ),
          pw.SizedBox(height: 30),
          pw.Text('Top 5 Products by Quantity Sold', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          if (topProducts.isEmpty)
            pw.Text('No product sales data')
          else
            pw.Table.fromTextArray(
              data: [
                ['Product', 'Quantity Sold', 'Revenue (ETB)'],
                ...topProducts.map((p) => [p['name'], p['quantity'].toString(), 'ETB ${p['revenue'].toStringAsFixed(2)}']),
              ],
              border: pw.TableBorder.all(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          pw.SizedBox(height: 30),
          pw.Text('Generated on ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<Uint8List> generateEmployeesReport(
    int totalEmployees,
    int activeEmployees,
    double totalCommissions,
    double paidCommissions,
    double pendingCommissions,
  ) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text('Employees Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 20),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatCard('Total', totalEmployees.toString()),
              _buildStatCard('Active', activeEmployees.toString()),
            ],
          ),
          pw.SizedBox(height: 30),
          pw.Text('Commission Summary', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.Table.fromTextArray(
            data: [
              ['Type', 'Amount (ETB)'],
              ['Total', 'ETB ${totalCommissions.toStringAsFixed(2)}'],
              ['Paid', 'ETB ${paidCommissions.toStringAsFixed(2)}'],
              ['Pending', 'ETB ${pendingCommissions.toStringAsFixed(2)}'],
            ],
            border: pw.TableBorder.all(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 30),
          pw.Text('Generated on ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildStatCard(String label, String value) {
    return pw.Container(
      width: 150,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          pw.Text(value, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 5),
          pw.Text(label),
        ],
      ),
    );
  }
}