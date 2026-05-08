import 'package:flutter/material.dart';
import '../../services/database_helper.dart';
import '../../services/sync_service.dart';
import '../../utils/colors.dart';
import '../../utils/error_handler.dart';

class RolesScreen extends StatefulWidget {
  const RolesScreen({super.key});

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _roles = [];
  List<Map<String, dynamic>> _filteredRoles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRoles();
    _syncService.dataChangedStream.listen((_) {
      _loadRoles();
    });
  }

  Future<void> _loadRoles() async {
    setState(() => _isLoading = true);
    try {
      final roles = List<Map<String, dynamic>>.from(await _dbHelper.query('roles'))
        ..sort(
          (a, b) => (a['name'] ?? '').toString().compareTo(
            (b['name'] ?? '').toString(),
          ),
        );
      if (!mounted) return;
      setState(() {
        _roles = roles;
        _filteredRoles = roles;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ErrorHandler.showError(context, 'Failed to load roles: $e');
    }
  }

  void _filterRoles(String query) {
    final trimmed = query.trim().toLowerCase();
    setState(() {
      _filteredRoles = trimmed.isEmpty
          ? _roles
          : _roles.where((role) {
              final name = (role['name'] ?? '').toString().toLowerCase();
              final salaryType = (role['salary_type'] ?? '')
                  .toString()
                  .toLowerCase();
              return name.contains(trimmed) || salaryType.contains(trimmed);
            }).toList();
    });
  }

  Future<void> _showRoleDialog([Map<String, dynamic>? role]) async {
    final nameController = TextEditingController(
      text: role?['name']?.toString() ?? '',
    );
    final salaryController = TextEditingController(
      text: role?['default_monthly_salary']?.toString() ?? '',
    );
    var salaryType = (role?['salary_type'] ?? 'commission').toString();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Theme(
              data: ThemeData.light(),
              child: AlertDialog(
                title: Text(role == null ? 'Add Role' : 'Edit Role'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Role Name *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: salaryType,
                        decoration: const InputDecoration(
                          labelText: 'Salary Type *',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'commission',
                            child: Text('Commission'),
                          ),
                          DropdownMenuItem(
                            value: 'monthly',
                            child: Text('Monthly'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            salaryType = value;
                            if (salaryType != 'monthly') {
                              salaryController.clear();
                            }
                          });
                        },
                      ),
                      if (salaryType == 'monthly') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: salaryController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Default Monthly Salary',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(role == null ? 'Add' : 'Save'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != true) return;

    final name = nameController.text.trim();
    if (name.isEmpty) {
      if (mounted) ErrorHandler.showWarning(context, 'Role name is required');
      return;
    }

    final payload = <String, dynamic>{
      'name': name,
      'salary_type': salaryType,
      'default_monthly_salary': salaryType == 'monthly'
          ? double.tryParse(salaryController.text.trim())
          : null,
      'created_at':
          role?['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
    };

    try {
      if (role == null) {
        await _dbHelper.insert('roles', payload);
      } else {
        await _dbHelper.update('roles', {
          ...role,
          ...payload,
          'id': role['id'],
        });
      }
      await _loadRoles();
      _syncService.triggerBackgroundSync();
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showError(context, 'Failed to save role: $e');
    }
  }

  Future<void> _deleteRole(Map<String, dynamic> role) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text('Delete Role'),
          content: Text('Delete ${role['name']}?'),
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

    try {
      await _dbHelper.delete('roles', role['id']);
      await _loadRoles();
      _syncService.triggerBackgroundSync();
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showError(context, 'Failed to delete role: $e');
    }
  }

  String _salaryText(Map<String, dynamic> role) {
    final salary = role['default_monthly_salary'];
    if (salary == null) return 'Default: -';
    return 'Default: ETB ${salary.toString()}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Roles'),
        backgroundColor: AppColors.primaryRed,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: AppColors.white),
              decoration: InputDecoration(
                hintText: 'Search roles...',
                hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: AppColors.white),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.white.withOpacity(0.1),
              ),
              onChanged: _filterRoles,
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
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _filteredRoles.isEmpty
            ? const Center(
                child: Text(
                  'No roles found.',
                  style: TextStyle(color: AppColors.white),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: _filteredRoles.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: AppColors.white, height: 0.5),
                itemBuilder: (context, index) {
                  final role = _filteredRoles[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: role['salary_type'] == 'monthly'
                          ? AppColors.info
                          : AppColors.primaryRed,
                      child: Text(
                        (role['name'] ?? '?').toString()[0].toUpperCase(),
                        style: const TextStyle(color: AppColors.white),
                      ),
                    ),
                    title: Text(
                      role['name']?.toString() ?? 'Unnamed Role',
                      style: const TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${role['salary_type']} • ${_salaryText(role)}',
                      style: TextStyle(
                        color: AppColors.white.withOpacity(0.7),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _showRoleDialog(role),
                          icon: const Icon(
                            Icons.edit,
                            color: AppColors.primaryRed,
                          ),
                        ),
                        IconButton(
                          onPressed: () => _deleteRole(role),
                          icon: const Icon(
                            Icons.delete,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showRoleDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
