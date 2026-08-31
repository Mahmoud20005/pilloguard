import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService extends ChangeNotifier {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  BluetoothDevice? _device;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  Timer? _mockDataTimer;
  
  final String targetDeviceName = "SleepMonitor_Device"; 
  
  bool _isScanning = false;
  bool get isScanning => _isScanning;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  bool _isMockMode = false;
  bool get isMockMode => _isMockMode;

  final StreamController<Map<String, dynamic>> _sensorDataController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get sensorDataStream => _sensorDataController.stream;

  Future<void> startScanning() async {
    if (_isScanning || _isConnected) return;
    
    _isScanning = true;
    _isMockMode = false;
    notifyListeners();

    try {
      // Start scanning
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 3)); // Shorter timeout for demo

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.platformName == targetDeviceName) {
            FlutterBluePlus.stopScan();
            _connectToDevice(r.device);
            return;
          }
        }
      });

      // Wait for scan to finish
      await Future.delayed(const Duration(seconds: 3));
      if (_isScanning && !_isConnected) {
        // Fallback to mock data if device not found after timeout
        FlutterBluePlus.stopScan();
        _isScanning = false;
        startMockDataStream();
      }
    } catch (e) {
      _isScanning = false;
      startMockDataStream();
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _isScanning = false;
    notifyListeners();
    _device = device;
    
    _connectionSubscription = _device!.connectionState.listen((BluetoothConnectionState state) async {
      if (state == BluetoothConnectionState.connected) {
        _isConnected = true;
        notifyListeners();
        // Discover services
        List<BluetoothService> services = await _device!.discoverServices();
        for (BluetoothService service in services) {
          // Listen to characteristics
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.properties.notify) {
              await characteristic.setNotifyValue(true);
              characteristic.lastValueStream.listen((value) {
                if (value.isNotEmpty) {
                  _sensorDataController.add({
                    'hr': 75,
                    'spo2': 98,
                    'ax': 0.1,
                    'ay': 0.0,
                    'az': 0.9,
                    'temp': 36.5,
                  });
                }
              });
            }
          }
        }
      } else if (state == BluetoothConnectionState.disconnected) {
        _isConnected = false;
        notifyListeners();
      }
    });
    
    await _device!.connect(license: License.nonprofit);
  }

  void stopScanningAndDisconnect() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    if (_device != null) {
      _device!.disconnect();
    }
    _mockDataTimer?.cancel();
    
    _isScanning = false;
    _isConnected = false;
    _isMockMode = false;
    notifyListeners();
  }

  // Helper method for testing UI without real hardware
  void startMockDataStream() {
    _isMockMode = true;
    _isConnected = true; // Act as if connected for UI
    notifyListeners();

    _mockDataTimer?.cancel();
    
    double pillowX = 0.1;
    double pillowY = 0.2;
    int hr = 65;
    
    _mockDataTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      final random = DateTime.now().millisecond;
      if (random % 3 == 0) {
        hr += (random % 2 == 0 ? 1 : -1);
        hr = hr.clamp(55, 85);
      }
      
      if (random % 10 == 0) {
        pillowX = ((random % 200) / 100) - 1; // -1 to 1
        pillowY = ((random % 200) / 100) - 1; // -1 to 1
      }
      
      _sensorDataController.add({
        'hr': hr,
        'spo2': 98 + (random % 3), // 98, 99, 100
        'ax': pillowX,
        'ay': pillowY,
        'az': 0.8,
        'temp': 36.5 + ((random % 10) / 100), // 36.5 to 36.59
        'snore': random > 950, // occasional mock snore
      });
    });
  }
}
