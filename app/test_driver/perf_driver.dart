// #167: writes what integration_test/perf_test.dart reports to
// build/integration_response_data.json, where tools/perf.py reads it.

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
