import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';

class AddEditMetricsScreen extends StatefulWidget {
  final String accountId;
  const AddEditMetricsScreen({super.key, required this.accountId});

  @override
  _AddEditMetricsScreenState createState() => _AddEditMetricsScreenState();
}

class _AddEditMetricsScreenState extends State<AddEditMetricsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final _formKey = GlobalKey<FormState>();
  final _followersController = TextEditingController();
  final _postsController = TextEditingController();
  final _likesController = TextEditingController();
  final _commentsController = TextEditingController();
  final _sharesController = TextEditingController();
  final _viewsController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) =>
          Theme(data: ThemeData.light(), child: child!),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await _dbHelper.insert('social_metrics', {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'accountId': widget.accountId,
        'date': _selectedDate.millisecondsSinceEpoch,
        'followers': int.tryParse(_followersController.text) ?? 0,
        'posts': int.tryParse(_postsController.text) ?? 0,
        'likes': int.tryParse(_likesController.text) ?? 0,
        'comments': int.tryParse(_commentsController.text) ?? 0,
        'shares': int.tryParse(_sharesController.text) ?? 0,
        'views': int.tryParse(_viewsController.text) ?? 0,
      });
      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        _syncService.syncAll();
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Metrics'),
        backgroundColor: AppColors.primaryRed,
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
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      // Date picker
                      ListTile(
                        title: Text(
                          'Date: ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                          style: const TextStyle(color: AppColors.white),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.calendar_today,
                            color: AppColors.white,
                          ),
                          onPressed: () => _selectDate(context),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Followers
                      TextFormField(
                        controller: _followersController,
                        style: const TextStyle(color: AppColors.white),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Followers',
                          labelStyle: const TextStyle(color: AppColors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.white.withOpacity(0.3),
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Posts
                      TextFormField(
                        controller: _postsController,
                        style: const TextStyle(color: AppColors.white),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Posts Count',
                          labelStyle: const TextStyle(color: AppColors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.white.withOpacity(0.3),
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Likes
                      TextFormField(
                        controller: _likesController,
                        style: const TextStyle(color: AppColors.white),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Likes',
                          labelStyle: const TextStyle(color: AppColors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.white.withOpacity(0.3),
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Comments
                      TextFormField(
                        controller: _commentsController,
                        style: const TextStyle(color: AppColors.white),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Comments',
                          labelStyle: const TextStyle(color: AppColors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.white.withOpacity(0.3),
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Shares
                      TextFormField(
                        controller: _sharesController,
                        style: const TextStyle(color: AppColors.white),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Shares',
                          labelStyle: const TextStyle(color: AppColors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.white.withOpacity(0.3),
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Views
                      TextFormField(
                        controller: _viewsController,
                        style: const TextStyle(color: AppColors.white),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Views',
                          labelStyle: const TextStyle(color: AppColors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.white.withOpacity(0.3),
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Save button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryRed,
                            foregroundColor: AppColors.white,
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: AppColors.white,
                                )
                              : const Text('Save Metrics'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
