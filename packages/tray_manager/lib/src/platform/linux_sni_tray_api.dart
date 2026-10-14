import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dbus/dbus.dart';
import 'package:tray_manager/src/platform/tray_api.dart';
import 'package:tray_manager/src/platform/tray_callback_api.dart';

/// Linux tray in pure Dart: a StatusNotifierItem (the icon) with a
/// com.canonical.dbusmenu menu on the session bus - what KDE, XFCE,
/// Cinnamon, MATE, Budgie and Ubuntu's GNOME (AppIndicator extension) show.
/// No native code and no new system library.
///
/// Without a StatusNotifierWatcher (plain GNOME) there is no tray:
/// [available] stays false and the app must not hide its window to it.
class LinuxSniTrayApi extends TrayApi {
  static const _itemPath = '/StatusNotifierItem';
  static const _menuPath = '/MenuBar';
  static const _itemInterface = 'org.kde.StatusNotifierItem';
  static const _menuInterface = 'com.canonical.dbusmenu';

  /// Whether a tray host took our icon.
  static bool available = false;

  LinuxSniTrayApi() : super('tray_manager');

  DBusClient? _client;
  _SniItem? _item;
  _DbusMenu? _menu;

  @override
  Future<void> initTray(List<Map<String, Object?>> items) async {
    if (_client != null) return updateMenu(items);
    final client = DBusClient.session(introspectable: false);
    final item = _SniItem();
    final menu = _DbusMenu();
    try {
      await client.registerObject(item);
      await client.registerObject(menu);
      final name = 'org.kde.StatusNotifierItem-$pid-1';
      await client.requestName(name);
      menu.setItems(items);
      await client.callMethod(
        destination: 'org.kde.StatusNotifierWatcher',
        path: DBusObjectPath('/StatusNotifierWatcher'),
        interface: 'org.kde.StatusNotifierWatcher',
        name: 'RegisterStatusNotifierItem',
        values: [DBusString(name)],
      );
      _client = client;
      _item = item;
      _menu = menu;
      available = true;
    } on Object {
      // No watcher (plain GNOME) or no session bus: no tray, quietly.
      available = false;
      await client.close();
    }
  }

  @override
  Future<void> updateMenu(List<Map<String, Object?>> items) async {
    final menu = _menu;
    if (menu == null) return;
    menu.setItems(items);
    await menu.emitSignal(_menuInterface, 'LayoutUpdated', [DBusUint32(menu.revision), const DBusInt32(0)]);
  }

  @override
  Future<void> setTrayIconPng(Uint8List iconPng, bool isMonochrome) async {
    final item = _item;
    if (item == null) return;
    item.pixmap = await _argbPixmap(iconPng, light: isMonochrome);
    await item.emitSignal(_itemInterface, 'NewIcon');
  }

  @override
  Future<void> disposeTray() async {
    available = false;
    await _client?.close();
    _client = null;
    _item = null;
    _menu = null;
  }

  /// IconPixmap wants ARGB32 in network byte order. A monochrome (template)
  /// icon is drawn in white: Linux panels are dark far more often than not.
  static Future<DBusValue> _argbPixmap(Uint8List png, {required bool light}) async {
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();
    final argb = Uint8List(rgba.length);
    for (var i = 0; i < rgba.length; i += 4) {
      argb[i] = rgba[i + 3];
      argb[i + 1] = light ? 255 : rgba[i];
      argb[i + 2] = light ? 255 : rgba[i + 1];
      argb[i + 3] = light ? 255 : rgba[i + 2];
    }

    return DBusArray(DBusSignature('(iiay)'), [
      DBusStruct([DBusInt32(image.width), DBusInt32(image.height), DBusArray.byte(argb)]),
    ]);
  }
}

class _SniItem extends DBusObject {
  _SniItem() : super(DBusObjectPath(LinuxSniTrayApi._itemPath));

  DBusValue pixmap = DBusArray(DBusSignature('(iiay)'));

  Map<String, DBusValue> get _properties => {
    'Category': const DBusString('ApplicationStatus'),
    'Id': const DBusString('cattunnel'),
    'Title': const DBusString('CatTunnel'),
    'Status': const DBusString('Active'),
    'WindowId': const DBusInt32(0),
    'IconName': const DBusString(''),
    'IconPixmap': pixmap,
    'ItemIsMenu': const DBusBoolean(true),
    'Menu': DBusObjectPath(LinuxSniTrayApi._menuPath),
    'ToolTip': DBusStruct([
      const DBusString(''),
      DBusArray(DBusSignature('(iiay)')),
      const DBusString('CatTunnel'),
      const DBusString(''),
    ]),
  };

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != LinuxSniTrayApi._itemInterface) return DBusMethodErrorResponse.unknownInterface();

    // ItemIsMenu: hosts open the menu themselves; these are no-ops.
    return switch (methodCall.name) {
      'ContextMenu' || 'Activate' || 'SecondaryActivate' || 'Scroll' => DBusMethodSuccessResponse(),
      _ => DBusMethodErrorResponse.unknownMethod(),
    };
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final value = interface == LinuxSniTrayApi._itemInterface ? _properties[name] : null;

    return value == null ? DBusMethodErrorResponse.unknownProperty() : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async =>
      DBusGetAllPropertiesResponse(interface == LinuxSniTrayApi._itemInterface ? _properties : {});
}

/// com.canonical.dbusmenu over the tray_manager item maps (TrayItemConverter):
/// `type` button/status/separator, `text`, `isEnabled`, `isChecked`,
/// `iconPng`, `children`; clicks go to the registered TrayCallbackApi by id.
class _DbusMenu extends DBusObject {
  _DbusMenu() : super(DBusObjectPath(LinuxSniTrayApi._menuPath));

  int revision = 0;

  /// dbusmenu id -> item map; 0 is the root.
  final _byId = <int, Map<String, Object?>>{};

  /// dbusmenu id -> its children's ids.
  final _childIds = <int, List<int>>{};

  void setItems(List<Map<String, Object?>> items) {
    revision++;
    _byId.clear();
    _childIds.clear();
    var next = 1;
    List<int> index(List<Map<String, Object?>> list) => [
      for (final item in list)
        () {
          final id = next++;
          _byId[id] = item;
          _childIds[id] = index(_children(item));

          return id;
        }(),
    ];

    _childIds[0] = index(items);
  }

  static List<Map<String, Object?>> _children(Map<String, Object?> item) => [
    for (final child in item['children'] as List<Object?>? ?? const [])
      if (child is Map) Map<String, Object?>.from(child),
  ];

  Map<String, DBusValue> _props(Map<String, Object?>? item) {
    if (item == null) return {'children-display': const DBusString('submenu')};
    final type = item['type'];
    if (type == 'separator') return {'type': const DBusString('separator')};
    final props = <String, DBusValue>{
      'label': DBusString((item['text'] as String? ?? '').replaceAll('_', '__')),
      'enabled': DBusBoolean(type != 'status' && (item['isEnabled'] as bool? ?? true)),
    };
    if (item['isChecked'] == true) {
      props['toggle-type'] = const DBusString('checkmark');
      props['toggle-state'] = const DBusInt32(1);
    }
    final icon = item['iconPng'];
    if (icon is Uint8List) props['icon-data'] = DBusArray.byte(icon);
    if (_children(item).isNotEmpty) props['children-display'] = const DBusString('submenu');

    return props;
  }

  DBusValue _layout(int id, int depth) => DBusStruct([
    DBusInt32(id),
    DBusDict.stringVariant(_props(_byId[id])),
    DBusArray.variant([
      if (depth != 0)
        for (final child in _childIds[id] ?? const <int>[]) _layout(child, depth < 0 ? -1 : depth - 1),
    ]),
  ]);

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != LinuxSniTrayApi._menuInterface) return DBusMethodErrorResponse.unknownInterface();
    final args = methodCall.values;
    switch (methodCall.name) {
      case 'GetLayout':
        final parent = args[0].asInt32();
        final depth = args[1].asInt32();

        return DBusMethodSuccessResponse([DBusUint32(revision), _layout(parent, depth)]);
      case 'GetGroupProperties':
        final ids = (args[0] as DBusArray).mapInt32();

        return DBusMethodSuccessResponse([
          DBusArray(DBusSignature('(ia{sv})'), [
            for (final id in ids.isEmpty ? _byId.keys : ids)
              if (id == 0 || _byId.containsKey(id))
                DBusStruct([DBusInt32(id), DBusDict.stringVariant(_props(_byId[id]))]),
          ]),
        ]);
      case 'GetProperty':
        final value = _props(_byId[args[0].asInt32()])[args[1].asString()];

        return value == null
            ? DBusMethodErrorResponse.unknownProperty()
            : DBusMethodSuccessResponse([DBusVariant(value)]);
      case 'Event':
        if (args[1].asString() == 'clicked') _click(args[0].asInt32());

        return DBusMethodSuccessResponse();
      case 'EventGroup':
        for (final event in (args[0] as DBusArray).children) {
          final fields = (event as DBusStruct).children;
          if (fields[1].asString() == 'clicked') _click(fields[0].asInt32());
        }

        return DBusMethodSuccessResponse([DBusArray.int32(const [])]);
      case 'AboutToShow':
        return DBusMethodSuccessResponse([const DBusBoolean(false)]);
      case 'AboutToShowGroup':
        return DBusMethodSuccessResponse([DBusArray.int32(const []), DBusArray.int32(const [])]);
    }

    return DBusMethodErrorResponse.unknownMethod();
  }

  void _click(int id) {
    final key = _byId[id]?['id'];
    // The host calls from the bus; the app's callbacks expect the UI loop.
    if (key is String) scheduleMicrotask(() => TrayCallbackApiSetup.current?.onMenuItemClicked(key));
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final value = interface == LinuxSniTrayApi._menuInterface ? _menuProperties[name] : null;

    return value == null ? DBusMethodErrorResponse.unknownProperty() : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async =>
      DBusGetAllPropertiesResponse(interface == LinuxSniTrayApi._menuInterface ? _menuProperties : {});

  static final _menuProperties = <String, DBusValue>{
    'Version': const DBusUint32(3),
    'TextDirection': const DBusString('ltr'),
    'Status': const DBusString('normal'),
    'IconThemePath': DBusArray.string(const []),
  };
}
