#include "file_drag.cc"

int main() {
  g_autofree char* directory = g_dir_make_tmp("kuraku-native-drag-XXXXXX", nullptr);
  g_assert_nonnull(directory);
  const std::string source = std::string(directory) + "/日本語 #1.mp4";
  const std::string target = std::string(directory) + "/renamed.mp4";
  g_assert_true(g_file_set_contents(source.c_str(), "video", -1, nullptr));
  int fd = open(source.c_str(), O_PATH | O_CLOEXEC);
  g_assert_cmpint(fd, >=, 0);
  g_assert_true(tracked_path(fd) == source);
  g_assert_cmpint(rename(source.c_str(), target.c_str()), ==, 0);
  g_assert_true(tracked_path(fd) == target);
  g_assert_cmpint(unlink(target.c_str()), ==, 0);
  g_assert_true(tracked_path(fd).empty());
  g_assert_true(g_file_set_contents(target.c_str(), "replacement", -1, nullptr));
  g_assert_true(tracked_path(fd).empty());
  close(fd);
  g_assert_true(tracked_path(fd).empty());
  g_assert_cmpint(unlink(target.c_str()), ==, 0);
  g_assert_cmpint(rmdir(directory), ==, 0);
}
