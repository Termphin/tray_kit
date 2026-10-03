import 'package:flutter/services.dart';

import 'icon.dart';
import 'menu.dart';
import 'platform.dart';

/// Windows and macOS, over the `tray_kit` channel.
class MethodChannelTrayKit extends TrayKitPlatform {
  MethodChannelTrayKit({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('tray_kit') {
    _channel.setMethodCallHandler(_handle);
  }

  final MethodChannel _channel;
  Map<int, VoidCallback> _actions = const {};
  VoidCallback? _onActivate;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<void> show({
    required TrayIcon icon,
    required String tooltip,
    required List<TrayMenuItem> menu,
    required VoidCallback? onActivate,
  }) async {
    final encoded = EncodedTrayMenu.encode(menu);
    _actions = encoded.actions;
    _onActivate = onActivate;
    await _channel.invokeMethod<void>('show', {
      'icon': icon.bytes,
      'template': icon.isTemplate,
      'tooltip': tooltip,
      'menu': encoded.items,
    });
  }

  @override
  Future<void> hide() async {
    _actions = const {};
    _onActivate = null;
    await _channel.invokeMethod<void>('hide');
  }

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'activate':
        _onActivate?.call();
      case 'select':
        if (call.arguments case final int id) _actions[id]?.call();
    }
    return null;
  }
}
