import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/reading_provider.dart';
import '../models/reading_model.dart';
import '../services/google_sheets_service.dart';
import 'login_screen.dart';
import '../services/google_sheets_service.dart';
import 'login_screen.dart';
import 'manual_entry_screen.dart';
import 'visualization_screen.dart';
import 'summary_screen.dart';


import '../services/google_sheets_service.dart'; // Import service
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final String username;
  final int? sessionRowIndex;

  const HomeScreen({
    super.key, 
    required this.username, 
    this.sessionRowIndex
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Si la app se cierra o se pone en segundo plano (detached o paused)
    // Intentar registrar salida si tenemos sessionRowIndex
    if (state == AppLifecycleState.detached && widget.sessionRowIndex != null) {
      _performLogoutLog();
    }
  }

  Future<void> _performLogoutLog() async {
    try {
      final service = GoogleSheetsService();
      // Ojo: Esto es una llamada async en un momento crítico (cierre app).
      // Puede no completarse siempre, pero es lo mejor que podemos hacer sin plugins nativos complejos.
      await service.logLogout(SPREADSHEET_ID, widget.sessionRowIndex!);
    } catch (e) {
      print("Error logging logout on close: $e");
    }
  }

  Future<void> _logout() async {
    if (widget.sessionRowIndex != null) {
      await _performLogoutLog();
    }
    
    if (mounted) {
       Navigator.of(context).pushReplacement(
         MaterialPageRoute(builder: (context) => const LoginScreen()),
       );
    }
  }

  @override
  Widget build(BuildContext context) {
    final readings = Provider.of<ReadingProvider>(context).readings;

    return Scaffold(
      appBar: AppBar(
        title: Text('Hola, ${widget.username}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_chart),
            tooltip: 'Resumen Mensual',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SummaryScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.show_chart),
            tooltip: 'Visualizar',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const VisualizationScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar Sesión',
            onPressed: _logout,
          ),
        ],
      ),
      body: readings.isEmpty
          ? const Center(
              child: Text('No hay lecturas registradas.\nPulsa + para añadir una.'),
            )
          : ListView.builder(
              itemCount: readings.length,
              itemBuilder: (context, index) {
                final reading = readings[index];
                return ListTile(
                  leading: Icon(
                    reading.type == MeterType.agua
                        ? Icons.water_drop
                        : Icons.lightbulb,
                    color: reading.type == MeterType.agua
                        ? Colors.blue
                        : Colors.orange,
                  ),
                  title: Text('${reading.type.name.toUpperCase()} - ${reading.value}'),
                  subtitle: Text('Apto: ${reading.apartmentId} - ${DateFormat('dd/MM/yyyy HH:mm').format(reading.date)}'),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const ManualEntryScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
