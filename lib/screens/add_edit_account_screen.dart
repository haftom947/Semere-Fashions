import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';

class AddEditAccountScreen extends StatefulWidget {
  final Map<String, dynamic>? accountData;
  const AddEditAccountScreen({super.key, this.accountData});

  @override
  _AddEditAccountScreenState createState() => _AddEditAccountScreenState();
}

class _AddEditAccountScreenState extends State<AddEditAccountScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _openingBalanceController = TextEditingController();
  final _notesController = TextEditingController();
  final _currencyController = TextEditingController();

  String _selectedType = 'cash';
  String? _selectedBranchId;
  List<Map<String, dynamic>> _branches = [];
  bool _isLoading = false;

  final List<String> _types = ['cash', 'bank'];

  @override
  void initState() {
    super.initState();
    _loadBranches();
    if (widget.accountData != null) {
      _nameController.text = widget.accountData!['name'] ?? '';
      _selectedType = widget.accountData!['type'] ?? 'cash';
      _openingBalanceController.text =
          widget.accountData!['opening_balance']?.toString() ?? '';
      _notesController.text = widget.accountData!['notes'] ?? '';
      _selectedBranchId = widget.accountData!['branchId']?.toString();
      _currencyController.text = widget.accountData!['currency'] ?? '';
    }
  }

  Future<void> _loadBranches() async {
    final branches = await _dbHelper.query('branches');
    if (!mounted) return;
    setState(() {
      _branches = List<Map<String, dynamic>>.from(branches);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedType == 'cash' &&
        (_selectedBranchId == null || _selectedBranchId!.isEmpty)) {
      ErrorHandler.showError(context, 'Select a branch for cash accounts');
      return;
    }
    setState(() => _isLoading = true);
    try {
      double opening = double.tryParse(_openingBalanceController.text) ?? 0.0;
      final existingAccount = widget.accountData;
      Map<String, dynamic> data = {
        'id':
            existingAccount?['id'] ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        'name': _nameController.text.trim(),
        'type': _selectedType,
        'opening_balance': opening,
        'currency': _currencyController.text.isNotEmpty
            ? _currencyController.text
            : 'ETB',
        'current_balance': existingAccount == null
            ? opening
            : (existingAccount['current_balance'] as num?)?.toDouble() ??
                  opening,
        'branchId': _selectedType == 'cash' ? _selectedBranchId : null,
        'notes': _notesController.text.trim(),
      };
      if (existingAccount == null) {
        await _dbHelper.insert('accounts', data);
      } else {
        await _dbHelper.update('accounts', data);
      }
      if (mounted) {
        _syncService.triggerBackgroundSync();
        ErrorHandler.showSuccess(
          context,
          widget.accountData == null ? 'Account saved' : 'Account updated',
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ErrorHandler.showError(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.accountData == null ? 'Add Account' : 'Edit Account',
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
                      // Account Name
                      TextFormField(
                        controller: _nameController,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Account Name *',
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
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _selectedType = value;
                            if (_selectedType == 'bank') {
                              _selectedBranchId = null;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      if (_selectedType == 'cash') ...[
                        DropdownButtonFormField<String>(
                          initialValue: _selectedBranchId,
                          dropdownColor: AppColors.backgroundStart,
                          style: const TextStyle(color: AppColors.white),
                          decoration: InputDecoration(
                            labelText: 'Branch *',
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
                          items: _branches
                              .map(
                                (branch) => DropdownMenuItem<String>(
                                  value: branch['id']?.toString() ?? '',
                                  child: Text(
                                    branch['name'] ?? branch['id'] ?? 'Branch',
                                  ),
                                ),
                              )
                              .toList(),
                              onChanged: (value) async {
                                setState(() => _selectedBranchId = value);
                                if (value != null && value.isNotEmpty) {
                                  final branch = await _dbHelper.queryById(
                                      'branches', value);
                                  if (branch != null) {
                                    setState(() => _currencyController.text =
                                        (branch['currency'] ?? 'ETB').toString());
                                  }
                                }
                              },
                          validator: (value) => value == null || value.isEmpty
                              ? 'Required'
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Currency
                      TextFormField(
                        controller: _currencyController,
                        enabled: _selectedType != 'cash',
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Currency',
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

                      // Opening Balance
                      TextFormField(
                        controller: _openingBalanceController,
                        style: const TextStyle(color: AppColors.white),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText:
                              'Opening Balance (${_currencyController.text.isNotEmpty ? _currencyController.text : 'ETB'})',
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
                                  widget.accountData == null
                                      ? 'Add Account'
                                      : 'Update Account',
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
