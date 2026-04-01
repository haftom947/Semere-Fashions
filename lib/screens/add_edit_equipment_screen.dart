import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';

class AddEditEquipmentScreen extends StatefulWidget {
  final Map<String, dynamic>? equipmentData;
  const AddEditEquipmentScreen({super.key, this.equipmentData});

  @override
  _AddEditEquipmentScreenState createState() => _AddEditEquipmentScreenState();
}

class _AddEditEquipmentScreenState extends State<AddEditEquipmentScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _serialController = TextEditingController();
  final _makeController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _licensePlateController = TextEditingController();
  final _colorController = TextEditingController();
  final _insurancePolicyController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _registrationExpiry;
  DateTime? _insuranceExpiry;

  String _selectedType = 'machine';
  String _selectedStatus = 'active';
  String? _selectedAssignedTo;
  bool _isLoading = false;
  List<Map<String, dynamic>> _employees = [];

  final List<String> _types = ['machine', 'tool', 'vehicle'];
  final List<String> _statuses = ['active', 'maintenance', 'broken', 'retired'];

  @override
  void initState() {
    super.initState();
    if (widget.equipmentData != null) {
      _nameController.text = widget.equipmentData!['name'] ?? '';
      _serialController.text = widget.equipmentData!['serialNumber'] ?? '';
      _makeController.text = widget.equipmentData!['make'] ?? '';
      _modelController.text = widget.equipmentData!['model'] ?? '';
      _yearController.text = widget.equipmentData!['year']?.toString() ?? '';
      _licensePlateController.text =
          widget.equipmentData!['licensePlate'] ?? '';
      _colorController.text = widget.equipmentData!['color'] ?? '';
      _insurancePolicyController.text =
          widget.equipmentData!['insurance_policy'] ?? '';
      _notesController.text = widget.equipmentData!['notes'] ?? '';
      _selectedType = widget.equipmentData!['type'] ?? 'machine';
      _selectedStatus = widget.equipmentData!['status'] ?? 'active';
      if (widget.equipmentData!['registration_expiry'] != null) {
        _registrationExpiry = DateTime.fromMillisecondsSinceEpoch(
          widget.equipmentData!['registration_expiry'],
        );
      }
      if (widget.equipmentData!['insurance_expiry'] != null) {
        _insuranceExpiry = DateTime.fromMillisecondsSinceEpoch(
          widget.equipmentData!['insurance_expiry'],
        );
      }
      _selectedAssignedTo = widget.equipmentData!['assignedTo']?.toString() ?? '';
    }
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    final users = await _dbHelper.query('users');
    if (!mounted) return;
    setState(() {
      _employees = List<Map<String, dynamic>>.from(
        users.where((u) => u['status'] == 'active'),
      );
    });
  }

  Future<void> _selectRegistrationExpiry(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _registrationExpiry ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      builder: (context, child) =>
          Theme(data: ThemeData.light(), child: child!),
    );
    if (picked != null) {
      setState(() => _registrationExpiry = picked);
    }
  }

  Future<void> _selectInsuranceExpiry(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _insuranceExpiry ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      builder: (context, child) =>
          Theme(data: ThemeData.light(), child: child!),
    );
    if (picked != null) {
      setState(() => _insuranceExpiry = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> data = {
        'id':
            widget.equipmentData?['id'] ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        'name': _nameController.text.trim(),
        'type': _selectedType,
        'status': _selectedStatus,
        'serialNumber': _serialController.text.trim(),
        'make': _makeController.text.trim(),
        'model': _modelController.text.trim(),
        'year': int.tryParse(_yearController.text),
        'licensePlate': _licensePlateController.text.trim(),
        'color': _colorController.text.trim(),
        'registration_expiry': _registrationExpiry?.millisecondsSinceEpoch,
        'insurance_policy': _insurancePolicyController.text.trim(),
        'insurance_expiry': _insuranceExpiry?.millisecondsSinceEpoch,
        'notes': _notesController.text.trim(),
        'assignedTo': _selectedAssignedTo == null || _selectedAssignedTo!.isEmpty ? null : _selectedAssignedTo,
      };
      if (widget.equipmentData == null) {
        await _dbHelper.insert('equipment', data);
      } else {
        await _dbHelper.update('equipment', data);
      }
      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        _syncService.syncAll();
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.equipmentData == null ? 'Add Equipment' : 'Edit Equipment',
        ),
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
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      // Name
                      TextFormField(
                        controller: _nameController,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Equipment Name *',
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
                        validator: (value) =>
                            value == null || value.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Type dropdown
                      DropdownButtonFormField<String>(
                        initialValue: _selectedType,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Type *',
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
                        items: _types
                            .map(
                              (type) => DropdownMenuItem<String>(
                                value: type,
                                child: Text(type),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedType = value!),
                      ),
                      const SizedBox(height: 16),

                      // Status dropdown
                      DropdownButtonFormField<String>(
                        initialValue: _selectedStatus,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Status *',
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
                        items: _statuses
                            .map(
                              (status) => DropdownMenuItem<String>(
                                value: status,
                                child: Text(status),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedStatus = value!),
                      ),
                      const SizedBox(height: 16),

                      // Assigned employee
                      DropdownButtonFormField<String>(
                        initialValue: _selectedAssignedTo,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Assigned Employee',
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
                              'Unassigned',
                              style: TextStyle(color: AppColors.white),
                            ),
                          ),
                          ..._employees.map(
                            (employee) => DropdownMenuItem<String>(
                              value: employee['id']?.toString() ?? '',
                              child: Text(
                                employee['name'] ?? 'Unknown',
                                style: const TextStyle(color: AppColors.white),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedAssignedTo = value);
                        },
                      ),
                      const SizedBox(height: 16),

                      // Serial Number
                      TextFormField(
                        controller: _serialController,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Serial Number',
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
                      ),
                      const SizedBox(height: 16),

                      // Vehicle-specific fields
                      if (_selectedType == 'vehicle') ...[
                        TextFormField(
                          controller: _makeController,
                          style: const TextStyle(color: AppColors.white),
                          decoration: InputDecoration(
                            labelText: 'Make',
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
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _modelController,
                          style: const TextStyle(color: AppColors.white),
                          decoration: InputDecoration(
                            labelText: 'Model',
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
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _yearController,
                          style: const TextStyle(color: AppColors.white),
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Year',
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
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _licensePlateController,
                          style: const TextStyle(color: AppColors.white),
                          decoration: InputDecoration(
                            labelText: 'License Plate',
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
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _colorController,
                          style: const TextStyle(color: AppColors.white),
                          decoration: InputDecoration(
                            labelText: 'Color',
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
                        ),
                        const SizedBox(height: 16),

                        // Registration expiry
                        ListTile(
                          title: Text(
                            _registrationExpiry == null
                                ? 'Registration Expiry (optional)'
                                : 'Registration Expiry: ${_registrationExpiry!.day}/${_registrationExpiry!.month}/${_registrationExpiry!.year}',
                            style: const TextStyle(color: AppColors.white),
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.calendar_today,
                              color: AppColors.white,
                            ),
                            onPressed: () => _selectRegistrationExpiry(context),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Insurance policy
                        TextFormField(
                          controller: _insurancePolicyController,
                          style: const TextStyle(color: AppColors.white),
                          decoration: InputDecoration(
                            labelText: 'Insurance Policy Number',
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
                        ),
                        const SizedBox(height: 8),

                        // Insurance expiry
                        ListTile(
                          title: Text(
                            _insuranceExpiry == null
                                ? 'Insurance Expiry (optional)'
                                : 'Insurance Expiry: ${_insuranceExpiry!.day}/${_insuranceExpiry!.month}/${_insuranceExpiry!.year}',
                            style: const TextStyle(color: AppColors.white),
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.calendar_today,
                              color: AppColors.white,
                            ),
                            onPressed: () => _selectInsuranceExpiry(context),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Notes
                      TextFormField(
                        controller: _notesController,
                        style: const TextStyle(color: AppColors.white),
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Notes',
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
                      ),
                      const SizedBox(height: 24),

                      // Save button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryRed,
                            foregroundColor: AppColors.white,
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: AppColors.white,
                                )
                              : Text(
                                  widget.equipmentData == null
                                      ? 'Add Equipment'
                                      : 'Update Equipment',
                                ),
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
