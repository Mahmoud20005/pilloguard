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
  DateTime? _startTime;
  DateTime? _endTime;

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
    if (latestSession == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final sessionId = latestSession['id'] as int;
    final readings = await DatabaseHelper.instance.getSessionData(sessionId);
    final snoreEvents = await DatabaseHelper.instance.getSnoreEvents(sessionId);
    _startTime = DateTime.tryParse(latestSession['startTime'] as String);
    final endTime = latestSession['endTime'] as String?;
    _endTime = endTime == null ? null : DateTime.tryParse(endTime);
    _processRealData(readings, snoreEvents);
  }

  void _processRealData(
    List<Map<String, dynamic>> readings,
    List<Map<String, dynamic>> snoreEvents,
  ) {
    _heartRateSpots.clear();
    _snoreBarGroups.clear();
    
    int totalHr = 0;
    int totalSpo2 = 0;
    
    for (int i = 0; i < readings.length; i++) {
      final reading = readings[i];
      final hr = (reading['heartRate'] as num?)?.toInt();
      final spo2 = (reading['spO2'] as num?)?.toInt();
      if (hr != null) {
        totalHr += hr;
        _heartRateSpots.add(FlSpot(i.toDouble(), hr.toDouble()));
      }
      if (spo2 != null) totalSpo2 += spo2;
    }

    final hrCount = _heartRateSpots.length;
    final spo2Count = readings.where((r) => r['spO2'] != null).length;
    final temperatures = readings
        .map((r) => (r['temperature'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    _avgHr = hrCount == 0 ? 0 : (totalHr / hrCount).round();
    _avgSpo2 = spo2Count == 0 ? 0 : (totalSpo2 / spo2Count).round();
    _avgTemp = temperatures.isEmpty
        ? 0
        : temperatures.reduce((a, b) => a + b) / temperatures.length;
    _totalSnores = snoreEvents.length;
    for (final event in snoreEvents) {
      final timestamp = DateTime.tryParse(event['timestamp'] as String);
      if (timestamp == null) continue;
      final hour = timestamp.difference(_startTime ?? timestamp).inHours;
      final existing = _snoreBarGroups.indexWhere((group) => group.x == hour);
      if (existing >= 0) {
        final group = _snoreBarGroups[existing];
        final count = (group.barRods.first.toY + 1).clamp(0, 50).toDouble();
        _snoreBarGroups[existing] = BarChartGroupData(
          x: hour,
          barRods: [BarChartRodData(toY: count, color: Colors.orangeAccent)],
        );
      } else {
        _snoreBarGroups.add(BarChartGroupData(
          x: hour,
          barRods: [BarChartRodData(toY: 1, color: Colors.orangeAccent)],
        ));
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                if (_startTime == null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: Text('No data available for a sleep session.'),
                  )
                else
                  Text(
                    'Session: ${_startTime!.toLocal()} - ${_endTime?.toLocal() ?? 'In progress'}',
                    style: const TextStyle(color: Colors.grey),
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
                    _buildStatCard('Total Snores', _totalSnores == 0 ? 'No data available' : '$_totalSnores', Icons.mic, Colors.orange),
                    _buildStatCard('Avg Heart Rate', _avgHr == 0 ? 'No data available' : '$_avgHr bpm', Icons.favorite, Colors.redAccent),
                    _buildStatCard('Avg SpO2', _avgSpo2 == 0 ? 'No data available' : '$_avgSpo2 %', Icons.water_drop, Colors.lightBlue),
                    _buildStatCard('Avg Temp', _avgTemp == 0 ? 'No data available' : '${_avgTemp.toStringAsFixed(1)} °C', Icons.thermostat, Colors.pinkAccent),
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
            color: Colors.deepPurple.withValues(alpha: 0.3),
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
                _startTime == null ? 'Insufficient data' : 'Prototype summary',
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
                color: Colors.redAccent.withValues(alpha: 0.15),
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
