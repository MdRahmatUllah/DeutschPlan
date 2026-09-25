# Goldens

`docs/05-dev-guide/testing.md`: every screen × light/dark/glass × phone/tablet.

## Adding a screen

```dart
// test/golden/today_golden_test.dart
import 'golden_harness.dart';

void main() => goldenTest('today', builder: (_) => const TodayScreen());
```

That is the whole test. It emits six files into `goldens/`:

```
today_light_phone.png   today_light_tablet.png
today_dark_phone.png    today_dark_tablet.png
today_glass_phone.png   today_glass_tablet.png
```

Narrow the matrix with `modes:` or `devices:` where a screen genuinely has no
tablet layout — but say so in the test, because the default is all six.

## Goldens run on one platform only

Golden files are pixel comparisons, and text rendering is not identical across
operating systems — hinting, subpixel positioning and antialiasing all differ.
These were generated on **Windows**. A diff on another platform is about the
renderer, not the design.

So they carry the `golden` tag and are excluded from `make test`:

```
make test            # everything except goldens — runs anywhere
make goldens-verify  # the pixel comparison — one platform
```

Goldens are verified on Windows only. CI is off (#302), so a PR's basic check
runs the goldens of the screens it touches, and the full suite runs them all
when a milestone completes (`getting-started.md`, "The check before a merge").

## Regenerating

Per file, for the screens your change touches (from `app/`):

```
flutter test --update-goldens test/golden/<screen>_golden_test.dart
```

`make goldens` rewrites the whole suite, including files you did not mean to
touch, and hides an unintended change among hundreds. Keep it for a deliberate
suite-wide change, such as a token that moves every screen, and then review
every image it changed.

**Goldens are the design contract.** Open the diff as images and check each
change was intended. A golden that changed because a token moved is the system
working; a golden that changed because a padding drifted is the bug it exists to
catch.

## Why fonts load in `test/flutter_test_config.dart`

Flutter runs that file once per suite, outside the fake-async zone. Loading
fonts inside a `testWidgets` body instead hangs forever — real file I/O never
completes there, and the first attempt at this sat for five minutes without
producing a frame.

It reads `FontManifest.json` rather than naming families, which picks up
**MaterialIcons** as well. Without it every icon renders as an empty square, and
the first goldens shipped with exactly that.

## Glass

Glass goldens render with blur allowed, so they show the frosted treatment. The
opaque fallback has its own tests in `test/core/theme/glass_capability_test.dart`
rather than a golden, because it is a decision about capability rather than a
layout.
