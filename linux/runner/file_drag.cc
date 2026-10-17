#include "file_drag.h"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <map>
#include <string>
#include <vector>

struct FileDrag {
  GtkWidget* view;
  GdkEvent* event = nullptr;
  FlMethodCall* pending = nullptr;
  std::map<std::string, int> descriptors;
  std::vector<std::string> uris;
  bool failed = false;

  void release() {
    for (const auto& entry : descriptors) close(entry.second);
    descriptors.clear();
  }

  ~FileDrag() {
    release();
    if (event) gdk_event_free(event);
    g_clear_object(&pending);
  }
};

static void respond(FlMethodCall* call, FlValue* value) {
  fl_method_call_respond_success(call, value, nullptr);
}

static std::string tracked_path(int fd) {
  const std::string link = "/proc/self/fd/" + std::to_string(fd);
  g_autofree char* path = g_file_read_link(link.c_str(), nullptr);
  struct stat original, current;
  if (path && fstat(fd, &original) == 0 && stat(path, &current) == 0 &&
      S_ISREG(current.st_mode) && original.st_dev == current.st_dev && original.st_ino == current.st_ino) {
    return path;
  }
  return "";
}

static void method_call(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* state = static_cast<FileDrag*>(data);
  const char* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (strcmp(method, "release") == 0) {
    state->release();
    respond(call, nullptr);
  } else if (strcmp(method, "bookmark") == 0) {
    if (fl_value_get_type(args) != FL_VALUE_TYPE_LIST || state->pending) {
      fl_method_call_respond_error(call, "invalid_paths", "Expected idle file drag and file paths", nullptr, nullptr);
      return;
    }
    state->release();
    g_autoptr(FlValue) result = fl_value_new_map();
    for (size_t i = 0; i < fl_value_get_length(args); i++) {
      FlValue* path = fl_value_get_list_value(args, i);
      if (fl_value_get_type(path) != FL_VALUE_TYPE_STRING) break;
      const char* name = fl_value_get_string(path);
      int fd = open(name, O_PATH | O_CLOEXEC);
      if (fd < 0) break;
      state->descriptors[name] = fd;
      fl_value_set_string_take(result, name, fl_value_new_int(fd));
    }
    if (state->descriptors.size() != fl_value_get_length(args)) {
      state->release();
      fl_method_call_respond_error(call, "unavailable_file", "Could not track selected files", nullptr, nullptr);
      return;
    }
    respond(call, result);
  } else if (strcmp(method, "resolve") == 0) {
    g_autoptr(FlValue) result = fl_value_new_map();
    for (const auto& entry : state->descriptors) {
      const std::string path = tracked_path(entry.second);
      if (!path.empty()) {
        fl_value_set_string_take(result, entry.first.c_str(), fl_value_new_string(path.c_str()));
      }
    }
    respond(call, result);
  } else if (strcmp(method, "drag") == 0) {
    if (!state->event || state->pending || state->descriptors.empty()) {
      g_autoptr(FlValue) result = fl_value_new_string("cancel");
      respond(call, result);
      return;
    }
    state->uris.clear();
    for (const auto& entry : state->descriptors) {
      g_autofree char* uri = g_filename_to_uri(entry.first.c_str(), nullptr, nullptr);
      if (uri) state->uris.emplace_back(uri);
    }
    state->failed = false;
    state->pending = FL_METHOD_CALL(g_object_ref(call));
    GtkTargetEntry entries[] = {{const_cast<char*>("text/uri-list"), 0, 0}};
    GtkTargetList* targets = gtk_target_list_new(entries, 1);
    GdkDragContext* context = gtk_drag_begin_with_coordinates(state->view, targets,
        static_cast<GdkDragAction>(GDK_ACTION_COPY | GDK_ACTION_MOVE), 1, state->event, -1, -1);
    gtk_target_list_unref(targets);
    if (!context && state->pending) {
      g_autoptr(FlValue) result = fl_value_new_string("cancel");
      respond(state->pending, result);
      g_clear_object(&state->pending);
    }
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}

void register_file_drag(FlView* view) {
  auto* state = new FileDrag{GTK_WIDGET(view)};
  g_object_set_data_full(G_OBJECT(view), "kuraku-file-drag", state,
      [](gpointer data) { delete static_cast<FileDrag*>(data); });
  g_signal_connect(view, "event", G_CALLBACK(+[](GtkWidget*, GdkEvent* event, gpointer data) -> gboolean {
    auto* state = static_cast<FileDrag*>(data);
    if (event->type == GDK_BUTTON_PRESS && event->button.button == 1) {
      if (state->event) gdk_event_free(state->event);
      state->event = gdk_event_copy(event);
    }
    return FALSE;
  }), state);
  g_signal_connect(view, "drag-data-get", G_CALLBACK(+[](GtkWidget*, GdkDragContext*, GtkSelectionData* selection, guint, guint, gpointer data) {
    auto* state = static_cast<FileDrag*>(data);
    std::vector<gchar*> uris;
    for (auto& uri : state->uris) uris.push_back(const_cast<gchar*>(uri.c_str()));
    uris.push_back(nullptr);
    gtk_selection_data_set_uris(selection, uris.data());
  }), state);
  g_signal_connect(view, "drag-failed", G_CALLBACK(+[](GtkWidget*, GdkDragContext*, GtkDragResult, gpointer data) -> gboolean {
    static_cast<FileDrag*>(data)->failed = true;
    return FALSE;
  }), state);
  g_signal_connect(view, "drag-end", G_CALLBACK(+[](GtkWidget* widget, GdkDragContext* context, gpointer data) {
    auto* state = static_cast<FileDrag*>(data);
    if (!state->pending) return;
    const auto action = gdk_drag_context_get_selected_action(context);
    g_autoptr(FlValue) result = fl_value_new_string(state->failed ? "cancel" :
        action == GDK_ACTION_MOVE ? "move" : action == GDK_ACTION_COPY ? "copy" : "cancel");
    respond(state->pending, result);
    g_clear_object(&state->pending);
    // GTK consumes the release during a drag; finish Flutter's pointer sequence.
    if (state->event) {
      GdkEvent* release = gdk_event_copy(state->event);
      release->type = GDK_BUTTON_RELEASE;
      gtk_widget_event(widget, release);
      gdk_event_free(release);
      g_clear_pointer(&state->event, gdk_event_free);
    }
  }), state);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), "kuraku/file_drag", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call, state, nullptr);
}
