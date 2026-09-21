# Coding standards

- **Lints:** `flutter_lints` + `riverpod_lint` + project rules in `analysis_options.yaml` (`prefer_final_locals`, `avoid_dynamic_calls`, `require_trailing_commas`, `always_declare_return_types`). CI fails on any warning.
- **Imports:** `package:material_ui/material_ui.dart` / `package:cupertino_ui/cupertino_ui.dart` — never `package:flutter/material.dart`. Relative imports inside a feature; package imports across layers.
- **Domain purity:** `lib/domain/**` must not import Flutter, drift or any plugin. Enforced by a test that greps imports.
- **Models:** `freezed` for all value types; unions for `CardKind`, `ExamSection`, `SearchTier`, `TtsState`.
- **Providers:** codegen only; families keyed by primitive ids; `keepAlive` only where `state-management.md` allows.
- **Database:** every write in a transaction; DAOs return streams for lists the UI watches; never query in `build()`.
- **Dates:** `DateTime` in local time for plan dates (`isoDate` strings `YYYY-MM-DD`), UTC ISO-8601 for timestamps; the `clock` provider is the only source of "now".
- **Strings:** ARB with descriptions; German UI copy that is content (e.g. "Tag geschafft!") is still ARB, marked `@` as fixed German.
- **Accessibility:** every icon button has a `tooltip` and semantics label; every custom painter has a semantics node.
- **Logging:** `logging` package; no `print`; no analytics of any kind.
- **Commits:** Conventional Commits; PR titles reference the screen or engine (`feat(study): FR-T2-08 swipe to rate`).
