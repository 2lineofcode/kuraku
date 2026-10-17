#include "file_drag.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <utility>

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

void CheckResult(bool condition, const char* expression, int line) {
  if (!condition) {
    std::fprintf(stderr, "Windows file drag check failed at line %d: %s (Win32 error %lu)\n", line, expression, GetLastError());
    std::abort();
  }
}

#define Check(condition) CheckResult(condition, #condition, __LINE__)

class Messenger : public flutter::BinaryMessenger {
 public:
  flutter::BinaryMessageHandler handler;
  void Send(const std::string&, const uint8_t*, size_t, flutter::BinaryReply) const override {}
  void SetMessageHandler(const std::string&, flutter::BinaryMessageHandler value) override {
    handler = std::move(value);
  }
  EncodableValue Call(const std::string& method, const EncodableValue& arguments, bool expected_success = true) {
    const auto& codec = flutter::StandardMethodCodec::GetInstance();
    auto message = codec.EncodeMethodCall(flutter::MethodCall<EncodableValue>(method,
        std::make_unique<EncodableValue>(arguments)));
    bool replied = false;
    EncodableValue output;
    flutter::MethodResultFunctions<EncodableValue> result(
        [&](const auto* value) { Check(expected_success); replied = true; if (value) output = *value; },
        [&](const auto&, const auto&, const auto*) { Check(!expected_success); replied = true; },
        [&]() { Check(false); });
    handler(message->data(), message->size(), [&](const uint8_t* data, size_t length) {
      Check(codec.DecodeAndProcessResponseEnvelope(data, length, &result));
    });
    Check(replied);
    return output;
  }
};

int main() {
  Check(SUCCEEDED(OleInitialize(nullptr)));
  wchar_t temporary[MAX_PATH];
  Check(GetTempPathW(MAX_PATH, temporary) > 0);
  const auto directory = std::filesystem::path(temporary) / (L"kuraku drag " + std::to_wstring(GetCurrentProcessId()));
  Check(std::filesystem::create_directory(directory));
  const auto source = directory / L"日本語 #1.mp4";
  const auto target = directory / L"日本語 moved.mp4";
  const auto file = CreateFileW(source.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
  Check(file != INVALID_HANDLE_VALUE);
  CloseHandle(file);
  Messenger messenger;
  {
    FileDrag drag(&messenger, nullptr);
    const EncodableValue paths(EncodableList{EncodableValue(source.u8string())});
    const auto bookmarks = messenger.Call("bookmark", paths);
    Check(std::get<EncodableMap>(bookmarks).size() == 1);
    Check(MoveFileW(source.c_str(), target.c_str()) != 0);
    const auto resolved = std::get<EncodableMap>(messenger.Call("resolve", bookmarks));
    Check(std::filesystem::equivalent(std::filesystem::u8path(
        std::get<std::string>(resolved.at(EncodableValue(source.u8string())))), target));
    messenger.Call("release", EncodableValue());
    Check(std::get<EncodableMap>(messenger.Call("resolve", bookmarks)).empty());
    messenger.Call("bookmark", paths, false);
    messenger.Call("bookmark", EncodableValue(EncodableList{EncodableValue("relative.mp4")}), false);
    messenger.Call("bookmark", EncodableValue(EncodableList{}), false);
    messenger.Call("drag", EncodableValue(EncodableList{EncodableValue(target.u8string())}), false);
    Check(std::get<EncodableMap>(messenger.Call("resolve", bookmarks)).empty());
  }
  Check(!messenger.handler);
  Check(DeleteFileW(target.c_str()) != 0);
  Check(RemoveDirectoryW(directory.c_str()) != 0);
  OleUninitialize();
  std::puts("Windows file handles track Unicode renames and release safely.");
  return 0;
}
