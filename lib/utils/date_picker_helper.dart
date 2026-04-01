import 'package:flutter/material.dart';

class DatePickerHelper {
  static Future<DateTime?> pickDate(
    BuildContext context, {
    DateTime? initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    String? helpText,
  }) {
    return showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: firstDate ?? DateTime(2020),
      lastDate: lastDate ?? DateTime.now().add(const Duration(days: 3650)),
      helpText: helpText,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light(),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  static Future<DateTimeRange?> pickDateRange(
    BuildContext context, {
    DateTimeRange? initialDateRange,
    DateTime? firstDate,
    DateTime? lastDate,
    String? helpText,
  }) {
    final initialRange = initialDateRange ??
        DateTimeRange(
          start: DateTime.now().subtract(const Duration(days: 6)),
          end: DateTime.now(),
        );

    return showDateRangePicker(
      context: context,
      firstDate: firstDate ?? DateTime(2020),
      lastDate: lastDate ?? DateTime.now(),
      initialDateRange: initialRange,
      helpText: helpText,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light(),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
