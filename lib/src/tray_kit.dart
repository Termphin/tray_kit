import 'package:flutter/foundation.dart';

import 'icon.dart';
import 'menu.dart';
import 'platform.dart';

/// The app's icon in the system tray.
class TrayKit {
  TrayKit._();

  static final instance = TrayKit._();

  bool _shown = false;

  /// Whether the icon is up.
  bool get isShown => _shown;

  /// Whether this desktop has a tray. On Linux, false without a
  /// StatusNotifierItem host, such as GNOME without its AppIndicator
  /// extension.
  Future<bool> isSupported() => TrayKitPlatform.instance.isSupported();

  /// Shows [icon] with [tooltip] and [menu], or updates the icon already up.
  ///
  /// [onActivate] is a primary click on the icon. On macOS a click opens
  /// the menu instead.
  Future<void> show({
    required TrayIcon icon,
    String tooltip = '',
    List<TrayMenuItem> menu = const [],
    VoidCallback? onActivate,
  }) async {
    await TrayKitPlatform.instance.show(
      icon: icon,
      tooltip: tooltip,
      menu: menu,
      onActivate: onActivate,
    );
    _shown = true;
  }

  /// Takes the icon down.
  Future<void> hide() async {
    if (!_shown) return;
    _shown = false;
    await TrayKitPlatform.instance.hide();
  }
}
