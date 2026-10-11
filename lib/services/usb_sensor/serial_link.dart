import 'serial_link_stub.dart'
    if (dart.library.js_interop) 'serial_link_web.dart'
    as impl;

/// A USB serial connection to the IsdaSafe device, as text lines.
///
/// Only the web build can talk to USB devices (through the browser's Web
/// Serial API, Chrome and Edge on desktop); everywhere else [isSupported] is
/// false.
abstract class SerialLink {
  factory SerialLink() = impl.PlatformSerialLink;

  bool get isSupported;

  /// Asks the user to pick the device's port (browser chooser), then opens
  /// it. Returns false if they cancel the chooser.
  Future<bool> requestAndOpen();

  /// Opens a port the user already granted on an earlier visit, without
  /// prompting. Returns false if there is none (or it isn't plugged in).
  Future<bool> openGranted();

  /// Lines of text from the open port. Completes when the port closes or the
  /// device is unplugged.
  Stream<String> get lines;

  /// Sends [line] plus a newline to the device. Returns false if the port
  /// isn't open or the write fails.
  Future<bool> writeLine(String line);

  Future<void> close();
}
