import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/database_helper.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';
import '../utils/device_helper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();
  final FocusNode _rawKeyboardFocusNode = FocusNode();
  bool _isLoading = false;
  bool _obscurePin = true;

  @override
  void dispose() {
    _pinController.dispose();
    _pinFocusNode.dispose();
    _rawKeyboardFocusNode.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    String pin = _pinController.text.trim();

    if (pin.isEmpty) {
      ErrorHandler.showError(context, 'Please enter your PIN');
      return;
    }
    if (pin.length != 6 || int.tryParse(pin) == null) {
      ErrorHandler.showError(context, 'PIN must be exactly 6 digits');
      return;
    }

    setState(() => _isLoading = true);

    try {
      String email = 'pin$pin@semere.local';

      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: pin);

      Map<String, dynamic>? userData =
          await _dbHelper.queryById('users', userCredential.user!.uid);

      final needsRemoteRepair = userData == null ||
          userData['role'] == null ||
          userData['branchId'] == null;
      if (needsRemoteRepair) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .get();
        if (userDoc.exists) {
          userData = userDoc.data() as Map<String, dynamic>?;
        }
      }

      if (userData == null) {
        throw Exception(
          'User profile not found locally or in Firestore. Please contact admin.',
        );
      }

      final role = userData['role']?.toString();
      if (role == null || role.isEmpty) {
        throw Exception('User role is missing. Please contact admin.');
      }
      print('User role: "$role"');

      final currentDeviceId = await DeviceHelper.getDeviceId();
      final storedDeviceId =
          userData['deviceId']?.toString() ?? userData['device_id']?.toString();
      if (storedDeviceId != null &&
          storedDeviceId.isNotEmpty &&
          storedDeviceId != currentDeviceId) {
        await FirebaseAuth.instance.signOut();
        throw Exception('Account is locked to another device');
      }

      if (storedDeviceId == null || storedDeviceId.isEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(
          userCredential.user!.uid,
        ).set({'deviceId': currentDeviceId}, SetOptions(merge: true));
      }
      final localUserData = {
        'id': userCredential.user!.uid,
        'name': userData['name'],
        'phone': userData['phone'],
        'role': userData['role'],
        'branchId': userData['branchId'],
        'employmentType': userData['employmentType'],
        'status': userData['status'],
        'commissionRate': userData['commissionRate'],
        'tailorCut': userData['tailorCut'],
        'delivery_commission_type': userData['delivery_commission_type'],
        'delivery_commission_value': userData['delivery_commission_value'],
        'createdAt': userData['createdAt'],
        'device_id': currentDeviceId,
      };
      await _dbHelper.insert(
        'users',
        localUserData,
        markSynced: true,
        changedFields: localUserData,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userRole', role);
      await prefs.setString('userId', userCredential.user!.uid);

      // FCM setup should not block login if Firebase Installations is unavailable.
      try {
        FirebaseMessaging messaging = FirebaseMessaging.instance;
        NotificationSettings settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );

        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          String? token = await messaging.getToken();
          if (token != null) {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userCredential.user!.uid)
                .set({'fcmToken': token}, SetOptions(merge: true));
          }
        }

        if (role == 'admin' || role == 'manager') {
          await messaging.subscribeToTopic('admins');
        }
      } catch (e) {
        print('FCM setup skipped: $e');
      }

      if (!mounted) return;

      switch (role) {
        case 'admin':
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/admin',
            (route) => false,
          );
          break;
        case 'manager':
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/manager',
            (route) => false,
          );
          break;
        case 'sales':
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/sales',
            (route) => false,
          );
          break;
        case 'tailor':
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/tailor',
            (route) => false,
          );
          break;
        default:
          ErrorHandler.showError(context, 'Invalid role: "$role"');
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Login failed';
      if (e.code == 'user-not-found' || e.code == 'wrong-password') {
        message = 'Invalid PIN';
      }
      if (mounted) ErrorHandler.showError(context, message);
    } catch (e) {
      if (mounted) ErrorHandler.showError(context, 'Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.backgroundStart, AppColors.backgroundEnd],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Semere Fashions',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(height: 48),
                RawKeyboardListener(
                  focusNode: _rawKeyboardFocusNode,
                  onKey: (event) {
                    if (event.isKeyPressed(LogicalKeyboardKey.enter) &&
                        !_isLoading) {
                      _login();
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextFormField(
                      controller: _pinController,
                      focusNode: _pinFocusNode,
                      keyboardType: TextInputType.number,
                      obscureText: _obscurePin,
                      maxLength: 6,
                      textInputAction: TextInputAction.go,
                      onFieldSubmitted: (_) => _login(),
                      style: const TextStyle(color: AppColors.white),
                      decoration: InputDecoration(
                        labelText: 'Enter your 6-digit PIN',
                        labelStyle: const TextStyle(color: AppColors.white),
                        prefixIcon: const Icon(
                          Icons.lock,
                          color: AppColors.white,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePin
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: AppColors.white,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePin = !_obscurePin;
                            });
                          },
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryRed,
                      foregroundColor: AppColors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(
                            color: AppColors.white,
                          )
                        : const Text('Login', style: TextStyle(fontSize: 18)),
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
