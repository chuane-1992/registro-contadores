import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/reading_provider.dart';
import '../models/reading_model.dart';
import '../services/google_sheets_service.dart';

// TODO: REEMPLAZA ESTO CON EL ID DE TU HOJA DE CALCULO
// Lo encuentras en la URL: docs.google.com/spreadsheets/d/[ESTE_CODIGO_LARGO]/edit
const String SPREADSHEET_ID = '10Vlo8n5D68mTHW3JwD6xkNno3LItr0tqoSojNQg50h4';

class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  MeterType _selectedType = MeterType.agua;
  final _valueController = TextEditingController();
  
  // Date selection
  DateTime _selectedDate = DateTime.now();

  // Apartment selection
  String? _selectedApartment;
  List<String> _apartments = [];
  bool _isLoadingApartments = true;
  bool _isCheckingReading = false;
  String? _errorMessage;

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
          _checkExistingReading(); // Check reading for default selection
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingApartments = false;
        _errorMessage = 'Error cargando pisos: $e';
      });
    }
  }

  Future<void> _checkExistingReading() async {
    if (_selectedApartment == null) return;

    setState(() => _isCheckingReading = true);
    try {
      final service = GoogleSheetsService();
      final existingValue = await service.getReading(
        SPREADSHEET_ID, 
        _selectedApartment!, 
        _selectedType, 
        _selectedDate
      );

      if (existingValue != null) {
        _valueController.text = existingValue.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lectura existente cargada'), duration: Duration(seconds: 1)),
        );
      } else {
        _valueController.clear();
      }
    } catch (e) {
      print("Error checking reading: $e");
    } finally {
       if (mounted) setState(() => _isCheckingReading = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _checkExistingReading();
    }
  }

  Future<void> _saveReading() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedApartment == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor selecciona un apartamento')),
        );
        return;
      }

      setState(() => _isLoadingApartments = true); 

      try {
        final value = double.parse(_valueController.text);
        
        // Guardar en Google Sheets con la fecha seleccionada
        final service = GoogleSheetsService();
        await service.saveReading(
          SPREADSHEET_ID, 
          _selectedApartment!, 
          _selectedType, 
          value, 
          _selectedDate
        );

        final newReading = Reading(
          id: DateTime.now().toString(),
          type: _selectedType,
          value: value,
          date: _selectedDate,
          apartmentId: _selectedApartment!,
        );
        if (mounted) {
           Provider.of<ReadingProvider>(context, listen: false).addReading(newReading);
           Navigator.of(context).pop();
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('¡Lectura guardada en Excel correctamente!')),
           );
        }

      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error guardando en Excel: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoadingApartments = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Formato de fecha simple
    final dateStr = "${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}";

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva Lectura Manual'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.red.shade100,
                  child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                ),
              
              // Selector de Fecha
              ListTile(
                title: const Text("Fecha de Lectura"),
                subtitle: Text(dateStr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () => _selectDate(context),
              ),
              const Divider(),

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
                  _checkExistingReading();
                },
              ),
              const SizedBox(height: 10),
              
              // Apartment Dropdown
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
                        _checkExistingReading();
                      },
                      validator: (value) => value == null ? 'Requerido' : null,
                    ),

              const SizedBox(height: 10),
              TextFormField(
                controller: _valueController,
                decoration: InputDecoration(
                  labelText: 'Valor de Lectura',
                  suffixIcon: _isCheckingReading 
                    ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
                    : null
                ),
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
              
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoadingApartments ? null : _saveReading,
                child: const Text('Guardar Lectura'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
