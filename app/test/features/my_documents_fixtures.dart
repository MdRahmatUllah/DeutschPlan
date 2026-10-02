import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/document_repository.dart';

/// The MyDocuments artboard's four rows (#1222), newest first. Noon UTC, so
/// the day is the same in any test machine's zone.
List<DocumentEntry> artboardDocuments() => <DocumentEntry>[
  _entry(4, 'Nebenkosten 2025', 'photo', '2026-10-02', pages: 4, added: 5),
  _entry(3, 'Termin beim Bürgeramt', 'paste', '2026-09-28', added: 3),
  _entry(2, 'Mietvertrag', 'pdf', '2026-09-20', pages: 6, added: 12),
  _entry(1, 'Elternbrief Schule', 'photo', '2026-09-12'),
];

DocumentEntry _entry(
  int id,
  String title,
  String source,
  String day, {
  int pages = 1,
  int added = 0,
}) => (
  document: Document(
    id: id,
    title: title,
    source: source,
    createdAt: '${day}T12:00:00.000Z',
    body: 'Sehr geehrte Frau Rahman,',
    pageCount: pages,
    wordCount: 40,
  ),
  added: added,
);

/// D3's repository in memory: the list as a stream, and what was renamed
/// and deleted.
class FakeMyDocuments extends Fake implements DocumentRepository {
  FakeMyDocuments([List<DocumentEntry>? entries])
    : entries = entries ?? artboardDocuments();

  List<DocumentEntry> entries;
  final List<int> deleted = <int>[];

  /// 18 MB, rounded up: the artboard's storage line.
  int bytes = 17 * 1024 * 1024 + 300 * 1024;

  final StreamController<List<DocumentEntry>> _changes =
      StreamController<List<DocumentEntry>>.broadcast();

  void _changed(List<DocumentEntry> next) {
    entries = next;
    _changes.add(next);
  }

  @override
  Stream<List<DocumentEntry>> watchAll() async* {
    yield entries;
    yield* _changes.stream;
  }

  @override
  Future<void> rename(int id, String title) async => _changed(<DocumentEntry>[
    for (final e in entries)
      e.document.id == id
          ? (document: e.document.copyWith(title: title), added: e.added)
          : e,
  ]);

  @override
  Future<void> delete(int id, {Directory? support}) async {
    deleted.add(id);
    bytes = 0;
    _changed(<DocumentEntry>[
      for (final e in entries)
        if (e.document.id != id) e,
    ]);
  }

  @override
  Future<int> imageBytes({Directory? support}) async => bytes;

  @override
  Future<int> count() async => entries.length;
}

/// D3 without a database.
List<Override> myDocumentsStub([FakeMyDocuments? documents]) => <Override>[
  documentRepositoryProvider.overrideWithValue(documents ?? FakeMyDocuments()),
];
