import 'database_helper.dart';
import 'notification_service.dart';

class LowStockService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final NotificationService _notifService = NotificationService();

  Future<void> checkAndNotify() async {
    final products = await _dbHelper.query('products');
    final materials = await _dbHelper.query('materials');

    final lowStockItems = <String>[];
    for (var p in products) {
      final stock = p['stock'] ?? 0;
      final minLevel = p['minimumLevel'] ?? 5;
      if (stock < minLevel) {
        lowStockItems.add('Product: ${p['name']} (stock: $stock)');
      }
    }
    for (var m in materials) {
      final stock = m['stock'] ?? 0;
      final minLevel = m['minimumLevel'] ?? 5;
      if (stock < minLevel) {
        lowStockItems.add('Material: ${m['name']} (stock: $stock)');
      }
    }

    if (lowStockItems.isNotEmpty) {
      final title = 'Low Stock Alert';
      final body =
          lowStockItems.take(3).join('\n') +
          (lowStockItems.length > 3
              ? '\n+${lowStockItems.length - 3} more'
              : '');
      await _notifService.showNotification(id: 1, title: title, body: body);
    }
  }
}
