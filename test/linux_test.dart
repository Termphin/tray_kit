import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_kit/src/linux/dbus_menu_export.dart';
import 'package:tray_kit/src/linux/menu_tree.dart';
import 'package:tray_kit/src/linux/pixmap.dart';
import 'package:tray_kit/src/linux/status_notifier_export.dart';
import 'package:tray_kit/tray_kit.dart';

DBusMethodCall _call(String interface, String name, List<DBusValue> values) =>
    DBusMethodCall(
      sender: ':1.42',
      interface: interface,
      name: name,
      values: values,
    );

void main() {
  group('the menu on the bus', () {
    late List<String> picked;
    late DBusMenuExport menu;

    setUp(() {
      picked = [];
      menu = DBusMenuExport(
        DBusObjectPath('/MenuBar'),
        MenuTree([
          TrayMenuAction('Show', onSelected: () => picked.add('show')),
          const TrayMenuSeparator(),
          TrayMenuAction(
            'deploy_api',
            enabled: false,
            onSelected: () => picked.add('off'),
          ),
        ]),
      );
    });

    Future<DBusMethodResponse> click(int id) => menu.handleMethodCall(
      _call(kDBusMenuInterface, 'Event', [
        DBusInt32(id),
        const DBusString('clicked'),
        const DBusVariant(DBusString('')),
        const DBusUint32(0),
      ]),
    );

    Future<DBusMethodResponse> layout() => menu.handleMethodCall(
      _call(kDBusMenuInterface, 'GetLayout', [
        const DBusInt32(0),
        const DBusInt32(-1),
        DBusArray.string(const []),
      ]),
    );

    test('refuses ids it never had, the one past the last included', () async {
      for (final id in [4, -1, 1 << 30]) {
        final response = await click(id);
        expect(response, isA<DBusMethodErrorResponse>(), reason: '$id');
        expect(
          (response as DBusMethodErrorResponse).errorName,
          'com.canonical.dbusmenu.UnknownId',
        );
      }
    });

    test('runs a click after replying to it', () async {
      expect(await click(1), isA<DBusMethodSuccessResponse>());
      expect(picked, isEmpty);
      await pumpEventQueue();
      expect(picked, ['show']);
    });

    test('ignores a click on a disabled entry', () async {
      await click(3);
      await pumpEventQueue();
      expect(picked, isEmpty);
    });

    test('escapes underscores, which dbusmenu reads as mnemonics', () async {
      final children = (await layout()).returnValues[1].asStruct()[2];
      final label = children
          .asArray()[2]
          .asVariant()
          .asStruct()[1]
          .asStringVariantDict()['label'];
      expect(label?.asString(), 'deploy__api');
    });

    test('a new menu gets a new revision and drops the old ids', () async {
      final before = menu.revision;
      await menu.replace(MenuTree([const TrayMenuAction('Only')]));

      final response = await layout();
      expect(response.returnValues[0].asUint32(), before + 1);
      expect(response.returnValues[1].asStruct()[2].asArray(), hasLength(1));
      expect(await click(3), isA<DBusMethodErrorResponse>());
    });

    test('reports the ids of a group it did not know', () async {
      DBusValue clicked(int id) => DBusStruct([
        DBusInt32(id),
        const DBusString('clicked'),
        const DBusVariant(DBusString('')),
        const DBusUint32(0),
      ]);
      final response = await menu.handleMethodCall(
        _call(kDBusMenuInterface, 'EventGroup', [
          DBusArray(DBusSignature('(isvu)'), [clicked(1), clicked(99)]),
        ]),
      );
      await pumpEventQueue();

      expect(response.returnValues.single.asInt32Array(), [99]);
      expect(picked, ['show']);
    });

    test('refuses wrong arguments and other interfaces', () async {
      final wrong = await menu.handleMethodCall(
        _call(kDBusMenuInterface, 'Event', [const DBusString('1')]),
      );
      final other = await menu.handleMethodCall(
        _call('org.example.Other', 'Event', const []),
      );

      expect(wrong, isA<DBusMethodErrorResponse>());
      expect(other, isA<DBusMethodErrorResponse>());
    });
  });

  group('the item on the bus', () {
    StatusNotifierExport item({VoidCallback? onActivate}) =>
        StatusNotifierExport(
          appId: 'test',
          menuPath: DBusObjectPath('/MenuBar'),
          icon: Pixmap(1, 1, Uint8List.fromList([255, 1, 2, 3])),
          tooltip: 'Termphin',
          onActivate: onActivate,
        );

    test('answers its properties under KDE\'s interface name', () async {
      final response = await item().getProperty(
        'org.kde.StatusNotifierItem',
        'ToolTip',
      );

      expect(response, isA<DBusGetPropertyResponse>());
      expect(response.returnValues.single.signature.value, 'v');
      final tooltip = response.returnValues.single.asVariant();
      expect(tooltip.signature.value, '(sa(iiay)ss)');
      expect(tooltip.asStruct()[2].asString(), 'Termphin');
    });

    test('activates after replying', () async {
      var activated = 0;
      final response = await item(onActivate: () => activated++)
          .handleMethodCall(
            _call('org.kde.StatusNotifierItem', 'Activate', const [
              DBusInt32(0),
              DBusInt32(0),
            ]),
          );

      expect(response, isA<DBusMethodSuccessResponse>());
      expect(activated, 0);
      await pumpEventQueue();
      expect(activated, 1);
    });
  });

  test('pixels go out as ARGB', () {
    expect(Pixmap.rgbaToArgb(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])), [
      4,
      1,
      2,
      3,
      8,
      5,
      6,
      7,
    ]);
  });
}
