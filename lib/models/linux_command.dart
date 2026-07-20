import 'dart:convert';

class LinuxCommandExample {
  final String example;
  final String note;

  LinuxCommandExample({required this.example, required this.note});

  factory LinuxCommandExample.fromMap(Map<String, dynamic> map) {
    return LinuxCommandExample(
      example: map['example'] as String? ?? '',
      note: map['note'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {'example': example, 'note': note};
  }
}

class LinuxCommand {
  final int? id;
  final String command;
  final String descriptionZh;
  final String descriptionEn;
  final List<LinuxCommandExample> examples;
  final DateTime createdAt;
  final DateTime updatedAt;

  LinuxCommand({
    this.id,
    required this.command,
    required this.descriptionZh,
    required this.descriptionEn,
    this.examples = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'command': command,
      'description_zh': descriptionZh,
      'description_en': descriptionEn,
      'examples': examples.map((e) => e.toMap()).toList(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory LinuxCommand.fromMap(Map<String, dynamic> map) {
    List<LinuxCommandExample> parsedExamples = [];
    final examplesRaw = map['examples'];
    if (examplesRaw is String && examplesRaw.isNotEmpty && examplesRaw != '[]') {
      try {
        final list = (jsonDecode(examplesRaw) as List).cast<Map<String, dynamic>>();
        parsedExamples = list.map((e) => LinuxCommandExample.fromMap(e)).toList();
      } catch (_) {}
    } else if (examplesRaw is List) {
      parsedExamples = examplesRaw
          .map((e) => LinuxCommandExample.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }

    return LinuxCommand(
      id: map['id'] as int?,
      command: map['command'] as String,
      descriptionZh: map['description_zh'] as String? ?? '',
      descriptionEn: map['description_en'] as String? ?? '',
      examples: parsedExamples,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  LinuxCommand copyWith({
    int? id,
    String? command,
    String? descriptionZh,
    String? descriptionEn,
    List<LinuxCommandExample>? examples,
  }) {
    return LinuxCommand(
      id: id ?? this.id,
      command: command ?? this.command,
      descriptionZh: descriptionZh ?? this.descriptionZh,
      descriptionEn: descriptionEn ?? this.descriptionEn,
      examples: examples ?? this.examples,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
