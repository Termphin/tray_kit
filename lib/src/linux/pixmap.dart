import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dbus/dbus.dart';

/// An icon as StatusNotifierItem carries it: `(iiay)`, ARGB32 in network byte
/// order.
class Pixmap {
  const Pixmap(this.width, this.height, this.argb);

  final int width;
  final int height;
  final Uint8List argb;

  /// Decodes [png] into a pixmap.
  static Future<Pixmap> fromPng(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    try {
      final rgba = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      return Pixmap(
        image.width,
        image.height,
        rgbaToArgb(rgba!.buffer.asUint8List()),
      );
    } finally {
      image.dispose();
      codec.dispose();
    }
  }

  /// Moves each pixel's alpha from last to first.
  static Uint8List rgbaToArgb(Uint8List rgba) {
    final argb = Uint8List(rgba.length);
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      argb[i] = rgba[i + 3];
      argb[i + 1] = rgba[i];
      argb[i + 2] = rgba[i + 1];
      argb[i + 3] = rgba[i + 2];
    }
    return argb;
  }

  DBusValue toValue() =>
      DBusStruct([DBusInt32(width), DBusInt32(height), DBusArray.byte(argb)]);

  /// [pixmaps] as an `a(iiay)` array.
  static DBusValue array(Iterable<Pixmap> pixmaps) => DBusArray(
    DBusSignature('(iiay)'),
    [for (final pixmap in pixmaps) pixmap.toValue()],
  );
}
