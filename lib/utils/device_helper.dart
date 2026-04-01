import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class DeviceHelper {
  static Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      return android.id;
    }
    if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      return ios.identifierForVendor ?? ios.name;
    }
    if (Platform.isMacOS) {
      final mac = await deviceInfo.macOsInfo;
      return mac.model;
    }
    if (Platform.isWindows) {
      final windows = await deviceInfo.windowsInfo;
      return windows.computerName;
    }
    if (Platform.isLinux) {
      final linux = await deviceInfo.linuxInfo;
      return linux.machineId ?? linux.name ?? 'linux';
    }
    return Platform.operatingSystem;
  }
}
