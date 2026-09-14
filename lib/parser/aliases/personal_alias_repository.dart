import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'personal_alias.dart';

const _prefsKey = 'parser_personal_aliases';

String generatePersonalAliasId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Local-only for Phase 1 -- same SharedPreferences-JSON-list pattern as the
/// existing `DailyEntryRepository`/`WaterRepository` in main.dart. Shaped so
/// it can later grow a server-sync layer without changing this API.
class PersonalAliasRepository {
  PersonalAliasRepository(this._prefs);
  final SharedPreferences _prefs;

  List<PersonalAlias> _readAll() {
    final raw = _prefs.getString(_prefsKey);
    if (raw == null) return [];
    final list = json.decode(raw) as List<dynamic>;
    return list
        .map((e) => PersonalAlias.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _writeAll(List<PersonalAlias> aliases) async {
    await _prefs.setString(
      _prefsKey,
      json.encode(aliases.map((a) => a.toJson()).toList()),
    );
  }

  List<PersonalAlias> list({bool includeDeleted = false}) {
    final all = _readAll();
    return includeDeleted ? all : all.where((a) => !a.isDeleted).toList();
  }

  String? resolve(String normalizedPhrase, PersonalAliasKind kind, String locale) {
    for (final alias in _readAll()) {
      if (alias.isDeleted) continue;
      if (alias.kind != kind) continue;
      if (alias.locale != locale) continue;
      if (alias.normalizedPhrase == normalizedPhrase) return alias.canonicalId;
    }
    return null;
  }

  Future<PersonalAlias> add({
    required String locale,
    required PersonalAliasKind kind,
    required String phrase,
    required String normalizedPhrase,
    required String canonicalId,
  }) async {
    final now = DateTime.now();
    final alias = PersonalAlias(
      id: generatePersonalAliasId(),
      locale: locale,
      kind: kind,
      phrase: phrase,
      normalizedPhrase: normalizedPhrase,
      canonicalId: canonicalId,
      createdAt: now,
      updatedAt: now,
    );
    final all = _readAll()..add(alias);
    await _writeAll(all);
    return alias;
  }

  Future<void> softDelete(String id) async {
    final all = _readAll();
    final index = all.indexWhere((a) => a.id == id);
    if (index == -1) return;
    final existing = all[index];
    all[index] = PersonalAlias(
      id: existing.id,
      locale: existing.locale,
      kind: existing.kind,
      phrase: existing.phrase,
      normalizedPhrase: existing.normalizedPhrase,
      canonicalId: existing.canonicalId,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
      deletedAt: DateTime.now(),
    );
    await _writeAll(all);
  }
}
