import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'database.dart';

class SleepReportScreen extends StatefulWidget {
  const SleepReportScreen({super.key});

  @override
  State<SleepReportScreen> createState() => _SleepReportScreenState();
}

class _SleepReportScreenState extends State<SleepReportScreen> {
  final List<FlSpot> _heartRateSpots = [];
  final List<BarChartGroupData> _snoreBarGroups = [];
  int _totalSnores = 0;
  bool _isLoading = true;
  bool _isDemoData = false;

  int _avgHr = 0;
  int _avgSpo2 = 0;
  double _avgTemp = 0.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final latestSession = await DatabaseHelper.instance.getLatestSession();
    
    if (latestSession != null) {
      final sessionId = latestSession['id'] as int;
      final readings = await DatabaseHelper.instance.getSessionData(sessionId);
      
      if (readings.length > 10) {
        // We have enough real data
        _processRealData(readings);
        return;
      }
    }
    
    // Fallback to demo data for GitHub demo purposes
    _generateMockData();
  }

  void _processRealData(List<Map<String, dynamic>> readings) {
    _heartRateSpots.clear();
    _snoreBarGroups.clear();
    
    int totalHr = 0;
    int totalSpo2 = 0;
    
    // Just a simplistic mapping for demo purposes
    for (int i = 0; i < readings.length; i++) {
      final reading = readings[i];
      final hr = reading['heartRate'] as int;
      final spo2 = reading['spO2'] as int;
      
      totalHr += hr;
      totalSpo2 += spo2;
      
      // X axis is simply the reading index mapped to an 8 hour scale assuming we have ~readings.length over 8h
      double x = (i / readings.length) * 8;
      _heartRateSpots.add(FlSpot(x, hr.toDouble()));
    }

    _avgHr = (totalHr / readings.length).round();
    _avgSpo2 = (totalSpo2 / readings.length).round();
    _avgTemp = 36.5; // Fixed temp since it wasn't saved in schema
    _totalSnores = 0; // Requires snore table parsing which is out of scope for basic demo

    setState(() {
      _isLoading = false;
      _isDemoData = false;
    });
  }

  void _generateMockData() {
    final random = Random();
    
    _heartRateSpots.clear();
    _snoreBarGroups.clear();

    // Generate realistic heart rate line data (8 hours)
    for (double i = 0; i <= 8; i += 0.5) {
      double baseHr = 70 - 12 * sin(i / 8 * pi); 
      double noise = (random.nextDouble() * 4) - 2;
      _heartRateSpots.add(FlSpot(i, baseHr + noise));
    }

    // Generate snore bar data (8 hours)
    List<double> baseSnores = [5, 12, 28, 42, 35, 18, 8, 2];
    double totalSnoresCalc = 0;
    
    for (int i = 0; i < 8; i++) {
      double noise = (random.nextDouble() * 6) - 3; 
      double snores = (baseSnores[i] + noise).clamp(0, 50).toDouble();
      totalSnoresCalc += snores;
      
      _snoreBarGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: snores,
              gradient: const LinearGradient(
                colors: [Colors.orangeAccent, Colors.deepOrange],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
              width: 16,
              borderRadius: BorderRadius.circular(4),
            )
          ],
        ),
      );
    }
    
    _totalSnores = totalSnoresCalc.toInt();
    _avgHr = 64;
    _avgSpo2 = 97;
    _avgTemp = 36.4;

    setState(() {
      _isLoading = false;
      _isDemoData = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: const Text('Sleep Report', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isDemoData)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.blueAccent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Showing sample data. Start monitoring and save a session to view real data.",
                            style: GoogleFonts.outfit(color: Colors.blueAccent, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                _buildScoreHeader(),
                const SizedBox(height: 30),
                
                // Stats Grid
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.5,
                  children: [
                    _buildStatCard('Total Snores', '$_totalSnores', Icons.mic, Colors.orange),
                    _buildStatCard('Avg Heart Rate', '$_avgHr bpm', Icons.favorite, Colors.redAccent),
                    _buildStatCard('Avg SpO2', '$_avgSpo2 %', Icons.water_drop, Colors.lightBlue),
                    _buildStatCard('Avg Temp', '$_avgTemp °C', Icons.thermostat, Colors.pinkAccent),
                  ],
                ),
                const SizedBox(height: 40),

                // Heart Rate Chart
                Text('Heart Rate Over Night', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _buildHeartRateChart(),
                
                const SizedBox(height: 40),

                // Snore Chart
                Text('Snores Per Hour', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _buildSnoreChart(),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
    );
  }

  Widget _buildScoreHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.deepPurple, Colors.indigo],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 2,
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sleep Quality',
                style: GoogleFonts.outfit(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                '82 / 100',
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Icon(Icons.star_rounded, color: Colors.amber, size: 60),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Flexible(child: Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12), overflow: TextOverflow.ellipsis)),
            ],
          ),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildHeartRateChart() {
    return Container(
      height: 250,
      padding: const EdgeInsets.only(right: 16, left: 0, top: 24, bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1)),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: const TextStyle(color: Colors.grey, fontSize: 10)))),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22, getTitlesWidget: (val, meta) => Text('${val.toInt()}h', style: const TextStyle(color: Colors.grey, fontSize: 10)))),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: 8,
          minY: 50,
          maxY: 100,
          lineBarsData: [
            LineChartBarData(
              spots: _heartRateSpots,
              isCurved: true,
              color: Colors.redAccent,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.redAccent.withOpacity(0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSnoreChart() {
    return Container(
      height: 250,
      padding: const EdgeInsets.only(right: 16, left: 0, top: 24, bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 50,
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text('${value.toInt() + 1}h', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                ),
              ),
            ),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: const TextStyle(color: Colors.grey, fontSize: 10)))),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1)),
          borderData: FlBorderData(show: false),
          barGroups: _snoreBarGroups,
        ),
      ),
    );
  }
}
