import 'package:flutter/material.dart';
import 'package:tray_kit/tray_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tray = TrayKit.instance;
  final supported = await tray.isSupported();
  if (supported) {
    await tray.show(
      icon: await TrayIcon.asset('assets/tray.png'),
      tooltip: 'tray_kit example',
      onActivate: () => debugPrint('tray_kit: activated'),
      menu: [
        TrayMenuAction(
          'Say hello',
          onSelected: () => debugPrint('tray_kit: hello'),
        ),
        TraySubmenu('More', [
          TrayMenuAction(
            'Nested',
            onSelected: () => debugPrint('tray_kit: nested'),
          ),
          const TrayMenuAction('Disabled', enabled: false),
        ]),
        const TrayMenuSeparator(),
        TrayMenuAction('Hide', onSelected: tray.hide),
      ],
    );
  }
  debugPrint('tray_kit: shown supported=$supported');
  runApp(ExampleApp(supported: supported));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, required this.supported});

  final bool supported;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Text(
          supported ? 'Look in the tray' : 'This desktop has no tray',
        ),
      ),
    ),
  );
}
