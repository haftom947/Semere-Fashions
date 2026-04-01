import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/currency_helper.dart';
import '../utils/error_handler.dart';
import 'add_edit_account_screen.dart';

class AccountListScreen extends StatefulWidget {
  const AccountListScreen({Key? key}) : super(key: key);

  @override
  _AccountListScreenState createState() => _AccountListScreenState();
}

class _AccountListScreenState extends State<AccountListScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _uiAccounts = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAccounts();
    _syncService.dataChangedStream.listen((_) {
      _loadAccounts();
    });
  }

  Future<void> _loadAccounts() async {
    setState(() => _isLoading = true);
    var accounts = List<Map<String, dynamic>>.from(
      await _dbHelper.query('accounts'),
    );
    accounts.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
    setState(() {
      _accounts = accounts;
      _uiAccounts = accounts;
      _isLoading = false;
    });
  }

  void _filterAccounts(String query) {
    if (query.isEmpty) {
      setState(() {
        _uiAccounts = _accounts;
      });
      return;
    }
    final lowerQuery = query.toLowerCase();
    setState(() {
      _uiAccounts = _accounts.where((a) {
        return (a['name'] ?? '').toLowerCase().contains(lowerQuery) ||
            (a['type'] ?? '').toLowerCase().contains(lowerQuery);
      }).toList();
    });
  }

  Future<void> _deleteAccount(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text('Delete Account'),
          content: Text('Are you sure you want to delete $name?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    // Optimistic update
    setState(() {
      _uiAccounts.removeWhere((a) => a['id'] == id);
    });

    try {
      await _dbHelper.delete('accounts', id);
      _accounts.removeWhere((a) => a['id'] == id);
      _syncService.syncAll();
      if (mounted) ErrorHandler.showSuccess(context, 'Account deleted');
    } catch (e) {
      setState(() {
        _uiAccounts = List.from(_accounts);
      });
      if (mounted) ErrorHandler.showError(context, 'Delete failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        backgroundColor: AppColors.primaryRed,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddEditAccountScreen(),
                ),
              ).then((_) => _loadAccounts());
            },
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
                hintText: 'Search accounts...',
                hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: AppColors.white),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.white.withOpacity(0.1),
              ),
              onChanged: _filterAccounts,
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
          onRefresh: _loadAccounts,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _uiAccounts.isEmpty
              ? const Center(
                  child: Text(
                    'No accounts found.',
                    style: TextStyle(color: AppColors.white),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: _uiAccounts.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: AppColors.white, height: 0.5),
                  itemBuilder: (context, index) {
                    var account = _uiAccounts[index];
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: account['type'] == 'bank'
                            ? AppColors.info
                            : AppColors.success,
                        child: Icon(
                          account['type'] == 'bank'
                              ? Icons.account_balance
                              : Icons.money,
                          color: AppColors.white,
                          size: 16,
                        ),
                      ),
                      title: Text(
                        account['name'] ?? 'Unnamed',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        '${account['type']} · Balance: ${CurrencyHelper.formatAmount((account['current_balance'] as num?)?.toDouble(), null)}',
                        style: TextStyle(
                          color: AppColors.white.withOpacity(0.7),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.edit,
                              color: AppColors.primaryRed,
                              size: 20,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AddEditAccountScreen(
                                    accountData: account,
                                  ),
                                ),
                              ).then((_) => _loadAccounts());
                            },
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: AppColors.error,
                              size: 20,
                            ),
                            onPressed: () => _deleteAccount(
                              account['id'],
                              account['name'] ?? '',
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
