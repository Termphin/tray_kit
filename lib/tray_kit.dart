/// A system tray icon with a menu, on Linux, Windows and macOS.
library;

export 'src/channel.dart' show MethodChannelTrayKit;
export 'src/icon.dart';
export 'src/linux/linux_tray_kit.dart' show LinuxTrayKit;
export 'src/menu.dart' hide EncodedTrayMenu;
export 'src/platform.dart';
export 'src/tray_kit.dart';
