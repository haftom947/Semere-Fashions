import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/colors.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';

class AddEditMaintenanceLogScreen extends StatefulWidget {
  final String vehicleId;
  final Map<String, dynamic>? logData;
  const AddEditMaintenanceLogScreen({super.key, required this.vehicleId, this.logData});

  @override
  _AddEditMaintenanceLogScreenState createState() => _AddEditMaintenanceLogScreenState();
}

class _AddEditMaintenanceLogScreenState extends State<AddEditMaintenanceLogScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final _formKey = GlobalKey<FormState>();
  final _typeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _costController = TextEditingController();
  final _odometerController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  DateTime? _nextDueDate;
  bool _completed = false;
  bool _isLoading = false;

  final List<String> _maintenanceTypes = ['Oil Change', 'Tire Rotation', 'Brake Service', 'Engine Repair', 'Inspection', 'Other'];

  @override
  void initState() {
    super.initState();
    if (widget.logData != null) {
      _typeController.text = widget.logData!['type'] ?? '';
      _descriptionController.text = widget.logData!['description'] ?? '';
      _costController.text = widget.logData!['cost'].toString();
      _odometerController.text = widget.logData!['odometer'].toString();
      _notesController.text = widget.logData!['notes'] ?? '';
      _selectedDate = DateTime.fromMillisecondsSinceEpoch(widget.logData!['date']);
      if (widget.logData!['nextDue'] != null) {
        _nextDueDate = DateTime.fromMillisecondsSinceEpoch(widget.logData!['nextDue']);
      }
      _completed = widget.logData!['completed'] ?? false;
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _selectNextDueDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _nextDueDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() => _nextDueDate = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      String id = widget.logData?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
      Map<String, dynamic> data = {
        'id': id,
        'vehicleId': widget.vehicleId,
        'date': _selectedDate.millisecondsSinceEpoch,
        'type': _typeController.text.trim(),
        'description': _descriptionController.text.trim(),
        'cost': double.tryParse(_costController.text) ?? 0,
        'odometer': int.tryParse(_odometerController.text) ?? 0,
        'nextDue': _nextDueDate?.millisecondsSinceEpoch,
        'completed': _completed,
        'notes': _notesController.text.trim(),
      };
      if (widget.logData == null) {
        await _dbHelper.insert('maintenance_logs', data);
      } else {
        await _dbHelper.update('maintenance_logs', data);
      }
      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        _syncService.syncAll();
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.logData == null ? 'Add Maintenance' : 'Edit Maintenance'),
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
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                // Date
                ListTile(
                  title: Text(
                    'Date: ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                    style: const TextStyle(color: AppColors.white),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today, color: AppColors.white),
                    onPressed: () => _selectDate(context),
                  ),
                ),
                const SizedBox(height: 16),

                // Type dropdown
                DropdownButtonFormField<String>(
                  initialValue: _typeController.text.isEmpty ? null : _typeController.text,
                  dropdownColor: AppColors.backgroundStart,
                  style: const TextStyle(color: AppColors.white),
                  decoration: InputDecoration(
                    labelText: 'Maintenance Type *',
                    labelStyle: const TextStyle(color: AppColors.white),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white),
                    ),
                  ),
                  items: _maintenanceTypes.map((type) => DropdownMenuItem<String>(
                    value: type,
                    child: Text(type),
                  )).toList(),
                  onChanged: (value) => _typeController.text = value ?? '',
                  validator: (value) => value == null ? 'Select type' : null,
                ),
                const SizedBox(height: 16),

                // Description
                TextFormField(
                  controller: _descriptionController,
                  style: const TextStyle(color: AppColors.white),
                  decoration: InputDecoration(
                    labelText: 'Description',
                    labelStyle: const TextStyle(color: AppColors.white),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Cost
                TextFormField(
                  controller: _costController,
                  style: const TextStyle(color: AppColors.white),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Cost (ETB) *',
                    labelStyle: const TextStyle(color: AppColors.white),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white),
                    ),
                  ),
                  validator: (value) => value == null || value.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                // Odometer
                TextFormField(
                  controller: _odometerController,
                  style: const TextStyle(color: AppColors.white),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Odometer (km)',
                    labelStyle: const TextStyle(color: AppColors.white),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Next due date (optional)
                ListTile(
                  title: Text(
                    _nextDueDate == null
                        ? 'Next Due: (optional)'
                        : 'Next Due: ${_nextDueDate!.day}/${_nextDueDate!.month}/${_nextDueDate!.year}',
                    style: const TextStyle(color: AppColors.white),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today, color: AppColors.white),
                    onPressed: () => _selectNextDueDate(context),
                  ),
                ),
                const SizedBox(height: 8),

                // Completed checkbox
                CheckboxListTile(
                  title: const Text('Completed', style: TextStyle(color: AppColors.white)),
                  value: _completed,
                  onChanged: (value) => setState(() => _completed = value ?? false),
                ),
                const SizedBox(height: 16),

                // Notes
                TextFormField(
                  controller: _notesController,
                  style: const TextStyle(color: AppColors.white),
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Notes',
                    labelStyle: const TextStyle(color: AppColors.white),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: AppColors.white,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: AppColors.white)
                        : Text(widget.logData == null ? 'Add Record' : 'Update Record'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}