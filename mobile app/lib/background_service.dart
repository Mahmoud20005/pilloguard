import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'database.dart';
import 'ble_service.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();
  
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'sleep_monitor_channel',
      initialNotificationTitle: 'Sleep Monitoring Active',
      initialNotificationContent: 'Monitoring audio and vitals',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Create a new sleep session
  final sessionId = await DatabaseHelper.instance.createSession(DateTime.now());
  
  final bleService = BleService();
  
  // Use mock data if hardware is not present for testing
  bleService.startMockDataStream();

  // Audio/Snore detection has been removed for now.

  bleService.sensorDataStream.listen((data) {
    DatabaseHelper.instance.insertSensorReading(
      sessionId,
      data['hr'],
      data['spo2'],
      data['ax'],
      data['ay'],
      data['az'],
    );
  });

  service.on('stopService').listen((event) async {
    bleService.stopScanningAndDisconnect();
    await DatabaseHelper.instance.endSession(sessionId, DateTime.now());
    service.stopSelf();
  });
}
