import 'package:intl/intl.dart';
import 'database_helper.dart';

class RentService {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// Call this on app start (or in a periodic background task) to generate rent dues for the new month.
  Future<void> generateRentDuesIfNeeded() async {
    final now = DateTime.now();
    final currentMonth = DateFormat('yyyy-MM').format(now);
    final properties = await _dbHelper.query('properties');
    final propertyById = <String, Map<String, dynamic>>{};
    for (final property in properties) {
      final propertyId = property['id']?.toString();
      if (propertyId == null || propertyId.isEmpty) continue;
      propertyById[propertyId] = Map<String, dynamic>.from(property);
    }

    // Check if we have already generated dues for this month (by looking at rent_dues table)
    final allDues = await _dbHelper.query('rent_dues');
    final hasCurrentMonthDues = allDues.any(
      (due) => due['dueMonth'] == currentMonth,
    );
    if (!hasCurrentMonthDues) {
      final tenants = await _dbHelper.query('tenants');
      for (var tenant in tenants) {
        final property = propertyById[tenant['propertyId']?.toString()];
        final usageType =
            property?['usageType']?.toString() ??
            (property?['ownership'] == 'leased'
                ? 'business_use'
                : 'rented_out');
        if (usageType != 'rented_out') continue;

        final dueId =
            DateTime.now().millisecondsSinceEpoch.toString() + tenant['id'];
        final dueDate = DateTime(now.year, now.month, 5);
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

    final allLandlordDues = await _dbHelper.query('landlord_dues');
    final hasCurrentMonthLandlordDues = allLandlordDues.any(
      (due) => due['dueMonth'] == currentMonth,
    );
    if (hasCurrentMonthLandlordDues) return;

    for (final property in properties) {
      final rentalExpenseType =
          property['rentalExpenseType']?.toString() ?? 'lease';
      final landlordName = property['landlordName']?.toString().trim() ?? '';
      final monthlyRent =
          (property['monthlyRent'] as num?)?.toDouble() ?? 0.0;
      final mortgageMonthly =
          (property['mortgageMonthly'] as num?)?.toDouble() ?? 0.0;
      final amount = rentalExpenseType == 'mortgage'
          ? mortgageMonthly
          : monthlyRent;

      if (amount <= 0) continue;
      if (rentalExpenseType != 'mortgage' && landlordName.isEmpty) continue;

      final propertyId = property['id']?.toString();
      if (propertyId == null || propertyId.isEmpty) continue;

      final dueDate = DateTime(now.year, now.month, 5);
      await _dbHelper.insert('landlord_dues', {
        'id': '${propertyId}_$currentMonth',
        'propertyId': propertyId,
        'propertyName': property['name']?.toString() ?? 'Property',
        'landlordName':
            landlordName.isNotEmpty ? landlordName : 'Mortgage Payment',
        'amount': amount,
        'dueMonth': currentMonth,
        'dueDate': dueDate.millisecondsSinceEpoch,
        'status': 'pending',
        'createdAt': now.millisecondsSinceEpoch,
      });
    }
  }
}
