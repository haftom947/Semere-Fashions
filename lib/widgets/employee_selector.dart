import 'package:flutter/material.dart';
import '../utils/colors.dart';
import '../services/database_helper.dart';

class EmployeeSelector extends StatefulWidget {
  final Function(String employeeId, String employeeName, String role) onEmployeeSelected;
  final String? initialRole; // optional role filter
  const EmployeeSelector({super.key, required this.onEmployeeSelected, this.initialRole});

  @override
  _EmployeeSelectorState createState() => _EmployeeSelectorState();
}

class _EmployeeSelectorState extends State<EmployeeSelector> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filtered = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    var all = await _dbHelper.query('users');
    // Optionally filter by role
    if (widget.initialRole != null) {
      all = all.where((e) => e['role'] == widget.initialRole).toList();
    }
    setState(() {
      _employees = all;
      _filtered = all;
    });
  }

  void _filter(String query) {
    setState(() {
      if (query.isEmpty) {
        _filtered = _employees;
      } else {
        _filtered = _employees.where((e) =>
          (e['name'] ?? '').toLowerCase().contains(query.toLowerCase()) ||
          (e['role'] ?? '').toLowerCase().contains(query.toLowerCase())
        ).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          style: const TextStyle(color: AppColors.white),
          decoration: InputDecoration(
            hintText: 'Search employee...',
            hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.white),
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search, color: AppColors.white),
              onPressed: () => _filter(_searchController.text),
            ),
          ),
          onChanged: _filter,
        ),
        const SizedBox(height: 8),
        if (_filtered.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: AppColors.backgroundStart,
              border: Border.all(color: AppColors.white.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _filtered.length,
              itemBuilder: (context, index) {
                var emp = _filtered[index];
                return ListTile(
                  title: Text(emp['name'] ?? '', style: const TextStyle(color: AppColors.white)),
                  subtitle: Text(emp['role'] ?? '', style: TextStyle(color: AppColors.white.withOpacity(0.7))),
                  onTap: () {
                    widget.onEmployeeSelected(emp['id'], emp['name'] ?? '', emp['role'] ?? '');
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}