import 'package:flutter/material.dart';
import '../utils/colors.dart';

class EmployeesScreen extends StatelessWidget {
  const EmployeesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Employees'),
        backgroundColor: AppColors.primaryRed,
      ),
      body: Center(child: Text('Employees Screen - Coming Soon')),
    );
  }
}
