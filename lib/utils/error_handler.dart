import 'package:flutter/material.dart';

class ErrorHandler {
  static void showError(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static void showSuccess(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // NEW: warning snackbar (orange)
  static void showWarning(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static Future<T?> tryCatch<T>(
    BuildContext context,
    Future<T> Function() operation, {
    String? errorMessage,
  }) async {
    try {
      return await operation();
    } catch (e) {
      if (context.mounted) {
        showError(
          context,
          errorMessage ?? 'An error occurred: ${e.toString()}',
        );
      }
      return null;
    }
  }

  static void safeNavigate(BuildContext context, Widget Function() page) {
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => page()));
  }

  static void safePop(BuildContext context, [dynamic result]) {
    if (!context.mounted) return;
    Navigator.pop(context, result);
  }
}
