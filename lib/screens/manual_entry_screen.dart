import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/reading_provider.dart';
import '../models/reading_model.dart';

class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  MeterType _selectedType = MeterType.agua;
  final _valueController = TextEditingController();
  final _apartmentController = TextEditingController();

  void _saveReading() {
    if (_formKey.currentState!.validate()) {
      final value = double.parse(_valueController.text);
      final apartmentId = _apartmentController.text;

      final newReading = Reading(
        id: DateTime.now().toString(),
        type: _selectedType,
        value: value,
        date: DateTime.now(),
        apartmentId: apartmentId,
      );

      Provider.of<ReadingProvider>(context, listen: false).addReading(newReading);
      
      Navigator.of(context).pop(); // Go back to Home
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva Lectura Manual'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              DropdownButtonFormField<MeterType>(
                value: _selectedType,
                decoration: const InputDecoration(labelText: 'Tipo de Contador'),
                items: MeterType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type.name.toUpperCase()),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedType = value!;
                  });
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _valueController,
                decoration: const InputDecoration(labelText: 'Valor de Lectura'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor ingresa un valor';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Ingresa un número válido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _apartmentController,
                decoration: const InputDecoration(labelText: 'ID Apartamento / Piso'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor ingresa el ID del apartamento';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveReading,
                child: const Text('Guardar Lectura'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
