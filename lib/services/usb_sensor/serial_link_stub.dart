import 'serial_link.dart';

/// Non-web platforms: no USB serial access.
class PlatformSerialLink implements SerialLink {
  @override
  bool get isSupported => false;

  @override
  Future<bool> requestAndOpen() async => false;

  @override
  Future<bool> openGranted() async => false;

  @override
  Stream<String> get lines => const Stream.empty();

  @override
  Future<bool> writeLine(String line) async => false;

  @override
  Future<void> close() async {}
}
