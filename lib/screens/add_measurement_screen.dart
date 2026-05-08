import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../utils/colors.dart';

class AddMeasurementScreen extends StatefulWidget {
  final String customerId;
  const AddMeasurementScreen({super.key, required this.customerId});

  @override
  _AddMeasurementScreenState createState() => _AddMeasurementScreenState();
}

class _AddMeasurementScreenState extends State<AddMeasurementScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _types = [];
  final Map<String, TextEditingController> _controllers = {};
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    var types = List<Map<String, dynamic>>.from(
      await _dbHelper.query('measurement_types'),
    );
    types.sort((a, b) => (a['sortOrder'] ?? 0).compareTo(b['sortOrder'] ?? 0));
    setState(() {
      _types = types;
      for (var type in types) {
        _controllers[type['id']] = TextEditingController();
      }
      _isLoading = false;
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) =>
          Theme(data: ThemeData.light(), child: child!),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _save() async {
    for (var type in _types) {
      var value = double.tryParse(_controllers[type['id']]!.text);
      if (value != null) {
        await _dbHelper.insert('measurements', {
          'id': DateTime.now().millisecondsSinceEpoch.toString() + type['id'],
          'customer_id': widget.customerId,
          'measurement_type_id': type['id'],
          'date_taken': _selectedDate.millisecondsSinceEpoch,
          'value': value,
          'notes': '',
        });
      }
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Measurements'),
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
            : _types.isEmpty
            ? const Center(
                child: Text(
                  'No measurement types defined. Please add them in settings.',
                  style: TextStyle(color: AppColors.white),
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(16),
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
                    // Dynamic fields for each type
                    ..._types.map((type) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextFormField(
                          controller: _controllers[type['id']],
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: AppColors.darkGrey),
                          decoration: InputDecoration(
                            labelText:
                                '${type['name']} (${type['unit'] ?? ''})',
                            labelStyle:
                                const TextStyle(color: AppColors.darkGrey),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: AppColors.darkGrey.withOpacity(0.3),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide:
                                  BorderSide(color: AppColors.primaryRed),
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: AppColors.white,
                      ),
                      child: const Text('Save Measurements'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
