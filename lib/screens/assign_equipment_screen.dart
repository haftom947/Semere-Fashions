import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';

class AssignEquipmentScreen extends StatefulWidget {
  final String equipmentId;
  final String? currentAssignee;
  const AssignEquipmentScreen({
    super.key,
    required this.equipmentId,
    this.currentAssignee,
  });

  @override
  _AssignEquipmentScreenState createState() => _AssignEquipmentScreenState();
}

class _AssignEquipmentScreenState extends State<AssignEquipmentScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  String? _selectedEmployeeId;
  bool _isLoading = false;
  List<Map<String, dynamic>> _employees = [];

  @override
  void initState() {
    super.initState();
    _selectedEmployeeId = widget.currentAssignee?.toString();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    var users = await _dbHelper.query('users');
    setState(() {
      _employees = users.where((u) => u['status'] == 'active').toList();
    });
  }

  Future<void> _assign() async {
    setState(() => _isLoading = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await _dbHelper.update('equipment', {
        'id': widget.equipmentId,
        'assignedTo': _selectedEmployeeId == null || _selectedEmployeeId!.isEmpty
            ? null
            : _selectedEmployeeId,
        'syncStatus': 'pending',
        'lastModified': now,
      });

      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        _syncService.syncAll();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Equipment assigned successfully')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assign Equipment'),
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                value: _selectedEmployeeId,
                dropdownColor: AppColors.backgroundStart,
                style: const TextStyle(color: AppColors.white),
                decoration: InputDecoration(
                  labelText: 'Select Employee',
                  labelStyle: const TextStyle(color: AppColors.white),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: AppColors.white.withOpacity(0.3),
                    ),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.white),
                  ),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text(
                      'Unassign (no one)',
                      style: TextStyle(color: AppColors.white),
                    ),
                  ),
                  ..._employees.map(
                    (e) => DropdownMenuItem<String>(
                      value: e['id']?.toString() ?? '',
                      child: Text(
                        e['name'] ?? 'Unknown',
                        style: const TextStyle(color: AppColors.white),
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _selectedEmployeeId = value),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _assign,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: AppColors.white,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: AppColors.white)
                      : const Text('Save Assignment'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
