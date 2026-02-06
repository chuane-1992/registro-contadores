import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/reading_provider.dart';
import '../models/reading_model.dart';
import 'manual_entry_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final readings = Provider.of<ReadingProvider>(context).readings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de Contadores'),
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
