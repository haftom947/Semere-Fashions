import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';

class AssignEquipmentScreen extends StatefulWidget {
  final String equipmentId;
  final String? currentAssignee;
  const AssignEquipmentScreen({super.key, required this.equipmentId, this.currentAssignee});

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
    try {
      // Update equipment with new assignee
      var equipment = await _dbHelper.queryById('equipment', widget.equipmentId);
      if (equipment != null) {
        equipment['assignedTo'] = _selectedEmployeeId;
        await _dbHelper.update('equipment', equipment);
      }
      // Record assignment history – we can add an assignments table later
      // For now, just update local and sync
      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        _syncService.syncAll();
      }
      if (mounted) ErrorHandler.safePop(context);
    } catch (e) {
      if (mounted) ErrorHandler.showError(context, 'Error: $e');
    } finally {
      setState(() => _isLoading = false);
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
                initialValue: _selectedEmployeeId,
                dropdownColor: AppColors.backgroundStart,
                style: const TextStyle(color: AppColors.white),
                decoration: InputDecoration(
                  labelText: 'Select Employee',
                  labelStyle: const TextStyle(color: AppColors.white),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.white),
                  ),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('Unassign (no one)', style: TextStyle(color: AppColors.white)),
                  ),
                  ..._employees.map((e) => DropdownMenuItem<String>(
                    value: e['id'],
                    child: Text(e['name'] ?? 'Unknown', style: const TextStyle(color: AppColors.white)),
                  )),
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