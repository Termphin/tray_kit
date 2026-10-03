import 'package:flutter/foundation.dart';

import '../menu.dart';

/// One entry of a [MenuTree], under the id the bus knows it by.
@immutable
class MenuNode {
  const MenuNode({
    required this.id,
    this.label,
    this.enabled = true,
    this.separator = false,
    this.children = const [],
    this.onSelected,
  });

  final int id;
  final String? label;
  final bool enabled;
  final bool separator;
  final List<int> children;
  final VoidCallback? onSelected;
}

/// A menu flattened into ids: 0 is the root, the entries follow depth first.
class MenuTree {
  MenuTree(List<TrayMenuItem> items) {
    _nodes[0] = MenuNode(id: 0, children: _add(items));
  }

  final _nodes = <int, MenuNode>{};
  var _next = 1;

  List<int> _add(List<TrayMenuItem> items) {
    final ids = <int>[];
    for (final item in items) {
      final id = _next++;
      ids.add(id);
      _nodes[id] = switch (item) {
        TrayMenuSeparator() => MenuNode(id: id, separator: true),
        TrayMenuAction(:final label, :final enabled, :final onSelected) =>
          MenuNode(
            id: id,
            label: label,
            enabled: enabled,
            onSelected: onSelected,
          ),
        TraySubmenu(:final label, :final enabled, :final items) => MenuNode(
          id: id,
          label: label,
          enabled: enabled,
          children: _add(items),
        ),
      };
    }
    return ids;
  }

  /// The node under [id], or null for an id this menu never had.
  MenuNode? operator [](int id) => _nodes[id];

  Iterable<MenuNode> get nodes => _nodes.values;
}
