enum MeterType {
  agua,
  luz
}

class Reading {
  final String id;
  final MeterType type;
  final double value;
  final DateTime date;
  final String apartmentId;
  final bool isMeterChange;

  Reading({
    required this.id,
    required this.type,
    required this.value,
    required this.date,
    required this.apartmentId,
    this.isMeterChange = false,
  });
}
