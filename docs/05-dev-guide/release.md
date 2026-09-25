# Release

## Versioning
`pubspec.yaml` `version: MAJOR.MINOR.PATCH+BUILD`. Content has its own `content_version` (build timestamp) shown in About; a content-only release bumps PATCH.

## Android
- `flutter build appbundle --release --obfuscate --split-debug-info=build/symbols`
- 16 KB page-size check: `flutter build` with AGP 9 and all native plugins ≥ their compliant versions (`flutter_onnxruntime ≥ 1.5.1`, `llamadart` current).
- Play Console: data-safety form = "no data collected"; declare mic (Speaking) and notifications permissions.

## iOS
- Deployment target 16.0; SPM; `flutter build ipa --release`.
- Privacy manifest: no tracking; mic usage string; notifications; background modes `fetch` + `processing` for downloads/widget refresh.
- Widget extension target shares App Group `group.app.deutschplan`.

## Checklist
1. `make lint test goldens-verify` green (not `make goldens`, which rewrites every golden instead of checking it); integration smoke on both platforms.
2. Content rebuilt from the workbooks in `data/`; manifest diff reviewed (`make content-diff`: added/removed/changed words).
3. Licences screen regenerated (`dart run` licence collector) and model licence texts current.
4. `ENABLE_HYMT_DOWNLOAD` flag decision recorded in `decisions.md` for the target regions.
5. Tag `vX.Y.Z`, changelog entry, store notes in EN and BN.
