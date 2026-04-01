import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

class ExcelGenerator {
  static Uint8List generateSalesReport(
    List<Map<String, dynamic>> orders,
    double totalRevenue,
    int totalOrders,
    double avgOrderValue,
    List<Map<String, dynamic>> dailyData,
  ) {
    final excel = Excel.createExcel();
    final sheet = excel['Sales Report'];

    // Headers
    sheet.appendRow([
      TextCellValue('Date'),
      TextCellValue('Order ID'),
      TextCellValue('Customer'),
      TextCellValue('Amount'),
      TextCellValue('Status'),
    ]);

    // Data rows
    for (var order in orders) {
      final date = DateTime.fromMillisecondsSinceEpoch(order['createdAt']);
      final dateStr = DateFormat('dd/MM/yyyy').format(date);
      sheet.appendRow([
        TextCellValue(dateStr),
        TextCellValue(order['id']),
        TextCellValue(order['customerName'] ?? ''),
        DoubleCellValue(order['totalAmount']?.toDouble() ?? 0),
        TextCellValue(order['status'] ?? ''),
      ]);
    }

    // Summary
    sheet.appendRow([]); // empty row
    sheet.appendRow([TextCellValue('Summary')]);
    sheet.appendRow([TextCellValue('Total Orders'), IntCellValue(totalOrders)]);
    sheet.appendRow([
      TextCellValue('Total Revenue'),
      DoubleCellValue(totalRevenue),
    ]);
    sheet.appendRow([
      TextCellValue('Avg Order Value'),
      DoubleCellValue(avgOrderValue),
    ]);

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to generate Excel');
    return Uint8List.fromList(bytes);
  }

  static Uint8List generateProductsReport(
    List<Map<String, dynamic>> products,
    List<Map<String, dynamic>> topProducts,
  ) {
    final excel = Excel.createExcel();
    final sheet = excel['Products Report'];

    sheet.appendRow([
      TextCellValue('Name'),
      TextCellValue('Category'),
      TextCellValue('Stock'),
      TextCellValue('Min Level'),
      TextCellValue('Cost Price'),
      TextCellValue('Selling Price'),
    ]);

    for (var p in products) {
      sheet.appendRow([
        TextCellValue(p['name'] ?? ''),
        TextCellValue(p['category'] ?? ''),
        IntCellValue(p['stock'] ?? 0),
        IntCellValue(p['minimumLevel'] ?? 0),
        DoubleCellValue(p['costPrice']?.toDouble() ?? 0),
        DoubleCellValue(p['sellingPrice']?.toDouble() ?? 0),
      ]);
    }

    if (topProducts.isNotEmpty) {
      sheet.appendRow([]);
      sheet.appendRow([TextCellValue('Top 5 Products by Quantity Sold')]);
      sheet.appendRow([
        TextCellValue('Product'),
        TextCellValue('Quantity'),
        TextCellValue('Revenue'),
      ]);
      for (var tp in topProducts) {
        sheet.appendRow([
          TextCellValue(tp['name'] ?? ''),
          IntCellValue(tp['quantity'] ?? 0),
          DoubleCellValue(tp['revenue']?.toDouble() ?? 0),
        ]);
      }
    }

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to generate Excel');
    return Uint8List.fromList(bytes);
  }

  static Uint8List generateEmployeesReport(
    int totalEmployees,
    int activeEmployees,
    double totalCommissions,
    double paidCommissions,
    double pendingCommissions,
  ) {
    final excel = Excel.createExcel();
    final sheet = excel['Employees Report'];

    sheet.appendRow([
      TextCellValue('Total Employees'),
      TextCellValue('Active Employees'),
    ]);
    sheet.appendRow([
      IntCellValue(totalEmployees),
      IntCellValue(activeEmployees),
    ]);

    sheet.appendRow([]);
    sheet.appendRow([TextCellValue('Commission Summary')]);
    sheet.appendRow([
      TextCellValue('Total'),
      TextCellValue('Paid'),
      TextCellValue('Pending'),
    ]);
    sheet.appendRow([
      DoubleCellValue(totalCommissions),
      DoubleCellValue(paidCommissions),
      DoubleCellValue(pendingCommissions),
    ]);

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to generate Excel');
    return Uint8List.fromList(bytes);
  }
}
