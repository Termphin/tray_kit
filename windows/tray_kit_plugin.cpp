#include "include/tray_kit/tray_kit_plugin.h"

#include <windows.h>

#include <shellapi.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <variant>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr UINT kCallbackMessage = WM_APP + 0x7A1;
constexpr UINT kIconId = 1;

std::wstring Utf16(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int length = ::MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  if (length <= 0) return std::wstring();
  std::wstring utf16(static_cast<size_t>(length), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                        static_cast<int>(utf8.size()), utf16.data(), length);
  return utf16;
}

const EncodableValue* Find(const EncodableMap& map, const char* key) {
  const auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

template <typename T>
const T* Get(const EncodableMap& map, const char* key) {
  const EncodableValue* value = Find(map, key);
  return value == nullptr ? nullptr : std::get_if<T>(value);
}

int64_t Id(const EncodableMap& map) {
  const EncodableValue* value = Find(map, "id");
  if (value == nullptr) return 0;
  if (const auto* narrow = std::get_if<int32_t>(value)) return *narrow;
  if (const auto* wide = std::get_if<int64_t>(value)) return *wide;
  return 0;
}

std::wstring MenuLabel(const std::string& utf8) {
  std::wstring label;
  for (const wchar_t c : Utf16(utf8)) {
    label.push_back(c);
    if (c == L'&') label.push_back(L'&');
  }
  return label;
}

void AppendItems(HMENU menu, const EncodableList& items) {
  for (const EncodableValue& item : items) {
    const auto* map = std::get_if<EncodableMap>(&item);
    if (map == nullptr) continue;
    if (const bool* separator = Get<bool>(*map, "separator");
        separator != nullptr && *separator) {
      ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
      continue;
    }
    const std::string* label = Get<std::string>(*map, "label");
    const std::wstring text = MenuLabel(label == nullptr ? "" : *label);
    const bool* enabled = Get<bool>(*map, "enabled");
    const UINT state = (enabled == nullptr || *enabled) ? MF_ENABLED : MF_GRAYED;
    const EncodableList* children = Get<EncodableList>(*map, "children");
    if (children != nullptr) {
      HMENU submenu = ::CreatePopupMenu();
      AppendItems(submenu, *children);
      ::AppendMenuW(menu, MF_POPUP | MF_STRING | state,
                    reinterpret_cast<UINT_PTR>(submenu), text.c_str());
    } else {
      ::AppendMenuW(menu, MF_STRING | state, static_cast<UINT_PTR>(Id(*map)),
                    text.c_str());
    }
  }
}

class TrayKitPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit TrayKitPlugin(flutter::PluginRegistrarWindows* registrar);
  ~TrayKitPlugin() override;

  TrayKitPlugin(const TrayKitPlugin&) = delete;
  TrayKitPlugin& operator=(const TrayKitPlugin&) = delete;

 private:
  HWND Window() const;
  void Show(const EncodableMap& arguments);
  void Hide();
  bool Publish();
  void ShowMenu();
  std::optional<LRESULT> HandleWindowProc(HWND hwnd, UINT message,
                                          WPARAM wparam, LPARAM lparam);

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel_;
  int window_proc_id_ = -1;
  UINT taskbar_created_;
  HICON icon_ = nullptr;
  std::wstring tooltip_;
  EncodableList menu_;
  bool added_ = false;
  bool wanted_ = false;
};

void TrayKitPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  registrar->AddPlugin(std::make_unique<TrayKitPlugin>(registrar));
}

TrayKitPlugin::TrayKitPlugin(flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar),
      taskbar_created_(::RegisterWindowMessageW(L"TaskbarCreated")) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "tray_kit",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() == "show") {
          const auto* arguments = std::get_if<EncodableMap>(call.arguments());
          if (arguments == nullptr) {
            result->Error("bad-arguments", "show takes a map");
            return;
          }
          Show(*arguments);
          result->Success();
        } else if (call.method_name() == "hide") {
          Hide();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
  window_proc_id_ = registrar->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowProc(hwnd, message, wparam, lparam);
      });
}

TrayKitPlugin::~TrayKitPlugin() {
  registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
  Hide();
  channel_->SetMethodCallHandler(nullptr);
}

HWND TrayKitPlugin::Window() const {
  return ::GetAncestor(registrar_->GetView()->GetNativeWindow(), GA_ROOT);
}

void TrayKitPlugin::Show(const EncodableMap& arguments) {
  const std::string* tooltip = Get<std::string>(arguments, "tooltip");
  tooltip_ = Utf16(tooltip == nullptr ? "" : *tooltip);
  const EncodableList* menu = Get<EncodableList>(arguments, "menu");
  menu_ = menu == nullptr ? EncodableList() : *menu;

  if (const auto* png = Get<std::vector<uint8_t>>(arguments, "icon");
      png != nullptr && !png->empty()) {
    HICON icon = ::CreateIconFromResourceEx(
        const_cast<PBYTE>(png->data()), static_cast<DWORD>(png->size()), TRUE,
        0x00030000, ::GetSystemMetrics(SM_CXSMICON),
        ::GetSystemMetrics(SM_CYSMICON), LR_DEFAULTCOLOR);
    if (icon != nullptr) {
      if (icon_ != nullptr) ::DestroyIcon(icon_);
      icon_ = icon;
    }
  }
  wanted_ = true;
  Publish();
}

bool TrayKitPlugin::Publish() {
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = Window();
  data.uID = kIconId;
  data.uFlags = NIF_MESSAGE | NIF_TIP | (icon_ != nullptr ? NIF_ICON : 0);
  data.uCallbackMessage = kCallbackMessage;
  data.hIcon = icon_;
  wcsncpy_s(data.szTip, tooltip_.c_str(), _TRUNCATE);
  const BOOL ok = ::Shell_NotifyIconW(added_ ? NIM_MODIFY : NIM_ADD, &data);
  if (ok) added_ = true;
  return ok != FALSE;
}

void TrayKitPlugin::Hide() {
  wanted_ = false;
  if (added_) {
    NOTIFYICONDATAW data = {};
    data.cbSize = sizeof(data);
    data.hWnd = Window();
    data.uID = kIconId;
    ::Shell_NotifyIconW(NIM_DELETE, &data);
    added_ = false;
  }
  if (icon_ != nullptr) {
    ::DestroyIcon(icon_);
    icon_ = nullptr;
  }
}

void TrayKitPlugin::ShowMenu() {
  HMENU menu = ::CreatePopupMenu();
  if (menu == nullptr) return;
  AppendItems(menu, menu_);
  POINT cursor;
  ::GetCursorPos(&cursor);
  const HWND window = Window();
  ::SetForegroundWindow(window);
  const UINT picked = static_cast<UINT>(::TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, cursor.x, cursor.y,
      0, window, nullptr));
  ::PostMessageW(window, WM_NULL, 0, 0);
  ::DestroyMenu(menu);
  if (picked != 0) {
    channel_->InvokeMethod("select", std::make_unique<EncodableValue>(
                                         static_cast<int32_t>(picked)));
  }
}

std::optional<LRESULT> TrayKitPlugin::HandleWindowProc(HWND hwnd, UINT message,
                                                       WPARAM wparam,
                                                       LPARAM lparam) {
  if (message == taskbar_created_) {
    added_ = false;
    if (wanted_) Publish();
    return std::nullopt;
  }
  if (message != kCallbackMessage) return std::nullopt;
  switch (LOWORD(lparam)) {
    case WM_LBUTTONUP:
      channel_->InvokeMethod("activate", nullptr);
      break;
    case WM_RBUTTONUP:
    case WM_CONTEXTMENU:
      ShowMenu();
      break;
  }
  return 0;
}

}

void TrayKitPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  TrayKitPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
