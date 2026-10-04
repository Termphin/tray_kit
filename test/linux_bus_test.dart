import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_kit/tray_kit.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

const _itemInterface = 'org.kde.StatusNotifierItem';
const _menuInterface = 'com.canonical.dbusmenu';

/// Stands in for a panel: owns the watcher name and records registrations.
class _Watcher extends DBusObject {
  _Watcher() : super(DBusObjectPath('/StatusNotifierWatcher'));

  final registered = StreamController<String>.broadcast();

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.name == 'RegisterStatusNotifierItem' &&
        methodCall.signature == DBusSignature('s')) {
      registered.add(methodCall.values.single.asString());
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DBusServer server;
  late DBusAddress address;
  late DBusClient host;

  setUp(() async {
    server = DBusServer();
    address = await server.listenAddress(
      DBusAddress.unix(dir: Directory.systemTemp),
    );
    host = DBusClient(address);
  });

  tearDown(() async {
    await host.close();
    await server.close();
  });

  Future<_Watcher> startWatcher() async {
    final watcher = _Watcher();
    await host.requestName('org.kde.StatusNotifierWatcher');
    await host.registerObject(watcher);
    return watcher;
  }

  LinuxTrayKit tray() => LinuxTrayKit(bus: () => DBusClient(address));

  test('no watcher on the bus means no tray', () async {
    expect(await tray().isSupported(), isFalse);
  });

  test('a panel sees the icon, reads it, and its clicks arrive', () async {
    final watcher = await startWatcher();
    final kit = tray();
    expect(await kit.isSupported(), isTrue);

    final picked = Completer<String>();
    final activated = Completer<void>();
    final registration = watcher.registered.stream.first;
    await kit.show(
      icon: TrayIcon.png(_png),
      tooltip: 'Termphin - 1 session',
      onActivate: activated.complete,
      menu: [
        TrayMenuAction('Show', onSelected: () => picked.complete('show')),
        const TrayMenuSeparator(),
        TraySubmenu('New session', [
          TrayMenuAction('prod_db', onSelected: () => picked.complete('db')),
        ]),
      ],
    );
    final name = await registration;

    final item = DBusRemoteObject(
      host,
      name: name,
      path: DBusObjectPath('/StatusNotifierItem'),
    );
    final tooltip = await item.getProperty(_itemInterface, 'ToolTip');
    expect(tooltip.asStruct()[2].asString(), 'Termphin - 1 session');
    final pixmaps = (await item.getProperty(
      _itemInterface,
      'IconPixmap',
    )).asArray();
    expect(pixmaps.single.asStruct()[0].asInt32(), 1);
    final menuPath = (await item.getProperty(
      _itemInterface,
      'Menu',
    )).asObjectPath();

    final menu = DBusRemoteObject(host, name: name, path: menuPath);
    final layout = await menu.callMethod(_menuInterface, 'GetLayout', [
      const DBusInt32(0),
      const DBusInt32(-1),
      DBusArray.string(const []),
    ]);
    final top = layout.returnValues[1].asStruct()[2].asArray();
    expect(top, hasLength(3));
    final submenu = top[2].asVariant().asStruct();
    final nested = submenu[2].asArray().single.asVariant().asStruct();
    expect(nested[1].asStringVariantDict()['label']?.asString(), 'prod__db');

    await menu.callMethod(_menuInterface, 'Event', [
      nested[0],
      const DBusString('clicked'),
      const DBusVariant(DBusString('')),
      const DBusUint32(0),
    ]);
    expect(await picked.future.timeout(const Duration(seconds: 5)), 'db');

    await item.callMethod(_itemInterface, 'Activate', const [
      DBusInt32(0),
      DBusInt32(0),
    ]);
    await activated.future.timeout(const Duration(seconds: 5));

    final updates = StreamController<DBusSignal>();
    final subscription = DBusRemoteObjectSignalStream(
      object: menu,
      interface: _menuInterface,
      name: 'LayoutUpdated',
    ).listen(updates.add);
    addTearDown(subscription.cancel);
    await host.nameHasOwner(name);
    final layoutUpdated = updates.stream.first;
    await kit.show(
      icon: TrayIcon.png(_png),
      tooltip: 'Termphin',
      menu: const [TrayMenuAction('Quit')],
      onActivate: null,
    );
    final revision = (await layoutUpdated.timeout(
      const Duration(seconds: 5),
    )).values[0].asUint32();
    final after = await menu.callMethod(_menuInterface, 'GetLayout', [
      const DBusInt32(0),
      const DBusInt32(-1),
      DBusArray.string(const []),
    ]);
    expect(after.returnValues[0].asUint32(), revision);
    expect(after.returnValues[1].asStruct()[2].asArray(), hasLength(1));

    await kit.hide();
    expect(await host.nameHasOwner(name), isFalse);
  });

  test('shows that overlap put up one icon, not two', () async {
    final watcher = await startWatcher();
    final kit = tray();
    final names = <String>[];
    final sub = watcher.registered.stream.listen(names.add);

    await Future.wait([
      kit.show(
        icon: TrayIcon.png(_png),
        tooltip: 'a',
        menu: const [],
        onActivate: null,
      ),
      kit.show(
        icon: TrayIcon.png(_png),
        tooltip: 'b',
        menu: const [],
        onActivate: null,
      ),
      kit.show(
        icon: TrayIcon.png(_png),
        tooltip: 'c',
        menu: const [],
        onActivate: null,
      ),
    ]);
    await pumpEventQueue();
    await sub.cancel();

    expect(names, hasLength(1));
    await kit.hide();
    expect(await host.nameHasOwner(names.single), isFalse);
  });

  test('a stranger on the bus cannot crash the menu', () async {
    final watcher = await startWatcher();
    final kit = tray();
    final registration = watcher.registered.stream.first;
    await kit.show(
      icon: TrayIcon.png(_png),
      tooltip: '',
      menu: const [TrayMenuAction('Only')],
      onActivate: null,
    );
    final name = await registration;
    final menu = DBusRemoteObject(
      host,
      name: name,
      path: DBusObjectPath('/MenuBar'),
    );

    for (final id in [2, -1, 1 << 30]) {
      await expectLater(
        menu.callMethod(_menuInterface, 'Event', [
          DBusInt32(id),
          const DBusString('clicked'),
          const DBusVariant(DBusString('')),
          const DBusUint32(0),
        ]),
        throwsA(isA<DBusMethodResponseException>()),
      );
    }
    await expectLater(
      menu.callMethod(_menuInterface, 'Event', [const DBusString('x')]),
      throwsA(isA<DBusMethodResponseException>()),
    );

    final still = await menu.callMethod(_menuInterface, 'GetLayout', [
      const DBusInt32(0),
      const DBusInt32(-1),
      DBusArray.string(const []),
    ]);
    expect(still.returnValues[1].asStruct()[2].asArray(), hasLength(1));
    await kit.hide();
  });
}
