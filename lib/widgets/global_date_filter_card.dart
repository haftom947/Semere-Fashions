import 'package:flutter/material.dart';
import '../utils/app_date_filter.dart';
import '../utils/colors.dart';
import '../utils/date_picker_helper.dart';

class GlobalDateFilterCard extends StatelessWidget {
  const GlobalDateFilterCard({super.key});

  String _formatRange(DateTimeRange range) {
    final start = range.start;
    final end = range.end;
    return '${start.day}/${start.month}/${start.year} - ${end.day}/${end.month}/${end.year}';
  }

  Future<void> _pickRange(BuildContext context) async {
    final current = AppDateFilter.instance.range;
    final range = await DatePickerHelper.pickDateRange(
      context,
      initialDateRange: current,
      helpText: 'Pick global date range',
    );
    if (range != null) {
      AppDateFilter.instance.setRange(range);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTimeRange?>(
      valueListenable: AppDateFilter.instance.rangeNotifier,
      builder: (context, range, _) {
        final label = range == null ? 'All dates' : _formatRange(range);
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.white.withOpacity(0.12)),
          ),
          child: Row(
            children: [
              const Icon(Icons.date_range, color: AppColors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Global Date Range',
                      style: TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: const TextStyle(color: AppColors.white),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _pickRange(context),
                child: const Text('Pick', style: TextStyle(color: AppColors.white)),
              ),
              if (range != null)
                TextButton(
                  onPressed: () => AppDateFilter.instance.clear(),
                  child: const Text('Clear', style: TextStyle(color: AppColors.white)),
                ),
            ],
          ),
        );
      },
    );
  }
}
