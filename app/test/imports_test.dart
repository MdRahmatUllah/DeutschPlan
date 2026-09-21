import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// docs/05-dev-guide/coding-standards.md: the project uses the standalone
/// design-system packages. The in-SDK Material and Cupertino libraries are
/// deprecated from the November 2026 Flutter release and removed in 2027, so an
/// import of either is a build-breaking change waiting to happen.
void main() {
  test(
    'no file under lib/ imports the in-SDK Material or Cupertino libraries',
    () {
      const banned = <String, String>{
        'package:flutter/material.dart': 'package:material_ui/material_ui.dart',
        'package:flutter/cupertino.dart':
            'package:cupertino_ui/cupertino_ui.dart',
      };

      final offenders = <String>[];
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final source = file.readAsStringSync();
        for (final entry in banned.entries) {
          if (source.contains("'${entry.key}'") ||
              source.contains('"${entry.key}"')) {
            offenders.add(
              '${file.path}: imports ${entry.key} — use ${entry.value}',
            );
          }
        }
      }

      expect(offenders, isEmpty, reason: offenders.join('\n'));
    },
  );
}
