import 'package:flutter/material.dart';
import '../services/google_sheets_service.dart';
import 'manual_entry_screen.dart'; // Access to SPREADSHEET_ID

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  bool _isLoading = false;
  List<List<dynamic>> _data = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _data = [];
    });

    try {
      final service = GoogleSheetsService();
      // 1. Actualizar Año/Mes en el Excel
      await service.updateViewDate(SPREADSHEET_ID, _selectedMonth, _selectedYear);
      
      // 2. Leer la tabla resultante (fórmulas)
      final result = await service.fetchViewTable(SPREADSHEET_ID);
      
      setState(() {
        _data = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error actualizando/cargando resumen: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resumen Mensual (Excel)')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Month Dropdown
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _selectedMonth,
                    decoration: const InputDecoration(labelText: 'Mes'),
                    items: List.generate(12, (index) {
                      return DropdownMenuItem(
                        value: index + 1,
                        child: Text('${index + 1}'),
                      );
                    }),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedMonth = val);
                        _loadSummary();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                // Year Dropdown
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _selectedYear,
                    decoration: const InputDecoration(labelText: 'Año'),
                    items: List.generate(5, (index) {
                       final year = DateTime.now().year - 2 + index;
                       return DropdownMenuItem(value: year, child: Text('$year'));
                    }),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedYear = val);
                        _loadSummary();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadSummary,
                )
              ],
            ),
          ),
          
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator())),
            
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ),

          if (!_isLoading && _data.isEmpty && _errorMessage == null)
            const Expanded(child: Center(child: Text("No se recibieron datos de la hoja 'View'."))),

          if (!_isLoading && _data.isNotEmpty)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: () {
                    // Lógica de procesamiento de cabecera doble (Fila 3 y 4 del Excel)
                    if (_data.length < 2) return const Center(child: Text("Formato de tabla insuficiente."));
                    
                    final List<dynamic> catRow = _data[0]; 
                    final List<dynamic> unitRow = _data[1]; 
                    
                    // Las filas de datos son de la 5 a la 13 (índices 2 a 10)
                    final List<List<dynamic>> apartmentRows = _data.length > 2 
                        ? _data.sublist(2, _data.length >= 11 ? 11 : _data.length).where((row) => row.isNotEmpty).toList()
                        : [];

                    // La fila 15 es el total (índice 12 si hay 13 filas o más)
                    List<dynamic>? totalRow;
                    if (_data.length >= 13) {
                      totalRow = _data[12];
                    }

                    // Forzar 5 columnas (A-E)
                    final int columnCount = 5;

                    // Crear cabeceras combinadas
                    String lastCategory = '';
                    final List<Map<String, dynamic>> combinedHeaders = [];

                    for (int i = 0; i < columnCount; i++) {
                      String cat = i < catRow.length ? catRow[i]?.toString().trim() ?? '' : '';
                      String unit = i < unitRow.length ? unitRow[i]?.toString().trim() ?? '' : '';
                      
                      if (cat.isNotEmpty) lastCategory = cat;
                      
                      combinedHeaders.add({
                        'category': lastCategory,
                        'unit': unit,
                      });
                    }

                    return Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columnSpacing: 20,
                                headingRowHeight: 70,
                                dataRowHeight: 48,
                                dividerThickness: 0.5,
                                headingRowColor: MaterialStateProperty.all(Colors.blue.shade50),
                                columns: combinedHeaders.asMap().entries.map((entry) {
                                  final int idx = entry.key;
                                  final header = entry.value;
                                  final String category = header['category'].toString().toLowerCase();
                                  final String unit = header['unit'].toString();
                                  
                                  IconData? icon;
                                  Color color = Colors.black87;
                                  
                                  if (category.contains('agua')) {
                                    icon = Icons.water_drop;
                                    color = Colors.blue.shade700;
                                  } else if (category.contains('luz')) {
                                    icon = Icons.bolt;
                                    color = Colors.orange.shade700;
                                  } else if (idx == 0) {
                                    icon = Icons.home;
                                  }

                                  return DataColumn(
                                    label: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (icon != null) Icon(icon, size: 14, color: color),
                                            if (icon != null) const SizedBox(width: 4),
                                            Text(
                                              header['category'].toString().toUpperCase().isEmpty ? '...' : header['category'].toString().toUpperCase(), 
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold, 
                                                fontSize: 11,
                                                color: color,
                                              )
                                            ),
                                          ],
                                        ),
                                        if (unit.isNotEmpty)
                                          Text(
                                            unit,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade600,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                rows: apartmentRows.asMap().entries.map((entry) {
                                  final int rowIndex = entry.key;
                                  final List<dynamic> row = entry.value;
                                  
                                  return DataRow(
                                    color: MaterialStateProperty.resolveWith<Color?>((states) {
                                      if (rowIndex % 2 != 0) return Colors.blue.withOpacity(0.02);
                                      return null;
                                    }),
                                    cells: List.generate(columnCount, (i) {
                                      final String cellValue = i < row.length ? row[i]?.toString() ?? '' : '';
                                      return DataCell(
                                        Text(
                                          cellValue,
                                          style: TextStyle(
                                            fontWeight: i == 0 ? FontWeight.bold : FontWeight.w500,
                                            fontSize: 13,
                                          ),
                                        ),
                                      );
                                    }),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                        if (totalRow != null && totalRow.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              border: Border(top: BorderSide(color: Colors.grey.shade300, width: 2)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "TOTAL ACUMULADO", 
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)
                                ),
                                Row(
                                  children: [
                                    _buildTotalItem(
                                      icon: Icons.water_drop,
                                      color: Colors.blue.shade700,
                                      label: "Agua:",
                                      value: totalRow.length > 2 ? totalRow[2].toString() : "0",
                                    ),
                                    const SizedBox(width: 20),
                                    _buildTotalItem(
                                      icon: Icons.bolt,
                                      color: Colors.orange.shade700,
                                      label: "Luz:",
                                      value: totalRow.length > 4 ? totalRow[4].toString() : "0",
                                    ),
                                  ],
                                )
                              ],
                            ),
                          )
                      ],
                    );
                  }(),
                ),
              ),
            ),
          const SizedBox(height: 10),
          const Text("Datos obtenidos directamente de la pestaña 'View'", style: TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
  Widget _buildTotalItem({required IconData icon, required Color color, required String label, required String value}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(width: 4),
        Text(
          value, 
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)
        ),
      ],
    );
  }
}
