import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

import 'serial_link.dart';

/// The firmware's `Serial.begin(115200)`.
const _baudRate = 115200;

/// Web Serial API (https://wicg.github.io/serial/) bindings — only the parts
/// this app uses.
extension type _Serial._(JSObject _) implements JSObject {
  external JSPromise<_SerialPort> requestPort();
  external JSPromise<JSArray<_SerialPort>> getPorts();
}

extension type _SerialPort._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> open(_SerialOptions options);
  external JSPromise<JSAny?> close();
  external JSPromise<JSAny?> setSignals(_SerialSignals signals);
  external _ReadableStream? get readable;
  external _WritableStream? get writable;
}

extension type _WritableStream._(JSObject _) implements JSObject {
  external _Writer getWriter();
}

extension type _Writer._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSUint8Array chunk);
  external void releaseLock();
}

extension type _SerialOptions._(JSObject _) implements JSObject {
  external factory _SerialOptions({int baudRate});
}

extension type _SerialSignals._(JSObject _) implements JSObject {
  external factory _SerialSignals({bool dataTerminalReady, bool requestToSend});
}

extension type _ReadableStream._(JSObject _) implements JSObject {
  external _Reader getReader();
}

extension type _Reader._(JSObject _) implements JSObject {
  external JSPromise<_ReadResult> read();
  external JSPromise<JSAny?> cancel();
  external void releaseLock();
}

extension type _ReadResult._(JSObject _) implements JSObject {
  external bool get done;
  external JSUint8Array? get value;
}

_Serial? get _serial {
  final navigator = globalContext.getProperty<JSObject>('navigator'.toJS);
  if (!navigator.has('serial')) return null;
  return navigator.getProperty<_Serial>('serial'.toJS);
}

class PlatformSerialLink implements SerialLink {
  _SerialPort? _port;
  _Reader? _reader;
  StreamController<String>? _lines;

  @override
  bool get isSupported => _serial != null;

  @override
  Future<bool> requestAndOpen() async {
    final serial = _serial;
    if (serial == null) {
      debugPrint('[USB] Web Serial not available in this browser');
      return false;
    }
    debugPrint('[USB] opening the port chooser');
    final _SerialPort port;
    try {
      port = await serial.requestPort().toDart;
    } catch (e) {
      // The user closed the chooser without picking a port.
      debugPrint('[USB] no port picked: $e');
      return false;
    }
    debugPrint('[USB] port picked');
    return _open(port);
  }

  @override
  Future<bool> openGranted() async {
    final serial = _serial;
    if (serial == null) return false;
    try {
      final ports = (await serial.getPorts().toDart).toDart;
      debugPrint('[USB] ${ports.length} previously granted port(s)');
      if (ports.isEmpty) return false;
      return _open(ports.first);
    } catch (e) {
      debugPrint('[USB] getPorts failed: $e');
      return false;
    }
  }

  Future<bool> _open(_SerialPort port) async {
    await close();
    try {
      await port.open(_SerialOptions(baudRate: _baudRate)).toDart;
      debugPrint('[USB] port open at $_baudRate baud');
    } catch (e) {
      // Already open in another tab or the Arduino Serial Monitor, or
      // unplugged since it was granted.
      debugPrint('[USB] port.open failed: $e');
      return false;
    }
    // ESP32 boards wire DTR/RTS to their reset/boot pins; release both so the
    // board runs normally instead of being held in reset.
    try {
      await port
          .setSignals(
            _SerialSignals(dataTerminalReady: false, requestToSend: false),
          )
          .toDart;
    } catch (e) {
      debugPrint('[USB] setSignals failed (usually harmless): $e');
    }

    _port = port;
    _lines = StreamController<String>();
    unawaited(_pump(port, _lines!));
    return true;
  }

  Future<void> _pump(_SerialPort port, StreamController<String> out) async {
    final bytes = StreamController<List<int>>();
    final sub = bytes.stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(out.add);
    try {
      final readable = port.readable;
      if (readable == null) {
        debugPrint('[USB] port has no readable stream');
        return;
      }
      final reader = readable.getReader();
      _reader = reader;
      var total = 0;
      while (true) {
        final result = await reader.read().toDart;
        if (result.done) {
          debugPrint('[USB] read stream ended');
          break;
        }
        final chunk = result.value;
        if (chunk != null) {
          final data = Uint8List.fromList(chunk.toDart);
          // Only the first few chunks: proves bytes are arriving even when
          // no full line has come through yet (e.g. wrong baud rate).
          if (total < 256) {
            debugPrint('[USB] received ${data.length} byte(s)');
          }
          total += data.length;
          bytes.add(data);
        }
      }
    } catch (e) {
      // Unplugged, or close() cancelled the read.
      debugPrint('[USB] read stopped: $e');
    } finally {
      await bytes.close();
      await sub.asFuture<void>().catchError((_) {});
      await out.close();
    }
  }

  @override
  Stream<String> get lines => _lines?.stream ?? const Stream.empty();

  @override
  Future<bool> writeLine(String line) async {
    final writable = _port?.writable;
    if (writable == null) {
      debugPrint('[USB] write skipped: port not open');
      return false;
    }
    final writer = writable.getWriter();
    try {
      final bytes = Uint8List.fromList(utf8.encode('$line\n'));
      await writer.write(bytes.toJS).toDart;
      return true;
    } catch (e) {
      debugPrint('[USB] write failed: $e');
      return false;
    } finally {
      writer.releaseLock();
    }
  }

  @override
  Future<void> close() async {
    final reader = _reader, port = _port;
    _reader = null;
    _port = null;
    _lines = null;
    if (reader != null) {
      try {
        await reader.cancel().toDart;
        reader.releaseLock();
      } catch (_) {}
    }
    if (port != null) {
      try {
        await port.close().toDart;
      } catch (_) {}
    }
  }
}
