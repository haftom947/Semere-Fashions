import 'package:flutter/material.dart';

class AppDateFilter {
  AppDateFilter._();

  static final AppDateFilter instance = AppDateFilter._();

  final ValueNotifier<DateTimeRange?> rangeNotifier = ValueNotifier<DateTimeRange?>(null);

  DateTimeRange? get range => rangeNotifier.value;

  set range(DateTimeRange? value) => rangeNotifier.value = value;

  void setRange(DateTimeRange value) {
    rangeNotifier.value = value;
  }

  void clear() {
    rangeNotifier.value = null;
  }
}
