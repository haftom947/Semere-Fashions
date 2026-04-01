import 'package:flutter/material.dart';
import '../utils/colors.dart';

class EmployeeSelectorDialog extends StatelessWidget {
  final List<Map<String, dynamic>> employees;
  final String title;
  const EmployeeSelectorDialog({
    super.key,
    required this.employees,
    required this.title,
  });

  static Future<Map<String, dynamic>?> showEmployeeSelector(
    BuildContext context, {
    required List<Map<String, dynamic>> employees,
    required String title,
  }) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) =>
          EmployeeSelectorDialog(employees: employees, title: title),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light(),
      child: AlertDialog(
        title: Text(title, style: const TextStyle(color: Colors.black)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: employees.length,
            itemBuilder: (context, index) {
              var emp = employees[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primaryRed,
                  child: Text(
                    (emp['name'] ?? '?')[0].toUpperCase(),
                    style: const TextStyle(color: AppColors.white),
                  ),
                ),
                title: Text(
                  emp['name'] ?? '',
                  style: const TextStyle(color: Colors.black),
                ),
                subtitle: Text(
                  emp['role'] ?? '',
                  style: const TextStyle(color: Colors.black54),
                ),
                onTap: () => Navigator.pop(context, emp),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }
}
