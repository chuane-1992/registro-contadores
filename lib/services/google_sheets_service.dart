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
            return !['recibo', 'total', 'view'].contains(t);
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

  Future<AutoRefreshingAuthClient> _getAuthenticatedClient() async {
    final credentialsJson = await rootBundle.loadString('assets/credentials.json');
    final accountCredentials = ServiceAccountCredentials.fromJson(json.decode(credentialsJson));
    return clientViaServiceAccount(accountCredentials, _scopes);
  }
}
