import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_kit/src/menu.dart';
import 'package:tray_kit/tray_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('numbers entries depth first and keeps their actions', () {
    final picked = <String>[];
    final encoded = EncodedTrayMenu.encode([
      TrayMenuAction('a', onSelected: () => picked.add('a')),
      const TrayMenuSeparator(),
      TraySubmenu('sub', [
        TrayMenuAction('b', onSelected: () => picked.add('b')),
        const TrayMenuAction('off', enabled: false),
      ]),
    ]);

    expect(encoded.items, [
      {'id': 1, 'label': 'a', 'enabled': true},
      {'separator': true},
      {
        'id': 2,
        'label': 'sub',
        'enabled': true,
        'children': [
          {'id': 3, 'label': 'b', 'enabled': true},
          {'id': 4, 'label': 'off', 'enabled': false},
        ],
      },
    ]);
    encoded.actions[3]!();
    encoded.actions[1]!();
    expect(picked, ['b', 'a']);
    expect(encoded.actions.containsKey(4), isFalse);
  });

  group('MethodChannelTrayKit', () {
    const channel = MethodChannel('tray_kit');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> sent;

    setUp(() {
      sent = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        sent.add(call);
        return null;
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<void> fromNative(String method, [Object? arguments]) =>
        messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall(method, arguments)),
          (_) {},
        );

    test('a pick and a click come back to their callbacks', () async {
      final platform = MethodChannelTrayKit(channel: channel);
      final picked = <String>[];
      var activated = 0;
      await platform.show(
        icon: TrayIcon.png(Uint8List.fromList([1, 2, 3]), isTemplate: true),
        tooltip: 'tip',
        menu: [TrayMenuAction('a', onSelected: () => picked.add('a'))],
        onActivate: () => activated++,
      );

      final arguments = sent.single.arguments as Map;
      expect(arguments['tooltip'], 'tip');
      expect(arguments['template'], isTrue);
      expect(arguments['icon'], [1, 2, 3]);

      await fromNative('select', 1);
      await fromNative('select', 99);
      await fromNative('select', 'not an id');
      await fromNative('activate');
      expect(picked, ['a']);
      expect(activated, 1);

      await platform.hide();
      await fromNative('select', 1);
      await fromNative('activate');
      expect(picked, ['a']);
      expect(activated, 1);
    });
  });
}
