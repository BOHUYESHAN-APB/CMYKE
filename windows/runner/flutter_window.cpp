#include "flutter_window.h"

#include <optional>
#include <string>
#include <vector>
#include <atomic>
#include <thread>
#include <chrono>
#include <algorithm>
#include <cstring>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <mmdeviceapi.h>
#include <audioclient.h>
#include <functiondiscoverykeys_devpkey.h>
#include <shellapi.h>
#include <propidl.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

std::atomic<int64_t> g_injected_tts_token{0};

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

struct ParsedWav {
  int sample_rate = 0;
  int channels = 0;
  int bits_per_sample = 0;
  int format_tag = 0;  // 1 = PCM, 3 = IEEE_FLOAT
  std::vector<float> samples;  // interleaved
};

static uint32_t ReadU32LE(const uint8_t* p) {
  return (static_cast<uint32_t>(p[0])      ) |
         (static_cast<uint32_t>(p[1]) <<  8) |
         (static_cast<uint32_t>(p[2]) << 16) |
         (static_cast<uint32_t>(p[3]) << 24);
}

static uint16_t ReadU16LE(const uint8_t* p) {
  return static_cast<uint16_t>(p[0] | (p[1] << 8));
}

static bool ParseWavBytes(const std::vector<uint8_t>& bytes, ParsedWav* out) {
  if (!out) return false;
  out->samples.clear();
  if (bytes.size() < 44) return false;
  const uint8_t* p = bytes.data();
  if (std::memcmp(p, "RIFF", 4) != 0) return false;
  if (std::memcmp(p + 8, "WAVE", 4) != 0) return false;
  size_t pos = 12;
  uint16_t audio_format = 0;
  uint16_t num_channels = 0;
  uint32_t sample_rate = 0;
  uint16_t bits = 0;
  const uint8_t* data_ptr = nullptr;
  uint32_t data_size = 0;

  while (pos + 8 <= bytes.size()) {
    const uint8_t* chunk = p + pos;
    const uint32_t chunk_size = ReadU32LE(chunk + 4);
    pos += 8;
    if (pos + chunk_size > bytes.size()) {
      return false;
    }
    if (std::memcmp(chunk, "fmt ", 4) == 0) {
      if (chunk_size < 16) return false;
      audio_format = ReadU16LE(p + pos + 0);
      num_channels = ReadU16LE(p + pos + 2);
      sample_rate = ReadU32LE(p + pos + 4);
      bits = ReadU16LE(p + pos + 14);
    } else if (std::memcmp(chunk, "data", 4) == 0) {
      data_ptr = p + pos;
      data_size = chunk_size;
    }
    pos += chunk_size;
    // Chunks are padded to even sizes.
    if (pos & 1) pos += 1;
  }

  if (!data_ptr || data_size == 0) return false;
  if (num_channels == 0 || sample_rate == 0) return false;
  if (!(audio_format == 1 || audio_format == 3)) return false;
  if (audio_format == 1 && bits != 16) return false;
  if (audio_format == 3 && bits != 32) return false;

  const uint32_t bytes_per_sample = bits / 8;
  const uint32_t frame_bytes = bytes_per_sample * num_channels;
  if (frame_bytes == 0) return false;
  const uint32_t frames = data_size / frame_bytes;
  if (frames == 0) return false;

  out->sample_rate = static_cast<int>(sample_rate);
  out->channels = static_cast<int>(num_channels);
  out->bits_per_sample = static_cast<int>(bits);
  out->format_tag = static_cast<int>(audio_format);
  out->samples.resize(static_cast<size_t>(frames) * num_channels);

  if (audio_format == 1) {
    // PCM 16-bit
    const int16_t* s = reinterpret_cast<const int16_t*>(data_ptr);
    const size_t count = static_cast<size_t>(frames) * num_channels;
    for (size_t i = 0; i < count; i += 1) {
      out->samples[i] = static_cast<float>(s[i]) / 32768.0f;
    }
  } else {
    // IEEE float 32-bit
    const float* s = reinterpret_cast<const float*>(data_ptr);
    const size_t count = static_cast<size_t>(frames) * num_channels;
    for (size_t i = 0; i < count; i += 1) {
      out->samples[i] = s[i];
    }
  }
  return true;
}

static std::vector<float> ResampleToInterleavedFloat(
    const std::vector<float>& in,
    int in_rate,
    int in_channels,
    int out_rate,
    int out_channels) {
  if (in.empty() || in_rate <= 0 || out_rate <= 0 || in_channels <= 0 ||
      out_channels <= 0) {
    return {};
  }
  const size_t in_frames = in.size() / static_cast<size_t>(in_channels);
  if (in_frames == 0) return {};
  const size_t out_frames =
      static_cast<size_t>((in_frames * static_cast<uint64_t>(out_rate) + in_rate - 1) / in_rate);

  std::vector<float> out;
  out.resize(out_frames * static_cast<size_t>(out_channels));

  const double ratio = static_cast<double>(in_rate) / static_cast<double>(out_rate);
  for (size_t of = 0; of < out_frames; of += 1) {
    const double src_pos = static_cast<double>(of) * ratio;
    const size_t i0 = static_cast<size_t>(src_pos);
    const size_t i1 = std::min(i0 + 1, in_frames - 1);
    const float frac = static_cast<float>(src_pos - static_cast<double>(i0));

    auto in_sample = [&](size_t frame, int ch) -> float {
      const size_t idx = frame * static_cast<size_t>(in_channels) + static_cast<size_t>(ch);
      return idx < in.size() ? in[idx] : 0.0f;
    };
    auto get_in = [&](size_t frame, int out_ch) -> float {
      if (in_channels == out_channels) {
        return in_sample(frame, out_ch);
      }
      if (in_channels == 1 && out_channels >= 2) {
        return in_sample(frame, 0);
      }
      if (in_channels >= 2 && out_channels == 1) {
        // downmix to mono
        float sum = 0.0f;
        for (int c = 0; c < in_channels; c += 1) sum += in_sample(frame, c);
        return sum / static_cast<float>(in_channels);
      }
      // Fallback: clamp channel index.
      const int ch = std::min(out_ch, in_channels - 1);
      return in_sample(frame, ch);
    };

    for (int oc = 0; oc < out_channels; oc += 1) {
      const float s0 = get_in(i0, oc);
      const float s1 = get_in(i1, oc);
      out[of * static_cast<size_t>(out_channels) + static_cast<size_t>(oc)] =
          s0 * (1.0f - frac) + s1 * frac;
    }
  }
  return out;
}

static bool PlayFloatPcmToDeviceWASAPI(
    int64_t token,
    const std::wstring& device_id,
    const std::vector<float>& samples,
    int sample_rate,
    int channels) {
  if (samples.empty() || sample_rate <= 0 || channels <= 0) return false;
  ScopedComInit com;
  if (!com.ok()) return false;

  IMMDeviceEnumerator* enumerator = nullptr;
  HRESULT hr = ::CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                  __uuidof(IMMDeviceEnumerator),
                                  reinterpret_cast<void**>(&enumerator));
  if (FAILED(hr) || !enumerator) return false;

  IMMDevice* device = nullptr;
  hr = enumerator->GetDevice(device_id.c_str(), &device);
  enumerator->Release();
  if (FAILED(hr) || !device) return false;

  IAudioClient* client = nullptr;
  hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                        reinterpret_cast<void**>(&client));
  device->Release();
  if (FAILED(hr) || !client) return false;

  // Prefer float32 in shared mode, matching the device mix sample rate/channels.
  WAVEFORMATEX* mix = nullptr;
  hr = client->GetMixFormat(&mix);
  if (FAILED(hr) || !mix) {
    client->Release();
    return false;
  }
  const int out_rate = static_cast<int>(mix->nSamplesPerSec);
  const int out_channels = static_cast<int>(mix->nChannels);
  ::CoTaskMemFree(mix);

  // Resample/mix to the output format used for injection.
  const std::vector<float> out = ResampleToInterleavedFloat(
      samples, sample_rate, channels, out_rate, out_channels);
  if (out.empty()) {
    client->Release();
    return false;
  }
  const size_t frames_total = out.size() / static_cast<size_t>(out_channels);

  WAVEFORMATEX fmt{};
  fmt.wFormatTag = WAVE_FORMAT_IEEE_FLOAT;
  fmt.nChannels = static_cast<WORD>(out_channels);
  fmt.nSamplesPerSec = static_cast<DWORD>(out_rate);
  fmt.wBitsPerSample = 32;
  fmt.nBlockAlign = static_cast<WORD>(fmt.nChannels * (fmt.wBitsPerSample / 8));
  fmt.nAvgBytesPerSec = fmt.nSamplesPerSec * fmt.nBlockAlign;
  fmt.cbSize = 0;

  WAVEFORMATEX* closest = nullptr;
  hr = client->IsFormatSupported(AUDCLNT_SHAREMODE_SHARED, &fmt, &closest);
  if (closest) {
    ::CoTaskMemFree(closest);
    closest = nullptr;
  }
  if (FAILED(hr)) {
    client->Release();
    return false;
  }

  // 100ms buffer is a reasonable compromise for stability.
  const REFERENCE_TIME buffer_duration = 1000000;  // 100ms in 100ns units
  hr = client->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, buffer_duration, 0, &fmt,
                          nullptr);
  if (FAILED(hr)) {
    client->Release();
    return false;
  }

  UINT32 buffer_frames = 0;
  hr = client->GetBufferSize(&buffer_frames);
  if (FAILED(hr) || buffer_frames == 0) {
    client->Release();
    return false;
  }

  IAudioRenderClient* render = nullptr;
  hr = client->GetService(__uuidof(IAudioRenderClient),
                          reinterpret_cast<void**>(&render));
  if (FAILED(hr) || !render) {
    client->Release();
    return false;
  }

  hr = client->Start();
  if (FAILED(hr)) {
    render->Release();
    client->Release();
    return false;
  }

  size_t frame_cursor = 0;
  while (frame_cursor < frames_total) {
    if (g_injected_tts_token.load() != token) {
      break;
    }
    UINT32 padding = 0;
    hr = client->GetCurrentPadding(&padding);
    if (FAILED(hr)) {
      break;
    }
    const UINT32 available = buffer_frames > padding ? (buffer_frames - padding) : 0;
    if (available == 0) {
      std::this_thread::sleep_for(std::chrono::milliseconds(6));
      continue;
    }
    const size_t remain = frames_total - frame_cursor;
    const UINT32 to_write = static_cast<UINT32>(std::min<size_t>(remain, available));
    BYTE* data = nullptr;
    hr = render->GetBuffer(to_write, &data);
    if (FAILED(hr) || !data) {
      break;
    }
    const size_t floats = static_cast<size_t>(to_write) * static_cast<size_t>(out_channels);
    std::memcpy(
        data,
        out.data() + frame_cursor * static_cast<size_t>(out_channels),
        floats * sizeof(float));
    hr = render->ReleaseBuffer(to_write, 0);
    if (FAILED(hr)) {
      break;
    }
    frame_cursor += static_cast<size_t>(to_write);
  }

  // Allow the tail to drain (unless cancelled).
  if (g_injected_tts_token.load() == token) {
    for (int i = 0; i < 60; i += 1) {
      UINT32 padding = 0;
      if (FAILED(client->GetCurrentPadding(&padding))) break;
      if (padding == 0) break;
      std::this_thread::sleep_for(std::chrono::milliseconds(8));
      if (g_injected_tts_token.load() != token) break;
    }
  }

  client->Stop();
  render->Release();
  client->Release();
  return true;
}

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

std::optional<std::wstring> GetDefaultRenderDeviceId() {
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
  hr = enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device);
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

std::vector<AudioDeviceInfo> ListRenderDevices() {
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
  std::optional<std::wstring> default_id = GetDefaultRenderDeviceId();

  IMMDeviceCollection* collection = nullptr;
  hr = enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &collection);
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
         if (method == "stopInjectedTts") {
           // Invalidate any in-flight playback thread (best-effort).
           g_injected_tts_token.fetch_add(1);
           result->Success(flutter::EncodableValue(true));
           return;
         }
         if (method == "playWavToOutputDevice") {
           const auto* args =
               std::get_if<flutter::EncodableMap>(call.arguments());
           if (!args) {
             result->Success(flutter::EncodableValue(false));
             return;
           }
           std::wstring device_id;
           std::vector<uint8_t> wav_bytes;
           auto it_id = args->find(flutter::EncodableValue("deviceId"));
           if (it_id != args->end()) {
             if (const auto* s = std::get_if<std::string>(&it_id->second)) {
               // Endpoint IDs are ASCII-ish; this is sufficient for IDs.
               device_id.assign(s->begin(), s->end());
             }
           }
           auto it_bytes = args->find(flutter::EncodableValue("wavBytes"));
           if (it_bytes != args->end()) {
             if (const auto* b = std::get_if<std::vector<uint8_t>>(
                     &it_bytes->second)) {
               wav_bytes = *b;
             }
           }
           if (device_id.empty() || wav_bytes.empty()) {
             result->Success(flutter::EncodableValue(false));
             return;
           }

           // Cancel previous and start a new async playback.
           const int64_t token = g_injected_tts_token.fetch_add(1) + 1;
           std::thread([token, device_id = std::move(device_id),
                        wav_bytes = std::move(wav_bytes)]() mutable {
             ParsedWav wav;
             if (!ParseWavBytes(wav_bytes, &wav)) {
               return;
             }
             PlayFloatPcmToDeviceWASAPI(
                 token, device_id, wav.samples, wav.sample_rate, wav.channels);
           }).detach();

           result->Success(flutter::EncodableValue(true));
           return;
         }
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
        if (method == "listOutputDevices") {
          const auto devices = ListRenderDevices();
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
        if (method == "getDefaultOutputDevice") {
          const auto devices = ListRenderDevices();
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
