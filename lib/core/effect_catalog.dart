import 'dart:convert';
import 'package:flutter/services.dart';
import 'midi_protocol.dart';

class EffectCatalog {
  final Map<String, dynamic> _tables;
  EffectCatalog(this._tables);

  static Future<EffectCatalog> load() async => EffectCatalog(
    jsonDecode(await rootBundle.loadString('assets/editor_tables.json'))
        as Map<String, dynamic>,
  );

  List<String> models(int slot) => List<String>.from(
    (_tables['models'] as Map)[slotNames[slot]] ?? <String>[],
  );

  List<String> parameters(int slot, int type) {
    final name = slotNames[slot];
    final data = (_tables['params'] as Map)[name] as List;
    final count = (_tables['counts'] as Map)[name];
    if (name == 'DYN' || name == 'MOD') {
      return List<String>.from(data[type % data.length]);
    }
    if (name == 'EQ') {
      return List<String>.from(
        data[type % 3],
      ).take((count as List)[type % 3] as int).toList();
    }
    if (name == 'DLY') {
      return [
        ...List<String>.from(data[0]),
        (data[1] as List)[type % (data[1] as List).length] as String,
      ];
    }
    if (name == 'REV' && type == 7) {
      return ['SIZE', ...List<String>.from(data.skip(1))];
    }
    return List<String>.from(data).take(count as int).toList();
  }
}
