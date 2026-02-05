#include "flutter_window.h"

#include <optional>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

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
