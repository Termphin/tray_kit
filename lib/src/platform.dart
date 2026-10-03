import 'package:flutter/foundation.dart';

import 'channel.dart';
import 'icon.dart';
import 'menu.dart';

/// What [TrayKit] asks of each system.
abstract class TrayKitPlatform {
  static TrayKitPlatform instance = MethodChannelTrayKit();

  /// Whether this desktop draws tray icons at all.
  Future<bool> isSupported();

  /// Puts the icon up, or replaces what it shows.
  Future<void> show({
    required TrayIcon icon,
    required String tooltip,
    required List<TrayMenuItem> menu,
    required VoidCallback? onActivate,
  });

  /// Takes the icon down.
  Future<void> hide();
}
