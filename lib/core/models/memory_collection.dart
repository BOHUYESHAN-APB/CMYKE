import 'memory_record.dart';
import 'memory_tier.dart';

class MemoryCollection {
  MemoryCollection({
    required this.id,
    required this.tier,
    required this.name,
    required this.createdAt,
    List<MemoryRecord>? records,
    this.locked = false,
  }) : records = records ?? [];

  final String id;
  final MemoryTier tier;
  String name;
  final DateTime createdAt;
  final List<MemoryRecord> records;
  final bool locked;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tier': tier.key,
        'name': name,
        'created_at': createdAt.toIso8601String(),
        'records': records.map((record) => record.toJson()).toList(),
        'locked': locked,
      };

  factory MemoryCollection.fromJson(Map<String, dynamic> json) =>
      MemoryCollection(
        id: json['id'] as String,
        tier: MemoryTier.values.firstWhere(
          (tier) => tier.key == json['tier'],
          orElse: () => MemoryTier.context,
        ),
        name: json['name'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        records: (json['records'] as List<dynamic>? ?? [])
            .map((entry) => MemoryRecord.fromJson(entry as Map<String, dynamic>))
            .toList(),
        locked: json['locked'] as bool? ?? false,
      );
}
