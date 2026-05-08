import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';

class RecordPaymentScreen extends StatefulWidget {
  final String? orderId;

  const RecordPaymentScreen({Key? key, this.orderId}) : super(key: key);

  @override
  _RecordPaymentScreenState createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends State<RecordPaymentScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final TextEditingController _amountController = TextEditingController();
  String? _selectedOrderId;
  Map<String, dynamic>? _selectedOrder;
  double _amount = 0.0;
  String _method = 'cash';
  String _type = 'payment';
  final List<String> _methods = ['cash', 'card', 'transfer'];
  final List<String> _types = ['payment', 'refund'];
  List<Map<String, dynamic>> _accounts = [];
  String? _selectedAccountId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.orderId != null) {
      _loadOrder(widget.orderId!);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadOrder(String id) async {
    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final order = await _dbHelper.queryById('orders', id);
      if (!mounted) return;
      setState(() {
        _selectedOrderId = id;
        _selectedOrder = order != null
            ? Map<String, dynamic>.from(order)
            : null;
        _isLoading = false;
        _accounts = [];
        _selectedAccountId = null;
      });
      if (_selectedOrder != null) {
        await _loadAccounts();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ErrorHandler.showError(context, 'Failed to load order: $e');
    }
  }

  Future<void> _selectOrder() async {
    String typedOrderId = _selectedOrderId ?? '';
    final id = await showDialog<String>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text(
            'Enter Order ID',
            style: TextStyle(color: Colors.black),
          ),
          content: TextField(
            autofocus: true,
            controller: TextEditingController(text: typedOrderId),
            decoration: const InputDecoration(hintText: 'Order ID'),
            onChanged: (value) => typedOrderId = value.trim(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.blue)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, typedOrderId),
              child: const Text('OK', style: TextStyle(color: Colors.blue)),
            ),
          ],
        ),
      ),
    );
    if (id != null && id.trim().isNotEmpty) {
      await _loadOrder(id.trim());
    }
  }

  Future<void> _loadAccounts() async {
    if (_selectedOrder == null) return;
    final branchId = _selectedOrder!['branchId']?.toString();
    final accounts = List<Map<String, dynamic>>.from(
      await _dbHelper.query('accounts'),
    );
    final filtered = _method == 'cash'
        ? accounts
              .where(
                (account) =>
                    account['type']?.toString() == 'cash' &&
                    account['branchId']?.toString() == branchId,
              )
              .toList()
        : accounts
              .where(
                (account) =>
                    account['type']?.toString() == 'bank' &&
                    ((account['branchId']?.toString() ?? '').isEmpty),
              )
              .toList();
    if (!mounted) return;
    setState(() {
      _accounts = filtered;
      if (_accounts.isEmpty) {
        _selectedAccountId = null;
      } else if (_selectedAccountId == null ||
          !_accounts.any((a) => a['id']?.toString() == _selectedAccountId)) {
        _selectedAccountId = _accounts.first['id']?.toString();
      }
    });
  }

  Future<void> _submit() async {
    if (_selectedOrderId == null || _selectedOrder == null) {
      ErrorHandler.showError(context, 'Select an order');
      return;
    }
    if (_amount <= 0) {
      ErrorHandler.showError(context, 'Enter a valid amount');
      return;
    }
    if (_selectedAccountId == null) {
      ErrorHandler.showError(context, 'Select an account');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _dbHelper.addPayment(
        _selectedOrderId!,
        _amount,
        _method,
        type: _type,
        branchId: _selectedOrder!['branchId'] as String?,
        receivedBy: FirebaseAuth.instance.currentUser?.uid,
        accountId: _selectedAccountId!,
      );

      _syncService.emitDataChanged();
      _syncService.triggerBackgroundSync();
      if (mounted) {
        ErrorHandler.showSuccess(context, 'Payment recorded');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, 'Failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = (_selectedOrder?['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final paid = (_selectedOrder?['paid_amount'] as num?)?.toDouble() ?? 0.0;
    final remaining = total - paid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Payment'),
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
            : SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.orderId == null)
                      ElevatedButton(
                        onPressed: _selectOrder,
                        child: const Text('Select Order'),
                      ),
                    if (_selectedOrder != null) ...[
                      Card(
                        color: AppColors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Order: ${_selectedOrder!['id']}',
                                style: const TextStyle(color: Colors.black),
                              ),
                              Text(
                                'Customer: ${_selectedOrder!['customerName'] ?? 'Unknown'}',
                                style: const TextStyle(color: Colors.black),
                              ),
                              Text(
                                'Total: ETB ${total.toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.black),
                              ),
                              Text(
                                'Paid: ETB ${paid.toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.black),
                              ),
                              Text(
                                'Remaining: ETB ${remaining.toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.black),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _type,
                        items: _types
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(type),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _type = value);
                        },
                        decoration: const InputDecoration(labelText: 'Type'),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Amount'),
                        onChanged: (value) {
                          _amount = double.tryParse(value) ?? 0.0;
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _method,
                        items: _methods
                            .map(
                              (method) => DropdownMenuItem(
                                value: method,
                                child: Text(method),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _method = value;
                            _selectedAccountId = null;
                          });
                          _loadAccounts();
                        },
                        decoration: const InputDecoration(labelText: 'Method'),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedAccountId,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Account',
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
                        items: _accounts
                            .map(
                              (account) => DropdownMenuItem<String>(
                                value: account['id']?.toString(),
                                child: Text(
                                  '${account['name'] ?? 'Account'} '
                                  '(ETB ${(account['current_balance'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00'})',
                                  style: const TextStyle(
                                    color: AppColors.white,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() => _selectedAccountId = value);
                        },
                      ),
                      if (_accounts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'No matching accounts found for this method and branch.',
                            style: TextStyle(color: AppColors.warning),
                          ),
                        ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _submit,
                        child: const Text('Record'),
                      ),
                    ] else if (widget.orderId != null)
                      const Center(
                        child: Text(
                          'Order not found',
                          style: TextStyle(color: AppColors.white),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
