enum PersonalAliasKind { food, activity }

class PersonalAlias {
  const PersonalAlias({
    required this.id,
    required this.locale,
    required this.kind,
    required this.phrase,
    required this.normalizedPhrase,
    required this.canonicalId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String locale;
  final PersonalAliasKind kind;
  final String phrase;
  final String normalizedPhrase;
  final String canonicalId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'locale': locale,
        'kind': kind.name,
        'phrase': phrase,
        'normalizedPhrase': normalizedPhrase,
        'canonicalId': canonicalId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
      };

  factory PersonalAlias.fromJson(Map<String, dynamic> json) => PersonalAlias(
        id: json['id'] as String,
        locale: json['locale'] as String,
        kind: PersonalAliasKind.values.byName(json['kind'] as String),
        phrase: json['phrase'] as String,
        normalizedPhrase: json['normalizedPhrase'] as String,
        canonicalId: json['canonicalId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        deletedAt: json['deletedAt'] == null
            ? null
            : DateTime.parse(json['deletedAt'] as String),
      );
}
