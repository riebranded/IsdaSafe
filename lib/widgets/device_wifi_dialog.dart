import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../services/usb_sensor/device_registry.dart';
import '../services/usb_sensor/pond_readings_store.dart';
import '../services/usb_sensor/usb_sensor_hub.dart';
import '../theme/app_spacing.dart';

/// The password of the device's setup hotspot (`WIFI_SETUP_AP_PASSWORD` in
/// the firmware's isdasafe_wifi.h).
const deviceSetupHotspotPassword = 'isdasafe';

/// The device's setup hotspot: "IsdaSafe-" plus the last 4 characters of its
/// ID (see the firmware's isdasafe_wifi.h).
String deviceSetupHotspotName(String deviceId) =>
    'IsdaSafe-${deviceId.substring(deviceId.length - 4)}';

/// Why [showDeviceWifiDialog] is shown.
enum WifiSetupReason {
  /// Just paired, or never uploaded: the device isn't on WiFi yet.
  firstSetup,

  /// It was online and stopped uploading: it opens its hotspot by itself.
  reconnect,

  /// It's online and the owner wants another network: the dialog asks it
  /// (through the server) to open its hotspot.
  change,
}

/// Helps the owner put a device on their WiFi: explains the device's setup
/// hotspot (join it from a phone and pick the network there). Where the
/// browser can reach USB devices, the network can also be picked here with
/// the device plugged in.
///
/// While it's open it watches the device ([DeviceRegistry.wifiStatus]); once
/// the device has connected (it uploads again, or for [WifiSetupReason.change]
/// reports a different network) it closes and shows
/// [showWifiConnectedDialog].
Future<void> showDeviceWifiDialog(
  BuildContext context, {
  required String deviceId,
  WifiSetupReason reason = WifiSetupReason.firstSetup,
  UsbSensorHub? hub,
  DeviceRegistry? registry,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _DeviceWifiDialog(
      deviceId: deviceId,
      reason: reason,
      hub: hub ?? UsbSensorHub.instance,
      registry: registry ?? DeviceRegistry.instance,
    ),
  );
}

enum _Step { hotspot, scanning, pick, connecting, error }

class _DeviceWifiDialog extends StatefulWidget {
  const _DeviceWifiDialog({
    required this.deviceId,
    required this.reason,
    required this.hub,
    required this.registry,
  });

  final String deviceId;
  final WifiSetupReason reason;
  final UsbSensorHub hub;
  final DeviceRegistry registry;

  @override
  State<_DeviceWifiDialog> createState() => _DeviceWifiDialogState();
}

class _DeviceWifiDialogState extends State<_DeviceWifiDialog> {
  var _step = _Step.hotspot;
  List<WifiNetwork> _networks = [];
  String? _selected;
  bool _otherNetwork = false;
  bool _showPassword = false;
  String? _error;

  final _passwordField = TextEditingController();
  final _otherNameField = TextEditingController();

  /// For [WifiSetupReason.change]: whether the device was asked to open its
  /// hotspot (null while asking).
  bool? _changeRequested;

  /// How often [_check] asks whether the device has connected.
  static const _watchEvery = Duration(seconds: 5);

  /// The device's WiFi status when the dialog opened; null until loaded (or
  /// if it couldn't be).
  DeviceWifiStatus? _baseline;
  Timer? _watch;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (widget.reason == WifiSetupReason.change) _requestChange();
    _startWatching();
  }

  Future<void> _startWatching() async {
    _baseline = await widget.registry.wifiStatus(widget.deviceId);
    if (!mounted) return;
    setState(() {
      _watch = Timer.periodic(_watchEvery, (_) => _check());
    });
  }

  /// Whether the device has connected since the dialog opened.
  Future<void> _check() async {
    final status = await widget.registry.wifiStatus(widget.deviceId);
    if (status == null || !mounted || _done) return;
    final before = _baseline;
    final connected = widget.reason == WifiSetupReason.change
        // Online all along: only a different network counts.
        ? status.ssidChangedAt != null &&
              status.ssidChangedAt != before?.ssidChangedAt
        : status.lastSeenAt != null && status.lastSeenAt != before?.lastSeenAt;
    if (connected) _succeed(status.ssid);
  }

  /// Closes this dialog and shows the "connected" one.
  void _succeed(String? ssid) {
    if (_done) return;
    _done = true;
    _watch?.cancel();
    unawaited(PondReadingsStore.instance.refresh());
    final navigator = Navigator.of(context);
    navigator.pop();
    unawaited(
      showWifiConnectedDialog(
        navigator.context,
        deviceId: widget.deviceId,
        ssid: ssid,
      ),
    );
  }

  Future<void> _requestChange() async {
    setState(() => _changeRequested = null);
    final ok = await widget.registry.requestWifiSetup(widget.deviceId);
    if (mounted) setState(() => _changeRequested = ok);
  }

  @override
  void dispose() {
    _watch?.cancel();
    _passwordField.dispose();
    _otherNameField.dispose();
    super.dispose();
  }

  String get _ssid =>
      _otherNetwork ? _otherNameField.text.trim() : (_selected ?? '');

  Future<void> _scan() async {
    setState(() {
      _step = _Step.scanning;
      _error = null;
    });
    final hub = widget.hub;
    if (!hub.isConnected && !await hub.connect()) {
      if (!mounted) return;
      setState(() {
        _step = _Step.error;
        _error =
            "Couldn't open the device. Plug it in with a USB cable and try again."
                .tr;
      });
      return;
    }
    final networks = await hub.scanWifi();
    if (!mounted) return;
    if (networks == null) {
      setState(() {
        _step = _Step.error;
        _error =
            "The device didn't answer. Make sure it's plugged in and has the latest firmware, or use the phone steps instead."
                .tr;
      });
      return;
    }
    setState(() {
      _networks = networks;
      _selected ??= networks.firstOrNull?.ssid;
      _step = _Step.pick;
    });
  }

  Future<void> _connect() async {
    final ssid = _ssid;
    if (ssid.isEmpty) return;
    setState(() => _step = _Step.connecting);
    final result = await widget.hub.connectWifi(ssid, _passwordField.text);
    if (!mounted) return;
    if (result.ok) {
      _succeed(ssid);
      return;
    }
    setState(() {
      _step = _Step.error;
      _error = result.reason == null
          ? "The device didn't answer. Check the USB cable and try again.".tr
          : "Couldn't connect to {0}: {1}.".trf([ssid, result.reason!.tr]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.wifi),
      title: Text(switch (widget.reason) {
        WifiSetupReason.firstSetup => 'Connect the device to WiFi'.tr,
        WifiSetupReason.reconnect => 'Reconnect the device to WiFi'.tr,
        WifiSetupReason.change => "Change the device's WiFi".tr,
      }),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(child: _content(context)),
      ),
      actions: _actions(context),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    switch (_step) {
      case _Step.hotspot:
        final hotspot = deviceSetupHotspotName(widget.deviceId);
        final bold = theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.bold,
        );
        Widget step(int n, List<InlineSpan> text) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 12, child: Text('$n')),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: SelectableText.rich(TextSpan(children: text))),
            ],
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(switch (widget.reason) {
              WifiSetupReason.firstSetup =>
                'The device sends its readings over WiFi. Choose its network with your phone:'
                    .tr,
              WifiSetupReason.reconnect =>
                "The device isn't sending readings. If your WiFi is working, the device may be out of range or its WiFi password may have changed. Choose its network again with your phone:"
                    .tr,
              WifiSetupReason.change =>
                'The device keeps its current network until the new one works. Choose the new network with your phone:'
                    .tr,
            }),
            const SizedBox(height: AppSpacing.lg),
            step(1, [
              TextSpan(
                text: switch (widget.reason) {
                  WifiSetupReason.change => switch (_changeRequested) {
                    null => 'Asking the device to open its setup hotspot...'.tr,
                    true =>
                      'The device opens its setup hotspot within about a minute and keeps it open for 10 minutes.'
                          .tr,
                    false =>
                      "Couldn't reach the server to ask the device. Check your connection and try again."
                          .tr,
                  },
                  _ =>
                    "Make sure the device is powered on. When it can't reach a WiFi network, it opens its own setup hotspot within about 2 minutes."
                        .tr,
                },
                style: _changeRequested == false
                    ? TextStyle(color: theme.colorScheme.error)
                    : null,
              ),
            ]),
            step(2, [
              TextSpan(text: 'On your phone, join the WiFi network '.tr),
              TextSpan(text: hotspot, style: bold),
              TextSpan(text: ' (password: '.tr),
              TextSpan(text: deviceSetupHotspotPassword, style: bold),
              const TextSpan(text: ').'),
            ]),
            step(3, [
              TextSpan(
                text:
                    "A setup page opens (if it doesn't, open 192.168.4.1 in the browser). Pick your WiFi, type its password and tap Save and connect."
                        .tr,
              ),
            ]),
            step(4, [
              TextSpan(
                text:
                    'When it says Connected, switch your phone back to your usual WiFi.'
                        .tr,
              ),
            ]),
            Text(
              'The device screen also shows the network name and password while setup is open.'
                  .tr,
              style: theme.textTheme.bodySmall,
            ),
            if (_watch != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Waiting for the device to connect...'.tr,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      case _Step.scanning:
        return _busy('Looking for WiFi networks...'.tr);
      case _Step.connecting:
        return _busy(
          'Connecting the device to {0}. This takes up to 20 seconds.'.trf([
            _ssid,
          ]),
        );
      case _Step.error:
        return Text(
          _error ?? '',
          style: TextStyle(color: theme.colorScheme.error),
        );
      case _Step.pick:
        return _picker(context);
    }
  }

  Widget _busy(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: AppSpacing.lg),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );

  Widget _picker(BuildContext context) {
    final theme = Theme.of(context);
    final pluggedIn = widget.hub.deviceId;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pluggedIn != null && pluggedIn != widget.deviceId)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              'The device plugged in is {0}, not {1}.'.trf([
                pluggedIn,
                widget.deviceId,
              ]),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Text(
                'Choose a network'.tr,
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text('Scan again'.tr),
            ),
          ],
        ),
        if (_networks.isEmpty)
          Text('No networks found.'.tr, style: theme.textTheme.bodySmall),
        RadioGroup<String>(
          groupValue: _otherNetwork ? '' : _selected,
          onChanged: (value) => setState(() {
            _otherNetwork = value == '';
            if (value != '') _selected = value;
          }),
          child: Column(
            children: [
              for (final network in _networks)
                RadioListTile<String>(
                  value: network.ssid,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(network.ssid),
                  secondary: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${network.signalPercent}%'),
                      if (network.secured) ...[
                        const SizedBox(width: AppSpacing.xs),
                        const Icon(Icons.lock_outline, size: 16),
                      ],
                    ],
                  ),
                ),
              RadioListTile<String>(
                value: '',
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('Other (hidden) network'.tr),
              ),
            ],
          ),
        ),
        if (_otherNetwork)
          TextField(
            controller: _otherNameField,
            decoration: InputDecoration(labelText: 'Network name'.tr),
            onChanged: (_) => setState(() {}),
          ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _passwordField,
          obscureText: !_showPassword,
          decoration: InputDecoration(
            labelText: 'WiFi password'.tr,
            helperText: 'Leave empty for an open network.'.tr,
            suffixIcon: IconButton(
              icon: Icon(
                _showPassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          onSubmitted: (_) => _connect(),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Only 2.4 GHz networks are shown.'.tr,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  List<Widget> _actions(BuildContext context) {
    void close() => Navigator.of(context).pop();
    switch (_step) {
      case _Step.hotspot:
        return [
          if (widget.hub.isSupported)
            TextButton(onPressed: _scan, child: Text('Use USB instead'.tr)),
          if (_changeRequested == false)
            TextButton(onPressed: _requestChange, child: Text('Try again'.tr)),
          TextButton(onPressed: close, child: Text('Later'.tr)),
          FilledButton(onPressed: close, child: Text('Done'.tr)),
        ];
      case _Step.scanning:
      case _Step.connecting:
        return [];
      case _Step.pick:
        return [
          TextButton(
            onPressed: () => setState(() => _step = _Step.hotspot),
            child: Text('Back'.tr),
          ),
          FilledButton(
            onPressed: _ssid.isEmpty ? null : _connect,
            child: Text('Connect'.tr),
          ),
        ];
      case _Step.error:
        return [
          TextButton(
            onPressed: () => setState(() => _step = _Step.hotspot),
            child: Text('Use phone instead'.tr),
          ),
          FilledButton(
            onPressed: _networks.isEmpty
                ? _scan
                : () => setState(() => _step = _Step.pick),
            child: Text('Try again'.tr),
          ),
        ];
    }
  }
}

/// "Device connected to WiFi": shown once a device has joined a network
/// (by [showDeviceWifiDialog]). [ssid] is the network, when the device
/// reported it.
Future<void> showWifiConnectedDialog(
  BuildContext context, {
  required String deviceId,
  String? ssid,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        icon: Icon(Icons.wifi, size: 40, color: theme.colorScheme.primary),
        title: Text('Device connected to WiFi'.tr),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Text(
            ssid == null || ssid.isEmpty
                ? 'Device {0} is online. Its readings will appear within a minute.'
                      .trf([deviceId])
                : 'Device {0} is now connected to "{1}". Its readings will appear within a minute.'
                      .trf([deviceId, ssid]),
            textAlign: TextAlign.center,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'.tr),
          ),
        ],
      );
    },
  );
}
