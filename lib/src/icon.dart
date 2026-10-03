import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The picture in the tray, as PNG.
@immutable
class TrayIcon {
  const TrayIcon.png(this.bytes, {this.isTemplate = false});

  /// Reads the PNG at [key] from [bundle], or the root bundle.
  static Future<TrayIcon> asset(
    String key, {
    bool isTemplate = false,
    AssetBundle? bundle,
  }) async {
    final data = await (bundle ?? rootBundle).load(key);
    return TrayIcon.png(data.buffer.asUint8List(), isTemplate: isTemplate);
  }

  final Uint8List bytes;

  /// On macOS, drawn as a template the menu bar tints. Ignored elsewhere.
  final bool isTemplate;
}
