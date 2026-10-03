import 'dart:async';

import 'package:dbus/dbus.dart';

import 'menu_tree.dart';

const kDBusMenuInterface = 'com.canonical.dbusmenu';
const _unknownId = 'com.canonical.dbusmenu.UnknownId';
const _unknownProperty = 'com.canonical.dbusmenu.UnknownProperty';

/// A [MenuTree] on the bus under `com.canonical.dbusmenu`, version 3.
///
/// Every id a caller sends is looked up before it is used, and a click runs
/// only after the reply, on an entry that is enabled.
class DBusMenuExport extends DBusObject {
  DBusMenuExport(super.path, this._tree);

  MenuTree _tree;
  var _revision = 1;

  int get revision => _revision;

  /// Swaps in [tree] and has hosts read the layout again.
  Future<void> replace(MenuTree tree) async {
    _tree = tree;
    _revision++;
    await emitSignal(kDBusMenuInterface, 'LayoutUpdated', [
      DBusUint32(_revision),
      const DBusInt32(0),
    ]);
  }

  static Map<String, DBusValue> get _ownProperties => {
    'Version': const DBusUint32(3),
    'TextDirection': const DBusString('ltr'),
    'Status': const DBusString('normal'),
    'IconThemePath': DBusArray.string(const []),
  };

  static Map<String, DBusValue> _propertiesOf(MenuNode node) => {
    if (node.separator) 'type': const DBusString('separator'),
    if (node.label case final label?)
      'label': DBusString(label.replaceAll('_', '__')),
    if (!node.enabled) 'enabled': const DBusBoolean(false),
    if (node.children.isNotEmpty)
      'children-display': const DBusString('submenu'),
  };

  static Map<String, DBusValue> _filter(
    Map<String, DBusValue> properties,
    Set<String> names,
  ) => names.isEmpty
      ? properties
      : {
          for (final entry in properties.entries)
            if (names.contains(entry.key)) entry.key: entry.value,
        };

  DBusValue _layout(MenuNode node, int depth, Set<String> names) => DBusStruct([
    DBusInt32(node.id),
    DBusDict.stringVariant(_filter(_propertiesOf(node), names)),
    DBusArray.variant([
      if (depth != 0)
        for (final id in node.children)
          _layout(_tree[id]!, depth < 0 ? depth : depth - 1, names),
    ]),
  ]);

  void _event(MenuNode node, String event) {
    final onSelected = node.onSelected;
    if (event == 'clicked' && node.enabled && onSelected != null) {
      Timer.run(onSelected);
    }
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != kDBusMenuInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final args = methodCall.values;
    final signature = methodCall.signature.value;
    return switch ((methodCall.name, signature)) {
      ('GetLayout', 'iias') => _getLayout(
        args[0].asInt32(),
        args[1].asInt32(),
        args[2].asStringArray().toSet(),
      ),
      ('GetGroupProperties', 'aias') => _getGroupProperties(
        args[0].asInt32Array(),
        args[1].asStringArray().toSet(),
      ),
      ('GetProperty', 'is') => _getProperty(
        args[0].asInt32(),
        args[1].asString(),
      ),
      ('Event', 'isvu') => _onEvent(args[0].asInt32(), args[1].asString()),
      ('EventGroup', 'a(isvu)') => _onEventGroup(args[0].asArray()),
      ('AboutToShow', 'i') =>
        _tree[args[0].asInt32()] == null
            ? DBusMethodErrorResponse(_unknownId)
            : DBusMethodSuccessResponse([const DBusBoolean(false)]),
      ('AboutToShowGroup', 'ai') => DBusMethodSuccessResponse([
        DBusArray.int32(const []),
        DBusArray.int32([
          for (final id in args[0].asInt32Array())
            if (_tree[id] == null) id,
        ]),
      ]),
      (
        'GetLayout' ||
            'GetGroupProperties' ||
            'GetProperty' ||
            'Event' ||
            'EventGroup' ||
            'AboutToShow' ||
            'AboutToShowGroup',
        _,
      ) =>
        DBusMethodErrorResponse.invalidArgs(),
      _ => DBusMethodErrorResponse.unknownMethod(),
    };
  }

  DBusMethodResponse _getLayout(int parent, int depth, Set<String> names) {
    final node = _tree[parent];
    if (node == null) return DBusMethodErrorResponse(_unknownId);
    return DBusMethodSuccessResponse([
      DBusUint32(_revision),
      _layout(node, depth, names),
    ]);
  }

  DBusMethodResponse _getGroupProperties(Iterable<int> ids, Set<String> names) {
    final nodes = ids.isEmpty
        ? _tree.nodes
        : [for (final id in ids) ?_tree[id]];
    return DBusMethodSuccessResponse([
      DBusArray(DBusSignature('(ia{sv})'), [
        for (final node in nodes)
          DBusStruct([
            DBusInt32(node.id),
            DBusDict.stringVariant(_filter(_propertiesOf(node), names)),
          ]),
      ]),
    ]);
  }

  DBusMethodResponse _getProperty(int id, String name) {
    final node = _tree[id];
    if (node == null) return DBusMethodErrorResponse(_unknownId);
    final value = _propertiesOf(node)[name];
    if (value == null) return DBusMethodErrorResponse(_unknownProperty);
    return DBusMethodSuccessResponse([DBusVariant(value)]);
  }

  DBusMethodResponse _onEvent(int id, String event) {
    final node = _tree[id];
    if (node == null) return DBusMethodErrorResponse(_unknownId);
    _event(node, event);
    return DBusMethodSuccessResponse();
  }

  DBusMethodResponse _onEventGroup(List<DBusValue> events) {
    final unknown = <int>[];
    for (final event in events) {
      final fields = event.asStruct();
      final id = fields[0].asInt32();
      final node = _tree[id];
      if (node == null) {
        unknown.add(id);
      } else {
        _event(node, fields[1].asString());
      }
    }
    return DBusMethodSuccessResponse([DBusArray.int32(unknown)]);
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final value = interface == kDBusMenuInterface ? _ownProperties[name] : null;
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async =>
      DBusGetAllPropertiesResponse(
        interface == kDBusMenuInterface ? _ownProperties : const {},
      );

  @override
  List<DBusIntrospectInterface> introspect() => [
    DBusIntrospectInterface(
      kDBusMenuInterface,
      methods: [
        _method('GetLayout', ['i', 'i', 'as'], ['u', '(ia{sv}av)']),
        _method('GetGroupProperties', ['ai', 'as'], ['a(ia{sv})']),
        _method('GetProperty', ['i', 's'], ['v']),
        _method('Event', ['i', 's', 'v', 'u'], []),
        _method('EventGroup', ['a(isvu)'], ['ai']),
        _method('AboutToShow', ['i'], ['b']),
        _method('AboutToShowGroup', ['ai'], ['ai', 'ai']),
      ],
      signals: [
        DBusIntrospectSignal(
          'LayoutUpdated',
          args: [
            DBusIntrospectArgument(
              DBusSignature('u'),
              DBusArgumentDirection.out,
            ),
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.out,
            ),
          ],
        ),
      ],
      properties: [
        for (final entry in _ownProperties.entries)
          DBusIntrospectProperty(
            entry.key,
            entry.value.signature,
            access: DBusPropertyAccess.read,
          ),
      ],
    ),
  ];
}

DBusIntrospectMethod _method(
  String name,
  List<String> inputs,
  List<String> outputs,
) => DBusIntrospectMethod(
  name,
  args: [
    for (final type in inputs)
      DBusIntrospectArgument(DBusSignature(type), DBusArgumentDirection.in_),
    for (final type in outputs)
      DBusIntrospectArgument(DBusSignature(type), DBusArgumentDirection.out),
  ],
);
