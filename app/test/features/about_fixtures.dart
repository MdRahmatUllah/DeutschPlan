import 'package:deutschplan/features/me/about_screen.dart';
import 'package:deutschplan/features/me/licences_screen.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// The MIT licence's opening, enough for [licenceKind] to name it.
const String mit =
    'Permission is hereby granted, free of charge, to any person obtaining '
    'a copy of this software.';

/// The Licences artboard's packages.
final List<Licence> artboardPackages = <Licence>[
  for (final (name, kind) in <(String, String)>[
    ('flutter', 'BSD-3-Clause'),
    ('sqflite', 'BSD-2-Clause'),
    ('go_router', 'BSD-3-Clause'),
    ('onnxruntime', 'MIT'),
    ('llama.cpp', 'MIT'),
    ('fsrs', 'MIT'),
  ])
    (name: name, kind: kind, asset: null, text: '$name licence'),
];

/// M9 and M8 as the artboards draw them: version 1.0.0 (build 41), the
/// course of 21 Sep 2026, and six packages.
List<Override> aboutStub() => <Override>[
  appVersionProvider.overrideWith(
    (ref) async => (version: '1.0.0', build: '41'),
  ),
  contentFactsProvider.overrideWith(
    (ref) async => (
      version: '202609210900',
      builtAt: DateTime(2026, 9, 21, 9),
      words: 5594,
      grammar: 182,
      sentences: 11188,
    ),
  ),
  packageLicencesProvider.overrideWith((ref) async => artboardPackages),
];
