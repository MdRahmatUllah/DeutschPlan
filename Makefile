# DeutschPlan developer entry points.
#
# docs/05-dev-guide/getting-started.md documents these; this file is what makes
# them real. Every target runs from the repository root.
#
# Note: lint uses `dart analyze`, NOT `flutter analyze`. The latter does not
# load the analysis_server plugin that riverpod_lint ships as, so it reports a
# clean run while every riverpod rule is silently inactive (ADR 18).

APP := app
DART := cd $(APP) &&

.DEFAULT_GOAL := help

.PHONY: help content gen gen-watch test goldens update-goldens lint format \
        release-android release-ios clean

help: ## List the targets
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

content: ## Excel -> content.db -> app/assets/db/content.db
	python tools/excel_to_sqlite.py
	python tools/verify_content.py
	@mkdir -p $(APP)/assets/db
	cp content/build/content.db $(APP)/assets/db/content.db
	@echo "content.db copied to $(APP)/assets/db/"

gen: ## Migration helpers, then build_runner: riverpod, freezed, drift, go_router
	$(DART) dart run drift_dev schema steps drift_schemas/ lib/data/db/schema_versions.dart
	$(DART) dart run drift_dev schema generate drift_schemas/ test/db/generated/
	$(DART) dart run build_runner build --delete-conflicting-outputs

schema-dump: ## Capture the CURRENT schema as a fixture. Run after bumping schemaVersion.
	$(DART) dart run drift_dev schema dump lib/data/db/app_database.dart drift_schemas/
	@echo
	@echo "Fixture written to app/drift_schemas/. Commit it — it is the only"
	@echo "record of this schema once user_schema.drift moves on. Then run"
	@echo "\`make gen\` and write the migration step."

gen-watch: ## build_runner in watch mode
	$(DART) dart run build_runner watch --delete-conflicting-outputs

test: ## Unit, widget and db tests. Goldens are separate - see below.
	$(DART) flutter test --exclude-tags golden

goldens-verify: ## Compare goldens. ONE platform only - see test/golden/README.md
	$(DART) flutter test test/golden

goldens: update-goldens ## Alias for update-goldens

update-goldens: ## Regenerate every golden. REVIEW THE IMAGE DIFF.
	$(DART) flutter test test/golden --update-goldens
	@echo
	@echo "Goldens rewritten. They are the design contract — open the diff as"
	@echo "images and check every change was intended before committing."

lint: ## Analyzer and formatter, as CI runs them
	$(DART) dart analyze --fatal-infos
	$(DART) dart format --output=none --set-exit-if-changed .

format: ## Apply the formatter
	$(DART) dart format .

release-android: ## Signed app bundle (see docs/05-dev-guide/release.md)
	$(DART) flutter build appbundle --release \
		--obfuscate --split-debug-info=build/symbols

release-ios: ## Uploadable ipa (see docs/05-dev-guide/release.md)
	$(DART) flutter build ipa --release \
		--obfuscate --split-debug-info=build/symbols

clean: ## Remove build output
	$(DART) flutter clean
	rm -rf content/build
