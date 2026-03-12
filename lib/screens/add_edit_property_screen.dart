import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';

class AddEditPropertyScreen extends StatefulWidget {
  final Map<String, dynamic>? propertyData;
  const AddEditPropertyScreen({Key? key, this.propertyData}) : super(key: key);

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

  String _selectedType = 'shop';
  String _selectedOwnership = 'owned';
  String _selectedStatus = 'vacant';
  bool _isLoading = false;

  final List<String> _types = ['shop', 'warehouse', 'flat', 'office'];
  final List<String> _ownerships = ['owned', 'leased'];
  final List<String> _statuses = ['vacant', 'occupied', 'maintenance'];

  @override
  void initState() {
    super.initState();
    if (widget.propertyData != null) {
      _nameController.text = widget.propertyData!['name'] ?? '';
      _addressController.text = widget.propertyData!['address'] ?? '';
      _monthlyRentController.text = widget.propertyData!['monthlyRent']?.toString() ?? '';
      _landlordNameController.text = widget.propertyData!['landlordName'] ?? '';
      _landlordPhoneController.text = widget.propertyData!['landlordPhone'] ?? '';
      _selectedType = widget.propertyData!['type'] ?? 'shop';
      _selectedOwnership = widget.propertyData!['ownership'] ?? 'owned';
      _selectedStatus = widget.propertyData!['status'] ?? 'vacant';
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> data = {
        'id': widget.propertyData?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'type': _selectedType,
        'ownership': _selectedOwnership,
        'status': _selectedStatus,
        'monthlyRent': double.tryParse(_monthlyRentController.text) ?? 0,
        if (_selectedOwnership == 'leased') ...{
          'landlordName': _landlordNameController.text.trim(),
          'landlordPhone': _landlordPhoneController.text.trim(),
        },
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.propertyData == null ? 'Add Property' : 'Edit Property'),
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
                            borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty ? 'Required' : null,
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
                            borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Type dropdown
                      DropdownButtonFormField<String>(
                        value: _selectedType,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Type *',
                          labelStyle: const TextStyle(color: AppColors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                        items: _types.map((type) => DropdownMenuItem<String>(
                          value: type,
                          child: Text(type),
                        )).toList(),
                        onChanged: (value) => setState(() => _selectedType = value!),
                      ),
                      const SizedBox(height: 16),

                      // Ownership dropdown
                      DropdownButtonFormField<String>(
                        value: _selectedOwnership,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Ownership *',
                          labelStyle: const TextStyle(color: AppColors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                        items: _ownerships.map((own) => DropdownMenuItem<String>(
                          value: own,
                          child: Text(own),
                        )).toList(),
                        onChanged: (value) => setState(() => _selectedOwnership = value!),
                      ),
                      const SizedBox(height: 16),

                      // Status dropdown (new)
                      DropdownButtonFormField<String>(
                        value: _selectedStatus,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Status',
                          labelStyle: const TextStyle(color: AppColors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                        items: _statuses.map((status) => DropdownMenuItem<String>(
                          value: status,
                          child: Text(status),
                        )).toList(),
                        onChanged: (value) => setState(() => _selectedStatus = value!),
                      ),
                      const SizedBox(height: 16),

                      // Monthly Rent
                      TextFormField(
                        controller: _monthlyRentController,
                        style: const TextStyle(color: AppColors.white),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Monthly Rent (ETB) *',
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

                      // Conditional fields for leased properties
                      if (_selectedOwnership == 'leased') ...[
                        TextFormField(
                          controller: _landlordNameController,
                          style: const TextStyle(color: AppColors.white),
                          decoration: InputDecoration(
                            labelText: 'Landlord Name',
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
                        TextFormField(
                          controller: _landlordPhoneController,
                          style: const TextStyle(color: AppColors.white),
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'Landlord Phone',
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
                      ],

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
                              ? const CircularProgressIndicator(color: AppColors.white)
                              : Text(widget.propertyData == null ? 'Add Property' : 'Update Property'),
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