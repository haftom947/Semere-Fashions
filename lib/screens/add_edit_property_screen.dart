import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';

class AddEditPropertyScreen extends StatefulWidget {
  final Map<String, dynamic>? propertyData;
  const AddEditPropertyScreen({super.key, this.propertyData});

  @override
  _AddEditPropertyScreenState createState() => _AddEditPropertyScreenState();
}

class _AddEditPropertyScreenState extends State<AddEditPropertyScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _monthlyRentController = TextEditingController();
  final _landlordNameController = TextEditingController();
  final _landlordPhoneController = TextEditingController();
  final _mortgageBankController = TextEditingController();
  final _mortgageMonthlyController = TextEditingController();

  String _selectedType = 'shop';
  String _selectedUsageType = 'rented_out';
  String _selectedOwnership = 'owned';
  String _selectedStatus = 'vacant';
  String _rentalExpenseType = 'lease';
  bool _isLoading = false;

  final List<String> _types = ['shop', 'warehouse', 'flat', 'office'];
  final List<String> _usageTypes = ['rented_out', 'business_use'];
  final List<String> _ownerships = ['owned', 'leased'];
  final List<String> _statuses = ['vacant', 'occupied', 'maintenance'];

  @override
  void initState() {
    super.initState();
    if (widget.propertyData != null) {
      _nameController.text = widget.propertyData!['name'] ?? '';
      _addressController.text = widget.propertyData!['address'] ?? '';
      _monthlyRentController.text =
          widget.propertyData!['monthlyRent']?.toString() ?? '';
      _landlordNameController.text = widget.propertyData!['landlordName'] ?? '';
      _landlordPhoneController.text =
          widget.propertyData!['landlordPhone'] ?? '';
      _mortgageBankController.text =
          widget.propertyData!['mortgageBank'] ?? '';
      _mortgageMonthlyController.text =
          widget.propertyData!['mortgageMonthly']?.toString() ?? '';
      _selectedType = widget.propertyData!['type'] ?? 'shop';
      _selectedUsageType =
          widget.propertyData!['usageType'] ??
          ((widget.propertyData!['ownership'] ?? 'owned') == 'leased'
              ? 'business_use'
              : 'rented_out');
      _selectedOwnership = widget.propertyData!['ownership'] ?? 'owned';
      _selectedStatus = widget.propertyData!['status'] ?? 'vacant';
      _rentalExpenseType =
          widget.propertyData!['rentalExpenseType'] ?? 'lease';
    }
  }

  String _usageLabel(String usage) {
    switch (usage) {
      case 'business_use':
        return 'Business Use';
      case 'rented_out':
      default:
        return 'Rented Out';
    }
  }

  String _rentLabel() {
    return _selectedUsageType == 'business_use'
        ? 'Monthly Lease Cost (ETB) *'
        : 'Monthly Rent Income (ETB) *';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> data = {
        'id':
            widget.propertyData?['id'] ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'type': _selectedType,
        'usageType': _selectedUsageType,
        'ownership': _selectedOwnership,
        'status': _selectedStatus,
        'monthlyRent': double.tryParse(_monthlyRentController.text) ?? 0,
        'landlordName': _landlordNameController.text.trim(),
        'landlordPhone': _landlordPhoneController.text.trim(),
        'mortgageBank': _mortgageBankController.text.trim(),
        'mortgageMonthly':
            double.tryParse(_mortgageMonthlyController.text) ?? 0,
        'rentalExpenseType': _rentalExpenseType,
      };
      if (widget.propertyData == null) {
        await _dbHelper.insert('properties', data);
      } else {
        await _dbHelper.update('properties', data);
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
          widget.propertyData == null ? 'Add Property' : 'Edit Property',
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
                          labelText: 'Property Name *',
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

                      // Address
                      TextFormField(
                        controller: _addressController,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Address',
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

                      // Purpose dropdown
                      DropdownButtonFormField<String>(
                        initialValue: _selectedUsageType,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Property Purpose *',
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
                        items: _usageTypes
                            .map(
                              (usage) => DropdownMenuItem<String>(
                                value: usage,
                                child: Text(_usageLabel(usage)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedUsageType = value!),
                      ),
                      const SizedBox(height: 16),

                      // Ownership dropdown
                      DropdownButtonFormField<String>(
                        initialValue: _selectedOwnership,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Ownership *',
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
                        items: _ownerships
                            .map(
                              (own) => DropdownMenuItem<String>(
                                value: own,
                                child: Text(own),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedOwnership = value!),
                      ),
                      const SizedBox(height: 16),

                      // Status dropdown (new)
                      DropdownButtonFormField<String>(
                        initialValue: _selectedStatus,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Status',
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

                      DropdownButtonFormField<String>(
                        initialValue: _rentalExpenseType,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Rental Expense Type',
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
                        items: const [
                          DropdownMenuItem(
                            value: 'lease',
                            child: Text('Leased (pay rent to landlord)'),
                          ),
                          DropdownMenuItem(
                            value: 'mortgage',
                            child: Text('Owned with mortgage'),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _rentalExpenseType = value!),
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _landlordNameController,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Landlord Name',
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
                        controller: _landlordPhoneController,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Landlord Phone',
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
                      if (_rentalExpenseType == 'mortgage') ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _mortgageBankController,
                          style: const TextStyle(color: AppColors.white),
                          decoration: InputDecoration(
                            labelText: 'Mortgage Bank',
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
                          controller: _mortgageMonthlyController,
                          style: const TextStyle(color: AppColors.white),
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Monthly Payment (ETB)',
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
                      ],

                      // Monthly Rent
                      TextFormField(
                        controller: _monthlyRentController,
                        style: const TextStyle(color: AppColors.white),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: _rentLabel(),
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

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.white.withOpacity(0.18),
                          ),
                        ),
                        child: Text(
                          _selectedUsageType == 'rented_out'
                              ? 'Rented Out: use this when the property has tenants and you want to collect rent from them.'
                              : 'Business Use: use this when the company occupies the property itself. Tenant management does not apply here.',
                          style: const TextStyle(
                            color: AppColors.white,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

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
                                  widget.propertyData == null
                                      ? 'Add Property'
                                      : 'Update Property',
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
