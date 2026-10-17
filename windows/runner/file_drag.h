#ifndef RUNNER_FILE_DRAG_H_
#define RUNNER_FILE_DRAG_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <map>
#include <memory>
#include <string>

class FileDrag {
 public:
  FileDrag(flutter::BinaryMessenger* messenger, HWND window);
  ~FileDrag();

 private:
  void Release();
  HWND window_;
  std::map<std::string, HANDLE> handles_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif
