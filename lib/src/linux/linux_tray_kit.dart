import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

import '../icon.dart';
import '../menu.dart';
import '../platform.dart';
import 'dbus_menu_export.dart';
import 'menu_tree.dart';
import 'pixmap.dart';
import 'status_notifier_export.dart';

/// The watcher every StatusNotifierItem host in use registers: KDE's, GNOME's
/// AppIndicator extension, Xfce's and Cinnamon's.
const kStatusNotifierWatcher = 'org.kde.StatusNotifierWatcher';

/// Linux: a StatusNotifierItem with a dbusmenu, over the session bus, in Dart.
class LinuxTrayKit extends TrayKitPlatform {
  LinuxTrayKit({DBusClient Function()? bus})
    : _connect = bus ?? DBusClient.session;

  /// Called by Flutter's plugin registrant.
  static void registerWith() => TrayKitPlatform.instance = LinuxTrayKit();

  final DBusClient Function() _connect;
  _Session? _session;
  Uint8List? _iconBytes;
  Pixmap? _pixmap;

  @override
  Future<bool> isSupported() async {
    final bus = _connect();
    try {
      return await bus.nameHasOwner(kStatusNotifierWatcher);
    } on Object {
      return false;
    } finally {
      await bus.close();
    }
  }

  Future<Pixmap> _pixmapFor(TrayIcon icon) async {
    if (!identical(icon.bytes, _iconBytes) || _pixmap == null) {
      _pixmap = await Pixmap.fromPng(icon.bytes);
      _iconBytes = icon.bytes;
    }
    return _pixmap!;
  }

  @override
  Future<void> show({
    required TrayIcon icon,
    required String tooltip,
    required List<TrayMenuItem> menu,
    required VoidCallback? onActivate,
  }) async {
    final pixmap = await _pixmapFor(icon);
    final session = _session;
    if (session != null) {
      await session.update(pixmap, tooltip, MenuTree(menu), onActivate);
      return;
    }
    final created = _Session(_connect());
    try {
      await created.open(pixmap, tooltip, MenuTree(menu), onActivate);
    } on Object {
      await created.close();
      rethrow;
    }
    _session = created;
  }

  @override
  Future<void> hide() async {
    final session = _session;
    _session = null;
    await session?.close();
  }
}

class _Session {
  _Session(this.bus);

  final DBusClient bus;
  StatusNotifierExport? _item;
  DBusMenuExport? _menu;
  String? _name;

  static var _count = 0;

  Future<void> open(
    Pixmap icon,
    String tooltip,
    MenuTree tree,
    VoidCallback? onActivate,
  ) async {
    final name = 'org.kde.StatusNotifierItem-$pid-${++_count}';
    final reply = await bus.requestName(
      name,
      flags: {DBusRequestNameFlag.doNotQueue},
    );
    if (reply != DBusRequestNameReply.primaryOwner) {
      throw StateError('Could not own $name: $reply');
    }
    _name = name;
    final menu = _menu = DBusMenuExport(DBusObjectPath('/MenuBar'), tree);
    final item = _item = StatusNotifierExport(
      appId: 'tray_kit_$pid',
      menuPath: menu.path,
      icon: icon,
      tooltip: tooltip,
      onActivate: onActivate,
    );
    await bus.registerObject(menu);
    await bus.registerObject(item);
    await bus.callMethod(
      destination: kStatusNotifierWatcher,
      path: DBusObjectPath('/StatusNotifierWatcher'),
      interface: kStatusNotifierWatcher,
      name: 'RegisterStatusNotifierItem',
      values: [DBusString(name)],
      replySignature: DBusSignature.empty,
    );
  }

  Future<void> update(
    Pixmap icon,
    String tooltip,
    MenuTree tree,
    VoidCallback? onActivate,
  ) async {
    final item = _item!;
    final changed = [
      if (!identical(item.icon, icon)) 'NewIcon',
      if (item.tooltip != tooltip) ...['NewTitle', 'NewToolTip'],
    ];
    item
      ..icon = icon
      ..tooltip = tooltip
      ..onActivate = onActivate;
    await _menu!.replace(tree);
    await item.announce(changed);
  }

  Future<void> close() async {
    final item = _item;
    final menu = _menu;
    final name = _name;
    try {
      if (item != null) await bus.unregisterObject(item);
      if (menu != null) await bus.unregisterObject(menu);
      if (name != null) await bus.releaseName(name);
    } on Object {
      return;
    } finally {
      await bus.close();
    }
  }
}
