import 'package:flutter/foundation.dart';
import '../models/reading_model.dart';

class ReadingProvider with ChangeNotifier {
  final List<Reading> _readings = [];

  List<Reading> get readings => [..._readings];

  void addReading(Reading reading) {
    _readings.add(reading);
    notifyListeners();
  }

  // Future expansion: method to fetch readings from a database, etc.
}
