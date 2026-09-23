class Address {
  final String id;
  final String label;
  final String line1;
  final String? line2;
  final String? landmark;
  final String city;
  final String state;
  final String? pincode;
  final double? lat;
  final double? lng;
  final bool isDefault;

  const Address({
    required this.id,
    required this.label,
    required this.line1,
    this.line2,
    this.landmark,
    required this.city,
    required this.state,
    this.pincode,
    this.lat,
    this.lng,
    this.isDefault = false,
  });

  String get fullText => [
        line1,
        if (line2 != null && line2!.trim().isNotEmpty) line2,
        if (landmark != null && landmark!.trim().isNotEmpty) landmark,
        city,
        state,
        if (pincode != null && pincode!.trim().isNotEmpty) pincode,
      ].join(', ');

  factory Address.fromJson(Map<String, dynamic> json) => Address(
        id: json['id'] as String,
        label: json['label'] as String? ?? 'Home',
        line1: json['line1'] as String,
        line2: json['line2'] as String?,
        landmark: json['landmark'] as String?,
        city: json['city'] as String? ?? 'Hajipur',
        state: json['state'] as String? ?? 'Bihar',
        pincode: json['pincode'] as String?,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        isDefault: json['is_default'] as bool? ?? false,
      );

  Map<String, dynamic> toInsertJson(String customerId) => {
        'customer_id': customerId,
        'label': label,
        'line1': line1,
        'line2': line2,
        'landmark': landmark,
        'city': city,
        'state': state,
        'pincode': pincode,
        'lat': lat,
        'lng': lng,
        'is_default': isDefault,
      };
}
