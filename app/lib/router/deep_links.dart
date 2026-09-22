import 'package:deutschplan/router/app_router.dart';

/// The app's own URL scheme. `navigation.md`: "Local scheme only."
///
/// Nothing on the web serves this, and nothing outside the phone can claim it
/// in a way the app would follow — the reminder notification and the home
/// screen widget are the only two things that send one.
const String deepLinkScheme = 'deutschplan';

/// Turns a `deutschplan://…` link into a location in the route table.
///
/// The two are not the same, and that is the whole reason this exists.
/// `deutschplan://exam/A1.2` names a *step*, and the step's exams live on a
/// tab of L2 — while `/exam/:attemptId` in the route table is the runner for
/// one attempt. Handing the link straight to the router would open an exam
/// with the attempt id "A1.2".
///
/// Returns [fallbackLocation] for anything it does not recognise, because a
/// link that arrived from a notification the learner tapped has to land
/// somewhere: `navigation.md`'s four shapes are what the app sends, and
/// anything else is a stale link from an older build.
String resolveDeepLink(Uri link) {
  // A link is identified by its *host*, not its path: `deutschplan://today`
  // has the word in the host and an empty path, and `deutschplan://word/x`
  // has `word` in the host and `/x` in the path. Reading `uri.path` alone
  // would make the first one indistinguishable from the second.
  final segments = <String>[
    if (link.host.isNotEmpty) link.host,
    ...link.pathSegments.where((segment) => segment.isNotEmpty),
  ];

  if (segments.isEmpty) return fallbackLocation;

  switch (segments) {
    // deutschplan://today
    case <String>['today']:
      return '/today';

    // deutschplan://learn/A2.1 — the step, opened on its Words tab.
    case <String>['learn']:
      return '/learn';
    case <String>['learn', final String code]:
      return '/learn/step/${Uri.encodeComponent(code)}';

    // deutschplan://word/<uid>?speak=1 — the widget's *Pronounce* action.
    // The query is carried through rather than acted on here: whether the
    // word plays is the screen's business, and a resolver that made noise
    // would be a surprising thing for a pure function to do.
    case <String>['word', final String uid]:
      final speak = link.queryParameters[speakParameter];
      return Uri(
        path: '/word/${Uri.encodeComponent(uid)}',
        queryParameters: speak == null
            ? null
            : <String, String>{speakParameter: speak},
      ).toString();

    // deutschplan://exam/A1.2 — the step's exam hub, which is a tab of L2 and
    // not the `/exam/:attemptId` runner.
    case <String>['exam', final String code]:
      return '/learn/step/${Uri.encodeComponent(code)}?tab=exams';

    default:
      return fallbackLocation;
  }
}

/// `?speak=1` on a word link. `widget.md` FR-X1-02: "the app plays on open".
const String speakParameter = 'speak';

/// The routes a deep link does not interrupt.
///
/// An exam is timed and FR-L12-04 makes leaving one a decision, with a dialog
/// and an abandoned attempt. A `go` is not a pop, so `ExamBackGuard` never
/// sees a link — and the reminder firing at 19:30 while the learner is
/// mid-exam is an ordinary sequence, not a contrived one. The link is
/// dropped rather than queued: it says "open Today", and Today will still be
/// there when they finish.
bool interruptible(String location) => !location.startsWith('/exam/');

/// The only value that asks for speech.
///
/// A truthy-string reading would make `?speak=0` play, which is the one value
/// someone writing that query would expect to be silent.
const String speakOn = '1';

/// Whether a link asks for the word to be spoken.
bool wantsSpeech(Uri location) =>
    location.queryParameters[speakParameter] == speakOn;
