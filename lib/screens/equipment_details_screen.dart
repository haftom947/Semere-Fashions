import 'package:flutter/material.dart';
import '../utils/colors.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import 'assign_equipment_screen.dart';

class EquipmentDetailsScreen extends StatefulWidget {
  final String equipmentId;
  const EquipmentDetailsScreen({super.key, required this.equipmentId});

  @override
  _EquipmentDetailsScreenState createState() => _EquipmentDetailsScreenState();
}

class _EquipmentDetailsScreenState extends State<EquipmentDetailsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  Map<String, dynamic>? _equipment;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _syncService.dataChangedStream.listen((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _equipment = await _dbHelper.queryById('equipment', widget.equipmentId);
    setState(() => _isLoading = false);
  }

  Future<String> _getEmployeeName(String? employeeId) async {
    if (employeeId == null) return 'No one';
    var user = await _dbHelper.queryById('users', employeeId);
    return user?['name'] ?? 'Unknown';
  }

  String _formatDate(int? timestamp) {
    if (timestamp == null) return 'Not set';
    var date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equipment Details'),
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
            : _equipment == null
            ? const Center(
                child: Text(
                  'Equipment not found',
                  style: TextStyle(color: AppColors.white),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Name: ${_equipment!['name']}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('Type: ${_equipment!['type']}'),
                          Text('Status: ${_equipment!['status']}'),
                          if (_equipment!['serialNumber'] != null)
                            Text('Serial: ${_equipment!['serialNumber']}'),
                          if (_equipment!['make'] != null)
                            Text('Make: ${_equipment!['make']}'),
                          if (_equipment!['model'] != null)
                            Text('Model: ${_equipment!['model']}'),
                          if (_equipment!['year'] != null)
                            Text('Year: ${_equipment!['year']}'),
                          if (_equipment!['licensePlate'] != null)
                            Text('License: ${_equipment!['licensePlate']}'),
                          if (_equipment!['color'] != null)
                            Text('Color: ${_equipment!['color']}'),
                          // New fields
                          if (_equipment!['registration_expiry'] != null)
                            Text(
                              'Registration Expiry: ${_formatDate(_equipment!['registration_expiry'])}',
                            ),
                          if (_equipment!['insurance_policy'] != null)
                            Text(
                              'Insurance Policy: ${_equipment!['insurance_policy']}',
                            ),
                          if (_equipment!['insurance_expiry'] != null)
                            Text(
                              'Insurance Expiry: ${_formatDate(_equipment!['insurance_expiry'])}',
                            ),
                          if (_equipment!['notes'] != null)
                            Text('Notes: ${_equipment!['notes']}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Assignment',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          FutureBuilder<String>(
                            future: _getEmployeeName(_equipment!['assignedTo']),
                            builder: (context, snap) {
                              return Text(
                                'Currently assigned to: ${snap.data ?? 'No one'}',
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            AssignEquipmentScreen(
                                              equipmentId: widget.equipmentId,
                                              currentAssignee:
                                                  _equipment!['assignedTo'],
                                            ),
                                      ),
                                    ).then((_) => _loadData());
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.info,
                                    foregroundColor: AppColors.white,
                                  ),
                                  child: Text(
                                    _equipment!['assignedTo'] == null
                                        ? 'Assign'
                                        : 'Reassign',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
