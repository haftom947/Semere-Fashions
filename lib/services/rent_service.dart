import 'package:intl/intl.dart';
import 'database_helper.dart';

class RentService {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// Call this on app start (or in a periodic background task) to generate rent dues for the new month.
  Future<void> generateRentDuesIfNeeded() async {
    final now = DateTime.now();
    final currentMonth = DateFormat('yyyy-MM').format(now);

    // Check if we have already generated dues for this month (by looking at rent_dues table)
    final allDues = await _dbHelper.query('rent_dues');
    final hasCurrentMonthDues = allDues.any((due) => due['dueMonth'] == currentMonth);
    if (hasCurrentMonthDues) return;

    // Get all active tenants
    final tenants = await _dbHelper.query('tenants');
    if (tenants.isEmpty) return;

    for (var tenant in tenants) {
      final dueId = DateTime.now().millisecondsSinceEpoch.toString() + tenant['id'];
      final dueDate = DateTime(now.year, now.month, 5); // due on 5th
      await _dbHelper.insert('rent_dues', {
        'id': dueId,
        'tenantId': tenant['id'],
        'tenantName': tenant['name'],
        'propertyId': tenant['propertyId'],
        'amount': tenant['monthlyRent'],
        'dueMonth': currentMonth,
        'dueDate': dueDate.millisecondsSinceEpoch,
        'status': 'pending',
        'createdAt': now.millisecondsSinceEpoch,
      });
    }
  }
}