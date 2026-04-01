import 'package:flutter/material.dart';
import '../utils/colors.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import 'fuel_logs_screen.dart';
import 'maintenance_logs_screen.dart';

class VehicleDetailsScreen extends StatefulWidget {
  final String vehicleId;
  const VehicleDetailsScreen({super.key, required this.vehicleId});

  @override
  _VehicleDetailsScreenState createState() => _VehicleDetailsScreenState();
}

class _VehicleDetailsScreenState extends State<VehicleDetailsScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  Map<String, dynamic>? _vehicle;
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadVehicle();
  }

  Future<void> _loadVehicle() async {
    setState(() => _isLoading = true);
    _vehicle = await _dbHelper.queryById('equipment', widget.vehicleId);
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_vehicle?['name'] ?? 'Vehicle Details'),
        backgroundColor: AppColors.primaryRed,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Fuel Logs'),
            Tab(text: 'Maintenance'),
          ],
        ),
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
            : _vehicle == null
            ? const Center(
                child: Text(
                  'Vehicle not found',
                  style: TextStyle(color: AppColors.white),
                ),
              )
            : Column(
                children: [
                  // Vehicle summary card
                  Card(
                    margin: const EdgeInsets.all(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Make: ${_vehicle!['make'] ?? 'N/A'}'),
                          Text('Model: ${_vehicle!['model'] ?? 'N/A'}'),
                          Text('Year: ${_vehicle!['year'] ?? 'N/A'}'),
                          Text(
                            'License: ${_vehicle!['licensePlate'] ?? 'N/A'}',
                          ),
                          Text('Status: ${_vehicle!['status']}'),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        FuelLogsScreen(vehicleId: widget.vehicleId),
                        MaintenanceLogsScreen(vehicleId: widget.vehicleId),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
