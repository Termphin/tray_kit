import Cocoa
import FlutterMacOS

/// The menu bar item behind `TrayKit` on macOS.
public class TrayKitPlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private var statusItem: NSStatusItem?

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "tray_kit", binaryMessenger: registrar.messenger)
    let instance = TrayKitPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "show":
      guard let arguments = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad-arguments", message: "show takes a map", details: nil))
        return
      }
      show(arguments)
      result(nil)
    case "hide":
      hide()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func show(_ arguments: [String: Any]) {
    let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem = item
    if let button = item.button {
      if let data = (arguments["icon"] as? FlutterStandardTypedData)?.data,
        let image = NSImage(data: data)
      {
        let side = NSStatusBar.system.thickness - 4
        let scale = side / max(image.size.width, image.size.height)
        image.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        image.isTemplate = arguments["template"] as? Bool ?? false
        button.image = image
      }
      button.toolTip = arguments["tooltip"] as? String
    }
    let menu = NSMenu()
    menu.autoenablesItems = false
    append(arguments["menu"] as? [Any] ?? [], to: menu)
    item.menu = menu
  }

  private func hide() {
    if let item = statusItem {
      NSStatusBar.system.removeStatusItem(item)
    }
    statusItem = nil
  }

  private func append(_ entries: [Any], to menu: NSMenu) {
    for case let entry as [String: Any] in entries {
      if entry["separator"] as? Bool == true {
        menu.addItem(NSMenuItem.separator())
        continue
      }
      let item = NSMenuItem(title: entry["label"] as? String ?? "", action: nil, keyEquivalent: "")
      item.isEnabled = entry["enabled"] as? Bool ?? true
      if let children = entry["children"] as? [Any] {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        append(children, to: submenu)
        item.submenu = submenu
      } else if let id = entry["id"] as? Int {
        item.target = self
        item.action = #selector(picked(_:))
        item.tag = id
      }
      menu.addItem(item)
    }
  }

  @objc private func picked(_ sender: NSMenuItem) {
    NSApp.activate(ignoringOtherApps: true)
    channel.invokeMethod("select", arguments: sender.tag)
  }
}
