import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/admin_home.dart';
import 'screens/manager_home.dart';
import 'screens/sales_home.dart';
import 'screens/tailor_home.dart';
import 'screens/orders_list_screen.dart';
import 'screens/order_details_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/employee_list_screen.dart';
import 'screens/customers_screen.dart';
import 'screens/reports_screen.dart';
import 'utils/colors.dart';
import 'screens/branch_list_screen.dart';
import 'screens/product_list_screen.dart';
import 'screens/material_list_screen.dart';
import 'screens/add_edit_product_screen.dart';
import 'screens/add_edit_material_screen.dart';
import 'screens/create_order_screen.dart';
import 'screens/equipment_list_screen.dart';
import 'screens/supplier_list_screen.dart';
import 'screens/property_list_screen.dart';
import 'screens/tenant_list_screen.dart';
import 'screens/rent_payment_screen.dart';
import 'screens/social_accounts_screen.dart';
import 'screens/commissions_screen.dart';
import 'screens/purchase_orders_list_screen.dart';
import 'screens/social_dashboard_screen.dart';
import 'screens/measurement_types_screen.dart';
import 'screens/account_list_screen.dart';
import 'screens/cash_flow_screen.dart';
import 'screens/production_order_screen.dart';
import 'screens/employee_payments_screen.dart';
import 'screens/add_edit_employee_payment_screen.dart';
import 'screens/supplier_materials_screen.dart';
import 'screens/leave_request_screen.dart';
import 'screens/leave_requests_list_screen.dart';
import 'services/notification_service.dart';
import 'services/rent_service.dart';
import 'services/low_stock_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await NotificationService().init();
  await RentService().generateRentDuesIfNeeded();
  await LowStockService().checkAndNotify();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Semere Fashions',
      theme: ThemeData(
        primaryColor: AppColors.primaryRed,
        colorScheme: ColorScheme.dark(
          primary: AppColors.primaryRed,
          secondary: AppColors.accent,
          background: AppColors.backgroundStart,
          surface: AppColors.cardBackground,
          error: AppColors.error,
          onPrimary: AppColors.white,
          onSecondary: AppColors.white,
          onBackground: AppColors.white,
          onSurface: AppColors.black,
          onError: AppColors.white,
        ),
        scaffoldBackgroundColor: AppColors.backgroundStart,
        cardColor: AppColors.cardBackground,
        fontFamily: 'Montserrat',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: AppColors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryRed,
            foregroundColor: AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.white,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.white, width: 2),
          ),
          filled: true,
          fillColor: AppColors.white.withOpacity(0.1),
          hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
          labelStyle: const TextStyle(color: AppColors.white),
        ),
      ),
      initialRoute: '/login',
      routes: {
        '/create-order': (context) => CreateOrderScreen(),
        '/branches': (context) => BranchListScreen(),
        '/login': (context) => LoginScreen(),
        '/admin': (context) => AdminHome(),
        '/manager': (context) => ManagerHome(),
        '/sales': (context) => SalesHome(),
        '/tailor': (context) => TailorHome(),
        '/dashboard': (context) => DashboardScreen(role: 'admin'),
        '/properties': (context) => PropertyListScreen(),
        '/orders': (context) => OrdersListScreen(),
        '/inventory': (context) => InventoryScreen(),
        '/employees': (context) => EmployeeListScreen(),
        '/customers': (context) => CustomersScreen(),
        '/reports': (context) => ReportsScreen(),
        '/products': (context) => ProductListScreen(),
        '/materials': (context) => MaterialListScreen(),
        '/equipment': (context) => EquipmentListScreen(),
        '/suppliers': (context) => SupplierListScreen(),
        '/social': (context) => SocialAccountsScreen(),
        '/commissions': (context) => CommissionsScreen(),
        '/purchase_orders': (context) => PurchaseOrdersListScreen(),
        '/social_dashboard': (context) => SocialDashboardScreen(),
        '/measurement_types': (context) => MeasurementTypesScreen(),
        '/accounts': (context) => AccountListScreen(),
        '/cashflow': (context) => CashFlowScreen(),
        '/production': (context) => ProductionOrderScreen(),
        '/employee_payments': (context) => EmployeePaymentsScreen(employeeId: '', employeeName: ''),
        '/leave_request': (context) => LeaveRequestScreen(),
        '/leave_requests': (context) => LeaveRequestsListScreen(),
      },
      onUnknownRoute: (RouteSettings settings) {
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            body: Center(
              child: Text('Route ${settings.name} not found'),
            ),
          ),
        );
      },
    );
  }
}