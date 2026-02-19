#include "flutter_window.h"

#include <optional>
#include <string>
#include <vector>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <mmdeviceapi.h>
#include <functiondiscoverykeys_devpkey.h>
#include <shellapi.h>
#include <propidl.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

class ScopedComInit {
 public:
  ScopedComInit() : hr_(::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)) {}
  ~ScopedComInit() {
    if (hr_ == S_OK || hr_ == S_FALSE) {
      ::CoUninitialize();
    }
  }
  bool ok() const { return hr_ == S_OK || hr_ == S_FALSE || hr_ == RPC_E_CHANGED_MODE; }

 private:
  HRESULT hr_;
};

std::string WideToUtf8(const std::wstring& input) {
  if (input.empty()) {
    return std::string();
  }
  const int size_needed =
      ::WideCharToMultiByte(CP_UTF8, 0, input.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (size_needed <= 0) {
    return std::string();
  }
  std::string output;
  output.resize(static_cast<size_t>(size_needed - 1));
  ::WideCharToMultiByte(CP_UTF8, 0, input.c_str(), -1, output.data(), size_needed, nullptr, nullptr);
  return output;
}

struct AudioDeviceInfo {
  std::wstring id;
  std::wstring name;
  bool is_default = false;
};

std::optional<std::wstring> GetDefaultCaptureDeviceId() {
  ScopedComInit com;
  if (!com.ok()) {
    return std::nullopt;
  }
  IMMDeviceEnumerator* enumerator = nullptr;
  HRESULT hr = ::CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                  CLSCTX_ALL, __uuidof(IMMDeviceEnumerator),
                                  reinterpret_cast<void**>(&enumerator));
  if (FAILED(hr) || !enumerator) {
    return std::nullopt;
  }
  IMMDevice* device = nullptr;
  hr = enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &device);
  enumerator->Release();
  if (FAILED(hr) || !device) {
    return std::nullopt;
  }
  LPWSTR id = nullptr;
  std::optional<std::wstring> out;
  if (SUCCEEDED(device->GetId(&id)) && id) {
    out = std::wstring(id);
    ::CoTaskMemFree(id);
  }
  device->Release();
  return out;
}

std::vector<AudioDeviceInfo> ListCaptureDevices() {
  std::vector<AudioDeviceInfo> devices;
  ScopedComInit com;
  if (!com.ok()) {
    return devices;
  }
  IMMDeviceEnumerator* enumerator = nullptr;
  HRESULT hr = ::CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                  CLSCTX_ALL, __uuidof(IMMDeviceEnumerator),
                                  reinterpret_cast<void**>(&enumerator));
  if (FAILED(hr) || !enumerator) {
    return devices;
  }
  std::optional<std::wstring> default_id = GetDefaultCaptureDeviceId();

  IMMDeviceCollection* collection = nullptr;
  hr = enumerator->EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE, &collection);
  enumerator->Release();
  if (FAILED(hr) || !collection) {
    return devices;
  }
  UINT count = 0;
  collection->GetCount(&count);
  for (UINT i = 0; i < count; ++i) {
    IMMDevice* device = nullptr;
    if (FAILED(collection->Item(i, &device)) || !device) {
      continue;
    }
    LPWSTR id = nullptr;
    std::wstring device_id;
    if (SUCCEEDED(device->GetId(&id)) && id) {
      device_id = id;
      ::CoTaskMemFree(id);
    }
    IPropertyStore* store = nullptr;
    std::wstring friendly_name;
    if (SUCCEEDED(device->OpenPropertyStore(STGM_READ, &store)) && store) {
      PROPVARIANT prop;
      ::PropVariantInit(&prop);
      if (SUCCEEDED(store->GetValue(PKEY_Device_FriendlyName, &prop))) {
        if (prop.vt == VT_LPWSTR && prop.pwszVal) {
          friendly_name = prop.pwszVal;
        }
      }
      ::PropVariantClear(&prop);
      store->Release();
    }
    device->Release();

    AudioDeviceInfo info;
    info.id = device_id;
    info.name = friendly_name.empty() ? device_id : friendly_name;
    info.is_default = default_id.has_value() && device_id == default_id.value();
    devices.push_back(std::move(info));
  }
  collection->Release();
  return devices;
}

void ApplyStyleChange(HWND hwnd) {
  ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                     SWP_FRAMECHANGED);
}

void SetAlwaysOnTop(HWND hwnd, bool value) {
  ::SetWindowPos(hwnd, value ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

void SetSkipTaskbar(HWND hwnd, bool value) {
  LONG ex = ::GetWindowLong(hwnd, GWL_EXSTYLE);
  if (value) {
    ex |= WS_EX_TOOLWINDOW;
    ex &= ~WS_EX_APPWINDOW;
  } else {
    ex &= ~WS_EX_TOOLWINDOW;
    ex |= WS_EX_APPWINDOW;
  }
  ::SetWindowLong(hwnd, GWL_EXSTYLE, ex);
  ApplyStyleChange(hwnd);
}

void SetFrameless(HWND hwnd, bool value) {
  LONG style = ::GetWindowLong(hwnd, GWL_STYLE);
  if (value) {
    style &= ~WS_OVERLAPPEDWINDOW;
    style |= WS_POPUP;
  } else {
    style &= ~WS_POPUP;
    style |= WS_OVERLAPPEDWINDOW;
  }
  ::SetWindowLong(hwnd, GWL_STYLE, style);
  ApplyStyleChange(hwnd);
}

void SetResizable(HWND hwnd, bool value) {
  LONG style = ::GetWindowLong(hwnd, GWL_STYLE);
  if (value) {
    style |= WS_THICKFRAME | WS_MAXIMIZEBOX | WS_MINIMIZEBOX;
  } else {
    style &= ~WS_THICKFRAME;
    style &= ~WS_MAXIMIZEBOX;
    // Keep minimize box to allow task switching if needed.
  }
  ::SetWindowLong(hwnd, GWL_STYLE, style);
  ApplyStyleChange(hwnd);
}

void SetIgnoreMouseEvents(HWND hwnd, bool value) {
  LONG ex = ::GetWindowLong(hwnd, GWL_EXSTYLE);
  if (value) {
    ex |= WS_EX_LAYERED | WS_EX_TRANSPARENT;
  } else {
    ex &= ~WS_EX_TRANSPARENT;
  }
  ::SetWindowLong(hwnd, GWL_EXSTYLE, ex);
  ApplyStyleChange(hwnd);
}

void StartDragging(HWND hwnd) {
  ::ReleaseCapture();
  ::SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
}

void SetSize(HWND hwnd, int width, int height) {
  ::SetWindowPos(hwnd, nullptr, 0, 0, width, height,
                 SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
}

flutter::EncodableMap GetBounds(HWND hwnd) {
  RECT rect;
  ::GetWindowRect(hwnd, &rect);
  flutter::EncodableMap out;
  out[flutter::EncodableValue("x")] =
      flutter::EncodableValue(static_cast<int32_t>(rect.left));
  out[flutter::EncodableValue("y")] =
      flutter::EncodableValue(static_cast<int32_t>(rect.top));
  out[flutter::EncodableValue("width")] =
      flutter::EncodableValue(static_cast<int32_t>(rect.right - rect.left));
  out[flutter::EncodableValue("height")] =
      flutter::EncodableValue(static_cast<int32_t>(rect.bottom - rect.top));
  return out;
}

void SetBounds(HWND hwnd, int x, int y, int width, int height) {
  ::SetWindowPos(hwnd, nullptr, x, y, width, height,
                 SWP_NOZORDER | SWP_NOACTIVATE);
}

void WinShow(HWND hwnd) { ::ShowWindow(hwnd, SW_SHOW); }
void WinHide(HWND hwnd) { ::ShowWindow(hwnd, SW_HIDE); }
void WinClose(HWND hwnd) { ::PostMessage(hwnd, WM_CLOSE, 0, 0); }

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "cmyke/window",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [this](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        HWND hwnd = GetHandle();
        const auto& method = call.method_name();
        const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments());

        auto getBool = [&](const char* key, bool default_value) -> bool {
          if (!args) return default_value;
          auto it = args->find(flutter::EncodableValue(key));
          if (it == args->end()) return default_value;
          if (const auto* v = std::get_if<bool>(&it->second)) return *v;
          return default_value;
        };
        auto getInt = [&](const char* key, int default_value) -> int {
          if (!args) return default_value;
          auto it = args->find(flutter::EncodableValue(key));
          if (it == args->end()) return default_value;
          if (const auto* v = std::get_if<int>(&it->second)) return *v;
          if (const auto* v64 = std::get_if<int64_t>(&it->second))
            return static_cast<int>(*v64);
          return default_value;
        };

        if (method == "setAlwaysOnTop") {
          SetAlwaysOnTop(hwnd, getBool("value", false));
          result->Success();
          return;
        }
        if (method == "setSkipTaskbar") {
          SetSkipTaskbar(hwnd, getBool("value", false));
          result->Success();
          return;
        }
        if (method == "setFrameless") {
          SetFrameless(hwnd, getBool("value", false));
          result->Success();
          return;
        }
        if (method == "setResizable") {
          SetResizable(hwnd, getBool("value", true));
          result->Success();
          return;
        }
        if (method == "setIgnoreMouseEvents") {
          SetIgnoreMouseEvents(hwnd, getBool("value", false));
          result->Success();
          return;
        }
        if (method == "startDragging") {
          StartDragging(hwnd);
          result->Success();
          return;
        }
        if (method == "setSize") {
          SetSize(hwnd, getInt("width", 420), getInt("height", 520));
          result->Success();
          return;
        }
        if (method == "getBounds") {
          result->Success(flutter::EncodableValue(GetBounds(hwnd)));
          return;
        }
        if (method == "setBounds") {
          SetBounds(hwnd, getInt("x", 10), getInt("y", 10),
                    getInt("width", 420), getInt("height", 520));
          result->Success();
          return;
        }
        if (method == "show") {
          WinShow(hwnd);
          result->Success();
          return;
        }
        if (method == "hide") {
          WinHide(hwnd);
          result->Success();
          return;
        }
        if (method == "close") {
          WinClose(hwnd);
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  // Keep the channel alive for the lifetime of the window.
  channel_ = std::move(channel);

  auto audio_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "cmyke/audio",
          &flutter::StandardMethodCodec::GetInstance());
  audio_channel->SetMethodCallHandler(
      [](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        const auto& method = call.method_name();
        if (method == "listInputDevices") {
          const auto devices = ListCaptureDevices();
          flutter::EncodableList out;
          out.reserve(devices.size());
          for (const auto& device : devices) {
            flutter::EncodableMap entry;
            entry[flutter::EncodableValue("id")] =
                flutter::EncodableValue(WideToUtf8(device.id));
            entry[flutter::EncodableValue("name")] =
                flutter::EncodableValue(WideToUtf8(device.name));
            entry[flutter::EncodableValue("isDefault")] =
                flutter::EncodableValue(device.is_default);
            out.emplace_back(std::move(entry));
          }
          result->Success(flutter::EncodableValue(out));
          return;
        }
        if (method == "getDefaultInputDevice") {
          const auto devices = ListCaptureDevices();
          for (const auto& device : devices) {
            if (!device.is_default) continue;
            flutter::EncodableMap entry;
            entry[flutter::EncodableValue("id")] =
                flutter::EncodableValue(WideToUtf8(device.id));
            entry[flutter::EncodableValue("name")] =
                flutter::EncodableValue(WideToUtf8(device.name));
            result->Success(flutter::EncodableValue(entry));
            return;
          }
          result->Success(flutter::EncodableValue());
          return;
        }
        if (method == "openSoundSettings") {
          ::ShellExecuteW(nullptr, L"open", L"ms-settings:sound", nullptr, nullptr,
                          SW_SHOWNORMAL);
          result->Success();
          return;
        }
        result->NotImplemented();
      });
  audio_channel_ = std::move(audio_channel);
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
