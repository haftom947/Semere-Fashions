import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';
import 'add_measurement_screen.dart';

class CustomerDetailsScreen extends StatefulWidget {
  final String customerId;
  final String customerName;
  const CustomerDetailsScreen({Key? key, required this.customerId, required this.customerName}) : super(key: key);

  @override
  _CustomerDetailsScreenState createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _measurements = [];
  List<Map<String, dynamic>> _types = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    var types = await _dbHelper.query('measurement_types');
    var allMeasurements = await _dbHelper.query('measurements');
    var filtered = allMeasurements.where((m) => m['customer_id'] == widget.customerId).toList();
    // Sort by date taken (most recent first)
    filtered.sort((a, b) => (b['date_taken'] as int).compareTo(a['date_taken'] as int));
    if (mounted) {
      setState(() {
        _types = types;
        _measurements = filtered;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteMeasurement(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Measurement'),
        content: const Text('Are you sure you want to delete this measurement?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _dbHelper.delete('measurements', id);
      if (mounted) {
        _loadData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customerName),
        backgroundColor: AppColors.primaryRed,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.backgroundStart, AppColors.backgroundEnd],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _measurements.isEmpty
                ? const Center(
                    child: Text('No measurements yet. Tap + to add.',
                        style: TextStyle(color: AppColors.white)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _measurements.length,
                    itemBuilder: (context, index) {
                      var measurement = _measurements[index];
                      var type = _types.firstWhere(
                        (t) => t['id'] == measurement['measurement_type_id'],
                        orElse: () => {'name': 'Unknown', 'unit': ''},
                      );
                      DateTime date = DateTime.fromMillisecondsSinceEpoch(measurement['date_taken']);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text('${type['name']}: ${measurement['value']} ${type['unit'] ?? ''}'),
                          subtitle: Text('Date: ${date.day}/${date.month}/${date.year}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: AppColors.error),
                            onPressed: () => _deleteMeasurement(measurement['id']),
                          ),
                        ),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddMeasurementScreen(customerId: widget.customerId),
            ),
          ).then((_) {
            if (mounted) {
              _loadData();
            }
          });
        },
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.add),
      ),
    );
  }
}