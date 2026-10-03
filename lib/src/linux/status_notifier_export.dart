import 'dart:async';

import 'package:dbus/dbus.dart';

import 'pixmap.dart';

/// The interface names hosts use for an item; KDE's is the one in practice.
const kStatusNotifierItemInterfaces = {
  'org.kde.StatusNotifierItem',
  'org.freedesktop.StatusNotifierItem',
};

/// The tray icon itself on the bus: its picture, tooltip and menu path.
class StatusNotifierExport extends DBusObject {
  StatusNotifierExport({
    required this.appId,
    required this.menuPath,
    required this.icon,
    required this.tooltip,
    this.onActivate,
  }) : super(DBusObjectPath('/StatusNotifierItem'));

  final String appId;
  final DBusObjectPath menuPath;
  Pixmap icon;
  String tooltip;
  void Function()? onActivate;

  Map<String, DBusValue> get _properties => {
    'Category': const DBusString('ApplicationStatus'),
    'Id': DBusString(appId),
    'Title': DBusString(tooltip),
    'Status': const DBusString('Active'),
    'WindowId': const DBusInt32(0),
    'IconName': const DBusString(''),
    'IconPixmap': Pixmap.array([icon]),
    'OverlayIconName': const DBusString(''),
    'OverlayIconPixmap': Pixmap.array(const []),
    'AttentionIconName': const DBusString(''),
    'AttentionIconPixmap': Pixmap.array(const []),
    'AttentionMovieName': const DBusString(''),
    'ToolTip': DBusStruct([
      const DBusString(''),
      Pixmap.array(const []),
      DBusString(tooltip),
      const DBusString(''),
    ]),
    'ItemIsMenu': const DBusBoolean(false),
    'Menu': menuPath,
  };

  /// Tells hosts that [signals] (`NewIcon`, `NewTitle`, `NewToolTip`) changed.
  Future<void> announce(Iterable<String> signals) async {
    for (final signal in signals) {
      for (final interface in kStatusNotifierItemInterfaces) {
        await emitSignal(interface, signal);
      }
    }
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (!kStatusNotifierItemInterfaces.contains(methodCall.interface)) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final signature = methodCall.signature.value;
    switch (methodCall.name) {
      case 'Activate' when signature == 'ii':
        if (onActivate case final activate?) Timer.run(activate);
        return DBusMethodSuccessResponse();
      case 'SecondaryActivate' || 'ContextMenu' when signature == 'ii':
        return DBusMethodSuccessResponse();
      case 'Scroll' when signature == 'is':
        return DBusMethodSuccessResponse();
      case 'ProvideXdgActivationToken' when signature == 's':
        return DBusMethodSuccessResponse();
      case 'Activate' ||
          'SecondaryActivate' ||
          'ContextMenu' ||
          'Scroll' ||
          'ProvideXdgActivationToken':
        return DBusMethodErrorResponse.invalidArgs();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final value = kStatusNotifierItemInterfaces.contains(interface)
        ? _properties[name]
        : null;
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async =>
      DBusGetAllPropertiesResponse(
        kStatusNotifierItemInterfaces.contains(interface)
            ? _properties
            : const {},
      );

  @override
  List<DBusIntrospectInterface> introspect() => [
    DBusIntrospectInterface(
      kStatusNotifierItemInterfaces.first,
      methods: [
        for (final name in ['Activate', 'SecondaryActivate', 'ContextMenu'])
          _pointMethod(name),
        DBusIntrospectMethod(
          'Scroll',
          args: [
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.in_,
            ),
            DBusIntrospectArgument(
              DBusSignature('s'),
              DBusArgumentDirection.in_,
            ),
          ],
        ),
      ],
      signals: [
        for (final name in ['NewIcon', 'NewTitle', 'NewToolTip'])
          DBusIntrospectSignal(name),
      ],
      properties: [
        for (final entry in _properties.entries)
          DBusIntrospectProperty(
            entry.key,
            entry.value.signature,
            access: DBusPropertyAccess.read,
          ),
      ],
    ),
  ];
}

DBusIntrospectMethod _pointMethod(String name) => DBusIntrospectMethod(
  name,
  args: [
    DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_),
    DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_),
  ],
);
