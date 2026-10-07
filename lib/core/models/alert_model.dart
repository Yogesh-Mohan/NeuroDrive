class AlertModel {
  final String id;
  final DateTime timestamp;
  final String riskLevel;
  final String message;
  final String source;

  AlertModel({
    required this.id,
    required this.timestamp,
    required this.riskLevel,
    required this.message,
    required this.source,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'riskLevel': riskLevel,
        'message': message,
        'source': source,
      };

  factory AlertModel.fromJson(Map<String, dynamic> json) => AlertModel(
        id: json['id'],
        timestamp: DateTime.parse(json['timestamp']),
        riskLevel: json['riskLevel'],
        message: json['message'],
        source: json['source'],
      );
}
