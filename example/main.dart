import 'package:flutter/material.dart';
import 'package:tray_kit/tray_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tray = TrayKit.instance;
  if (await tray.isSupported()) {
    await tray.show(
      icon: await TrayIcon.asset('assets/tray.png'),
      tooltip: 'tray_kit example',
      menu: [
        TrayMenuAction('Say hello', onSelected: () => debugPrint('hello')),
        const TrayMenuSeparator(),
        TrayMenuAction('Hide', onSelected: tray.hide),
      ],
    );
  }
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Look in the tray'))),
    ),
  );
}
