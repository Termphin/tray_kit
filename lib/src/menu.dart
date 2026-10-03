import 'package:flutter/foundation.dart';

/// An entry in the tray icon's menu.
@immutable
sealed class TrayMenuItem {
  const TrayMenuItem();
}

/// A menu entry that runs [onSelected] when picked.
final class TrayMenuAction extends TrayMenuItem {
  const TrayMenuAction(this.label, {this.onSelected, this.enabled = true});

  final String label;
  final VoidCallback? onSelected;
  final bool enabled;
}

/// A menu entry that opens [items] as a submenu.
final class TraySubmenu extends TrayMenuItem {
  const TraySubmenu(this.label, this.items, {this.enabled = true});

  final String label;
  final List<TrayMenuItem> items;
  final bool enabled;
}

/// A line between groups of entries.
final class TrayMenuSeparator extends TrayMenuItem {
  const TrayMenuSeparator();
}

/// A menu with every action numbered, as a native side receives it.
@immutable
class EncodedTrayMenu {
  const EncodedTrayMenu(this.items, this.actions);

  /// Maps of `separator`, or `id`, `label`, `enabled` and `children`.
  final List<Map<String, Object?>> items;

  /// The callback behind each id in [items].
  final Map<int, VoidCallback> actions;

  /// Numbers [menu] depth first, starting at 1.
  factory EncodedTrayMenu.encode(List<TrayMenuItem> menu) {
    final actions = <int, VoidCallback>{};
    var next = 1;

    List<Map<String, Object?>> encode(List<TrayMenuItem> items) {
      final encoded = <Map<String, Object?>>[];
      for (final item in items) {
        switch (item) {
          case TrayMenuSeparator():
            encoded.add({'separator': true});
          case TrayMenuAction(:final label, :final enabled, :final onSelected):
            final id = next++;
            if (onSelected != null) actions[id] = onSelected;
            encoded.add({'id': id, 'label': label, 'enabled': enabled});
          case TraySubmenu(:final label, :final enabled, :final items):
            final id = next++;
            encoded.add({
              'id': id,
              'label': label,
              'enabled': enabled,
              'children': encode(items),
            });
        }
      }
      return encoded;
    }

    return EncodedTrayMenu(encode(menu), actions);
  }
}
