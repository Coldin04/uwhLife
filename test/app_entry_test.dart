import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/features/apps/models/app_entry.dart';

AppEntry _entry(Map<String, dynamic> overrides) {
  return AppEntry.fromJson(<String, dynamic>{
    'name': '应用',
    'category': '教务',
    'icon': 'apps_rounded',
    'color': '0EA5E9',
    'url': 'https://example.com',
    ...overrides,
  });
}

void main() {
  group('AppEntry', () {
    test('maps native destinations', () {
      expect(
        _entry(<String, dynamic>{
          'nativeDestination': 'paycode',
        }).nativeDestination,
        AppNativeDestination.payCode,
      );
      expect(
        _entry(<String, dynamic>{
          'nativeDestination': 'schedule',
        }).nativeDestination,
        AppNativeDestination.schedule,
      );
      expect(_entry(<String, dynamic>{}).nativeDestination, isNull);
      expect(
        _entry(<String, dynamic>{'nativeDestination': '未知'}).nativeDestination,
        isNull,
      );
    });

    test('reads the app scheme and keeps url as the fallback', () {
      final entry = _entry(<String, dynamic>{
        'appScheme': 'cxstudy://cxstudy',
        'url': 'https://apps.chaoxing.com',
      });

      expect(entry.appScheme, 'cxstudy://cxstudy');
      expect(entry.url, 'https://apps.chaoxing.com');
      expect(_entry(<String, dynamic>{}).appScheme, isNull);
    });
  });

  group('assets/app_list.json', () {
    final entries =
        (jsonDecode(File('assets/app_list.json').readAsStringSync()) as List)
            .cast<Map<String, dynamic>>();

    test('every entry parses and has a usable target', () {
      expect(entries, isNotEmpty);
      for (final json in entries) {
        final entry = AppEntry.fromJson(json);
        expect(entry.name, isNotEmpty, reason: '$json');
        expect(
          entry.url.isNotEmpty || entry.nativeDestination != null,
          isTrue,
          reason: '${entry.name} 既没有 url 也没有原生入口',
        );
        // 图标 key 必须在注册表里，否则会静默退化成默认图标。
        expect(
          iconRegistry.containsKey(json['icon']),
          isTrue,
          reason: '${entry.name} 的图标 ${json['icon']} 未注册',
        );
      }
    });

    test('names are unique', () {
      final names = entries.map((json) => json['name']).toList();
      expect(names.toSet().length, names.length);
    });

    test('scheme entries always carry a fallback url', () {
      final schemeEntries = entries
          .map(AppEntry.fromJson)
          .where((entry) => entry.appScheme != null);

      expect(schemeEntries, isNotEmpty);
      for (final entry in schemeEntries) {
        expect(entry.url, isNotEmpty, reason: '${entry.name} 缺少兜底地址');
      }
    });
  });
}
