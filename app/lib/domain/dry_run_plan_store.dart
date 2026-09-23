import 'package:deutschplan/domain/plan_engine.dart';

/// A [PlanStore] that reads through to [_inner] and keeps every write to
/// itself, so [PlanEngine.previewDay] can run the real `openDay` and leave no
/// rows behind.
///
/// Tomorrow's numbers on Today's done state and on T6 come from here
/// (FR-T6-02): the same planning code, not a second estimate of it. Reads made
/// after a write see that write, because the engine reads back what it planned
/// — a day whose new words were just picked is "already planned" for the rest
/// of the run.
class DryRunPlanStore implements PlanStore {
  DryRunPlanStore(this._inner);

  final PlanStore _inner;

  /// Rows the run added, by day and kind, in the order it added them.
  final Map<(PlanDate, PlanKind), List<String>> _added =
      <(PlanDate, PlanKind), List<String>>{};

  bool _lastPlannedSet = false;
  PlanDate? _lastPlanned;

  bool _stepChanged = false;
  ActiveStep? _active;
  String? _completed;

  Iterable<String> get _addedNew => <String>[
    for (final entry in _added.entries)
      if (entry.key.$2 == PlanKind.newWord) ...entry.value,
  ];

  @override
  Future<ActiveStep?> activeStep() async =>
      _stepChanged ? _active : _inner.activeStep();

  @override
  Future<List<String>> unplannedWords(
    String sublevelCode, {
    required int limit,
  }) async {
    final taken = _addedNew.toSet();
    // Ask for enough that the ones this run already planned can be dropped.
    final words = await _inner.unplannedWords(
      sublevelCode,
      limit: limit + taken.length,
    );
    return words.where((uid) => !taken.contains(uid)).take(limit).toList();
  }

  @override
  Future<List<RevisionCandidate>> revisionCandidates() =>
      _inner.revisionCandidates();

  @override
  Future<List<String>> plannedOn(PlanDate date, PlanKind kind) async {
    final stored = await _inner.plannedOn(date, kind);
    return <String>[
      ...stored,
      for (final uid in _added[(date, kind)] ?? const <String>[])
        if (!stored.contains(uid)) uid,
    ];
  }

  @override
  Future<List<String>> grammarDueOn(PlanDate date) => _inner.grammarDueOn(date);

  @override
  Future<void> addToPlan(
    PlanDate date,
    PlanKind kind,
    List<String> uids,
  ) async {
    final present = await plannedOn(date, kind);
    (_added[(date, kind)] ??= <String>[]).addAll(
      uids.where((uid) => !present.contains(uid)),
    );
  }

  @override
  Future<List<String>> backlogBefore(PlanDate today) async {
    // A row this run planned is never done, so any before [today] is open.
    final added = <(PlanDate, String)>[
      for (final entry in _added.entries)
        if (entry.key.$2 == PlanKind.newWord &&
            daysBetween(entry.key.$1, today) > 0)
          for (final uid in entry.value) (entry.key.$1, uid),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    return <String>[
      for (final (_, uid) in added) uid,
      ...await _inner.backlogBefore(today),
    ];
  }

  @override
  Future<PlanDate?> lastPlannedDate() async =>
      _lastPlannedSet ? _lastPlanned : _inner.lastPlannedDate();

  @override
  Future<void> setLastPlannedDate(PlanDate date) async {
    _lastPlannedSet = true;
    _lastPlanned = date;
  }

  @override
  Future<String?> stepAfter(String sublevelCode) =>
      _inner.stepAfter(sublevelCode);

  @override
  Future<void> completeStep(String sublevelCode, PlanDate on) async {
    _stepChanged = true;
    _active = null;
    _completed = sublevelCode;
  }

  @override
  Future<void> enroll(ActiveStep step) async {
    _stepChanged = true;
    _active = step;
  }

  @override
  Future<bool> hasEverEnrolled() async =>
      _stepChanged || await _inner.hasEverEnrolled();

  @override
  Future<String?> lastCompletedStep() async =>
      _completed ?? await _inner.lastCompletedStep();

  @override
  Future<Set<PlanDate>> activeDays(
    PlanDate today, {
    required int lookbackDays,
  }) => _inner.activeDays(today, lookbackDays: lookbackDays);

  @override
  Future<(int, int)> newItemProgress(PlanDate today) async {
    final (planned, introduced) = await _inner.newItemProgress(today);
    final added = <String>[
      for (final entry in _added.entries)
        if (entry.key.$2 == PlanKind.newWord &&
            daysBetween(entry.key.$1, today) >= 0)
          ...entry.value,
    ];
    return (planned + added.length, introduced);
  }

  @override
  Future<int> openPlanItems(PlanDate date) async {
    final added = <String>[
      for (final entry in _added.entries)
        if (entry.key.$1 == date) ...entry.value,
    ];
    return await _inner.openPlanItems(date) + added.length;
  }

  @override
  Future<MeasuredSeconds> measuredSeconds() => _inner.measuredSeconds();
}
