import 'package:flutter/material.dart';
import '../utils/colors.dart';

class EmployeeSelectorDialog extends StatelessWidget {
  final List<Map<String, dynamic>> employees;
  final String title;
  const EmployeeSelectorDialog({Key? key, required this.employees, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
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
              title: Text(emp['name'] ?? ''),
              subtitle: Text(emp['role'] ?? ''),
              onTap: () => Navigator.pop(context, emp),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}