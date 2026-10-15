import 'dart:async';

import 'package:isdasafev2/services/usb_sensor/pond_readings_store.dart';
import 'package:isdasafev2/widgets/app_tour.dart';

/// Runs before every test file. Ponds only show readings once an IsdaSafe
/// device is paired; screens tests that aren't about pairing get every pond
/// paired with a healthy reading per metric. Pairing tests install their
/// own store.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  PondReadingsStore.instance = PondReadingsStore.everyPondPaired();
  // The first-run app tour would cover every AppShell test; tour tests turn
  // it back on.
  AppTour.autoStartEnabled = false;
  await testMain();
}
