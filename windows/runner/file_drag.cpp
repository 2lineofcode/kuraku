#include "file_drag.h"

#include <flutter/standard_method_codec.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <vector>

namespace {
std::wstring Wide(const std::string& text) {
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring result(length, L'\0');
  if (length > 0) MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      text.data(), static_cast<int>(text.size()), result.data(), length);
  return result;
}

std::string Utf8(const std::wstring& text) {
  const int length = WideCharToMultiByte(CP_UTF8, 0, text.data(),
      static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  std::string result(length, '\0');
  if (length > 0) WideCharToMultiByte(CP_UTF8, 0, text.data(),
      static_cast<int>(text.size()), result.data(), length, nullptr, nullptr);
  return result;
}
}

FileDrag::FileDrag(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "kuraku/file_drag", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    using flutter::EncodableMap;
    using flutter::EncodableValue;
    const auto& method = call.method_name();
    if (method == "release") {
      Release();
      result->Success();
      return;
    }
    if (method == "resolve") {
      EncodableMap resolved;
      for (const auto& entry : handles_) {
        const DWORD length = GetFinalPathNameByHandleW(entry.second, nullptr, 0, FILE_NAME_NORMALIZED);
        if (length == 0) continue;
        std::wstring path(length, L'\0');
        const DWORD written = GetFinalPathNameByHandleW(entry.second, path.data(), length, FILE_NAME_NORMALIZED);
        if (written == 0 || written >= length) continue;
        path.resize(written);
        if (path.rfind(L"\\\\?\\UNC\\", 0) == 0) path = L"\\\\" + path.substr(8);
        else if (path.rfind(L"\\\\?\\", 0) == 0) path = path.substr(4);
        resolved[EncodableValue(entry.first)] = EncodableValue(Utf8(path));
      }
      result->Success(EncodableValue(resolved));
      return;
    }
    if (method != "bookmark" && method != "drag") {
      result->NotImplemented();
      return;
    }
    const auto* paths = call.arguments() ? std::get_if<flutter::EncodableList>(call.arguments()) : nullptr;
    if (!paths || paths->empty()) {
      result->Error("invalid_paths", "Select at least one file");
      return;
    }
    if (method == "bookmark") {
      Release();
      EncodableMap bookmarks;
      for (const auto& value : *paths) {
        const auto* path = std::get_if<std::string>(&value);
        if (!path || path->find('\0') != std::string::npos || handles_.find(*path) != handles_.end()) break;
        const auto wide = Wide(*path);
        if (wide.empty() || PathIsRelativeW(wide.c_str())) break;
        const HANDLE handle = CreateFileW(wide.c_str(), FILE_READ_ATTRIBUTES,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (handle == INVALID_HANDLE_VALUE) break;
        handles_[*path] = handle;
        bookmarks[value] = value;
      }
      if (bookmarks.size() != paths->size()) {
        Release();
        result->Error("unavailable", "Could not track the selected files");
      } else {
        result->Success(EncodableValue(bookmarks));
      }
      return;
    }
    std::vector<PCIDLIST_ABSOLUTE> items;
    for (const auto& value : *paths) {
      const auto* path = std::get_if<std::string>(&value);
      if (!path || handles_.find(*path) == handles_.end()) break;
      const auto item = ILCreateFromPathW(Wide(*path).c_str());
      if (!item) break;
      items.push_back(item);
    }
    Microsoft::WRL::ComPtr<IShellItemArray> array;
    Microsoft::WRL::ComPtr<IDataObject> data;
    HRESULT status = E_INVALIDARG;
    if (items.size() == paths->size()) {
      status = SHCreateShellItemArrayFromIDLists(static_cast<UINT>(items.size()), items.data(), &array);
      if (SUCCEEDED(status)) status = array->BindToHandler(nullptr, BHID_DataObject, IID_PPV_ARGS(&data));
    }
    for (const auto item : items) CoTaskMemFree(const_cast<PIDLIST_ABSOLUTE>(item));
    DWORD effect = DROPEFFECT_NONE;
    if (SUCCEEDED(status)) status = SHDoDragDrop(window_, data.Get(), nullptr,
        DROPEFFECT_COPY | DROPEFFECT_MOVE, &effect);
    if (FAILED(status)) result->Error("drag_failed", "Windows Shell could not start file drag");
    else result->Success(EncodableValue(effect == DROPEFFECT_MOVE ? "move" : effect == DROPEFFECT_COPY ? "copy" : "cancel"));
  });
}

FileDrag::~FileDrag() {
  channel_->SetMethodCallHandler(nullptr);
  Release();
}

void FileDrag::Release() {
  for (const auto& entry : handles_) CloseHandle(entry.second);
  handles_.clear();
}
