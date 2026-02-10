import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/google_sheets_service.dart';
import '../models/reading_model.dart';
import 'manual_entry_screen.dart'; // To access SPREADSHEET_ID

class VisualizationScreen extends StatefulWidget {
  const VisualizationScreen({super.key});

  @override
  State<VisualizationScreen> createState() => _VisualizationScreenState();
}

class _VisualizationScreenState extends State<VisualizationScreen> {
  String? _selectedApartment;
  List<String> _apartments = [];
  bool _isLoadingApartments = true;
  bool _isLoadingData = false;
  String? _errorMessage;

  List<Reading> _waterReadings = [];
  List<Reading> _lightReadings = [];

  @override
  void initState() {
    super.initState();
    _loadApartments();
  }

  Future<void> _loadApartments() async {
    try {
      final service = GoogleSheetsService();
      final apartments = await service.fetchApartments(SPREADSHEET_ID);
      setState(() {
        _apartments = apartments;
        _isLoadingApartments = false;
        if (apartments.isNotEmpty) {
          _selectedApartment = apartments.first;
          _loadHistory();
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingApartments = false;
        _errorMessage = 'Error cargando pisos: $e';
      });
    }
  }

  Future<void> _loadHistory() async {
    if (_selectedApartment == null) return;
    
    setState(() {
      _isLoadingData = true;
      _errorMessage = null;
    });

    try {
      final service = GoogleSheetsService();
      final history = await service.fetchApartmentHistory(SPREADSHEET_ID, _selectedApartment!);
      
      setState(() {
        final now = DateTime.now();
        
        // Filtrar para mostrar solo hasta el mes actual
        _waterReadings = history['agua']!.where((r) {
          return r.date.year < now.year || (r.date.year == now.year && r.date.month <= now.month);
        }).toList();
        
        _lightReadings = history['luz']!.where((r) {
          return r.date.year < now.year || (r.date.year == now.year && r.date.month <= now.month);
        }).toList();
        
        _isLoadingData = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingData = false;
        _errorMessage = 'Error cargando historial: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visualizar Consumo')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Dropdown
            _isLoadingApartments
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<String>(
                    value: _selectedApartment,
                    decoration: const InputDecoration(labelText: 'Apartamento / Piso'),
                    items: _apartments.map((apt) {
                      return DropdownMenuItem(
                        value: apt,
                        child: Text(apt),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedApartment = value;
                      });
                      _loadHistory();
                    },
                  ),
            
            const SizedBox(height: 20),

            if (_errorMessage != null)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),

            if (_isLoadingData)
               const Expanded(child: Center(child: CircularProgressIndicator())),

            if (!_isLoadingData && _selectedApartment != null)
              Expanded(
                child: _waterReadings.isEmpty && _lightReadings.isEmpty 
                  ? const Center(child: Text("No hay datos históricos."))
                  : Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(children: [
                              Container(width: 12, height: 12, color: Colors.blue),
                              const SizedBox(width: 4),
                              const Text("Agua"),
                            ]),
                            const SizedBox(width: 20),
                            Row(children: [
                              Container(width: 12, height: 12, color: Colors.orange),
                              const SizedBox(width: 4),
                              const Text("Luz"),
                            ]),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Expanded(child: _buildChart()),
                      ],
                    ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    // Combine dates to find range
    final allReadings = [..._waterReadings, ..._lightReadings];
    if (allReadings.isEmpty) return const SizedBox();

    allReadings.sort((a, b) => a.date.compareTo(b.date));

    // Calculate Max for normalization
    double maxWater = _waterReadings.fold(0, (prev, r) => r.value > prev ? r.value : prev);
    double maxLight = _lightReadings.fold(0, (prev, r) => r.value > prev ? r.value : prev);

    // Evitar división por cero
    if (maxWater == 0) maxWater = 100;
    if (maxLight == 0) maxLight = 100;

    // Buffer para que el pico no toque el techo
    maxWater *= 1.2;
    maxLight *= 1.2;

    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.blueGrey,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                // Recuperar valor original
                final isWater = spot.barIndex == 0;
                final rawValue = isWater ? (spot.y * maxWater) : (spot.y * maxLight);
                return LineTooltipItem(
                  '${isWater ? "Consumo Agua" : "Consumo Luz"}: ${rawValue.toStringAsFixed(1)}',
                  TextStyle(color: isWater ? Colors.blueAccent : Colors.orangeAccent),
                );
              }).toList();
            }
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                return Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Text(DateFormat('MM/yy').format(date), style: const TextStyle(fontSize: 10)),
                );
              },
              reservedSize: 30,
              // Intervalo dinámico según la duración de datos podría ser mejor, pero dejamos fijo por ahora
            ),
          ),
          leftTitles: AxisTitles(
            axisNameWidget: const Text("Luz (kWh)", style: TextStyle(color: Colors.orange, fontSize: 10)),
            sideTitles: SideTitles(
              showTitles: true, 
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                // Eje Izquierdo = LUZ (Orange)
                // Value va de 0 a 1. Recuperamos valor de Luz.
                final realValue = value * maxLight;
                if (value == 0) return const SizedBox();
                return Text(realValue.toStringAsFixed(0), style: const TextStyle(color: Colors.orange, fontSize: 10));
              },
            ),
          ),
          rightTitles: AxisTitles(
            axisNameWidget: const Text("Agua (m3)", style: TextStyle(color: Colors.blue, fontSize: 10)),
            sideTitles: SideTitles(
              showTitles: true, 
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                // Eje Derecho = AGUA (Blue)
                final realValue = value * maxWater;
                if (value == 0) return const SizedBox();
                return Text(realValue.toStringAsFixed(1), style: const TextStyle(color: Colors.blue, fontSize: 10));
              },
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(show: true, drawVerticalLine: true, verticalInterval: 2629800000 * 3),
        borderData: FlBorderData(show: true, border: Border.all(color: const Color(0xff37434d))),
        lineBarsData: [
          // Water Line (Blue) -> Mapped to Right Axis logic
          LineChartBarData(
            spots: _waterReadings.map((r) => FlSpot(r.date.millisecondsSinceEpoch.toDouble(), r.value / maxWater)).toList(),
            isCurved: true,
            color: Colors.blue,
            barWidth: 3,
            dotData: FlDotData(show: true),
          ),
          // Light Line (Orange) -> Mapped to Left Axis logic
          LineChartBarData(
            spots: _lightReadings.map((r) => FlSpot(r.date.millisecondsSinceEpoch.toDouble(), r.value / maxLight)).toList(),
            isCurved: true,
            color: Colors.orange,
            barWidth: 3,
            dotData: FlDotData(show: true),
          ),
        ],
        extraLinesData: ExtraLinesData(
          verticalLines: [
            ..._waterReadings.where((r) => r.isMeterChange).map((r) => VerticalLine(
              x: r.date.millisecondsSinceEpoch.toDouble(),
              color: Colors.black54,
              strokeWidth: 2,
              dashArray: [5, 5],
              label: VerticalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                labelResolver: (_) => "Cambio medidor Agua",
              ),
            )),
            ..._lightReadings.where((r) => r.isMeterChange).map((r) => VerticalLine(
              x: r.date.millisecondsSinceEpoch.toDouble(),
              color: Colors.black54,
              strokeWidth: 2,
              dashArray: [5, 5],
              label: VerticalLineLabel(
                show: true,
                alignment: Alignment.topLeft,
                style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                labelResolver: (_) => "Cambio medidor Luz",
              ),
            )),
          ],
        ),
        minY: 0,
        maxY: 1, // Normalized scale
      ),
    );
  }
}
