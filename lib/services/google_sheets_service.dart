import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';
import '../models/reading_model.dart';
import 'package:intl/intl.dart';

class GoogleSheetsService {
  // Scopes needed for the API (Updated to allow writing)
  static const _scopes = [sheets.SheetsApi.spreadsheetsScope];

  /// Obtiene los nombres de las pestañas (hojas) del Excel.
  /// Asume que cada pestaña corresponde a un apartamento (ej. "1ro", "2A").
  Future<List<String>> fetchApartments(String spreadsheetId) async {
    try {
      final client = await _getAuthenticatedClient();
      final sheetsApi = sheets.SheetsApi(client);

      final spreadsheet = await sheetsApi.spreadsheets.get(spreadsheetId);
      client.close();

      if (spreadsheet.sheets == null) return [];

      final sheetTitles = spreadsheet.sheets!
          .map((sheet) => sheet.properties?.title ?? '')
          .where((title) => title.isNotEmpty)
          // Filtrar pestañas que no son apartamentos (case-insensitive para mayor seguridad)
          .where((title) {
            final t = title.toLowerCase();
            return !['recibo', 'total', 'view', 'usuarios', 'registros'].contains(t);
          })
          .toList();

      return sheetTitles;
    } catch (e) {
      print('Error fetching apartments: $e');
      rethrow;
    }
  }

  /// Busca la fila correspondiente al mes actual y guarda la lectura.
  /// columna B (index 1) = Agua
  /// columna F (index 5) = Luz
  Future<void> saveReading(String spreadsheetId, String apartmentTab, MeterType type, double value, DateTime date) async {
    final client = await _getAuthenticatedClient();
    final sheetsApi = sheets.SheetsApi(client);

    try {
      // 1. Leer columna A (Fechas) de la pestaña seleccionada
      // Nota: Asumimos formato dd/MM/yyyy o similar en el Excel.
      final range = '$apartmentTab!A:A'; 
      final response = await sheetsApi.spreadsheets.values.get(spreadsheetId, range);
      
      if (response.values == null) throw Exception('No se encontraron fechas en la columna A');

      // 2. Buscar la fila que coincida con el mes y año actual
      // Buscamos coincidencia aproximada (mismo mes y año)
      int rowIndex = -1;
      
      // Ajuste: Los índices de Google Sheets empiezan en 1, pero la lista values empieza en 0.
      // Si values[0] es la fila 1 (encabezado), values[n] es fila n+1.
      for (int i = 0; i < response.values!.length; i++) {
        final row = response.values![i];
        if (row.isEmpty) continue;
        
        final cellValue = row.first.toString();
        try {
          // Intentamos parsear la fecha. El formato puede variar, intentamos estándar.
          // En la captura se ve: 1/1/2020, 1/5/2025 (d/M/yyyy)
          // Nota: Google Sheets a veces devuelve números de serie para fechas, pero la API JSON suele devolver Strings formateados.
          
          List<String> parts = cellValue.split('/');
          if (parts.length == 3) {
            int month = int.parse(parts[1]);
            int year = int.parse(parts[2]);
            
            if (month == date.month && year == date.year) {
              rowIndex = i + 1; // 1-based index for A1 notation
              break;
            }
          }
        } catch (e) {
          // Ignorar celdas que no sean fechas (headers, vacías, etc)
        }
      }

      if (rowIndex == -1) {
        throw Exception('No se encontró una fila para la fecha ${date.month}/${date.year} en la hoja $apartmentTab');
      }

      // 3. Escribir dato
      // Agua -> Columna B (B)
      // Luz -> Columna F (F)
      String columnLetter = (type == MeterType.agua) ? 'B' : 'F';
      String cellRange = '$apartmentTab!$columnLetter$rowIndex';
      
      final valueRange = sheets.ValueRange(
        range: cellRange,
        values: [[value]], // Array de arrays
      );

      await sheetsApi.spreadsheets.values.update(
        valueRange, 
        spreadsheetId, 
        cellRange, 
        valueInputOption: 'USER_ENTERED' // Para que Excel lo interprete como número
      );

    } finally {
      client.close();
    }
  }

  /// Obtiene la lectura existente para una fecha y tipo dado. Retorna null si no existe.
  Future<double?> getReading(String spreadsheetId, String apartmentTab, MeterType type, DateTime date) async {
    final client = await _getAuthenticatedClient();
    final sheetsApi = sheets.SheetsApi(client);

    try {
      final range = '$apartmentTab!A:A'; 
      final response = await sheetsApi.spreadsheets.values.get(spreadsheetId, range);
      
      if (response.values == null) return null;

      int rowIndex = -1;
      for (int i = 0; i < response.values!.length; i++) {
        final row = response.values![i];
        if (row.isEmpty) continue;
        
        final cellValue = row.first.toString();
        try {
          List<String> parts = cellValue.split('/');
          if (parts.length == 3) {
            int month = int.parse(parts[1]);
            int year = int.parse(parts[2]);
            
            if (month == date.month && year == date.year) {
              rowIndex = i + 1;
              break;
            }
          }
        } catch (e) {
          // ignore
        }
      }

      if (rowIndex == -1) return null;

      // Leer la celda específica
      String columnLetter = (type == MeterType.agua) ? 'B' : 'F';
      String cellRange = '$apartmentTab!$columnLetter$rowIndex';
      
      final cellResponse = await sheetsApi.spreadsheets.values.get(spreadsheetId, cellRange);
      
      if (cellResponse.values != null && cellResponse.values!.isNotEmpty && cellResponse.values!.first.isNotEmpty) {
        // Limpiar el valor (ej. "123,45" -> 123.45, quitar símbolos de moneda si hay)
        String rawValue = cellResponse.values!.first.first.toString();
        // Simple limpieza: reemplazar coma por punto, quitar letras
        rawValue = rawValue.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
        return double.tryParse(rawValue);
      }
      
      return null;

    } catch (e) {
      print('Error getting reading: $e');
      return null;
    } finally {
      client.close();
    }
  }

  Future<Map<String, List<Reading>>> fetchApartmentHistory(String spreadsheetId, String apartmentTab) async {
    final client = await _getAuthenticatedClient();
    final sheetsApi = sheets.SheetsApi(client);

    try {
    // Leer columnas A-G: [Fecha (0), Agua Lectura (1), Agua Consumo (2), ..., Luz Lectura (5), Luz Consumo (6)]
    final range = '$apartmentTab!A2:G'; 
    final response = await sheetsApi.spreadsheets.values.get(spreadsheetId, range);
    
    final List<Reading> waterReadings = [];
    final List<Reading> lightReadings = [];

    if (response.values != null) {
      // Primero extraemos y parseamos todo de forma segura
      List<Map<String, dynamic>> parsedRows = [];
      
      for (var row in response.values!) {
        if (row.isEmpty || row.length < 1) continue;
        
        DateTime? date;
        try {
           final dateStr = row[0].toString();
           List<String> parts = dateStr.split('/');
           if (parts.length == 3) {
             date = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
           }
        } catch (_) {}
        if (date == null) continue;

        parsedRows.add({
          'date': date,
          'row': row,
        });
      }

      // IMPORTANTE: Ordenar por fecha para comparar lecturas consecutivas correctamente
      parsedRows.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

      double? lastWaterReading;
      double? lastLightReading;

      for (var item in parsedRows) {
        final date = item['date'] as DateTime;
        final row = item['row'] as List<dynamic>;

        // AGUA: Lectura (Index 1), Consumo (Index 2)
        if (row.length > 2) {
           final readingStr = row[1].toString().replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
           final consumptionStr = row[2].toString().replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
           
           final reading = double.tryParse(readingStr);
           final consumption = double.tryParse(consumptionStr);

           if (consumption != null) {
             bool isChange = false;
             if (reading != null && lastWaterReading != null && reading < lastWaterReading) {
               isChange = true;
             }
             if (reading != null) lastWaterReading = reading;

             waterReadings.add(Reading(
               id: 'W-${date.millisecondsSinceEpoch}', 
               type: MeterType.agua, 
               value: consumption, 
               date: date, 
               apartmentId: apartmentTab,
               isMeterChange: isChange,
              ));
           }
        }

        // LUZ: Lectura (Index 5), Consumo (Index 6)
        if (row.length > 6) {
           final readingStr = row[5].toString().replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
           final consumptionStr = row[6].toString().replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
           
           final reading = double.tryParse(readingStr);
           final consumption = double.tryParse(consumptionStr);

           if (consumption != null) {
             bool isChange = false;
             if (reading != null && lastLightReading != null && reading < lastLightReading) {
               isChange = true;
             }
             if (reading != null) lastLightReading = reading;

             lightReadings.add(Reading(
               id: 'L-${date.millisecondsSinceEpoch}', 
               type: MeterType.luz, 
               value: consumption, 
               date: date, 
               apartmentId: apartmentTab,
               isMeterChange: isChange,
              ));
           }
        }
      }
    }
    
    // Ya están ordenadas por la lógica anterior
    return {
      'agua': waterReadings,
      'luz': lightReadings,
    };

    } catch (e) {
      print('Error fetching history: $e');
      return {'agua': [], 'luz': []};
    } finally {
      client.close();
    }
  }

  Future<bool> validateUser(String spreadsheetId, String username, String password) async {
    final client = await _getAuthenticatedClient();
    final sheetsApi = sheets.SheetsApi(client);

    try {
      final range = 'Usuarios!A:B'; // Col A = User, Col B = Pass
      final response = await sheetsApi.spreadsheets.values.get(spreadsheetId, range);

      if (response.values == null) return false;

      for (var row in response.values!) {
        if (row.length < 2) continue;
        final userSheet = row[0].toString().trim();
        final passSheet = row[1].toString().trim();

        // Comparación simple (sensible a mayúsculas/minúsculas)
        if (userSheet == username && passSheet == password) {
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Error validating user: $e');
      return false;
    } finally {
      client.close();
    }
  }

  /// Registra el inicio de sesión en la hoja 'Registros'. Retorna el índice de la fila (1-based).
  Future<int?> logLogin(String spreadsheetId, String username) async {
    final client = await _getAuthenticatedClient();
    final sheetsApi = sheets.SheetsApi(client);

    try {
      final now = DateTime.now();
      final dateStr = DateFormat('dd/MM/yyyy').format(now);
      final timeStr = DateFormat('HH:mm:ss').format(now);

      // Escribir en Registros!A:C (Usuario, Fecha, Hora Entrada)
      // Append añade al final
      final valueRange = sheets.ValueRange(
        values: [[username, dateStr, timeStr, '']], // D (Salida) vacío
      );

      final response = await sheetsApi.spreadsheets.values.append(
        valueRange, 
        spreadsheetId, 
        'Registros!A:D', 
        valueInputOption: 'USER_ENTERED'
      );

      // Obtener el índice de la fila donde se escribió
      // updatedRange suele ser "Registros!A15:D15"
      if (response.updates != null && response.updates!.updatedRange != null) {
        final range = response.updates!.updatedRange!;
        // Extraer el número final
        final regex = RegExp(r'!A(\d+):');
        final match = regex.firstMatch(range);
        if (match != null) {
          return int.parse(match.group(1)!);
        }
        // Fallback: parsear todo el string si el regex falla o formato diferente
        final parts = range.split('!A');
        if (parts.length > 1) {
           final rowPart = parts[1].split(':');
           return int.tryParse(rowPart[0]);
        }
      }
      return null;
    } catch (e) {
      print('Error logging login: $e');
      return null;
    } finally {
      client.close();
    }
  }

  /// Registra la hora de salida en la columna D de la fila indicada.
  Future<void> logLogout(String spreadsheetId, int rowIndex) async {
    final client = await _getAuthenticatedClient();
    final sheetsApi = sheets.SheetsApi(client);

    try {
      final now = DateTime.now();
      final timeStr = DateFormat('HH:mm:ss').format(now);

      final cellRange = 'Registros!D$rowIndex';
      final valueRange = sheets.ValueRange(values: [[timeStr]]);

      await sheetsApi.spreadsheets.values.update(
        valueRange, 
        spreadsheetId, 
        cellRange, 
        valueInputOption: 'USER_ENTERED'
      );
    } catch (e) {
      print('Error logging logout: $e');
    } finally {
      client.close();
    }
  }

  Future<List<Map<String, dynamic>>> fetchMonthlySummary(String spreadsheetId, int month, int year) async {
    final client = await _getAuthenticatedClient();
    final sheetsApi = sheets.SheetsApi(client);
    final List<Map<String, dynamic>> summaryData = [];

    try {
      final apartments = await fetchApartments(spreadsheetId);
      
      for (var apartment in apartments) {
        try {
          // Leer rango A:H para tener fecha y precios
          final range = '$apartment!A2:H'; 
          final response = await sheetsApi.spreadsheets.values.get(spreadsheetId, range);

          if (response.values != null) {
            for (var row in response.values!) {
              if (row.isEmpty || row.length < 1) continue;
              
              // Chequear fecha (Col A)
              String dateStr = row[0].toString();
              List<String> parts = dateStr.split('/');
              if (parts.length != 3) continue;

              int? rMonth = int.tryParse(parts[1]);
              int? rYear = int.tryParse(parts[2]);

              if (rMonth == month && rYear == year) {
                // Encontrado!
                // C: Agua Consumo (Index 2)
                // D: Agua Precio (Index 3)
                // G: Luz Consumo (Index 6)
                // H: Luz Precio (Index 7)
                
                String waterVal = (row.length > 2) ? row[2].toString() : '';
                String waterPrice = (row.length > 3) ? row[3].toString() : '';
                String lightVal = (row.length > 6) ? row[6].toString() : '';
                String lightPrice = (row.length > 7) ? row[7].toString() : '';

                summaryData.add({
                  'apartment': apartment,
                  'water': waterVal,
                  'waterPrice': waterPrice,
                  'light': lightVal,
                  'lightPrice': lightPrice,
                });
                break; // Ya encontramos el mes para este piso
              }
            }
          }
        } catch (e) {
          print("Error fetching summary for $apartment: $e");
        }
      }
      
      return summaryData;

    } catch (e) {
      print('Error fetching monthly summary: $e');
      return [];
    } finally {
      client.close();
    }
  }

  /// Actualiza las celdas B1 (Año) y B2 (Mes) en la pestaña 'View'.
  Future<void> updateViewDate(String spreadsheetId, int month, int year) async {
    final client = await _getAuthenticatedClient();
    final sheetsApi = sheets.SheetsApi(client);

    try {
      // B1 = Año, B2 = Mes
      final valueRange = sheets.ValueRange(
        range: 'View!B1:B2',
        majorDimension: 'COLUMNS',
        values: [[year, month]],
      );

      await sheetsApi.spreadsheets.values.update(
        valueRange, 
        spreadsheetId, 
        'View!B1:B2', 
        valueInputOption: 'USER_ENTERED'
      );
    } catch (e) {
      print('Error updating view date: $e');
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Lee el rango A3:E15 de la pestaña 'View'.
  Future<List<List<dynamic>>> fetchViewTable(String spreadsheetId) async {
    final client = await _getAuthenticatedClient();
    final sheetsApi = sheets.SheetsApi(client);

    try {
      final response = await sheetsApi.spreadsheets.values.get(spreadsheetId, 'View!A3:E15');
      return response.values ?? [];
    } catch (e) {
      print('Error fetching view table: $e');
      return [];
    } finally {
      client.close();
    }
  }

  Future<AutoRefreshingAuthClient> _getAuthenticatedClient() async {
    final credentialsJson = await rootBundle.loadString('assets/credentials.json');
    final accountCredentials = ServiceAccountCredentials.fromJson(json.decode(credentialsJson));
    return clientViaServiceAccount(accountCredentials, _scopes);
  }
}
