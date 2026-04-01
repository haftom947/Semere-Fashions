import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/app_date_filter.dart';
import '../utils/colors.dart';
import '../utils/currency_helper.dart';

class CashFlowScreen extends StatefulWidget {
  const CashFlowScreen({super.key});

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
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    AppDateFilter.instance.rangeNotifier.addListener(_onGlobalRangeChanged);
    _loadData();
    _syncService.dataChangedStream.listen((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    AppDateFilter.instance.rangeNotifier.removeListener(_onGlobalRangeChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onGlobalRangeChanged() {
    if (!mounted) return;
    setState(_applyFilters);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    var accounts = List<Map<String, dynamic>>.from(
      await _dbHelper.query('accounts'),
    );
    var transactions = List<Map<String, dynamic>>.from(
      await _dbHelper.query('transactions'),
    );
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

    final globalRange = AppDateFilter.instance.range;
    if (globalRange != null) {
      final start = DateTime(
        globalRange.start.year,
        globalRange.start.month,
        globalRange.start.day,
      ).millisecondsSinceEpoch;
      final end = DateTime(
        globalRange.end.year,
        globalRange.end.month,
        globalRange.end.day,
        23,
        59,
        59,
        999,
      ).millisecondsSinceEpoch;
      filtered = filtered.where((t) {
        final date = (t['date'] as int?) ?? 0;
        return date >= start && date <= end;
      }).toList();
    }

    // Account filter
    if (_selectedAccountId != 'all') {
      filtered = filtered
          .where((t) => t['account_id'] == _selectedAccountId)
          .toList();
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
    AppDateFilter.instance.clear();
  }

  Future<void> _selectEndDate(BuildContext context) async {
    AppDateFilter.instance.clear();
  }

  void _clearFilters() {
    setState(() {
      _selectedAccountId = 'all';
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
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
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
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            CurrencyHelper.formatAmount(balance, null),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: balance >= 0
                                  ? AppColors.success
                                  : AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ValueListenableBuilder<DateTimeRange?>(
                        valueListenable: AppDateFilter.instance.rangeNotifier,
                        builder: (context, range, _) {
                          return Text(
                            range == null
                                ? 'Global date filter: All dates'
                                : 'Global date filter: ${range.start.day}/${range.start.month}/${range.start.year} - ${range.end.day}/${range.end.month}/${range.end.year}',
                            style: const TextStyle(color: AppColors.white),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Transactions list
                    Expanded(
                      child: _filteredTransactions.isEmpty
                          ? const Center(
                              child: Text(
                                'No transactions found.',
                                style: TextStyle(color: AppColors.white),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              itemCount: _filteredTransactions.length,
                              separatorBuilder: (_, _) => const Divider(
                                color: AppColors.white,
                                height: 0.5,
                              ),
                              itemBuilder: (context, index) {
                                var t = _filteredTransactions[index];
                                DateTime date =
                                    DateTime.fromMillisecondsSinceEpoch(
                                      t['date'],
                                    );
                                String dateStr = DateFormat(
                                  'dd/MM/yy HH:mm',
                                ).format(date);
                                double amount =
                                    (t['amount'] as num?)?.toDouble() ?? 0;
                                var account = _accounts.firstWhere(
                                  (a) => a['id'] == t['account_id'],
                                  orElse: () => {'name': 'Unknown'},
                                );
                                return ListTile(
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: amount >= 0
                                        ? AppColors.success
                                        : AppColors.error,
                                    child: Icon(
                                      amount >= 0
                                          ? Icons.arrow_upward
                                          : Icons.arrow_downward,
                                      color: AppColors.white,
                                      size: 16,
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          t['description'] ??
                                              t['category'] ??
                                              'Transaction',
                                          style: const TextStyle(
                                            color: AppColors.white,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${amount >= 0 ? '+' : '-'} ${CurrencyHelper.formatAmount(amount.abs(), null)}',
                                        style: TextStyle(
                                          color: amount >= 0
                                              ? AppColors.success
                                              : AppColors.error,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${account['name']} · $dateStr',
                                        style: TextStyle(
                                          color: AppColors.white.withOpacity(
                                            0.7,
                                          ),
                                        ),
                                      ),
                                      if (t['reference_id'] != null)
                                        Text(
                                          'Ref: ${t['reference_id']}',
                                          style: TextStyle(
                                            color: AppColors.white.withOpacity(
                                              0.5,
                                            ),
                                            fontSize: 12,
                                          ),
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
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text('Filter Transactions'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _selectedAccountId,
                    dropdownColor: AppColors.backgroundStart,
                    decoration: const InputDecoration(labelText: 'Account'),
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All Accounts'),
                      ),
                      ..._accounts.map(
                        (a) => DropdownMenuItem(
                          value: a['id'],
                          child: Text(a['name']),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedAccountId = value!);
                      this.setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Date range comes from the global dashboard picker.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(onPressed: _clearFilters, child: const Text('Clear')),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
