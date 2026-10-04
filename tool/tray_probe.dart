import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

const _watcher = 'org.kde.StatusNotifierWatcher';
const _item = 'org.kde.StatusNotifierItem';
const _menu = 'com.canonical.dbusmenu';

/// Checks, against a real panel on the session bus, that the example app's
/// icon is registered, readable and clickable. Exits non-zero on failure.
Future<void> main(List<String> args) async {
  final expectHost = !args.contains('--no-host');
  final bus = DBusClient.session();
  try {
    final watcher = DBusRemoteObject(
      bus,
      name: _watcher,
      path: DBusObjectPath('/StatusNotifierWatcher'),
    );

    final registered = await _poll(
      'an item registered with the watcher',
      () async {
        if (!await bus.nameHasOwner(_watcher)) return null;
        final items = (await watcher.getProperty(
          _watcher,
          'RegisteredStatusNotifierItems',
        )).asStringArray();
        return items
            .where((item) => item.contains('StatusNotifierItem'))
            .firstOrNull;
      },
    );
    stdout.writeln('registered: $registered');

    if (expectHost) {
      final host = (await watcher.getProperty(
        _watcher,
        'IsStatusNotifierHostRegistered',
      )).asBoolean();
      if (!host) throw StateError('no StatusNotifierHost is registered');
      stdout.writeln('host: registered');
    }

    final slash = registered.indexOf('/');
    final service = slash < 0 ? registered : registered.substring(0, slash);
    final path = slash < 0
        ? '/StatusNotifierItem'
        : registered.substring(slash);
    final item = DBusRemoteObject(
      bus,
      name: service,
      path: DBusObjectPath(path),
    );

    final tooltip = (await item.getProperty(
      _item,
      'ToolTip',
    )).asStruct()[2].asString();
    stdout.writeln('tooltip: $tooltip');
    if (tooltip != 'tray_kit example') throw StateError('unexpected tooltip');

    final menuPath = (await item.getProperty(_item, 'Menu')).asObjectPath();
    final menu = DBusRemoteObject(bus, name: service, path: menuPath);
    final layout = await menu.callMethod(_menu, 'GetLayout', [
      const DBusInt32(0),
      const DBusInt32(-1),
      DBusArray.string(const []),
    ]);
    DBusValue? hello;
    for (final child in layout.returnValues[1].asStruct()[2].asArray()) {
      final fields = child.asVariant().asStruct();
      final label = fields[1].asStringVariantDict()['label']?.asString();
      stdout.writeln('menu: $label');
      if (label == 'Say hello') hello = fields[0];
    }
    if (hello == null) throw StateError('no "Say hello" entry');
    await menu.callMethod(_menu, 'Event', [
      hello,
      const DBusString('clicked'),
      const DBusVariant(DBusString('')),
      DBusUint32(DateTime.now().millisecondsSinceEpoch ~/ 1000),
    ]);
    stdout.writeln('clicked: Say hello');
  } finally {
    await bus.close();
  }
}

Future<T> _poll<T extends Object>(
  String what,
  Future<T?> Function() check, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      final value = await check();
      if (value != null) return value;
    } on DBusMethodResponseException {
      await Future<void>.delayed(const Duration(seconds: 2));
      continue;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  throw TimeoutException('waiting for $what');
}
