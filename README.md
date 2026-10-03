# tray_kit

A system tray icon with a menu for Flutter on Linux, Windows and macOS.

- **Linux with nothing to install.** The icon is a StatusNotifierItem with a
  dbusmenu menu, spoken over the session bus in Dart. No libappindicator to
  build against or to ship. KDE, Xfce, Cinnamon, and GNOME with the
  AppIndicator extension draw it.
- **Windows**: a notification area icon. **macOS**: a menu bar item, with
  template images.
- One small API: an icon, a tooltip, a menu with submenus, a click.

## Usage

```dart
import 'package:tray_kit/tray_kit.dart';

final tray = TrayKit.instance;

if (await tray.isSupported()) {
  await tray.show(
    icon: await TrayIcon.asset('assets/tray.png'),
    tooltip: 'My app',
    onActivate: showWindow,
    menu: [
      TrayMenuAction('Show', onSelected: showWindow),
      const TrayMenuSeparator(),
      TraySubmenu('Recent', [
        TrayMenuAction('notes.txt', onSelected: () => open('notes.txt')),
      ]),
      const TrayMenuSeparator(),
      TrayMenuAction('Quit', onSelected: quit),
    ],
  );
}
```

Calling `show` again replaces the icon, tooltip and menu. `hide` takes the
icon down.

On macOS a click on the item opens its menu, so `onActivate` is not called
there. Pass `isTemplate: true` for a monochrome icon the menu bar tints.

## Linux

`isSupported()` is false when no StatusNotifierItem host is running - GNOME
without the AppIndicator extension, or a session without D-Bus. Check it
before hiding a window into the tray, or the window has no way back.

Every call on the bus is checked: unknown ids are refused, a click on a
disabled entry does nothing, and callbacks run after the reply goes out.

## License

MIT
