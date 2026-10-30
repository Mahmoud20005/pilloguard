import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService extends ChangeNotifier {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  static const serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const telemetryUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  static const commandUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const targetDeviceName = 'PilloGuard';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _telemetryCharacteristic;
  BluetoothCharacteristic? _commandCharacteristic;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _telemetrySubscription;
  bool _isScanning = false;
  bool _isConnected = false;

  final StreamController<Map<String, dynamic>> _sensorDataController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  bool get isMockMode => false;
  Stream<Map<String, dynamic>> get sensorDataStream =>
      _sensorDataController.stream;

  Future<void> startScanning() async {
    if (_isScanning || _isConnected) return;
    if (!await FlutterBluePlus.isSupported) {
      throw StateError('Bluetooth is not supported on this device.');
    }

    _isScanning = true;
    notifyListeners();
    await _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen(
      _handleScanResults,
      onError: (Object error, StackTrace stack) {
        _finishScanning();
      },
    );

    try {
      await FlutterBluePlus.startScan(
        withNames: [targetDeviceName],
        timeout: const Duration(seconds: 10),
      );
    } on Object {
      _finishScanning();
      rethrow;
    }
  }

  void _handleScanResults(List<ScanResult> results) {
    for (final result in results) {
      final name = result.device.platformName.isNotEmpty
          ? result.device.platformName
          : result.advertisementData.advName;
      if (name == targetDeviceName) {
        unawaited(FlutterBluePlus.stopScan());
        unawaited(_connectToDevice(result.device));
        return;
      }
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _finishScanning();
    await _connectionSubscription?.cancel();
    _device = device;
    _connectionSubscription = device.connectionState.listen(
      (state) => unawaited(_handleConnectionState(state)),
    );

    try {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );
    } on Object {
      await _disconnectSubscriptions();
      rethrow;
    }
  }

  Future<void> _handleConnectionState(BluetoothConnectionState state) async {
    if (state == BluetoothConnectionState.connected) {
      try {
        final services = await _device!.discoverServices();
        final service = services.where((item) =>
            item.uuid.str.toLowerCase() == serviceUuid).firstOrNull;
        if (service == null) {
          throw StateError('PilloGuard service was not found.');
        }
        _telemetryCharacteristic = service.characteristics
            .where((item) => item.uuid.str.toLowerCase() == telemetryUuid)
            .firstOrNull;
        _commandCharacteristic = service.characteristics
            .where((item) => item.uuid.str.toLowerCase() == commandUuid)
            .firstOrNull;
        if (_telemetryCharacteristic == null ||
            !_telemetryCharacteristic!.properties.notify) {
          throw StateError('PilloGuard telemetry characteristic was not found.');
        }
        if (_commandCharacteristic == null ||
            !_commandCharacteristic!.properties.write) {
          throw StateError('PilloGuard command characteristic was not found.');
        }
        await _telemetryCharacteristic!.setNotifyValue(true);
        await _telemetrySubscription?.cancel();
        _telemetrySubscription =
            _telemetryCharacteristic!.lastValueStream.listen(_parseTelemetry);
        _isConnected = true;
        notifyListeners();
      } on Object {
        await stopScanningAndDisconnect();
      }
    } else if (state == BluetoothConnectionState.disconnected) {
      _isConnected = false;
      _telemetryCharacteristic = null;
      notifyListeners();
    }
  }

  void _parseTelemetry(List<int> bytes) {
    if (bytes.isEmpty) return;
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
      if (decoded is! Map<String, dynamic>) return;
      final numericFields = [
        'left_pressure',
        'center_pressure',
        'right_pressure',
        'temperature',
        'atmospheric_pressure',
        'accel_x',
        'accel_y',
        'accel_z',
        'gyro_x',
        'gyro_y',
        'gyro_z',
        'proximity',
      ];
      for (final field in numericFields) {
        if (decoded[field] != null && decoded[field] is! num) return;
      }
      if (decoded['active_zone'] is! String) return;
      _sensorDataController.add(decoded);
    } on FormatException {
      // Ignore malformed packets; the next telemetry notification can recover.
    }
  }

  Future<void> writeCommand(String command) async {
    final characteristic = _commandCharacteristic;
    if (!_isConnected || characteristic == null) {
      throw StateError('PilloGuard command characteristic is not connected.');
    }
    if (!characteristic.properties.write) {
      throw StateError('PilloGuard command characteristic is not writable.');
    }
    try {
      await characteristic.write(utf8.encode(command), withoutResponse: false);
    } on Object catch (error, stackTrace) {
      debugPrint('PilloGuard command write failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> stopScanningAndDisconnect() async {
    await FlutterBluePlus.stopScan();
    _finishScanning();
    await _disconnectSubscriptions();
    final device = _device;
    _device = null;
    if (device != null) {
      await device.disconnect();
    }
    if (_isConnected) {
      _isConnected = false;
      notifyListeners();
    }
  }

  void _finishScanning() {
    if (!_isScanning) return;
    _isScanning = false;
    notifyListeners();
  }

  Future<void> _disconnectSubscriptions() async {
    await _telemetrySubscription?.cancel();
    await _connectionSubscription?.cancel();
    _telemetrySubscription = null;
    _connectionSubscription = null;
    _telemetryCharacteristic = null;
    _commandCharacteristic = null;
  }

  @override
  void dispose() {
    unawaited(stopScanningAndDisconnect());
    unawaited(_sensorDataController.close());
    super.dispose();
  }
}
