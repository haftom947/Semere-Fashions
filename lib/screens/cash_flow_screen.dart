import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';

class CashFlowScreen extends StatefulWidget {
  const CashFlowScreen({Key? key}) : super(key: key);

  @override
  _CashFlowScreenState createState() => _CashFlowScreenState();
}

class _CashFlowScreenState extends State<CashFlowScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _filteredTransactions = [];
  List<Map<String, dynamic>> _accounts = [];
  bool _isLoading = true;
  String _selectedAccountId = 'all';
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _searchController = TextEditingController();

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
    var accounts = await _dbHelper.query('accounts');
    var transactions = await _dbHelper.query('transactions');
    transactions.sort((a, b) => (b['date'] as int).compareTo(a['date'] as int));
    setState(() {
      _accounts = accounts;
      _transactions = transactions;
      _applyFilters();
      _isLoading = false;
    });
  }

  void _applyFilters() {
    var filtered = _transactions;
    
    // Account filter
    if (_selectedAccountId != 'all') {
      filtered = filtered.where((t) => t['account_id'] == _selectedAccountId).toList();
    }
    
    // Date range filter
    if (_startDate != null) {
      filtered = filtered.where((t) => (t['date'] as int) >= _startDate!.millisecondsSinceEpoch).toList();
    }
    if (_endDate != null) {
      filtered = filtered.where((t) => (t['date'] as int) <= _endDate!.millisecondsSinceEpoch + 86400000).toList();
    }
    
    // Search filter
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((t) {
        return (t['description'] ?? '').toLowerCase().contains(query) ||
               (t['category'] ?? '').toLowerCase().contains(query) ||
               (t['reference_id'] ?? '').toLowerCase().contains(query);
      }).toList();
    }
    
    setState(() {
      _filteredTransactions = filtered;
    });
  }

  void _filterByAccount(String? value) {
    setState(() {
      _selectedAccountId = value ?? 'all';
      _applyFilters();
    });
  }

  void _search(String query) {
    _applyFilters();
  }

  double _getRunningBalance() {
    double balance = 0;
    for (var t in _filteredTransactions) {
      balance += (t['amount'] as num?)?.toDouble() ?? 0;
    }
    return balance;
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        _applyFilters();
      });
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
        _applyFilters();
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedAccountId = 'all';
      _startDate = null;
      _endDate = null;
      _searchController.clear();
      _applyFilters();
    });
  }

  @override
  Widget build(BuildContext context) {
    double balance = _getRunningBalance();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Flow'),
        backgroundColor: AppColors.primaryRed,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: AppColors.white),
              decoration: InputDecoration(
                hintText: 'Search transactions...',
                hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: AppColors.white),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.white.withOpacity(0.1),
              ),
              onChanged: _search,
            ),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.backgroundStart, AppColors.backgroundEnd],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // Balance card
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Running Balance',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            'ETB ${balance.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: balance >= 0 ? AppColors.success : AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Transactions list
                    Expanded(
                      child: _filteredTransactions.isEmpty
                          ? const Center(
                              child: Text('No transactions found.', style: TextStyle(color: AppColors.white)),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _filteredTransactions.length,
                              separatorBuilder: (_, __) => const Divider(color: AppColors.white, height: 0.5),
                              itemBuilder: (context, index) {
                                var t = _filteredTransactions[index];
                                DateTime date = DateTime.fromMillisecondsSinceEpoch(t['date']);
                                String dateStr = DateFormat('dd/MM/yy HH:mm').format(date);
                                double amount = (t['amount'] as num?)?.toDouble() ?? 0;
                                var account = _accounts.firstWhere(
                                  (a) => a['id'] == t['account_id'],
                                  orElse: () => {'name': 'Unknown'},
                                );
                                return ListTile(
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: amount >= 0 ? AppColors.success : AppColors.error,
                                    child: Icon(
                                      amount >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                                      color: AppColors.white,
                                      size: 16,
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          t['description'] ?? t['category'] ?? 'Transaction',
                                          style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                      Text(
                                        '${amount >= 0 ? '+' : '-'} ETB ${amount.abs().toStringAsFixed(2)}',
                                        style: TextStyle(
                                          color: amount >= 0 ? AppColors.success : AppColors.error,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${account['name']} · $dateStr',
                                        style: TextStyle(color: AppColors.white.withOpacity(0.7)),
                                      ),
                                      if (t['reference_id'] != null)
                                        Text(
                                          'Ref: ${t['reference_id']}',
                                          style: TextStyle(color: AppColors.white.withOpacity(0.5), fontSize: 12),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Transactions'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: _selectedAccountId,
                  dropdownColor: AppColors.backgroundStart,
                  decoration: const InputDecoration(labelText: 'Account'),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All Accounts')),
                    ..._accounts.map((a) => DropdownMenuItem(
                      value: a['id'],
                      child: Text(a['name']),
                    )),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedAccountId = value!);
                    this.setState(() {});
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(_startDate == null
                          ? 'Start date'
                          : DateFormat('dd/MM/yyyy').format(_startDate!)),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _startDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() => _startDate = picked);
                          this.setState(() {});
                        }
                      },
                      child: const Text('Pick'),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(_endDate == null
                          ? 'End date'
                          : DateFormat('dd/MM/yyyy').format(_endDate!)),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _endDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() => _endDate = picked);
                          this.setState(() {});
                        }
                      },
                      child: const Text('Pick'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(onPressed: _clearFilters, child: const Text('Clear')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}