import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'splash_screen.dart';
import 'sleep_report_screen.dart';
import 'ble_service.dart';
import 'database.dart';
import 'snore_confirmation_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BleService()),
      ],
      child: const SnoreMonitorApp(),
    ),
  );
}

class SnoreMonitorApp extends StatelessWidget {
  const SnoreMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SleepGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF03DAC6),
          surface: Color(0xFF1E1E1E),
        ),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
      ),
      home: const SplashScreen(destination: DashboardScreen()),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  StreamSubscription? _sensorDataSubscription;
  Timer? _snoreIndicatorTimer;
  int? _sessionId;
  Future<int>? _sessionCreation;
  late final SnoreConfirmationGate _snoreGate;

  int _heartRate = 0;
  int _spO2 = 0;
  int _snoreCount = 0;
  double _pillowX = 0.0;
  double _pillowY = 0.0;
  double _bodyTemp = 0.0;
  final bool _snoreDetectedNow = false;

  @override
  void initState() {
    super.initState();
    final bleService = Provider.of<BleService>(context, listen: false);
    _snoreGate = SnoreConfirmationGate(
      writeConfirmedCommand: () => bleService.writeCommand('SNORE_CONFIRMED'),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Listen to BleService stream
    _sensorDataSubscription = bleService.sensorDataStream.listen((data) {
      if (!mounted) return;
      setState(() {
        _heartRate = (data['heart_rate'] as num?)?.toInt() ?? 0;
        _spO2 = (data['spo2'] as num?)?.toInt() ?? 0;
        _pillowX = (data['accel_x'] as num?)?.toDouble() ?? 0.0;
        _pillowY = (data['accel_y'] as num?)?.toDouble() ?? 0.0;
        _bodyTemp = (data['temperature'] as num?)?.toDouble() ?? 0.0;
      });
      unawaited(_persistTelemetry(data));
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _sensorDataSubscription?.cancel();
    _snoreIndicatorTimer?.cancel();
    _snoreGate.resetEpisode();
    unawaited(_endCurrentSession());
    super.dispose();
  }
  
  Future<void> _requestPermissionsAndScan(BleService bleService) async {
    if (bleService.isConnected || bleService.isScanning) {
      bleService.stopScanningAndDisconnect();
      await _endCurrentSession();
      _pulseController.stop();
      _pulseController.reset();
      setState(() {
        _heartRate = 0;
        _spO2 = 0;
        _snoreCount = 0;
        _pillowX = 0.0;
        _pillowY = 0.0;
        _bodyTemp = 0.0;
      });
      return;
    }

    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses.values.every((status) => status.isGranted)) {
      await bleService.startScanning();
      _pulseController.repeat(reverse: true);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissions required to scan for devices')),
        );
      }

    }
  }

  Future<void> _persistTelemetry(Map<String, dynamic> data) async {
    _sessionCreation ??=
        DatabaseHelper.instance.createSession(DateTime.now());
    _sessionId ??= await _sessionCreation!;
    await DatabaseHelper.instance.insertSensorReading(_sessionId!, data);
  }

  Future<void> _endCurrentSession() async {
    final sessionId = _sessionId ?? await _sessionCreation;
    if (sessionId == null) return;
    await DatabaseHelper.instance.endSession(sessionId, DateTime.now());
    _sessionId = null;
    _sessionCreation = null;
  }

  @override
  Widget build(BuildContext context) {
    final bleService = Provider.of<BleService>(context);
    final isMonitoring = bleService.isConnected;

    // Pulse only when scanning or monitoring
    if (bleService.isScanning || bleService.isConnected) {
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.reset();
      }
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('SleepGuard', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Dynamic Status Header
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: _snoreDetectedNow ? Colors.redAccent.withValues(alpha: 0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: _snoreDetectedNow ? Colors.redAccent : Colors.transparent),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_snoreDetectedNow) ...[
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      const Text("Snore Detected!", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ] else ...[
                      Icon(
                        bleService.isConnected ? Icons.bluetooth_connected : (bleService.isScanning ? Icons.bluetooth_searching : Icons.bluetooth),
                        color: bleService.isConnected ? Colors.blueAccent : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        bleService.isConnected
                          ? "PilloGuard Connected"
                          : (bleService.isScanning ? "Scanning..." : "Disconnected"),
                        style: TextStyle(
                          color: bleService.isConnected ? Colors.blueAccent : Colors.grey, 
                          fontWeight: FontWeight.bold
                        ),
                      ),
                    ]
                  ],
                ),
              ),
              const Spacer(),
              
              // Main Pulsing Button
              ScaleTransition(
                scale: _pulseAnimation,
                child: GestureDetector(
                  onTap: () => _requestPermissionsAndScan(bleService),
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: (bleService.isConnected || bleService.isScanning)
                            ? [Colors.deepPurple, Colors.indigo]
                            : [Theme.of(context).colorScheme.primary, Colors.blueAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: ((bleService.isConnected || bleService.isScanning) ? Colors.deepPurple : Theme.of(context).colorScheme.primary).withValues(alpha: 0.4),
                          blurRadius: 30,
                          spreadRadius: 10,
                        )
                      ],
                    ),
                    child: Center(
                      child: Text(
                        (bleService.isConnected || bleService.isScanning) ? 'STOP\nSLEEP' : 'START\nSLEEP',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 60),
              
              // Live Data Status Cards
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildDataCard(Icons.favorite, 'Heart Rate', isMonitoring ? '$_heartRate bpm' : '--', Colors.redAccent, isMonitoring),
                  _buildDataCard(Icons.water_drop, 'SpO2', isMonitoring ? '$_spO2 %' : '--', Colors.lightBlue, isMonitoring),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildDataCard(Icons.mic, 'Snores', isMonitoring ? '$_snoreCount' : '--', Colors.orange, isMonitoring),
                  _buildPillowVisualCard(isMonitoring),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildDataCard(Icons.thermostat, 'Body Temp', isMonitoring ? '${_bodyTemp.toStringAsFixed(1)} °C' : '--', Colors.pinkAccent, isMonitoring),
                  Expanded(child: Container(margin: const EdgeInsets.symmetric(horizontal: 6))), // Empty placeholder for alignment
                ],
              ),
              const Spacer(),
              
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SleepReportScreen()),
                  );
                },
                icon: const Icon(Icons.bar_chart),
                label: const Text('View Sleep Report'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Colors.white,
                  elevation: 5,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataCard(IconData icon, String title, String value, Color activeColor, bool isMonitoring) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isMonitoring ? activeColor.withValues(alpha: 0.3) : Colors.white10),
          boxShadow: isMonitoring ? [BoxShadow(color: activeColor.withValues(alpha: 0.1), blurRadius: 10)] : [],
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: isMonitoring ? activeColor : Colors.grey),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isMonitoring ? Colors.white : Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildPillowVisualCard(bool isMonitoring) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isMonitoring ? Colors.greenAccent.withValues(alpha: 0.3) : Colors.white10),
          boxShadow: isMonitoring ? [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.1), blurRadius: 10)] : [],
        ),
        child: Column(
          children: [
            Icon(Icons.bed, size: 28, color: isMonitoring ? Colors.greenAccent : Colors.grey),
            const SizedBox(height: 8),
            const Text('Pillow Axis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
            const SizedBox(height: 4),
            SizedBox(
              height: 25,
              child: Center(
                child: isMonitoring 
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.001) // Add perspective
                        ..rotateX(_pillowY)     // Y axis controls up/down tilt (pitch)
                        ..rotateY(_pillowX),    // X axis controls left/right tilt (roll)
                      child: Container(
                        width: 50,
                        height: 25,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 4, offset: const Offset(0, 4))
                          ],
                        ),
                      ),
                    )
                  : const Text('--', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
