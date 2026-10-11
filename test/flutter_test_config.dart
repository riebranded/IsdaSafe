import 'dart:async';

import 'package:isdasafev2/services/usb_sensor/pond_readings_store.dart';

/// Runs before every test file. Ponds only show readings once an IsdaSafe
/// device is paired; screens tests that aren't about pairing get every pond
/// paired with a healthy reading per metric. Pairing tests install their
/// own store.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  PondReadingsStore.instance = PondReadingsStore.everyPondPaired();
  await testMain();
}
