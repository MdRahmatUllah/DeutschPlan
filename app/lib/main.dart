import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Entry point. Real bootstrap work (opening user.db, copying content.db,
/// loading settings, resolving the theme) lands in `bootstrap.dart` — see
/// docs/04-screens/splash.md, FR-S1-01.
void main() {
  runApp(const ProviderScope(child: DeutschPlanApp()));
}

class DeutschPlanApp extends StatelessWidget {
  const DeutschPlanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'DeutschPlan', home: const _Placeholder());
  }
}

// ponytail: placeholder shell so the app runs; replaced by the router shell in #67.
class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('DeutschPlan')));
  }
}
