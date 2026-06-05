#include "CAdwaita.h"

#include <adwaita.h>
#include <gdk/gdkkeysyms.h>
#if defined(__linux__)
#include <webkit/webkit.h>
#include <jsc/jsc.h>
#else
typedef void WebKitUserContentManager;
typedef void WebKitWebView;
#endif
#if defined(__APPLE__)
#include <objc/message.h>
#include <objc/objc.h>
#include <objc/runtime.h>
#endif
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define OMNI_ADW_INTERNAL_PRESENT_SETTINGS_ACTION_ID -1001

static void omni_set_rgba(GdkRGBA *color, double red, double green, double blue, double alpha);
static double omni_unit_clamp(double value);
static gboolean omni_parse_semantic_color(const char *raw, GdkRGBA *color);

#if defined(__APPLE__)
GtkWidget *omni_macos_web_view_new(const char *url, void *native_view);
GtkWidget *omni_macos_web_view_new_ex(
    const char *identity,
    const char *url,
    const char *html,
    const char *base_url,
    const char **request_header_names,
    const char **request_header_values,
    int32_t request_header_count,
    const char *application_name,
    const char *custom_user_agent,
    double page_zoom,
    int32_t allows_back_forward_navigation_gestures,
    int32_t javascript_can_open_windows,
    int32_t javascript_enabled,
    double minimum_font_size,
    int32_t is_inspectable,
    int32_t allows_inline_media_playback,
    int32_t media_playback_requires_user_gesture,
    void *native_view,
    const char **script_sources,
    const int32_t *script_injection_times,
    const int32_t *script_main_frame_only,
    int32_t script_count,
    const char **content_rule_identifiers,
    const char **content_rule_sources,
    int32_t content_rule_count,
    const char **message_handler_names,
    int32_t message_handler_count,
    const char *accessibility_label,
    const char *accessibility_description,
    omni_adw_web_message_callback message_callback,
    omni_adw_web_navigation_callback navigation_callback,
    omni_adw_web_policy_callback policy_callback,
    omni_adw_web_response_policy_callback response_policy_callback,
    omni_adw_web_download_destination_callback download_destination_callback,
    omni_adw_web_title_callback title_callback,
    omni_adw_web_progress_callback progress_callback,
    omni_adw_web_cookie_callback cookie_callback,
    omni_adw_web_script_dialog_callback script_dialog_callback,
    void *callback_context);
int32_t omni_macos_web_view_unregister(const char *identity);
int32_t omni_macos_web_view_evaluate_javascript(const char *identity, const char *script, omni_adw_web_evaluate_callback callback, void *callback_context);
int32_t omni_macos_web_view_load_uri(const char *identity, const char *url);
int32_t omni_macos_web_view_load_request(const char *identity, const char *url, const char **header_names, const char **header_values, int32_t header_count);
int32_t omni_macos_web_view_load_html(const char *identity, const char *html, const char *base_url);
int32_t omni_macos_web_view_go_back(const char *identity);
int32_t omni_macos_web_view_go_forward(const char *identity);
int32_t omni_macos_web_view_reload(const char *identity);
int32_t omni_macos_web_view_stop_loading(const char *identity);
int32_t omni_macos_web_view_can_go_back(const char *identity);
int32_t omni_macos_web_view_can_go_forward(const char *identity);
int32_t omni_macos_web_view_set_zoom(const char *identity, double page_zoom);
int32_t omni_macos_web_view_set_allows_back_forward_navigation_gestures(const char *identity, int32_t enabled);
int32_t omni_macos_web_view_set_javascript_can_open_windows(const char *identity, int32_t enabled);
int32_t omni_macos_web_view_set_javascript_enabled(const char *identity, int32_t enabled);
int32_t omni_macos_web_view_set_minimum_font_size(const char *identity, double size);
int32_t omni_macos_web_view_set_inspectable(const char *identity, int32_t enabled);
int32_t omni_macos_web_view_set_user_agent(const char *identity, const char *application_name, const char *custom_user_agent);
int32_t omni_macos_web_view_add_user_script(const char *identity, const char *source, int32_t injection_time, int32_t main_frame_only);
int32_t omni_macos_web_view_remove_all_user_scripts(const char *identity);
int32_t omni_macos_web_view_register_message_handler_named(const char *identity, const char *name);
int32_t omni_macos_web_view_unregister_message_handler_named(const char *identity, const char *name);
int32_t omni_macos_web_view_add_content_rule(const char *identity, const char *identifier, const char *source);
int32_t omni_macos_web_view_remove_all_content_rules(const char *identity);
int32_t omni_macos_web_view_focus(const char *identity);
int32_t omni_macos_web_view_scroll_by_identity(const char *identity, double dx, double dy);
int32_t omni_macos_web_view_scroll_page_identity(const char *identity, int32_t direction);
gboolean omni_macos_web_view_handle_key(guint keyval, GdkModifierType state);
gboolean omni_macos_web_view_widget_scroll(GtkWidget *widget, double dx, double dy);
gboolean omni_macos_web_view_widget_scroll_page(GtkWidget *widget, int direction);
void omni_macos_web_view_set_modal_occlusion(gboolean occluded);
void omni_macos_text_input_install(void *app);
#endif

#define OMNI_MACOS_ACCESSIBILITY_MAX_ELEMENTS 512
#define OMNI_NATIVE_ACCESSIBILITY_ROW_UPDATE_LIMIT 2048
#define OMNI_HEADER_ACTION_SEGMENTED 1
#define OMNI_HEADER_ACTION_SELECTED 2
#define OMNI_ENTRY_TEXT_COMMIT_DELAY_MS 1500
#define OMNI_MODAL_DISMISS_DELAY_MS 150
#define OMNI_ADW_LIFECYCLE_MAIN_WINDOW_CLOSE_REQUEST 1
#define OMNI_ADW_LIFECYCLE_APP_QUIT_REQUEST 2

struct OmniAdwApp {
  AdwApplication *application;
  GtkWidget *window;
  GtkWidget *root_overlay;
  GtkWidget *shell;
  GtkWidget *body_slot;
  GtkWidget *header;
  GtkWidget *header_title_box;
  GtkWidget *header_title_label;
  GtkWidget *header_tab_strip;
  GtkWidget *header_selected_tab;
  GtkWidget *header_start_actions;
  GtkWidget *header_end_actions;
  GtkWidget *header_entry_row;
  GtkWidget *header_entry;
  GtkWidget *header_new_tab_button;
  GtkWidget *header_sidebar_button;
  GtkWidget *content;
  GtkWidget *active_split_view;
  gboolean sidebar_show_sidebar;
  GHashTable *sidebar_collapsed_items;
  int32_t tab_count;
  int32_t active_tab;
  GtkWidget *settings_window;
  GtkWidget *settings_content;
  gboolean present_settings_on_activate;
  GtkWidget *command_button;
  GtkWidget *command_popover;
  GtkWidget *command_content;
  GtkWidget *app_menu_button;
  GtkWidget *app_menu_surface;
  AdwDialog *modal_dialog;
  GtkWidget *modal_accessibility_root;
  int32_t modal_close_action_id;
  gboolean modal_force_closing;
  char *title;
  char *header_entry_placeholder;
  char *header_entry_text;
  int32_t header_entry_action_id;
  omni_adw_action_callback callback;
  omni_adw_text_callback text_callback;
  omni_adw_key_callback key_callback;
  omni_adw_focus_callback focus_callback;
  omni_adw_event_callback event_callback;
  omni_adw_lifecycle_callback lifecycle_callback;
  void *context;
  int32_t focused_action_id;
  int32_t default_width;
  int32_t default_height;
  GtkEventController *key_controller;
  guint pending_ui_flush_source;
  guint macos_accessibility_sync_source;
  guint modal_dismiss_source;
  gboolean application_actions_installed;
};

enum {
  OMNI_ADW_EVENT_LEFT_MOUSE_DOWN = 1,
  OMNI_ADW_EVENT_LEFT_MOUSE_UP = 2,
  OMNI_ADW_EVENT_RIGHT_MOUSE_DOWN = 3,
  OMNI_ADW_EVENT_RIGHT_MOUSE_UP = 4,
  OMNI_ADW_EVENT_MOUSE_MOVED = 5,
  OMNI_ADW_EVENT_FLAGS_CHANGED = 6,
  OMNI_ADW_EVENT_KEY_DOWN = 7,
  OMNI_ADW_EVENT_SCROLL_WHEEL = 8
};

static uint32_t omni_adw_event_modifiers(GdkModifierType state) {
  uint32_t modifiers = 0;
  if ((state & (GDK_META_MASK | GDK_SUPER_MASK)) != 0) modifiers |= 1u << 0;
  if ((state & GDK_CONTROL_MASK) != 0) modifiers |= 1u << 1;
  if ((state & GDK_ALT_MASK) != 0) modifiers |= 1u << 2;
  if ((state & GDK_SHIFT_MASK) != 0) modifiers |= 1u << 3;
  return modifiers;
}

static gboolean omni_adw_dispatch_native_event(
  OmniAdwApp *app,
  int32_t event_type,
  double x,
  double y,
  int32_t click_count,
  GdkModifierType state,
  guint keyval
) {
  if (!app || !app->event_callback) return FALSE;
  guint unicode = keyval ? gdk_keyval_to_unicode(keyval) : 0;
  int32_t consumed = app->event_callback(
    event_type,
    x,
    y,
    click_count,
    omni_adw_event_modifiers(state),
    keyval,
    unicode,
    app->context
  );
  return consumed != 0;
}

static GdkModifierType omni_adw_current_controller_state(GtkEventController *controller) {
  if (!controller) return 0;
  return gtk_event_controller_get_current_event_state(controller);
}

static gboolean omni_widget_or_parent_is_native_interactive(GtkWidget *widget) {
  GtkWidget *current = widget;
  while (current) {
    if (
      g_object_get_data(G_OBJECT(current), "omni-context-menu-popover") != NULL ||
      GTK_IS_BUTTON(current) ||
      GTK_IS_CHECK_BUTTON(current) ||
      GTK_IS_MENU_BUTTON(current) ||
      GTK_IS_ENTRY(current) ||
      GTK_IS_TEXT_VIEW(current) ||
      GTK_IS_DROP_DOWN(current) ||
      GTK_IS_COLOR_BUTTON(current) ||
      ADW_IS_ACTION_ROW(current) ||
      ADW_IS_EXPANDER_ROW(current) ||
      ADW_IS_SWITCH_ROW(current) ||
	      GTK_IS_SCALE(current) ||
	      GTK_IS_SPIN_BUTTON(current) ||
	      GTK_IS_CALENDAR(current)
#if defined(__APPLE__)
	      || g_object_get_data(G_OBJECT(current), "omni-macos-web-view") != NULL
#endif
	#if defined(__linux__)
	      || WEBKIT_IS_WEB_VIEW(current)
	#endif
    ) {
      return TRUE;
    }
    current = gtk_widget_get_parent(current);
  }
  return FALSE;
}

static gboolean omni_widget_or_parent_is_native_scrollable(GtkWidget *widget) {
  GtkWidget *current = widget;
  while (current) {
    if (
	      GTK_IS_SCROLLED_WINDOW(current) ||
	      GTK_IS_TEXT_VIEW(current)
#if defined(__APPLE__)
	      || g_object_get_data(G_OBJECT(current), "omni-macos-web-view") != NULL
#endif
	#if defined(__linux__)
	      || WEBKIT_IS_WEB_VIEW(current)
	#endif
    ) {
      return TRUE;
    }
    current = gtk_widget_get_parent(current);
  }
  return FALSE;
}

static GtkWidget *omni_current_event_picked_widget(GtkEventController *controller) {
  if (!controller) return NULL;
  GtkWidget *widget = gtk_event_controller_get_widget(controller);
  GdkEvent *event = gtk_event_controller_get_current_event(controller);
  double x = 0.0;
  double y = 0.0;
  if (!widget || !event || !gdk_event_get_position(event, &x, &y)) return NULL;
  return gtk_widget_pick(widget, x, y, GTK_PICK_DEFAULT);
}

struct OmniAdwNode {
  GtkWidget *widget;
  int32_t split_child_count;
};

typedef struct {
  char **labels;
  int32_t *action_ids;
  int32_t *depths;
  double *font_sizes;
  char **font_weights;
  int32_t *font_italics;
  char **css_classes;
  gboolean *collapsed;
  int32_t *visible_indices;
  int32_t visible_count;
  int32_t count;
  GListModel *model;
  GtkWidget **rows;
} OmniStringListData;

typedef struct {
  double x;
  double y;
} OmniClickStart;

typedef struct {
  GdkRGBA *stops;
  int32_t count;
  double start_x;
  double start_y;
  double end_x;
  double end_y;
} OmniAdwGradientData;

typedef struct {
  omni_adw_tick_callback callback;
  void *context;
} OmniAdwTickBridge;

typedef struct {
  omni_adw_web_message_callback message_callback;
  omni_adw_web_navigation_callback navigation_callback;
  omni_adw_web_policy_callback policy_callback;
  omni_adw_web_response_policy_callback response_policy_callback;
  omni_adw_web_download_destination_callback download_destination_callback;
  omni_adw_web_title_callback title_callback;
  omni_adw_web_progress_callback progress_callback;
  omni_adw_web_cookie_callback cookie_callback;
  omni_adw_web_script_dialog_callback script_dialog_callback;
  void *callback_context;
  GHashTable *message_handler_ids;
  WebKitWebView *web_view;
} OmniWebViewBridge;

typedef struct {
  OmniWebViewBridge *bridge;
  char *name;
} OmniWebViewScriptHandler;

typedef struct {
  omni_adw_web_evaluate_callback callback;
  void *callback_context;
} OmniWebViewEvaluation;

typedef struct {
  WebKitUserContentManager *manager;
  struct OmniWebViewDeferredLoad *deferred_load;
} OmniWebViewFilterInstall;

typedef struct {
  OmniWebViewBridge *bridge;
  WebKitUserContentManager *manager;
  char *name;
} OmniWebViewHandlerInstall;

typedef struct OmniWebViewDeferredLoad {
  WebKitWebView *web_view;
  char *url;
  char *html;
  char *base_url;
  char **request_header_names;
  char **request_header_values;
  int32_t request_header_count;
  int32_t pending_filters;
  gboolean did_load;
} OmniWebViewDeferredLoad;

static GHashTable *omni_webkit_views_by_identity = NULL;

static void omni_accessible_label(GtkWidget *widget, const char *label);
static void omni_accessible_description(GtkWidget *widget, const char *description);
static void omni_accessible_role_description(GtkWidget *widget, const char *description);
static void omni_queue_widget_redraw(GtkWidget *widget);
static void omni_queue_widget_and_ancestors_redraw(GtkWidget *widget);

static GHashTable *omni_webkit_view_registry(void) {
  if (!omni_webkit_views_by_identity) {
    omni_webkit_views_by_identity = g_hash_table_new_full(g_str_hash, g_str_equal, free, g_object_unref);
  }
  return omni_webkit_views_by_identity;
}

static gpointer omni_webkit_lookup_view(const char *identity) {
#if defined(__linux__)
  if (!identity || !identity[0] || !omni_webkit_views_by_identity) return NULL;
  GtkWidget *widget = GTK_WIDGET(g_hash_table_lookup(omni_webkit_views_by_identity, identity));
  if (!widget || !WEBKIT_IS_WEB_VIEW(widget)) return NULL;
  return WEBKIT_WEB_VIEW(widget);
#else
  (void)identity;
  return NULL;
#endif
}

static void omni_webkit_unregister_identity(GtkWidget *widget, gpointer user_data) {
  (void)widget;
  const char *identity = (const char *)user_data;
  if (identity && omni_webkit_views_by_identity) {
    g_hash_table_remove(omni_webkit_views_by_identity, identity);
  }
}

static char *omni_strdup(const char *s) {
  if (!s) return strdup("");
  return strdup(s);
}

static GtkWidget *omni_create_webkit_web_view(const char *url, void *native_view) {
  if (!url || !url[0]) return NULL;
#if defined(__APPLE__)
  GtkWidget *native_web_view = omni_macos_web_view_new(url, native_view);
  if (native_web_view) return native_web_view;
#elif defined(__linux__)
  GtkWidget *web_view = GTK_WIDGET(webkit_web_view_new());
  if (!web_view) return NULL;
  webkit_web_view_load_uri(WEBKIT_WEB_VIEW(web_view), url);
  gtk_widget_set_hexpand(web_view, TRUE);
  gtk_widget_set_vexpand(web_view, TRUE);
  gtk_widget_set_halign(web_view, GTK_ALIGN_FILL);
  gtk_widget_set_valign(web_view, GTK_ALIGN_FILL);
  gtk_widget_add_css_class(web_view, "omni-web-view");
  omni_accessible_label(web_view, url);
  omni_accessible_description(web_view, "Web content");
  return web_view;
#endif
  return NULL;
}

#if defined(__linux__)
static void omni_webkit_signature_append_checksum(GString *signature, const char *value) {
  if (!signature) return;
  char *checksum = g_compute_checksum_for_string(G_CHECKSUM_SHA256, value ? value : "", -1);
  g_string_append(signature, checksum ? checksum : "");
  g_free(checksum);
}

static gboolean omni_webkit_signature_is_unchanged(GObject *object, const char *key, char *signature) {
  if (!object || !key || !signature) {
    g_free(signature);
    return FALSE;
  }
  const char *previous = (const char *)g_object_get_data(object, key);
  if (previous && strcmp(previous, signature) == 0) {
    g_free(signature);
    return TRUE;
  }
  g_object_set_data_full(object, key, signature, g_free);
  return FALSE;
}

static char *omni_webkit_string_list_signature(const char **values, int32_t count) {
  GString *signature = g_string_new(NULL);
  if (!signature) return NULL;
  g_string_append_printf(signature, "%d", count);
  for (int32_t i = 0; i < count; i++) {
    g_string_append_c(signature, '\n');
    omni_webkit_signature_append_checksum(signature, values ? values[i] : NULL);
  }
  return g_string_free(signature, FALSE);
}

static char *omni_webkit_string_pair_list_signature(const char **keys, const char **values, int32_t count) {
  GString *signature = g_string_new(NULL);
  if (!signature) return NULL;
  g_string_append_printf(signature, "%d", count);
  for (int32_t i = 0; i < count; i++) {
    g_string_append_c(signature, '\n');
    omni_webkit_signature_append_checksum(signature, keys ? keys[i] : NULL);
    g_string_append_c(signature, '=');
    omni_webkit_signature_append_checksum(signature, values ? values[i] : NULL);
  }
  return g_string_free(signature, FALSE);
}

static char *omni_webkit_user_scripts_signature(
    const char **script_sources,
    const int32_t *script_injection_times,
    const int32_t *script_main_frame_only,
    int32_t script_count) {
  GString *signature = g_string_new(NULL);
  if (!signature) return NULL;
  g_string_append_printf(signature, "%d", script_count);
  for (int32_t i = 0; i < script_count; i++) {
    g_string_append_printf(
        signature,
        "\n%d:%d:",
        script_injection_times ? script_injection_times[i] : 1,
        script_main_frame_only ? script_main_frame_only[i] : 0);
    omni_webkit_signature_append_checksum(signature, script_sources ? script_sources[i] : NULL);
  }
  return g_string_free(signature, FALSE);
}

static char *omni_jsc_value_to_json(JSCValue *value) {
  if (!value) return g_strdup("null");
  if (jsc_value_is_null(value) || jsc_value_is_undefined(value)) return g_strdup("null");
  if (jsc_value_is_boolean(value)) return g_strdup(jsc_value_to_boolean(value) ? "true" : "false");
  if (jsc_value_is_number(value)) return g_strdup_printf("%.17g", jsc_value_to_double(value));
  if (jsc_value_is_string(value)) {
    char *s = jsc_value_to_string(value);
    char *escaped = g_strescape(s ? s : "", NULL);
    char *json = g_strdup_printf("\"%s\"", escaped ? escaped : "");
    g_free(escaped);
    g_free(s);
    return json;
  }
  JSCContext *context = jsc_value_get_context(value);
  JSCValue *json = jsc_context_get_value(context, "JSON");
  JSCValue *stringify = jsc_value_object_get_property(json, "stringify");
  JSCValue *parameters[1] = { value };
  JSCValue *result = jsc_value_function_callv(stringify, 1, parameters);
  if (!result || jsc_value_is_undefined(result) || jsc_value_is_null(result)) return g_strdup("null");
  char *s = jsc_value_to_string(result);
  char *copy = g_strdup(s ? s : "null");
  g_free(s);
  return copy;
}

static void omni_webkit_script_message(WebKitUserContentManager *manager, JSCValue *value, gpointer user_data) {
  OmniWebViewScriptHandler *handler = (OmniWebViewScriptHandler *)user_data;
  OmniWebViewBridge *bridge = handler ? handler->bridge : NULL;
  if (!bridge || !bridge->message_callback) return;
  (void)manager;
  char *json = omni_jsc_value_to_json(value);
  bridge->message_callback(bridge->callback_context, handler->name ? handler->name : "", json ? json : "null");
  g_free(json);
}

static void omni_webkit_script_handler_free(gpointer data, GClosure *closure) {
  (void)closure;
  OmniWebViewScriptHandler *handler = (OmniWebViewScriptHandler *)data;
  if (!handler) return;
  free(handler->name);
  free(handler);
}

static void omni_webkit_install_message_handler(WebKitUserContentManager *manager, OmniWebViewBridge *bridge, const char *name) {
  if (!manager || !bridge || !name || !name[0]) return;
  if (!bridge->message_handler_ids) {
    bridge->message_handler_ids = g_hash_table_new_full(g_str_hash, g_str_equal, free, NULL);
  }
  gpointer existing = g_hash_table_lookup(bridge->message_handler_ids, name);
  if (existing) {
    g_signal_handler_disconnect(manager, GPOINTER_TO_UINT(existing));
    g_hash_table_remove(bridge->message_handler_ids, name);
  }
  webkit_user_content_manager_register_script_message_handler(manager, name, NULL);
  OmniWebViewScriptHandler *handler = calloc(1, sizeof(OmniWebViewScriptHandler));
  if (!handler) return;
  handler->bridge = bridge;
  handler->name = omni_strdup(name);
  char *signal_name = g_strdup_printf("script-message-received::%s", name);
  guint handler_id = (guint)g_signal_connect_data(manager, signal_name, G_CALLBACK(omni_webkit_script_message), handler, omni_webkit_script_handler_free, 0);
  g_hash_table_replace(bridge->message_handler_ids, omni_strdup(name), GUINT_TO_POINTER(handler_id));
  g_free(signal_name);
}

static void omni_webkit_sync_message_handlers(
    WebKitUserContentManager *manager,
    OmniWebViewBridge *bridge,
    const char **message_handler_names,
    int32_t message_handler_count) {
  if (!manager || !bridge) return;
  char *signature = omni_webkit_string_list_signature(message_handler_names, message_handler_count);
  if (omni_webkit_signature_is_unchanged(G_OBJECT(manager), "omni-webkit-message-handlers-signature", signature)) {
    return;
  }
  if (bridge->message_handler_ids) {
    GHashTableIter iter;
    gpointer key = NULL;
    gpointer value = NULL;
    GPtrArray *names = g_ptr_array_new_with_free_func(g_free);
    g_hash_table_iter_init(&iter, bridge->message_handler_ids);
    while (g_hash_table_iter_next(&iter, &key, &value)) {
      const char *name = (const char *)key;
      guint handler_id = GPOINTER_TO_UINT(value);
      if (handler_id) g_signal_handler_disconnect(manager, handler_id);
      if (name && name[0]) g_ptr_array_add(names, g_strdup(name));
    }
    for (guint i = 0; i < names->len; i++) {
      const char *name = (const char *)g_ptr_array_index(names, i);
      webkit_user_content_manager_unregister_script_message_handler(manager, name, NULL);
    }
    g_ptr_array_free(names, TRUE);
    g_hash_table_remove_all(bridge->message_handler_ids);
  }
  for (int32_t i = 0; i < message_handler_count; i++) {
    if (!message_handler_names || !message_handler_names[i]) continue;
    omni_webkit_install_message_handler(manager, bridge, message_handler_names[i]);
  }
}

static void omni_webkit_sync_user_scripts(
    WebKitUserContentManager *manager,
    const char **script_sources,
    const int32_t *script_injection_times,
    const int32_t *script_main_frame_only,
    int32_t script_count) {
  if (!manager) return;
  char *signature = omni_webkit_user_scripts_signature(
      script_sources,
      script_injection_times,
      script_main_frame_only,
      script_count);
  if (omni_webkit_signature_is_unchanged(G_OBJECT(manager), "omni-webkit-user-scripts-signature", signature)) {
    return;
  }
  webkit_user_content_manager_remove_all_scripts(manager);
  for (int32_t i = 0; i < script_count; i++) {
    if (!script_sources || !script_sources[i]) continue;
    WebKitUserScriptInjectionTime time = script_injection_times && script_injection_times[i] == 0
        ? WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START
        : WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_END;
    WebKitUserContentInjectedFrames frames = script_main_frame_only && script_main_frame_only[i]
        ? WEBKIT_USER_CONTENT_INJECT_TOP_FRAME
        : WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES;
    WebKitUserScript *script = webkit_user_script_new(script_sources[i], frames, time, NULL, NULL);
    webkit_user_content_manager_add_script(manager, script);
    webkit_user_script_unref(script);
  }
}

static WebKitUserContentFilterStore *omni_webkit_filter_store(void) {
  static WebKitUserContentFilterStore *store = NULL;
  if (store) return store;

  char *directory = g_build_filename(g_get_user_cache_dir(), "omnikit", "webkit-content-filters", NULL);
  if (!directory) return NULL;
  g_mkdir_with_parents(directory, 0700);
  store = webkit_user_content_filter_store_new(directory);
  g_free(directory);
  return store;
}

static void omni_webkit_filter_install_free(gpointer data) {
  OmniWebViewFilterInstall *install = (OmniWebViewFilterInstall *)data;
  if (!install) return;
  if (install->manager) g_object_unref(install->manager);
  free(install);
}

static char **omni_webkit_copy_string_array(const char **values, int32_t count) {
  if (!values || count <= 0) return NULL;
  char **copy = calloc((size_t)count, sizeof(char *));
  if (!copy) return NULL;
  for (int32_t i = 0; i < count; i++) {
    copy[i] = omni_strdup(values[i]);
  }
  return copy;
}

static void omni_webkit_free_string_array(char **values, int32_t count) {
  if (!values) return;
  for (int32_t i = 0; i < count; i++) free(values[i]);
  free(values);
}

static char *omni_webkit_request_signature(
    const char *url,
    const char **header_names,
    const char **header_values,
    int32_t header_count) {
  if (!url || !url[0]) return NULL;
  GString *signature = g_string_new(url);
  if (!signature) return NULL;
  for (int32_t i = 0; i < header_count; i++) {
    g_string_append_c(signature, '\n');
    omni_webkit_signature_append_checksum(signature, header_names ? header_names[i] : NULL);
    g_string_append_c(signature, ':');
    omni_webkit_signature_append_checksum(signature, header_values ? header_values[i] : NULL);
  }
  return g_string_free(signature, FALSE);
}

static void omni_webkit_clear_request_signature(WebKitWebView *web_view) {
  if (!web_view) return;
  g_object_set_data_full(G_OBJECT(web_view), "omni-last-request-signature", NULL, NULL);
}

static gboolean omni_webkit_request_is_current(
    WebKitWebView *web_view,
    const char *url,
    const char **header_names,
    const char **header_values,
    int32_t header_count) {
  if (!web_view || !url || !url[0]) return TRUE;
  char *signature = omni_webkit_request_signature(url, header_names, header_values, header_count);
  const char *previous = (const char *)g_object_get_data(G_OBJECT(web_view), "omni-last-request-signature");
  if (signature && previous && strcmp(previous, signature) == 0) {
    g_free(signature);
    return TRUE;
  }

  const gboolean has_headers = header_names && header_values && header_count > 0;
  const char *current = webkit_web_view_get_uri(web_view);
  if (!has_headers && current && strcmp(current, url) == 0) {
    if (signature) {
      g_object_set_data_full(G_OBJECT(web_view), "omni-last-request-signature", signature, g_free);
    }
    return TRUE;
  }

  if (signature) {
    g_object_set_data_full(G_OBJECT(web_view), "omni-last-request-signature", signature, g_free);
  }
  return FALSE;
}

static char *omni_webkit_html_signature(const char *html, const char *base_url) {
  if (!html) return NULL;
  char *checksum = g_compute_checksum_for_string(G_CHECKSUM_SHA256, html, -1);
  if (!checksum) return NULL;
  char *signature = g_strdup_printf("%s\n%s", base_url ? base_url : "", checksum);
  g_free(checksum);
  return signature;
}

static void omni_webkit_clear_html_signature(WebKitWebView *web_view) {
  if (!web_view) return;
  g_object_set_data_full(G_OBJECT(web_view), "omni-last-html-signature", NULL, NULL);
}

static gboolean omni_webkit_load_html(WebKitWebView *web_view, const char *html, const char *base_url, gboolean force) {
  if (!web_view || !html) return FALSE;
  char *signature = omni_webkit_html_signature(html, base_url);
  const char *previous = (const char *)g_object_get_data(G_OBJECT(web_view), "omni-last-html-signature");
  if (!force && signature && previous && strcmp(previous, signature) == 0) {
    g_free(signature);
    return FALSE;
  }
  if (signature) {
    g_object_set_data_full(G_OBJECT(web_view), "omni-last-html-signature", signature, g_free);
  }
  omni_webkit_clear_request_signature(web_view);
  webkit_web_view_load_html(web_view, html, base_url && base_url[0] ? base_url : NULL);
  return TRUE;
}

static gboolean omni_webkit_load_html_if_changed(WebKitWebView *web_view, const char *html, const char *base_url) {
  return omni_webkit_load_html(web_view, html, base_url, FALSE);
}

static gboolean omni_webkit_load_uri_with_headers(
    WebKitWebView *web_view,
    const char *url,
    const char **header_names,
    const char **header_values,
    int32_t header_count) {
  if (!web_view || !url || !url[0]) return FALSE;
  if (omni_webkit_request_is_current(web_view, url, header_names, header_values, header_count)) return FALSE;
  omni_webkit_clear_html_signature(web_view);
  if (!header_names || !header_values || header_count <= 0) {
    webkit_web_view_load_uri(web_view, url);
    return TRUE;
  }

  WebKitURIRequest *request = webkit_uri_request_new(url);
  SoupMessageHeaders *headers = request ? webkit_uri_request_get_http_headers(request) : NULL;
  if (headers) {
    for (int32_t i = 0; i < header_count; i++) {
      if (header_names[i] && header_names[i][0] && header_values[i]) {
        soup_message_headers_replace(headers, header_names[i], header_values[i]);
      }
    }
  }
  if (request) {
    webkit_web_view_load_request(web_view, request);
    g_object_unref(request);
  } else {
    webkit_web_view_load_uri(web_view, url);
  }
  return TRUE;
}

static OmniWebViewDeferredLoad *omni_webkit_deferred_load_new(
    WebKitWebView *web_view,
    const char *url,
    const char *html,
    const char *base_url,
    const char **request_header_names,
    const char **request_header_values,
    int32_t request_header_count) {
  OmniWebViewDeferredLoad *load = calloc(1, sizeof(OmniWebViewDeferredLoad));
  if (!load) return NULL;
  load->web_view = web_view ? WEBKIT_WEB_VIEW(g_object_ref(web_view)) : NULL;
  load->url = omni_strdup(url);
  load->html = omni_strdup(html);
  load->base_url = omni_strdup(base_url);
  load->request_header_count = request_header_count > 0 ? request_header_count : 0;
  load->request_header_names = omni_webkit_copy_string_array(request_header_names, load->request_header_count);
  load->request_header_values = omni_webkit_copy_string_array(request_header_values, load->request_header_count);
  if (!load->request_header_names || !load->request_header_values) {
    omni_webkit_free_string_array(load->request_header_names, load->request_header_count);
    omni_webkit_free_string_array(load->request_header_values, load->request_header_count);
    load->request_header_names = NULL;
    load->request_header_values = NULL;
    load->request_header_count = 0;
  }
  return load;
}

static void omni_webkit_deferred_load_free(OmniWebViewDeferredLoad *load) {
  if (!load) return;
  if (load->web_view) g_object_unref(load->web_view);
  free(load->url);
  free(load->html);
  free(load->base_url);
  omni_webkit_free_string_array(load->request_header_names, load->request_header_count);
  omni_webkit_free_string_array(load->request_header_values, load->request_header_count);
  free(load);
}

static void omni_webkit_deferred_load_start(OmniWebViewDeferredLoad *load) {
  if (!load || load->did_load) return;
  load->did_load = TRUE;
  if (load->web_view && load->html && load->html[0]) {
    omni_webkit_load_html_if_changed(load->web_view, load->html, load->base_url);
  } else if (load->web_view && load->url && load->url[0]) {
    omni_webkit_load_uri_with_headers(
        load->web_view,
        load->url,
        (const char **)load->request_header_names,
        (const char **)load->request_header_values,
        load->request_header_count);
  } else if (load->web_view) {
    omni_webkit_load_html_if_changed(load->web_view, "<!doctype html><title>Blank</title>", "about:blank");
  }
  omni_webkit_deferred_load_free(load);
}

static void omni_webkit_deferred_load_filter_finished(OmniWebViewDeferredLoad *load) {
  if (!load) return;
  load->pending_filters -= 1;
  if (load->pending_filters <= 0) {
    omni_webkit_deferred_load_start(load);
  }
}

static void omni_webkit_filter_saved(GObject *object, GAsyncResult *result, gpointer user_data) {
  OmniWebViewFilterInstall *install = (OmniWebViewFilterInstall *)user_data;
  GError *error = NULL;
  WebKitUserContentFilter *filter = webkit_user_content_filter_store_save_finish(WEBKIT_USER_CONTENT_FILTER_STORE(object), result, &error);
  if (filter && install && install->manager) {
    webkit_user_content_manager_add_filter(install->manager, filter);
    webkit_user_content_filter_unref(filter);
  }
  if (error) g_error_free(error);
  OmniWebViewDeferredLoad *deferred_load = install ? install->deferred_load : NULL;
  omni_webkit_filter_install_free(install);
  omni_webkit_deferred_load_filter_finished(deferred_load);
}

static void omni_webkit_install_content_filters(
    WebKitUserContentManager *manager,
    const char **identifiers,
    const char **sources,
    int32_t count,
    OmniWebViewDeferredLoad *deferred_load) {
  if (!manager || !identifiers || !sources || count <= 0) return;
  WebKitUserContentFilterStore *store = omni_webkit_filter_store();
  if (!store) return;

  for (int32_t i = 0; i < count; i++) {
    if (!identifiers[i] || !identifiers[i][0] || !sources[i] || !sources[i][0]) continue;
    GBytes *source = g_bytes_new(sources[i], strlen(sources[i]));
    OmniWebViewFilterInstall *install = calloc(1, sizeof(OmniWebViewFilterInstall));
    if (!source || !install) {
      if (source) g_bytes_unref(source);
      free(install);
      continue;
    }
    install->manager = WEBKIT_USER_CONTENT_MANAGER(g_object_ref(manager));
    install->deferred_load = deferred_load;
    if (deferred_load) deferred_load->pending_filters += 1;
    webkit_user_content_filter_store_save(store, identifiers[i], source, NULL, omni_webkit_filter_saved, install);
    g_bytes_unref(source);
  }
}

static void omni_webkit_sync_content_filters(
    WebKitUserContentManager *manager,
    const char **identifiers,
    const char **sources,
    int32_t count,
    OmniWebViewDeferredLoad *deferred_load) {
  if (!manager) return;
  char *signature = omni_webkit_string_pair_list_signature(identifiers, sources, count);
  if (omni_webkit_signature_is_unchanged(G_OBJECT(manager), "omni-webkit-content-filters-signature", signature)) {
    return;
  }
  webkit_user_content_manager_remove_all_filters(manager);
  omni_webkit_install_content_filters(manager, identifiers, sources, count, deferred_load);
}

static double omni_webkit_cookie_expires_at(SoupCookie *cookie) {
  GDateTime *expires = cookie ? soup_cookie_get_expires(cookie) : NULL;
  return expires ? (double)g_date_time_to_unix(expires) : -1.0;
}

static WebKitCookieManager *omni_webkit_cookie_manager(void) {
  WebKitNetworkSession *session = webkit_network_session_get_default();
  return session ? webkit_network_session_get_cookie_manager(session) : NULL;
}

static SoupCookie *omni_webkit_cookie_new(
    const char *name,
    const char *value,
    const char *domain,
    const char *path,
    double expires_at,
    int32_t secure,
    int32_t http_only) {
  if (!name || !name[0] || !domain || !domain[0]) return NULL;
  int max_age = -1;
  if (expires_at > 0) {
    gint64 now = g_get_real_time() / G_USEC_PER_SEC;
    double remaining = expires_at - (double)now;
    max_age = remaining > 0 ? (int)remaining : 0;
  }
  SoupCookie *cookie = soup_cookie_new(
      name,
      value ? value : "",
      domain,
      path && path[0] ? path : "/",
      max_age);
  if (!cookie) return NULL;
  soup_cookie_set_secure(cookie, secure ? TRUE : FALSE);
  soup_cookie_set_http_only(cookie, http_only ? TRUE : FALSE);
  return cookie;
}

static void omni_webkit_sync_cookies_finished(GObject *object, GAsyncResult *result, gpointer user_data) {
  OmniWebViewBridge *bridge = (OmniWebViewBridge *)user_data;
  if (!bridge || !bridge->cookie_callback) return;

  GError *error = NULL;
  GList *cookies = webkit_cookie_manager_get_all_cookies_finish(WEBKIT_COOKIE_MANAGER(object), result, &error);
  if (error) {
    g_error_free(error);
    return;
  }

  int32_t count = (int32_t)g_list_length(cookies);
  if (count <= 0) {
    bridge->cookie_callback(bridge->callback_context, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0);
    g_list_free_full(cookies, (GDestroyNotify)soup_cookie_free);
    return;
  }

  const char **names = g_new0(const char *, count);
  const char **values = g_new0(const char *, count);
  const char **domains = g_new0(const char *, count);
  const char **paths = g_new0(const char *, count);
  double *expires_at = g_new0(double, count);
  int32_t *secure = g_new0(int32_t, count);
  int32_t *http_only = g_new0(int32_t, count);

  int32_t index = 0;
  for (GList *item = cookies; item && index < count; item = item->next, index++) {
    SoupCookie *cookie = (SoupCookie *)item->data;
    names[index] = soup_cookie_get_name(cookie);
    values[index] = soup_cookie_get_value(cookie);
    domains[index] = soup_cookie_get_domain(cookie);
    paths[index] = soup_cookie_get_path(cookie);
    expires_at[index] = omni_webkit_cookie_expires_at(cookie);
    secure[index] = soup_cookie_get_secure(cookie) ? 1 : 0;
    http_only[index] = soup_cookie_get_http_only(cookie) ? 1 : 0;
  }

  bridge->cookie_callback(
      bridge->callback_context,
      names,
      values,
      domains,
      paths,
      expires_at,
      secure,
      http_only,
      count);

  g_free(names);
  g_free(values);
  g_free(domains);
  g_free(paths);
  g_free(expires_at);
  g_free(secure);
  g_free(http_only);
  g_list_free_full(cookies, (GDestroyNotify)soup_cookie_free);
}

static void omni_webkit_sync_cookies(OmniWebViewBridge *bridge) {
  if (!bridge || !bridge->cookie_callback) return;
  WebKitCookieManager *cookie_manager = omni_webkit_cookie_manager();
  if (!cookie_manager) return;
  webkit_cookie_manager_get_all_cookies(cookie_manager, NULL, omni_webkit_sync_cookies_finished, bridge);
}

static void omni_webkit_back_forward_list_changed(WebKitBackForwardList *list, WebKitBackForwardListItem *item_added, GList *items_removed, gpointer user_data) {
  (void)list;
  (void)item_added;
  (void)items_removed;
  OmniWebViewBridge *bridge = (OmniWebViewBridge *)user_data;
  if (bridge && bridge->navigation_callback) {
    bridge->navigation_callback(bridge->callback_context, 3, NULL, NULL);
  }
}

static void omni_webkit_click_pressed(GtkGestureClick *gesture, int n_press, double x, double y, gpointer user_data) {
  (void)gesture;
  (void)n_press;
  (void)x;
  (void)y;
  GtkWidget *web_view = GTK_WIDGET(user_data);
  if (web_view) gtk_widget_grab_focus(web_view);
}

static gboolean omni_queue_widget_redraw_idle(gpointer data) {
  GtkWidget *widget = GTK_WIDGET(data);
  if (widget) {
    gtk_widget_queue_resize(widget);
    gtk_widget_queue_draw(widget);
  }
  g_object_unref(widget);
  return G_SOURCE_REMOVE;
}

static void omni_queue_widget_redraw(GtkWidget *widget) {
  if (!widget) return;
  gtk_widget_queue_resize(widget);
  gtk_widget_queue_draw(widget);
  GtkNative *native = gtk_widget_get_native(widget);
  GdkSurface *surface = native ? gtk_native_get_surface(native) : NULL;
  if (surface) gdk_surface_queue_render(surface);
  if (GTK_IS_ENTRY(widget) || GTK_IS_TEXT_VIEW(widget)) return;
  g_object_ref(widget);
  g_idle_add(omni_queue_widget_redraw_idle, widget);
}

static void omni_queue_widget_and_ancestors_redraw(GtkWidget *widget) {
  GtkWidget *current = widget;
  int depth = 0;
  while (current && depth < 8) {
    omni_queue_widget_redraw(current);
    current = gtk_widget_get_parent(current);
    depth += 1;
  }
}

static void omni_webkit_load_changed(WebKitWebView *web_view, WebKitLoadEvent load_event, gpointer user_data) {
  if (web_view) omni_queue_widget_and_ancestors_redraw(GTK_WIDGET(web_view));
  OmniWebViewBridge *bridge = (OmniWebViewBridge *)user_data;
  const char *uri = webkit_web_view_get_uri(web_view);
  if (g_getenv("OMNI_WEBKITGTK_TRACE")) {
    g_printerr("OMNI_WEBKITGTK_LOAD event=%d uri=%s\n", (int)load_event, uri ? uri : "");
  }
  if (!bridge || !bridge->navigation_callback) return;
  if (load_event == WEBKIT_LOAD_STARTED) {
    bridge->navigation_callback(bridge->callback_context, 0, uri, NULL);
  } else if (load_event == WEBKIT_LOAD_COMMITTED) {
    bridge->navigation_callback(bridge->callback_context, 4, uri, NULL);
  } else if (load_event == WEBKIT_LOAD_FINISHED) {
    bridge->navigation_callback(bridge->callback_context, 1, uri, NULL);
    omni_webkit_sync_cookies(bridge);
  }
}

static void omni_webkit_title_changed(WebKitWebView *web_view, GParamSpec *pspec, gpointer user_data) {
  (void)pspec;
  if (web_view) omni_queue_widget_and_ancestors_redraw(GTK_WIDGET(web_view));
  OmniWebViewBridge *bridge = (OmniWebViewBridge *)user_data;
  if (!bridge || !bridge->title_callback) return;
  const char *title = webkit_web_view_get_title(web_view);
  bridge->title_callback(bridge->callback_context, title ? title : "");
}

static void omni_webkit_progress_changed(WebKitWebView *web_view, GParamSpec *pspec, gpointer user_data) {
  (void)pspec;
  if (web_view) omni_queue_widget_and_ancestors_redraw(GTK_WIDGET(web_view));
  OmniWebViewBridge *bridge = (OmniWebViewBridge *)user_data;
  if (!bridge || !bridge->progress_callback) return;
  bridge->progress_callback(bridge->callback_context, webkit_web_view_get_estimated_load_progress(web_view));
}

static gboolean omni_webkit_script_dialog(WebKitWebView *web_view, WebKitScriptDialog *dialog, gpointer user_data) {
  (void)web_view;
  OmniWebViewBridge *bridge = (OmniWebViewBridge *)user_data;
  if (!bridge || !bridge->script_dialog_callback || !dialog) return FALSE;

  int32_t handled = 0;
  int32_t confirmed = 0;
  WebKitScriptDialogType type = webkit_script_dialog_get_dialog_type(dialog);
  const char *message = webkit_script_dialog_get_message(dialog);
  const char *default_text = type == WEBKIT_SCRIPT_DIALOG_PROMPT ? webkit_script_dialog_prompt_get_default_text(dialog) : NULL;
  char *prompt_text = bridge->script_dialog_callback(
      bridge->callback_context,
      (int32_t)type,
      message ? message : "",
      default_text ? default_text : "",
      &handled,
      &confirmed);

  if (!handled) {
    if (prompt_text) free(prompt_text);
    return FALSE;
  }

  if (type == WEBKIT_SCRIPT_DIALOG_CONFIRM || type == WEBKIT_SCRIPT_DIALOG_BEFORE_UNLOAD_CONFIRM) {
    webkit_script_dialog_confirm_set_confirmed(dialog, confirmed ? TRUE : FALSE);
  } else if (type == WEBKIT_SCRIPT_DIALOG_PROMPT) {
    webkit_script_dialog_prompt_set_text(dialog, prompt_text ? prompt_text : "");
  }
  webkit_script_dialog_close(dialog);
  if (prompt_text) free(prompt_text);
  return TRUE;
}

static gboolean omni_webkit_load_failed(WebKitWebView *web_view, WebKitLoadEvent load_event, const char *failing_uri, GError *error, gpointer user_data) {
  OmniWebViewBridge *bridge = (OmniWebViewBridge *)user_data;
  if (g_getenv("OMNI_WEBKITGTK_TRACE")) {
    g_printerr("OMNI_WEBKITGTK_LOAD_FAILED event=%d uri=%s error=%s\n", (int)load_event, failing_uri ? failing_uri : "", error ? error->message : "");
  }
  if (bridge && bridge->navigation_callback) {
    bridge->navigation_callback(bridge->callback_context, 2, failing_uri ? failing_uri : webkit_web_view_get_uri(web_view), error ? error->message : "Load failed");
  }
  return FALSE;
}

static int32_t omni_webkit_navigation_type(WebKitNavigationType type) {
  switch (type) {
    case WEBKIT_NAVIGATION_TYPE_LINK_CLICKED: return 0;
    case WEBKIT_NAVIGATION_TYPE_FORM_SUBMITTED: return 1;
    case WEBKIT_NAVIGATION_TYPE_BACK_FORWARD: return 2;
    case WEBKIT_NAVIGATION_TYPE_RELOAD: return 3;
    case WEBKIT_NAVIGATION_TYPE_FORM_RESUBMITTED: return 4;
    case WEBKIT_NAVIGATION_TYPE_OTHER: return -1;
    default: return -1;
  }
}

static gboolean omni_webkit_decide_policy(WebKitWebView *web_view, WebKitPolicyDecision *decision, WebKitPolicyDecisionType type, gpointer user_data) {
  OmniWebViewBridge *bridge = (OmniWebViewBridge *)user_data;
  if (!bridge) return FALSE;
  if (type == WEBKIT_POLICY_DECISION_TYPE_RESPONSE) {
    if (!bridge->response_policy_callback || !WEBKIT_IS_RESPONSE_POLICY_DECISION(decision)) return FALSE;
    WebKitResponsePolicyDecision *response_decision = WEBKIT_RESPONSE_POLICY_DECISION(decision);
    WebKitURIResponse *response = webkit_response_policy_decision_get_response(response_decision);
    const char *uri = response ? webkit_uri_response_get_uri(response) : webkit_web_view_get_uri(web_view);
    const char *mime_type = response ? webkit_uri_response_get_mime_type(response) : NULL;
    const char *suggested_filename = response ? webkit_uri_response_get_suggested_filename(response) : NULL;
    guint64 content_length = response ? webkit_uri_response_get_content_length(response) : 0;
    int32_t can_show = webkit_response_policy_decision_is_mime_type_supported(response_decision) ? 1 : 0;
    int32_t policy = bridge->response_policy_callback(
        bridge->callback_context,
        uri ? uri : "",
        mime_type ? mime_type : "",
        can_show,
        (int64_t)content_length,
        suggested_filename ? suggested_filename : "");
    if (policy == 2) {
      if (bridge->download_destination_callback) {
        char *destination = bridge->download_destination_callback(
            bridge->callback_context,
            uri ? uri : "",
            mime_type ? mime_type : "",
            (int64_t)content_length,
            suggested_filename ? suggested_filename : "");
        if (!destination || !destination[0]) {
          g_free(destination);
          webkit_policy_decision_ignore(decision);
          return TRUE;
        }
        char *destination_uri = NULL;
        if (g_str_has_prefix(destination, "file://")) {
          destination_uri = g_strdup(destination);
        } else {
          destination_uri = g_filename_to_uri(destination, NULL, NULL);
        }
        WebKitNetworkSession *session = webkit_network_session_get_default();
        WebKitDownload *download = uri && uri[0] && session ? webkit_network_session_download_uri(session, uri) : NULL;
        if (download && destination_uri) {
          webkit_download_set_destination(download, destination_uri);
        }
        g_free(destination_uri);
        g_free(destination);
        webkit_policy_decision_ignore(decision);
        return TRUE;
      }
      webkit_policy_decision_download(decision);
      return TRUE;
    }
    if (policy == 0) {
      webkit_policy_decision_ignore(decision);
      return TRUE;
    }
    return FALSE;
  }
  if (!bridge->policy_callback) return FALSE;
  if (type != WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION &&
      type != WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) return FALSE;
  if (!WEBKIT_IS_NAVIGATION_POLICY_DECISION(decision)) return FALSE;
  WebKitNavigationAction *action = webkit_navigation_policy_decision_get_navigation_action(WEBKIT_NAVIGATION_POLICY_DECISION(decision));
  WebKitURIRequest *request = action ? webkit_navigation_action_get_request(action) : NULL;
  const char *uri = request ? webkit_uri_request_get_uri(request) : webkit_web_view_get_uri(web_view);
  int32_t navigation_type = action ? omni_webkit_navigation_type(webkit_navigation_action_get_navigation_type(action)) : -1;
  int32_t is_new_window = type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION ? 1 : 0;
  int32_t allow = bridge->policy_callback(bridge->callback_context, uri ? uri : "", navigation_type, is_new_window);
  if (allow) return FALSE;
  webkit_policy_decision_ignore(decision);
  return TRUE;
}

static void omni_webkit_download_started(WebKitWebContext *context, WebKitDownload *download, gpointer user_data) {
  (void)context;
  OmniWebViewBridge *bridge = (OmniWebViewBridge *)user_data;
  if (!bridge || !bridge->download_destination_callback || !download) return;
  if (bridge->web_view && webkit_download_get_web_view(download) != bridge->web_view) return;
  WebKitURIRequest *request = webkit_download_get_request(download);
  WebKitURIResponse *response = webkit_download_get_response(download);
  const char *uri = response ? webkit_uri_response_get_uri(response) : (request ? webkit_uri_request_get_uri(request) : NULL);
  const char *mime_type = response ? webkit_uri_response_get_mime_type(response) : NULL;
  const char *suggested_filename = response ? webkit_uri_response_get_suggested_filename(response) : NULL;
  guint64 content_length = response ? webkit_uri_response_get_content_length(response) : 0;
  char *destination = bridge->download_destination_callback(
      bridge->callback_context,
      uri ? uri : "",
      mime_type ? mime_type : "",
      (int64_t)content_length,
      suggested_filename ? suggested_filename : "");
  if (!destination || !destination[0]) {
    g_free(destination);
    webkit_download_cancel(download);
    return;
  }
  char *destination_uri = NULL;
  if (g_str_has_prefix(destination, "file://")) {
    destination_uri = g_strdup(destination);
  } else {
    destination_uri = g_filename_to_uri(destination, NULL, NULL);
  }
  if (destination_uri) {
    webkit_download_set_destination(download, destination_uri);
    g_free(destination_uri);
  } else {
    webkit_download_cancel(download);
  }
  g_free(destination);
}

static char *omni_webkit_sanitized_user_agent_value(const char *value) {
  if (!value || !value[0]) return NULL;
  GString *out = g_string_new(NULL);
  for (const unsigned char *p = (const unsigned char *)value; *p; p++) {
    if (*p == '\r' || *p == '\n' || *p == 0x7f || *p < 0x20) continue;
    g_string_append_c(out, (char)*p);
  }
  char *result = g_strstrip(g_string_free(out, FALSE));
  if (!result || !result[0]) {
    g_free(result);
    return NULL;
  }
  return result;
}

static const char *omni_webkit_default_user_agent(WebKitWebView *web_view, WebKitSettings *settings) {
  const char *stored = web_view ? (const char *)g_object_get_data(G_OBJECT(web_view), "omni-default-user-agent") : NULL;
  if (stored && stored[0]) return stored;
  const char *current = settings ? webkit_settings_get_user_agent(settings) : NULL;
  char *copy = omni_strdup(current && current[0] ? current : "");
  if (web_view && copy) {
    g_object_set_data_full(G_OBJECT(web_view), "omni-default-user-agent", copy, free);
    return (const char *)g_object_get_data(G_OBJECT(web_view), "omni-default-user-agent");
  }
  free(copy);
  return current;
}

static void omni_webkit_apply_user_agent(WebKitWebView *web_view, const char *application_name, const char *custom_user_agent) {
  if (!web_view) return;
  WebKitSettings *settings = webkit_web_view_get_settings(web_view);
  if (!settings) return;
  char *custom = omni_webkit_sanitized_user_agent_value(custom_user_agent);
  if (custom) {
    webkit_settings_set_user_agent(settings, custom);
    g_free(custom);
    return;
  }

  char *suffix = omni_webkit_sanitized_user_agent_value(application_name);
  if (suffix) {
    const char *base = omni_webkit_default_user_agent(web_view, settings);
    char *combined = (base && base[0]) ? g_strdup_printf("%s %s", base, suffix) : g_strdup(suffix);
    if (combined && combined[0]) {
      webkit_settings_set_user_agent(settings, combined);
    }
    g_free(combined);
    g_free(suffix);
    return;
  }

  webkit_settings_set_user_agent(settings, NULL);
}

static void omni_webkit_update_bridge_callbacks(
    WebKitWebView *web_view,
    omni_adw_web_message_callback message_callback,
    omni_adw_web_navigation_callback navigation_callback,
    omni_adw_web_policy_callback policy_callback,
    omni_adw_web_response_policy_callback response_policy_callback,
    omni_adw_web_download_destination_callback download_destination_callback,
    omni_adw_web_title_callback title_callback,
    omni_adw_web_progress_callback progress_callback,
    omni_adw_web_cookie_callback cookie_callback,
    omni_adw_web_script_dialog_callback script_dialog_callback,
    void *callback_context) {
  if (!web_view) return;
  OmniWebViewBridge *bridge = (OmniWebViewBridge *)g_object_get_data(G_OBJECT(web_view), "omni-webkit-bridge");
  if (!bridge) return;
  bridge->message_callback = message_callback;
  bridge->navigation_callback = navigation_callback;
  bridge->policy_callback = policy_callback;
  bridge->response_policy_callback = response_policy_callback;
  bridge->download_destination_callback = download_destination_callback;
  bridge->title_callback = title_callback;
  bridge->progress_callback = progress_callback;
  bridge->cookie_callback = cookie_callback;
  bridge->script_dialog_callback = script_dialog_callback;
  bridge->callback_context = callback_context;
}

static void omni_webkit_update_settings(
    WebKitWebView *web_view,
    const char *application_name,
    const char *custom_user_agent,
    double page_zoom,
    int32_t allows_back_forward_navigation_gestures,
    int32_t javascript_can_open_windows,
    int32_t javascript_enabled,
    double minimum_font_size,
    int32_t is_inspectable,
    int32_t allows_inline_media_playback,
    int32_t media_playback_requires_user_gesture) {
  if (!web_view) return;
  WebKitSettings *settings = webkit_web_view_get_settings(web_view);
  if (!settings) return;
  webkit_settings_set_javascript_can_open_windows_automatically(settings, javascript_can_open_windows ? TRUE : FALSE);
  webkit_settings_set_enable_javascript(settings, javascript_enabled ? TRUE : FALSE);
  webkit_settings_set_minimum_font_size(settings, minimum_font_size > 0 ? (guint)minimum_font_size : 0);
  webkit_settings_set_enable_developer_extras(settings, is_inspectable ? TRUE : FALSE);
  webkit_settings_set_media_playback_allows_inline(settings, allows_inline_media_playback ? TRUE : FALSE);
  webkit_settings_set_media_playback_requires_user_gesture(settings, media_playback_requires_user_gesture ? TRUE : FALSE);
  webkit_settings_set_enable_back_forward_navigation_gestures(settings, allows_back_forward_navigation_gestures ? TRUE : FALSE);
  omni_webkit_apply_user_agent(web_view, application_name, custom_user_agent);
  webkit_web_view_set_zoom_level(web_view, page_zoom > 0 ? page_zoom : 1.0);
}

static void omni_webkit_load_if_needed(
    WebKitWebView *web_view,
    const char *url,
    const char *html,
    const char *base_url,
    const char **request_header_names,
    const char **request_header_values,
    int32_t request_header_count) {
  if (!web_view) return;
  if (html) {
    omni_webkit_load_html_if_changed(web_view, html, base_url);
  } else if (url && url[0]) {
    omni_webkit_load_uri_with_headers(
        web_view,
        url,
        request_header_names,
        request_header_values,
        request_header_count);
  }
}

static void omni_webkit_detach_for_reuse(GtkWidget *widget) {
  if (!widget) return;
  GtkWidget *parent = gtk_widget_get_parent(widget);
  if (!parent) return;

  g_object_ref(widget);
  if (GTK_IS_BOX(parent)) {
    gtk_box_remove(GTK_BOX(parent), widget);
  } else if (GTK_IS_OVERLAY(parent)) {
    if (gtk_overlay_get_child(GTK_OVERLAY(parent)) == widget) {
      gtk_overlay_set_child(GTK_OVERLAY(parent), NULL);
    } else {
      gtk_overlay_remove_overlay(GTK_OVERLAY(parent), widget);
    }
  } else if (GTK_IS_LIST_BOX_ROW(parent)) {
    if (gtk_list_box_row_get_child(GTK_LIST_BOX_ROW(parent)) == widget) {
      gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(parent), NULL);
    } else {
      gtk_widget_unparent(widget);
    }
  } else if (GTK_IS_SCROLLED_WINDOW(parent)) {
    if (gtk_scrolled_window_get_child(GTK_SCROLLED_WINDOW(parent)) == widget) {
      gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(parent), NULL);
    } else {
      gtk_widget_unparent(widget);
    }
  } else if (GTK_IS_BUTTON(parent)) {
    if (gtk_button_get_child(GTK_BUTTON(parent)) == widget) {
      gtk_button_set_child(GTK_BUTTON(parent), NULL);
    } else {
      gtk_widget_unparent(widget);
    }
  } else if (GTK_IS_PANED(parent)) {
    if (gtk_paned_get_start_child(GTK_PANED(parent)) == widget) {
      gtk_paned_set_start_child(GTK_PANED(parent), NULL);
    } else if (gtk_paned_get_end_child(GTK_PANED(parent)) == widget) {
      gtk_paned_set_end_child(GTK_PANED(parent), NULL);
    } else {
      gtk_widget_unparent(widget);
    }
  } else if (ADW_IS_OVERLAY_SPLIT_VIEW(parent)) {
    if (adw_overlay_split_view_get_sidebar(ADW_OVERLAY_SPLIT_VIEW(parent)) == widget) {
      adw_overlay_split_view_set_sidebar(ADW_OVERLAY_SPLIT_VIEW(parent), NULL);
    } else if (adw_overlay_split_view_get_content(ADW_OVERLAY_SPLIT_VIEW(parent)) == widget) {
      adw_overlay_split_view_set_content(ADW_OVERLAY_SPLIT_VIEW(parent), NULL);
    } else {
      gtk_widget_unparent(widget);
    }
  } else if (ADW_IS_NAVIGATION_PAGE(parent)) {
    if (adw_navigation_page_get_child(ADW_NAVIGATION_PAGE(parent)) == widget) {
      adw_navigation_page_set_child(ADW_NAVIGATION_PAGE(parent), NULL);
    } else {
      gtk_widget_unparent(widget);
    }
  } else if (GTK_IS_WINDOW(parent)) {
    if (gtk_window_get_child(GTK_WINDOW(parent)) == widget) {
      gtk_window_set_child(GTK_WINDOW(parent), NULL);
    } else {
      gtk_widget_unparent(widget);
    }
  } else {
    gtk_widget_unparent(widget);
  }
  g_object_unref(widget);
}

static void omni_webkit_bridge_free(gpointer data) {
  OmniWebViewBridge *bridge = (OmniWebViewBridge *)data;
  if (!bridge) return;
  if (bridge->message_handler_ids) g_hash_table_destroy(bridge->message_handler_ids);
  free(bridge);
}

static void omni_webkit_clear_bridge_callbacks(WebKitWebView *web_view) {
  if (!web_view) return;
  OmniWebViewBridge *bridge = (OmniWebViewBridge *)g_object_get_data(G_OBJECT(web_view), "omni-webkit-bridge");
  if (!bridge) return;
  bridge->message_callback = NULL;
  bridge->navigation_callback = NULL;
  bridge->policy_callback = NULL;
  bridge->response_policy_callback = NULL;
  bridge->download_destination_callback = NULL;
  bridge->title_callback = NULL;
  bridge->progress_callback = NULL;
  bridge->cookie_callback = NULL;
  bridge->script_dialog_callback = NULL;
  bridge->callback_context = NULL;
}

static GtkWidget *omni_create_webkit_web_view_ex(
    const char *identity,
    const char *url,
    const char *html,
    const char *base_url,
    const char **request_header_names,
    const char **request_header_values,
    int32_t request_header_count,
    const char *application_name,
    const char *custom_user_agent,
    double page_zoom,
    int32_t allows_back_forward_navigation_gestures,
    int32_t javascript_can_open_windows,
    int32_t javascript_enabled,
    double minimum_font_size,
    int32_t is_inspectable,
    int32_t allows_inline_media_playback,
    int32_t media_playback_requires_user_gesture,
    const char **script_sources,
    const int32_t *script_injection_times,
    const int32_t *script_main_frame_only,
    int32_t script_count,
    const char **content_rule_identifiers,
    const char **content_rule_sources,
    int32_t content_rule_count,
    const char **message_handler_names,
    int32_t message_handler_count,
    const char **cookie_names,
    const char **cookie_values,
    const char **cookie_domains,
    const char **cookie_paths,
    const double *cookie_expires_at,
    const int32_t *cookie_secure,
    const int32_t *cookie_http_only,
    int32_t cookie_count,
    const char *accessibility_label,
    const char *accessibility_description,
    omni_adw_web_message_callback message_callback,
    omni_adw_web_navigation_callback navigation_callback,
    omni_adw_web_policy_callback policy_callback,
    omni_adw_web_response_policy_callback response_policy_callback,
    omni_adw_web_download_destination_callback download_destination_callback,
    omni_adw_web_title_callback title_callback,
    omni_adw_web_progress_callback progress_callback,
    omni_adw_web_cookie_callback cookie_callback,
    omni_adw_web_script_dialog_callback script_dialog_callback,
    void *callback_context) {
  WebKitWebView *existing = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (existing) {
    omni_webkit_detach_for_reuse(GTK_WIDGET(existing));
    omni_webkit_update_bridge_callbacks(
        existing,
        message_callback,
        navigation_callback,
        policy_callback,
        response_policy_callback,
        download_destination_callback,
        title_callback,
        progress_callback,
        cookie_callback,
        script_dialog_callback,
        callback_context);
    omni_webkit_update_settings(
        existing,
        application_name,
        custom_user_agent,
        page_zoom,
        allows_back_forward_navigation_gestures,
        javascript_can_open_windows,
        javascript_enabled,
        minimum_font_size,
        is_inspectable,
        allows_inline_media_playback,
        media_playback_requires_user_gesture);
    WebKitUserContentManager *manager = webkit_web_view_get_user_content_manager(existing);
    OmniWebViewBridge *bridge = (OmniWebViewBridge *)g_object_get_data(G_OBJECT(existing), "omni-webkit-bridge");
    omni_webkit_sync_user_scripts(
        manager,
        script_sources,
        script_injection_times,
        script_main_frame_only,
        script_count);
    if (manager) {
      omni_webkit_sync_content_filters(manager, content_rule_identifiers, content_rule_sources, content_rule_count, NULL);
    }
    omni_webkit_sync_message_handlers(manager, bridge, message_handler_names, message_handler_count);
    omni_webkit_load_if_needed(
        existing,
        url,
        html,
        base_url,
        request_header_names,
        request_header_values,
        request_header_count);
    if (accessibility_label && accessibility_label[0]) omni_accessible_label(GTK_WIDGET(existing), accessibility_label);
    if (accessibility_description && accessibility_description[0]) omni_accessible_description(GTK_WIDGET(existing), accessibility_description);
    omni_queue_widget_and_ancestors_redraw(GTK_WIDGET(existing));
    return GTK_WIDGET(existing);
  }

  WebKitUserContentManager *manager = webkit_user_content_manager_new();
  GtkWidget *web_view = GTK_WIDGET(g_object_new(WEBKIT_TYPE_WEB_VIEW, "user-content-manager", manager, NULL));
  g_object_unref(manager);
  if (!web_view) return NULL;

  manager = webkit_web_view_get_user_content_manager(WEBKIT_WEB_VIEW(web_view));
  omni_webkit_sync_user_scripts(manager, script_sources, script_injection_times, script_main_frame_only, script_count);
  OmniWebViewDeferredLoad *initial_load = omni_webkit_deferred_load_new(
      WEBKIT_WEB_VIEW(web_view),
      url,
      html,
      base_url,
      request_header_names,
      request_header_values,
      request_header_count);
  omni_webkit_sync_content_filters(manager, content_rule_identifiers, content_rule_sources, content_rule_count, initial_load);

  OmniWebViewBridge *bridge = calloc(1, sizeof(OmniWebViewBridge));
  bridge->web_view = WEBKIT_WEB_VIEW(web_view);
  bridge->message_callback = message_callback;
  bridge->navigation_callback = navigation_callback;
  bridge->policy_callback = policy_callback;
  bridge->response_policy_callback = response_policy_callback;
  bridge->download_destination_callback = download_destination_callback;
  bridge->title_callback = title_callback;
  bridge->progress_callback = progress_callback;
  bridge->cookie_callback = cookie_callback;
  bridge->script_dialog_callback = script_dialog_callback;
  bridge->callback_context = callback_context;

  for (int32_t i = 0; i < message_handler_count; i++) {
    if (!message_handler_names || !message_handler_names[i]) continue;
    omni_webkit_install_message_handler(manager, bridge, message_handler_names[i]);
  }

  if (cookie_count > 0) {
    WebKitCookieManager *cookie_manager = omni_webkit_cookie_manager();
    if (cookie_manager) {
      webkit_cookie_manager_set_accept_policy(cookie_manager, WEBKIT_COOKIE_POLICY_ACCEPT_ALWAYS);
      for (int32_t i = 0; i < cookie_count; i++) {
        if (!cookie_names || !cookie_values || !cookie_domains || !cookie_paths ||
            !cookie_names[i] || !cookie_domains[i] || !cookie_paths[i]) continue;
        SoupCookie *cookie = omni_webkit_cookie_new(
            cookie_names[i],
            cookie_values[i] ? cookie_values[i] : "",
            cookie_domains[i],
            cookie_paths[i][0] ? cookie_paths[i] : "/",
            cookie_expires_at ? cookie_expires_at[i] : -1,
            cookie_secure && cookie_secure[i] ? 1 : 0,
            cookie_http_only && cookie_http_only[i] ? 1 : 0);
        if (!cookie) continue;
        webkit_cookie_manager_add_cookie(cookie_manager, cookie, NULL, NULL, NULL);
        soup_cookie_free(cookie);
      }
    }
  }

  g_object_set_data_full(G_OBJECT(web_view), "omni-webkit-bridge", bridge, omni_webkit_bridge_free);
  if (identity && identity[0]) {
    char *identity_copy = omni_strdup(identity);
    g_object_set_data_full(G_OBJECT(web_view), "omni-webkit-identity", omni_strdup(identity), free);
    g_hash_table_replace(omni_webkit_view_registry(), omni_strdup(identity), g_object_ref(web_view));
    g_signal_connect_data(web_view, "destroy", G_CALLBACK(omni_webkit_unregister_identity), identity_copy, (GClosureNotify)free, 0);
  }

  omni_webkit_update_settings(
      WEBKIT_WEB_VIEW(web_view),
      application_name,
      custom_user_agent,
      page_zoom,
      allows_back_forward_navigation_gestures,
      javascript_can_open_windows,
      javascript_enabled,
      minimum_font_size,
      is_inspectable,
      allows_inline_media_playback,
      media_playback_requires_user_gesture);

  g_signal_connect(web_view, "load-changed", G_CALLBACK(omni_webkit_load_changed), bridge);
  g_signal_connect(web_view, "load-failed", G_CALLBACK(omni_webkit_load_failed), bridge);
  g_signal_connect(web_view, "decide-policy", G_CALLBACK(omni_webkit_decide_policy), bridge);
  WebKitWebContext *web_context = webkit_web_view_get_context(WEBKIT_WEB_VIEW(web_view));
  if (web_context && g_signal_lookup("download-started", G_OBJECT_TYPE(web_context)) != 0) {
    g_signal_connect(web_context, "download-started", G_CALLBACK(omni_webkit_download_started), bridge);
  }
  g_signal_connect(web_view, "notify::title", G_CALLBACK(omni_webkit_title_changed), bridge);
  g_signal_connect(web_view, "notify::estimated-load-progress", G_CALLBACK(omni_webkit_progress_changed), bridge);
  g_signal_connect(web_view, "script-dialog", G_CALLBACK(omni_webkit_script_dialog), bridge);
  WebKitBackForwardList *back_forward_list = webkit_web_view_get_back_forward_list(WEBKIT_WEB_VIEW(web_view));
  if (back_forward_list) {
    g_signal_connect(back_forward_list, "changed", G_CALLBACK(omni_webkit_back_forward_list_changed), bridge);
  }

  GtkGesture *click_gesture = gtk_gesture_click_new();
  g_signal_connect(click_gesture, "pressed", G_CALLBACK(omni_webkit_click_pressed), web_view);
  gtk_widget_add_controller(web_view, GTK_EVENT_CONTROLLER(click_gesture));

  if (!initial_load) {
    if (html && html[0]) {
      omni_webkit_load_html_if_changed(WEBKIT_WEB_VIEW(web_view), html, base_url);
    } else if (url && url[0]) {
      omni_webkit_load_uri_with_headers(
          WEBKIT_WEB_VIEW(web_view),
          url,
          request_header_names,
          request_header_values,
          request_header_count);
    } else {
      omni_webkit_load_html_if_changed(WEBKIT_WEB_VIEW(web_view), "<!doctype html><title>Blank</title>", "about:blank");
    }
  } else if (initial_load->pending_filters <= 0) {
    omni_webkit_deferred_load_start(initial_load);
    initial_load = NULL;
  }

  gtk_widget_set_hexpand(web_view, TRUE);
  gtk_widget_set_vexpand(web_view, TRUE);
  gtk_widget_set_halign(web_view, GTK_ALIGN_FILL);
  gtk_widget_set_valign(web_view, GTK_ALIGN_FILL);
  gtk_widget_set_focusable(web_view, TRUE);
  gtk_widget_add_css_class(web_view, "omni-web-view");
  omni_accessible_label(web_view, accessibility_label && accessibility_label[0] ? accessibility_label : (url ? url : "Web content"));
  omni_accessible_description(web_view, accessibility_description && accessibility_description[0] ? accessibility_description : "Web content");
  omni_accessible_role_description(web_view, "web document");
  gtk_accessible_update_property(
    GTK_ACCESSIBLE(web_view),
    GTK_ACCESSIBLE_PROPERTY_MULTI_LINE, TRUE,
    -1
  );
  omni_queue_widget_redraw(web_view);
  return web_view;
}

static void omni_webkit_evaluate_finished(GObject *object, GAsyncResult *result, gpointer user_data) {
  OmniWebViewEvaluation *evaluation = (OmniWebViewEvaluation *)user_data;
  if (!evaluation) return;
  GError *error = NULL;
  JSCValue *value = webkit_web_view_evaluate_javascript_finish(WEBKIT_WEB_VIEW(object), result, &error);
  char *json = error ? NULL : omni_jsc_value_to_json(value);
  if (evaluation->callback) {
    evaluation->callback(
        evaluation->callback_context,
        json ? json : "null",
        error ? error->message : NULL);
  }
  if (error) g_error_free(error);
  g_free(json);
  free(evaluation);
}
#endif

#if !defined(__linux__)
static gboolean omni_queue_widget_redraw_idle(gpointer data) {
  GtkWidget *widget = GTK_WIDGET(data);
  if (widget) {
    gtk_widget_queue_resize(widget);
    gtk_widget_queue_draw(widget);
  }
  g_object_unref(widget);
  return G_SOURCE_REMOVE;
}

static void omni_queue_widget_redraw(GtkWidget *widget) {
  if (!widget) return;
  gtk_widget_queue_resize(widget);
  gtk_widget_queue_draw(widget);
  GtkNative *native = gtk_widget_get_native(widget);
  GdkSurface *surface = native ? gtk_native_get_surface(native) : NULL;
  if (surface) gdk_surface_queue_render(surface);
  if (GTK_IS_ENTRY(widget) || GTK_IS_TEXT_VIEW(widget)) return;
  g_object_ref(widget);
  g_idle_add(omni_queue_widget_redraw_idle, widget);
}

static void omni_queue_widget_and_ancestors_redraw(GtkWidget *widget) {
  GtkWidget *current = widget;
  int depth = 0;
  while (current && depth < 8) {
    omni_queue_widget_redraw(current);
    current = gtk_widget_get_parent(current);
    depth += 1;
  }
}
#endif

int32_t omni_adw_web_view_load_uri(const char *identity, const char *url) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view || !url || !url[0]) return 0;
  omni_webkit_load_uri_with_headers(web_view, url, NULL, NULL, 0);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_load_uri(identity, url);
#else
  (void)identity; (void)url;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_load_request(const char *identity, const char *url, const char **header_names, const char **header_values, int32_t header_count) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view || !url || !url[0]) return 0;
  omni_webkit_load_uri_with_headers(web_view, url, header_names, header_values, header_count);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_load_request(identity, url, header_names, header_values, header_count);
#else
  (void)identity; (void)url; (void)header_names; (void)header_values; (void)header_count;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_load_html(const char *identity, const char *html, const char *base_url) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view || !html) return 0;
  omni_webkit_load_html(web_view, html, base_url, TRUE);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_load_html(identity, html, base_url);
#else
  (void)identity; (void)html; (void)base_url;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_unregister(const char *identity) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view || !omni_webkit_views_by_identity) return 0;
  omni_webkit_clear_bridge_callbacks(web_view);
  webkit_web_view_stop_loading(web_view);
  if (g_getenv("OMNI_WEBKITGTK_TRACE")) {
    g_printerr("OMNI_WEBKITGTK_UNREGISTER identity=%s view=%p\n", identity ? identity : "", web_view);
  }
  return g_hash_table_remove(omni_webkit_views_by_identity, identity) ? 1 : 0;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_unregister(identity);
#else
  (void)identity;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_evaluate_javascript(const char *identity, const char *script, omni_adw_web_evaluate_callback callback, void *callback_context) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view || !script) return 0;
  OmniWebViewEvaluation *evaluation = calloc(1, sizeof(OmniWebViewEvaluation));
  evaluation->callback = callback;
  evaluation->callback_context = callback_context;
  webkit_web_view_evaluate_javascript(web_view, script, -1, NULL, NULL, NULL, omni_webkit_evaluate_finished, evaluation);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_evaluate_javascript(identity, script, callback, callback_context);
#else
  (void)identity; (void)script; (void)callback; (void)callback_context;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_cookie_store_set(
    const char *name,
    const char *value,
    const char *domain,
    const char *path,
    double expires_at,
    int32_t secure,
    int32_t http_only) {
#if defined(__linux__)
  WebKitCookieManager *cookie_manager = omni_webkit_cookie_manager();
  if (!cookie_manager) return 0;
  SoupCookie *cookie = omni_webkit_cookie_new(name, value, domain, path, expires_at, secure, http_only);
  if (!cookie) return 0;
  webkit_cookie_manager_set_accept_policy(cookie_manager, WEBKIT_COOKIE_POLICY_ACCEPT_ALWAYS);
  webkit_cookie_manager_add_cookie(cookie_manager, cookie, NULL, NULL, NULL);
  soup_cookie_free(cookie);
  return 1;
#else
  (void)name; (void)value; (void)domain; (void)path; (void)expires_at; (void)secure; (void)http_only;
  return 0;
#endif
}

int32_t omni_adw_web_cookie_store_delete(
    const char *name,
    const char *value,
    const char *domain,
    const char *path,
    double expires_at,
    int32_t secure,
    int32_t http_only) {
#if defined(__linux__)
  WebKitCookieManager *cookie_manager = omni_webkit_cookie_manager();
  if (!cookie_manager) return 0;
  SoupCookie *cookie = omni_webkit_cookie_new(name, value, domain, path, expires_at, secure, http_only);
  if (!cookie) return 0;
  webkit_cookie_manager_delete_cookie(cookie_manager, cookie, NULL, NULL, NULL);
  soup_cookie_free(cookie);
  return 1;
#else
  (void)name; (void)value; (void)domain; (void)path; (void)expires_at; (void)secure; (void)http_only;
  return 0;
#endif
}

int32_t omni_adw_web_view_go_back(const char *identity) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view || !webkit_web_view_can_go_back(web_view)) return 0;
  webkit_web_view_go_back(web_view);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_go_back(identity);
#else
  (void)identity;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_go_forward(const char *identity) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view || !webkit_web_view_can_go_forward(web_view)) return 0;
  webkit_web_view_go_forward(web_view);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_go_forward(identity);
#else
  (void)identity;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_reload(const char *identity) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view) return 0;
  webkit_web_view_reload(web_view);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_reload(identity);
#else
  (void)identity;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_stop_loading(const char *identity) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view) return 0;
  webkit_web_view_stop_loading(web_view);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_stop_loading(identity);
#else
  (void)identity;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_can_go_back(const char *identity) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  return web_view && webkit_web_view_can_go_back(web_view) ? 1 : 0;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_can_go_back(identity);
#else
  (void)identity;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_can_go_forward(const char *identity) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  return web_view && webkit_web_view_can_go_forward(web_view) ? 1 : 0;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_can_go_forward(identity);
#else
  (void)identity;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_set_zoom(const char *identity, double page_zoom) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view) return 0;
  webkit_web_view_set_zoom_level(web_view, page_zoom > 0 ? page_zoom : 1.0);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_set_zoom(identity, page_zoom);
#else
  (void)identity; (void)page_zoom;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_set_allows_back_forward_navigation_gestures(const char *identity, int32_t enabled) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view) return 0;
  WebKitSettings *settings = webkit_web_view_get_settings(web_view);
  if (!settings) return 0;
  webkit_settings_set_enable_back_forward_navigation_gestures(settings, enabled ? TRUE : FALSE);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_set_allows_back_forward_navigation_gestures(identity, enabled);
#else
  (void)identity; (void)enabled;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_set_javascript_can_open_windows(const char *identity, int32_t enabled) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view) return 0;
  WebKitSettings *settings = webkit_web_view_get_settings(web_view);
  if (!settings) return 0;
  webkit_settings_set_javascript_can_open_windows_automatically(settings, enabled ? TRUE : FALSE);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_set_javascript_can_open_windows(identity, enabled);
#else
  (void)identity; (void)enabled;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_set_javascript_enabled(const char *identity, int32_t enabled) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view) return 0;
  WebKitSettings *settings = webkit_web_view_get_settings(web_view);
  if (!settings) return 0;
  webkit_settings_set_enable_javascript(settings, enabled ? TRUE : FALSE);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_set_javascript_enabled(identity, enabled);
#else
  (void)identity; (void)enabled;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_set_minimum_font_size(const char *identity, double size) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view) return 0;
  WebKitSettings *settings = webkit_web_view_get_settings(web_view);
  if (!settings) return 0;
  webkit_settings_set_minimum_font_size(settings, size > 0 ? (guint)size : 0);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_set_minimum_font_size(identity, size);
#else
  (void)identity; (void)size;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_set_inspectable(const char *identity, int32_t enabled) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view) return 0;
  WebKitSettings *settings = webkit_web_view_get_settings(web_view);
  if (!settings) return 0;
  webkit_settings_set_enable_developer_extras(settings, enabled ? TRUE : FALSE);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_set_inspectable(identity, enabled);
#else
  (void)identity; (void)enabled;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_set_user_agent(const char *identity, const char *application_name, const char *custom_user_agent) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view) return 0;
  omni_webkit_apply_user_agent(web_view, application_name, custom_user_agent);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_set_user_agent(identity, application_name, custom_user_agent);
#else
  (void)identity; (void)application_name; (void)custom_user_agent;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_add_user_script(const char *identity, const char *source, int32_t injection_time, int32_t main_frame_only) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view || !source) return 0;
  WebKitUserContentManager *manager = webkit_web_view_get_user_content_manager(web_view);
  if (!manager) return 0;
  WebKitUserScriptInjectionTime time = injection_time == 0
      ? WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START
      : WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_END;
  WebKitUserContentInjectedFrames frames = main_frame_only
      ? WEBKIT_USER_CONTENT_INJECT_TOP_FRAME
      : WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES;
  WebKitUserScript *script = webkit_user_script_new(source, frames, time, NULL, NULL);
  if (!script) return 0;
  webkit_user_content_manager_add_script(manager, script);
  webkit_user_script_unref(script);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_add_user_script(identity, source, injection_time, main_frame_only);
#else
  (void)identity; (void)source; (void)injection_time; (void)main_frame_only;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_remove_all_user_scripts(const char *identity) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view) return 0;
  WebKitUserContentManager *manager = webkit_web_view_get_user_content_manager(web_view);
  if (!manager) return 0;
  webkit_user_content_manager_remove_all_scripts(manager);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_remove_all_user_scripts(identity);
#else
  (void)identity;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_register_message_handler(const char *identity, const char *name) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view || !name || !name[0]) return 0;
  WebKitUserContentManager *manager = webkit_web_view_get_user_content_manager(web_view);
  OmniWebViewBridge *bridge = (OmniWebViewBridge *)g_object_get_data(G_OBJECT(web_view), "omni-webkit-bridge");
  if (!manager || !bridge) return 0;
  omni_webkit_install_message_handler(manager, bridge, name);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_register_message_handler_named(identity, name);
#else
  (void)identity; (void)name;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_unregister_message_handler(const char *identity, const char *name) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view || !name || !name[0]) return 0;
  WebKitUserContentManager *manager = webkit_web_view_get_user_content_manager(web_view);
  if (!manager) return 0;
  OmniWebViewBridge *bridge = (OmniWebViewBridge *)g_object_get_data(G_OBJECT(web_view), "omni-webkit-bridge");
  if (bridge && bridge->message_handler_ids) {
    gpointer existing = g_hash_table_lookup(bridge->message_handler_ids, name);
    if (existing) {
      g_signal_handler_disconnect(manager, GPOINTER_TO_UINT(existing));
      g_hash_table_remove(bridge->message_handler_ids, name);
    }
  }
  webkit_user_content_manager_unregister_script_message_handler(manager, name, NULL);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_unregister_message_handler_named(identity, name);
#else
  (void)identity; (void)name;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_add_content_rule(const char *identity, const char *identifier, const char *source) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view || !identifier || !identifier[0] || !source || !source[0]) return 0;
  WebKitUserContentManager *manager = webkit_web_view_get_user_content_manager(web_view);
  if (!manager) return 0;
  omni_webkit_install_content_filters(manager, &identifier, &source, 1, NULL);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_add_content_rule(identity, identifier, source);
#else
  (void)identity; (void)identifier; (void)source;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_remove_all_content_rules(const char *identity) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view) return 0;
  WebKitUserContentManager *manager = webkit_web_view_get_user_content_manager(web_view);
  if (!manager) return 0;
  webkit_user_content_manager_remove_all_filters(manager);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_remove_all_content_rules(identity);
#else
  (void)identity;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_focus(const char *identity) {
#if defined(__linux__)
  GtkWidget *web_view = GTK_WIDGET(omni_webkit_lookup_view(identity));
  if (!web_view) return 0;
  gtk_widget_set_focusable(web_view, TRUE);
  gtk_widget_grab_focus(web_view);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_focus(identity);
#else
  (void)identity;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_scroll_by(const char *identity, double dx, double dy) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view) return 0;
  char *script = g_strdup_printf(
      "(function(){"
        "var dx=%0.17g,dy=%0.17g;"
        "var el=document.scrollingElement||document.documentElement||document.body;"
        "if(el){"
          "var beforeX=el.scrollLeft,beforeY=el.scrollTop;"
          "el.scrollLeft=beforeX+dx;el.scrollTop=beforeY+dy;"
          "if((dx&&el.scrollLeft===beforeX)||(dy&&el.scrollTop===beforeY)){window.scrollBy({left:dx,top:dy,behavior:'auto'});}"
        "}else{window.scrollBy({left:dx,top:dy,behavior:'auto'});}"
      "})();",
      dx,
      dy);
  if (!script) return 0;
  webkit_web_view_evaluate_javascript(web_view, script, -1, NULL, NULL, NULL, NULL, NULL);
  g_free(script);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_scroll_by_identity(identity, dx, dy);
#else
  (void)identity; (void)dx; (void)dy;
  return 0;
#endif
#endif
}

int32_t omni_adw_web_view_scroll_page(const char *identity, int32_t direction) {
#if defined(__linux__)
  WebKitWebView *web_view = WEBKIT_WEB_VIEW(omni_webkit_lookup_view(identity));
  if (!web_view) return 0;
  char *script = g_strdup_printf(
      "(function(){"
        "var direction=%d;"
        "var page=Math.max(160,Math.floor((window.innerHeight||600)*0.82));"
        "window.scrollBy({left:0,top:(direction>=0?page:-page),behavior:'auto'});"
      "})();",
      direction);
  if (!script) return 0;
  webkit_web_view_evaluate_javascript(web_view, script, -1, NULL, NULL, NULL, NULL, NULL);
  g_free(script);
  return 1;
#else
#if defined(__APPLE__)
  return omni_macos_web_view_scroll_page_identity(identity, direction);
#else
  (void)identity; (void)direction;
  return 0;
#endif
#endif
}

static char *omni_sanitized_widget_name(const char *semantic_id) {
  char *copy = omni_strdup(semantic_id);
  for (char *p = copy; *p; p++) {
    if (!((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') || (*p >= '0' && *p <= '9') || *p == '-' || *p == '_')) {
      *p = '-';
    }
  }
  return copy;
}

static void free_label_array(gpointer data) {
  char **labels = (char **)data;
  if (!labels) return;
  for (char **p = labels; *p; p++) {
    free(*p);
  }
  free(labels);
}

static void free_string_list_data(gpointer data) {
  OmniStringListData *list = (OmniStringListData *)data;
  if (!list) return;
  if (list->labels) {
    for (int32_t i = 0; i < list->count; i++) {
      free(list->labels[i]);
    }
  }
  if (list->font_weights) {
    for (int32_t i = 0; i < list->count; i++) {
      free(list->font_weights[i]);
    }
  }
  if (list->css_classes) {
    for (int32_t i = 0; i < list->count; i++) {
      free(list->css_classes[i]);
    }
  }
  free(list->labels);
  free(list->action_ids);
  free(list->depths);
  free(list->font_sizes);
  free(list->font_weights);
  free(list->font_italics);
  free(list->css_classes);
  free(list->collapsed);
  free(list->visible_indices);
  free(list->rows);
  free(list);
}

typedef struct _OmniListRowObject {
  GObject parent_instance;
  int32_t original_index;
} OmniListRowObject;

typedef struct _OmniListRowObjectClass {
  GObjectClass parent_class;
} OmniListRowObjectClass;

GType omni_list_row_object_get_type(void);
#define OMNI_TYPE_LIST_ROW_OBJECT (omni_list_row_object_get_type())
#define OMNI_LIST_ROW_OBJECT(obj) ((OmniListRowObject *)(obj))
#define OMNI_IS_LIST_ROW_OBJECT(obj) (G_TYPE_CHECK_INSTANCE_TYPE((obj), OMNI_TYPE_LIST_ROW_OBJECT))

G_DEFINE_TYPE(OmniListRowObject, omni_list_row_object, G_TYPE_OBJECT)

static void omni_list_row_object_class_init(OmniListRowObjectClass *klass) {
  (void)klass;
}

static void omni_list_row_object_init(OmniListRowObject *object) {
  object->original_index = -1;
}

static OmniListRowObject *omni_list_row_object_new(int32_t original_index) {
  OmniListRowObject *object = g_object_new(OMNI_TYPE_LIST_ROW_OBJECT, NULL);
  object->original_index = original_index;
  return object;
}

typedef struct _OmniListModel {
  GObject parent_instance;
  OmniStringListData *data;
} OmniListModel;

typedef struct _OmniListModelClass {
  GObjectClass parent_class;
} OmniListModelClass;

GType omni_list_model_get_type(void);
#define OMNI_TYPE_LIST_MODEL (omni_list_model_get_type())
#define OMNI_LIST_MODEL(obj) ((OmniListModel *)(obj))

static void omni_list_model_list_model_init(GListModelInterface *iface);

G_DEFINE_TYPE_WITH_CODE(
  OmniListModel,
  omni_list_model,
  G_TYPE_OBJECT,
  G_IMPLEMENT_INTERFACE(G_TYPE_LIST_MODEL, omni_list_model_list_model_init)
)

static GType omni_list_model_get_item_type(GListModel *model) {
  (void)model;
  return OMNI_TYPE_LIST_ROW_OBJECT;
}

static guint omni_list_model_get_n_items(GListModel *model) {
  OmniListModel *self = OMNI_LIST_MODEL(model);
  OmniStringListData *list = self ? self->data : NULL;
  if (!list) return 0;
  if (list->visible_indices) return (guint)list->visible_count;
  return (guint)list->count;
}

static gpointer omni_list_model_get_item(GListModel *model, guint position) {
  OmniListModel *self = OMNI_LIST_MODEL(model);
  OmniStringListData *list = self ? self->data : NULL;
  if (!list) return NULL;
  int32_t original = (int32_t)position;
  if (list->visible_indices && position < (guint)list->visible_count) {
    original = list->visible_indices[position];
  }
  if (original < 0 || original >= list->count) return NULL;
  return omni_list_row_object_new(original);
}

static void omni_list_model_list_model_init(GListModelInterface *iface) {
  iface->get_item_type = omni_list_model_get_item_type;
  iface->get_n_items = omni_list_model_get_n_items;
  iface->get_item = omni_list_model_get_item;
}

static void omni_list_model_finalize(GObject *object) {
  OmniListModel *self = OMNI_LIST_MODEL(object);
  if (self->data) {
    self->data->model = NULL;
    free_string_list_data(self->data);
    self->data = NULL;
  }
  G_OBJECT_CLASS(omni_list_model_parent_class)->finalize(object);
}

static void omni_list_model_class_init(OmniListModelClass *klass) {
  GObjectClass *object_class = G_OBJECT_CLASS(klass);
  object_class->finalize = omni_list_model_finalize;
}

static void omni_list_model_init(OmniListModel *model) {
  model->data = NULL;
}

static OmniListModel *omni_list_model_new(OmniStringListData *data) {
  OmniListModel *model = g_object_new(OMNI_TYPE_LIST_MODEL, NULL);
  model->data = data;
  if (data) data->model = G_LIST_MODEL(model);
  return model;
}

static void omni_widget_expand(GtkWidget *widget, gboolean vertical) {
  if (!widget) return;
  gtk_widget_set_hexpand(widget, TRUE);
  gtk_widget_set_halign(widget, GTK_ALIGN_FILL);
  if (vertical) {
    gtk_widget_set_vexpand(widget, TRUE);
    gtk_widget_set_valign(widget, GTK_ALIGN_FILL);
  }
}

static gboolean omni_widget_is_textual_overlay(GtkWidget *widget) {
  if (!widget) return FALSE;
  if (GTK_IS_LABEL(widget) || GTK_IS_BUTTON(widget) || GTK_IS_IMAGE(widget)) return TRUE;
  if (!GTK_IS_BOX(widget)) return FALSE;
  gboolean saw_child = FALSE;
  for (GtkWidget *child = gtk_widget_get_first_child(widget); child; child = gtk_widget_get_next_sibling(child)) {
    saw_child = TRUE;
    if (!omni_widget_is_textual_overlay(child)) return FALSE;
  }
  return saw_child;
}

static gboolean omni_widget_has_explicit_width(GtkWidget *widget) {
  return widget && GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-explicit-width")) != 0;
}

static gboolean omni_widget_has_explicit_height(GtkWidget *widget) {
  return widget && GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-explicit-height")) != 0;
}

static void omni_widget_set_layout_size_recursive(GtkWidget *widget, int width, int height) {
  if (!widget || (width < 0 && height < 0)) return;
  gtk_widget_set_size_request(widget, width >= 0 ? width : -1, height >= 0 ? height : -1);

  if (!GTK_IS_OVERLAY(widget)) return;
  GtkWidget *base_child = gtk_overlay_get_child(GTK_OVERLAY(widget));
  if (!base_child) return;
  int child_width = width >= 0 && !omni_widget_has_explicit_width(base_child) ? width : -1;
  int child_height = height >= 0 && !omni_widget_has_explicit_height(base_child) ? height : -1;
  omni_widget_set_layout_size_recursive(base_child, child_width, child_height);
}

static GtkAlign omni_overlay_horizontal_align(const char *alignment) {
  if (!alignment) return GTK_ALIGN_CENTER;
  if (strstr(alignment, "Trailing") || strstr(alignment, "trailing")) return GTK_ALIGN_END;
  if (strstr(alignment, "Leading") || strstr(alignment, "leading")) return GTK_ALIGN_START;
  return GTK_ALIGN_CENTER;
}

static GtkAlign omni_overlay_vertical_align(const char *alignment) {
  if (!alignment) return GTK_ALIGN_CENTER;
  if (strstr(alignment, "bottom") || strstr(alignment, "Bottom")) return GTK_ALIGN_END;
  if (strstr(alignment, "top") || strstr(alignment, "Top")) return GTK_ALIGN_START;
  return GTK_ALIGN_CENTER;
}

static void omni_overlay_prepare_child(GtkWidget *widget, const char *alignment) {
  if (!widget) return;
  gboolean textual = omni_widget_is_textual_overlay(widget);
  gboolean explicit_width = omni_widget_has_explicit_width(widget);
  gboolean explicit_height = omni_widget_has_explicit_height(widget);

  if (textual || explicit_width) {
    gtk_widget_set_hexpand(widget, FALSE);
    gtk_widget_set_halign(widget, omni_overlay_horizontal_align(alignment));
  } else {
    gtk_widget_set_hexpand(widget, TRUE);
    gtk_widget_set_halign(widget, GTK_ALIGN_FILL);
  }

  if (textual || explicit_height) {
    gtk_widget_set_vexpand(widget, FALSE);
    gtk_widget_set_valign(widget, omni_overlay_vertical_align(alignment));
  } else {
    gtk_widget_set_vexpand(widget, TRUE);
    gtk_widget_set_valign(widget, GTK_ALIGN_FILL);
  }
}

static void omni_overlay_sync_base_child_size(GtkWidget *overlay) {
  if (!overlay || !GTK_IS_OVERLAY(overlay)) return;
  GtkWidget *child = gtk_overlay_get_child(GTK_OVERLAY(overlay));
  if (!child) return;
  int width = gtk_widget_get_width(overlay);
  int height = gtk_widget_get_height(overlay);
  int child_width = width > 0 && !omni_widget_has_explicit_width(child) ? width : -1;
  int child_height = height > 0 && !omni_widget_has_explicit_height(child) ? height : -1;
  if (child_width >= 0 || child_height >= 0) {
    omni_widget_set_layout_size_recursive(child, child_width, child_height);
    gtk_widget_queue_draw(child);
  }
}

static void omni_overlay_size_notify(GObject *object, GParamSpec *pspec, gpointer user_data) {
  (void)pspec;
  (void)user_data;
  omni_overlay_sync_base_child_size(GTK_WIDGET(object));
}

static void omni_overlay_install_size_sync(GtkWidget *overlay) {
  if (!overlay || !GTK_IS_OVERLAY(overlay)) return;
  if (g_object_get_data(G_OBJECT(overlay), "omni-overlay-size-sync-installed")) return;
  g_signal_connect(overlay, "notify::width", G_CALLBACK(omni_overlay_size_notify), NULL);
  g_signal_connect(overlay, "notify::height", G_CALLBACK(omni_overlay_size_notify), NULL);
  g_object_set_data(G_OBJECT(overlay), "omni-overlay-size-sync-installed", GINT_TO_POINTER(1));
}

static PangoWeight omni_font_weight_from_string(const char *weight) {
  if (!weight || !weight[0]) return PANGO_WEIGHT_NORMAL;
  if (g_ascii_strcasecmp(weight, "ultralight") == 0) return PANGO_WEIGHT_ULTRALIGHT;
  if (g_ascii_strcasecmp(weight, "thin") == 0) return PANGO_WEIGHT_THIN;
  if (g_ascii_strcasecmp(weight, "light") == 0) return PANGO_WEIGHT_LIGHT;
  if (g_ascii_strcasecmp(weight, "medium") == 0) return PANGO_WEIGHT_MEDIUM;
  if (g_ascii_strcasecmp(weight, "semibold") == 0) return PANGO_WEIGHT_SEMIBOLD;
  if (g_ascii_strcasecmp(weight, "bold") == 0) return PANGO_WEIGHT_BOLD;
  if (g_ascii_strcasecmp(weight, "heavy") == 0) return PANGO_WEIGHT_HEAVY;
  if (g_ascii_strcasecmp(weight, "black") == 0) return PANGO_WEIGHT_ULTRAHEAVY;
  return PANGO_WEIGHT_NORMAL;
}

static void omni_label_apply_font(GtkLabel *label, double size, const char *weight, gboolean italic) {
  if (!label) return;
  gboolean has_size = size > 0.0;
  gboolean has_weight = weight && weight[0];
  gboolean has_italic = italic != FALSE;
  if (!has_size && !has_weight && !has_italic) {
    gtk_label_set_attributes(label, NULL);
    return;
  }

  PangoAttrList *attrs = pango_attr_list_new();
  if (has_size) {
    PangoAttribute *attr = pango_attr_size_new_absolute((int)(size * PANGO_SCALE));
    pango_attr_list_insert(attrs, attr);
  }
  if (has_weight) {
    PangoAttribute *attr = pango_attr_weight_new(omni_font_weight_from_string(weight));
    pango_attr_list_insert(attrs, attr);
  }
  if (has_italic) {
    PangoAttribute *attr = pango_attr_style_new(PANGO_STYLE_ITALIC);
    pango_attr_list_insert(attrs, attr);
  }
  gtk_label_set_attributes(label, attrs);
  pango_attr_list_unref(attrs);
}

static void omni_widget_apply_font_recursive(GtkWidget *widget, double size, const char *weight, gboolean italic) {
  if (!widget) return;
  if (GTK_IS_LABEL(widget)) {
    omni_label_apply_font(GTK_LABEL(widget), size, weight, italic);
  }
  for (GtkWidget *child = gtk_widget_get_first_child(widget); child; child = gtk_widget_get_next_sibling(child)) {
    omni_widget_apply_font_recursive(child, size, weight, italic);
  }
}

static gboolean omni_cached_bool_update(GtkWidget *widget, const char *key, gboolean value) {
  if (!widget || !key) return FALSE;
  int next = value ? 1 : 2;
  int current = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), key));
  if (current == next) return FALSE;
  g_object_set_data(G_OBJECT(widget), key, GINT_TO_POINTER(next));
  return TRUE;
}

static void omni_accessible_label_with_native_update(GtkWidget *widget, const char *label, gboolean update_native) {
  if (!widget || !label || !label[0]) return;
  const char *current = (const char *)g_object_get_data(G_OBJECT(widget), "omni-accessible-label");
  if (current && strcmp(current, label) == 0) return;
  g_object_set_data_full(G_OBJECT(widget), "omni-accessible-label", omni_strdup(label), free);
  if (!update_native) return;
  gtk_accessible_update_property(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_PROPERTY_LABEL, label, -1);
}

static void omni_accessible_label(GtkWidget *widget, const char *label) {
  omni_accessible_label_with_native_update(widget, label, TRUE);
}

static void omni_accessible_description(GtkWidget *widget, const char *description) {
  if (!widget || !description || !description[0]) return;
  const char *current = (const char *)g_object_get_data(G_OBJECT(widget), "omni-accessible-description");
  if (current && strcmp(current, description) == 0) return;
  g_object_set_data_full(G_OBJECT(widget), "omni-accessible-description", omni_strdup(description), free);
  gtk_accessible_update_property(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_PROPERTY_DESCRIPTION, description, -1);
}

static void omni_accessible_role_description(GtkWidget *widget, const char *description) {
  if (!widget || !description || !description[0]) return;
  gtk_accessible_update_property(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_PROPERTY_ROLE_DESCRIPTION, description, -1);
}

static void omni_accessible_placeholder(GtkWidget *widget, const char *placeholder) {
  if (!widget || !placeholder || !placeholder[0]) return;
  gtk_accessible_update_property(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_PROPERTY_PLACEHOLDER, placeholder, -1);
}

static gboolean omni_entry_is_secure(GtkWidget *widget) {
  return widget && GTK_IS_ENTRY(widget) && !gtk_entry_get_visibility(GTK_ENTRY(widget));
}

static char *omni_mask_text(const char *value) {
  if (!value || !value[0]) return NULL;
  GString *masked = g_string_new("");
  for (const char *cursor = value; cursor && *cursor;) {
    gunichar ch = g_utf8_get_char(cursor);
    if (ch == 0) break;
    g_string_append(masked, "•");
    cursor = g_utf8_next_char(cursor);
  }
  return g_string_free(masked, FALSE);
}

static void omni_accessible_read_only(GtkWidget *widget, gboolean read_only) {
  if (!widget) return;
  gtk_accessible_update_property(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_PROPERTY_READ_ONLY, read_only, -1);
}

static void omni_accessible_multi_line(GtkWidget *widget, gboolean multi_line) {
  if (!widget) return;
  gtk_accessible_update_property(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_PROPERTY_MULTI_LINE, multi_line, -1);
}

static void omni_accessible_value_text(GtkWidget *widget, const char *value) {
  if (!widget || !value || !value[0]) return;
  char *masked = omni_entry_is_secure(widget) ? omni_mask_text(value) : NULL;
  const char *accessible_value = masked ? masked : value;
  const char *current = (const char *)g_object_get_data(G_OBJECT(widget), "omni-accessible-value");
  if (!current || strcmp(current, accessible_value) != 0) {
    g_object_set_data_full(G_OBJECT(widget), "omni-accessible-value", omni_strdup(accessible_value), free);
    gtk_accessible_update_property(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_PROPERTY_VALUE_TEXT, accessible_value, -1);
  }
  free(masked);
}

static void omni_accessible_set_disabled(GtkWidget *widget, gboolean disabled) {
  if (!widget) return;
  if (!omni_cached_bool_update(widget, "omni-accessible-disabled-cache", disabled)) return;
  gtk_accessible_update_state(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_STATE_DISABLED, disabled, -1);
}

static void omni_accessible_set_selected(GtkWidget *widget, gboolean selected) {
  if (!widget) return;
  if (!omni_cached_bool_update(widget, "omni-accessible-selected-cache", selected)) return;
  gtk_accessible_update_state(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_STATE_SELECTED, selected, -1);
}

static void omni_accessible_set_expanded(GtkWidget *widget, gboolean expanded) {
  if (!widget) return;
  if (!omni_cached_bool_update(widget, "omni-accessible-expanded-cache", expanded)) return;
  gtk_accessible_update_state(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_STATE_EXPANDED, expanded, -1);
}

static void omni_accessible_list_position(GtkWidget *widget, int32_t position, int32_t size) {
  if (!widget || position <= 0 || size <= 0) return;
  if (size > OMNI_NATIVE_ACCESSIBILITY_ROW_UPDATE_LIMIT) return;
  int current_position = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-accessible-pos-cache"));
  int current_size = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-accessible-set-size-cache"));
  if (current_position == position && current_size == size) return;
  g_object_set_data(G_OBJECT(widget), "omni-accessible-pos-cache", GINT_TO_POINTER(position));
  g_object_set_data(G_OBJECT(widget), "omni-accessible-set-size-cache", GINT_TO_POINTER(size));
  gtk_accessible_update_relation(
    GTK_ACCESSIBLE(widget),
    GTK_ACCESSIBLE_RELATION_POS_IN_SET, position,
    GTK_ACCESSIBLE_RELATION_SET_SIZE, size,
    -1
  );
}

static void omni_record_click_start(GtkGestureClick *gesture, double x, double y) {
  if (!gesture) return;
  OmniClickStart *start = (OmniClickStart *)g_object_get_data(G_OBJECT(gesture), "omni-click-start");
  if (!start) {
    start = calloc(1, sizeof(OmniClickStart));
    if (!start) return;
    g_object_set_data_full(G_OBJECT(gesture), "omni-click-start", start, free);
  }
  start->x = x;
  start->y = y;
}

static gboolean omni_click_is_stationary(GtkGestureClick *gesture, double x, double y) {
  if (!gesture) return FALSE;
  OmniClickStart *start = (OmniClickStart *)g_object_get_data(G_OBJECT(gesture), "omni-click-start");
  if (!start) return TRUE;
  double dx = x - start->x;
  double dy = y - start->y;
  if (dx < 0) dx = -dx;
  if (dy < 0) dy = -dy;
  return dx <= 8.0 && dy <= 8.0;
}

static void omni_macos_accessibility_sync(OmniAdwApp *app);
static void omni_macos_accessibility_cancel_pending(OmniAdwApp *app);
static void omni_macos_accessibility_schedule(OmniAdwApp *app);
static void omni_macos_accessibility_schedule_after_scroll(OmniAdwApp *app);
static void omni_flush_pending_ui(OmniAdwApp *app);

static int omni_native_dispatch_depth = 0;

static gboolean omni_flush_pending_ui_idle(gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app) return G_SOURCE_REMOVE;
  app->pending_ui_flush_source = 0;
  omni_flush_pending_ui(app);
  return G_SOURCE_REMOVE;
}

static void omni_schedule_pending_ui_flush(OmniAdwApp *app) {
  if (!app || app->pending_ui_flush_source != 0) return;
  app->pending_ui_flush_source = g_idle_add(omni_flush_pending_ui_idle, app);
}

static void omni_dispatch_action_callback(OmniAdwApp *app, int32_t action_id) {
  if (!app || !app->callback || action_id <= 0) return;
  omni_native_dispatch_depth += 1;
  app->callback(action_id, app->context);
  omni_native_dispatch_depth -= 1;
}

static void omni_dispatch_key_callback(OmniAdwApp *app, int32_t action_id, int32_t kind, uint32_t codepoint) {
  if (!app || !app->key_callback) return;
  omni_native_dispatch_depth += 1;
  app->key_callback(action_id, kind, codepoint, app->context);
  omni_native_dispatch_depth -= 1;
}

static void omni_flush_pending_ui(OmniAdwApp *app) {
  if (app && app->content) omni_queue_widget_and_ancestors_redraw(app->content);
  if (app && app->body_slot) omni_queue_widget_redraw(app->body_slot);
  if (app && app->window) omni_queue_widget_redraw(app->window);
  if (omni_native_dispatch_depth > 0 || (app && app->modal_dismiss_source != 0)) {
    omni_schedule_pending_ui_flush(app);
    return;
  }
  while (g_main_context_pending(NULL)) {
    g_main_context_iteration(NULL, FALSE);
  }
  GdkDisplay *display = gdk_display_get_default();
  if (display) gdk_display_flush(display);
  omni_macos_accessibility_cancel_pending(app);
  omni_macos_accessibility_sync(app);
}

static void present_settings_window(OmniAdwApp *app);
static void request_settings_refresh_and_present(OmniAdwApp *app);
static void present_about_dialog(OmniAdwApp *app);
static void install_application_actions(OmniAdwApp *app);
static void on_settings_clicked(GtkButton *button, gpointer data);
static gboolean on_settings_close_request(GtkWindow *window, gpointer data);
static gboolean on_main_window_close_request(GtkWindow *window, gpointer data);
static gboolean on_key_pressed(GtkEventControllerKey *controller, guint keyval, guint keycode, GdkModifierType state, gpointer data);
static void on_key_released(GtkEventControllerKey *controller, guint keyval, guint keycode, GdkModifierType state, gpointer data);
static void on_window_click_pressed(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data);
static void on_window_click_released(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data);
static void on_expander_expanded_notify(GObject *object, GParamSpec *pspec, gpointer data);
static void on_required_click_released(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data);
static void on_window_motion(GtkEventControllerMotion *controller, double x, double y, gpointer data);
static gboolean on_window_scroll(GtkEventControllerScroll *controller, double dx, double dy, gpointer data);
static void on_sidebar_toggle_toggled(GtkToggleButton *button, gpointer data);
static void on_split_show_sidebar_notify(GObject *object, GParamSpec *pspec, gpointer data);
static void on_header_tab_clicked(GtkButton *button, gpointer data);
static void on_entry_changed(GtkEditable *editable, gpointer data);
static void on_entry_activate(GtkEntry *entry, gpointer data);
static void omni_app_commit_active_text(OmniAdwApp *app);
static GtkWidget *find_first_entry_widget(GtkWidget *widget);
static GtkWidget *find_focused_entry_widget(GtkWidget *widget);
static const char *omni_symbolic_icon_name_for_label(const char *label);
static const char *omni_accessible_label_for_symbolic_label(const char *label);
static void omni_widget_add_css_classes(GtkWidget *widget, const char *css_classes);
static void omni_widget_replace_css_classes(GtkWidget *widget, const char *storage_key, const char *css_classes);
static void wire_actions(GtkWidget *widget, OmniAdwApp *app);
static GtkWidget *find_widget_for_action(GtkWidget *widget, int32_t action_id);
static int32_t first_action_id_with_accessible_label(GtkWidget *widget, const char *wanted);
static void on_string_list_setup(GtkSignalListItemFactory *factory, GtkListItem *list_item, gpointer data);
static void on_string_list_bind(GtkSignalListItemFactory *factory, GtkListItem *list_item, gpointer data);
static void on_string_list_activate(GtkListView *view, guint position, gpointer data);
static void on_virtual_list_button_clicked(GtkButton *button, gpointer data);
static void on_sidebar_disclosure_clicked(GtkButton *button, gpointer data);
static void on_sidebar_list_setup(GtkSignalListItemFactory *factory, GtkListItem *list_item, gpointer data);
static void on_sidebar_list_bind(GtkSignalListItemFactory *factory, GtkListItem *list_item, gpointer data);
static void on_plain_list_row_activated(GtkListBox *box, GtkListBoxRow *row, gpointer data);
static void sidebar_apply_saved_collapse_state(GtkWidget *list_widget, OmniAdwApp *app);

typedef struct {
  GtkAdjustment *adjustment;
  double value;
} OmniAdjustmentRestoreRequest;

static gboolean restore_adjustment_value(gpointer data) {
  OmniAdjustmentRestoreRequest *request = (OmniAdjustmentRestoreRequest *)data;
  if (!request) return G_SOURCE_REMOVE;
  if (request->adjustment) {
    double upper = gtk_adjustment_get_upper(request->adjustment);
    double page = gtk_adjustment_get_page_size(request->adjustment);
    double max = upper > page ? upper - page : 0;
    double clamped = request->value < 0 ? 0 : (request->value > max ? max : request->value);
    gtk_adjustment_set_value(request->adjustment, clamped);
    g_object_unref(request->adjustment);
  }
  free(request);
  return G_SOURCE_REMOVE;
}

static void schedule_adjustment_restore(GtkAdjustment *adjustment, double value) {
  if (!adjustment) return;
  OmniAdjustmentRestoreRequest *request = calloc(1, sizeof(OmniAdjustmentRestoreRequest));
  if (!request) return;
  request->adjustment = g_object_ref(adjustment);
  request->value = value;
  g_idle_add(restore_adjustment_value, request);
}

static double omni_semantic_scroll_to_pixels(double offset) {
  // OmniUI runtime scroll offsets are measured in terminal-style layout rows.
  // GTK adjustments are pixels, so use a conservative row height that matches
  // the native control density closely enough for ScrollViewReader targets.
  return offset * 28.0;
}

static void apply_initial_scroll_offset(GtkScrolledWindow *scrolled) {
  if (!scrolled) return;
  double *semantic_value = (double *)g_object_get_data(G_OBJECT(scrolled), "omni-scroll-offset");
  if (!semantic_value || *semantic_value <= 0.0) return;
  gboolean vertical = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(scrolled), "omni-scroll-vertical")) != 0;
  GtkAdjustment *adjustment = vertical
    ? gtk_scrolled_window_get_vadjustment(scrolled)
    : gtk_scrolled_window_get_hadjustment(scrolled);
  schedule_adjustment_restore(adjustment, *semantic_value);
}

static void sync_sidebar_toggle(OmniAdwApp *app) {
  if (!app || !app->header_sidebar_button) return;
  gboolean has_split = app->active_split_view && ADW_IS_OVERLAY_SPLIT_VIEW(app->active_split_view);
  gtk_widget_set_visible(app->header_sidebar_button, has_split);
  if (has_split) {
    gboolean show_sidebar = adw_overlay_split_view_get_show_sidebar(ADW_OVERLAY_SPLIT_VIEW(app->active_split_view));
    app->sidebar_show_sidebar = show_sidebar;
    g_object_set_data(G_OBJECT(app->header_sidebar_button), "omni-updating", GINT_TO_POINTER(1));
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(app->header_sidebar_button), show_sidebar);
    g_object_set_data(G_OBJECT(app->header_sidebar_button), "omni-updating", NULL);
    omni_accessible_set_expanded(app->header_sidebar_button, show_sidebar);
    gtk_accessible_update_state(
      GTK_ACCESSIBLE(app->header_sidebar_button),
      GTK_ACCESSIBLE_STATE_PRESSED,
      show_sidebar ? GTK_ACCESSIBLE_TRISTATE_TRUE : GTK_ACCESSIBLE_TRISTATE_FALSE,
      -1
    );
  }
}

static gboolean app_focus_is_native_text_widget(OmniAdwApp *app) {
  if (!app || !app->window) return FALSE;
  GtkWidget *focus = gtk_window_get_focus(GTK_WINDOW(app->window));
  while (focus) {
    if (GTK_IS_ENTRY(focus) || GTK_IS_TEXT_VIEW(focus)) return TRUE;
    focus = gtk_widget_get_parent(focus);
  }
  return FALSE;
}

static void omni_gtk_log_handler(const gchar *log_domain, GLogLevelFlags log_level, const gchar *message, gpointer user_data) {
  (void)user_data;
  if (message && strstr(message, "Theme parser warning") != NULL) return;
  g_log_default_handler(log_domain, log_level, message, NULL);
}

static GLogWriterOutput omni_gtk_log_writer(GLogLevelFlags log_level, const GLogField *fields, gsize n_fields, gpointer user_data) {
  for (gsize i = 0; i < n_fields; i++) {
    if (fields[i].key && strcmp(fields[i].key, "MESSAGE") == 0 && fields[i].value) {
      const char *message = (const char *)fields[i].value;
      if (strstr(message, "Theme parser warning") != NULL) {
        return G_LOG_WRITER_HANDLED;
      }
    }
  }
  return g_log_writer_default(log_level, fields, n_fields, user_data);
}

static void omni_install_log_filter_once(void) {
  static gboolean installed = FALSE;
  if (installed) return;
  installed = TRUE;
  g_log_set_writer_func(omni_gtk_log_writer, NULL, NULL);
  g_log_set_handler("Gtk", G_LOG_LEVEL_MASK | G_LOG_FLAG_FATAL | G_LOG_FLAG_RECURSION, omni_gtk_log_handler, NULL);
}

static GtkCssProvider *omni_semantic_color_provider = NULL;
static GtkCssProvider *omni_dynamic_css_provider = NULL;
static GHashTable *omni_dynamic_css_rule_set = NULL;
static GString *omni_dynamic_css_rules = NULL;
static gboolean omni_dynamic_css_provider_installed = FALSE;

static void omni_install_dynamic_css_provider(void) {
  GdkDisplay *display = gdk_display_get_default();
  if (!display) return;
  if (!omni_dynamic_css_provider) {
    omni_dynamic_css_provider = gtk_css_provider_new();
  }
  if (!omni_dynamic_css_provider_installed) {
    gtk_style_context_add_provider_for_display(
        display,
        GTK_STYLE_PROVIDER(omni_dynamic_css_provider),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION + 20);
    omni_dynamic_css_provider_installed = TRUE;
  }
  if (omni_dynamic_css_rules && omni_dynamic_css_rules->len > 0) {
    gtk_css_provider_load_from_string(omni_dynamic_css_provider, omni_dynamic_css_rules->str);
  }
}

void omni_adw_register_dynamic_css(const char *css_rule) {
  if (!css_rule || !css_rule[0]) return;
  if (!omni_dynamic_css_rule_set) {
    omni_dynamic_css_rule_set = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
  }
  if (!omni_dynamic_css_rules) {
    omni_dynamic_css_rules = g_string_new("");
  }
  if (g_hash_table_contains(omni_dynamic_css_rule_set, css_rule)) {
    omni_install_dynamic_css_provider();
    return;
  }
  g_hash_table_add(omni_dynamic_css_rule_set, g_strdup(css_rule));
  g_string_append(omni_dynamic_css_rules, css_rule);
  g_string_append_c(omni_dynamic_css_rules, '\n');
  omni_install_dynamic_css_provider();
}

static void omni_install_semantic_color_css(gboolean dark) {
  GdkDisplay *display = gdk_display_get_default();
  if (!display) return;
  if (omni_semantic_color_provider) {
    gtk_style_context_remove_provider_for_display(display, GTK_STYLE_PROVIDER(omni_semantic_color_provider));
    g_clear_object(&omni_semantic_color_provider);
  }

  const char *fg = dark ? "#f5f5f7" : "#1d1d1f";
  const char *secondary = dark ? "rgba(245,245,247,0.72)" : "rgba(29,29,31,0.72)";
  const char *tertiary = dark ? "rgba(245,245,247,0.55)" : "rgba(29,29,31,0.55)";
  const char *quaternary = dark ? "rgba(245,245,247,0.35)" : "rgba(29,29,31,0.35)";
  const char *card_bg = dark ? "rgba(245,245,247,0.10)" : "rgba(29,29,31,0.10)";
  const char *primary_bg = dark ? "rgba(245,245,247,0.14)" : "rgba(29,29,31,0.14)";
  const char *secondary_bg = dark ? "rgba(245,245,247,0.10)" : "rgba(29,29,31,0.10)";
  const char *tertiary_bg = dark ? "rgba(245,245,247,0.08)" : "rgba(29,29,31,0.08)";
  const char *quaternary_bg = dark ? "rgba(245,245,247,0.06)" : "rgba(29,29,31,0.06)";
  char *css = g_strdup_printf(
    ".omni-click-container, .omni-complex-button { color: %s; }"
    ".omni-click-container label, .omni-click-container image, .omni-complex-button label, .omni-complex-button image, .omni-text, .omni-text label, .omni-text image, .omni-symbol-image { color: %s; }"
    ".omni-fg-primary, .omni-fg-native, .omni-fg-card, .omni-fg-primary label, .omni-fg-native label, .omni-fg-card label, .omni-fg-primary image, .omni-fg-native image, .omni-fg-card image { color: %s; }"
    ".omni-fg-secondary, .omni-fg-secondary label, .omni-fg-secondary image { color: %s; }"
    ".omni-fg-tertiary, .omni-fg-tertiary label, .omni-fg-tertiary image { color: %s; }"
    ".omni-fg-quaternary, .omni-fg-quaternary label, .omni-fg-quaternary image { color: %s; }"
    ".omni-bg-card { background: %s; background-color: %s; border-radius: 10px; }"
    ".omni-bg-primary { background: %s; background-color: %s; border-radius: 6px; }"
    ".omni-bg-secondary { background: %s; background-color: %s; border-radius: 6px; }"
    ".omni-bg-tertiary { background: %s; background-color: %s; border-radius: 6px; }"
    ".omni-bg-quaternary { background: %s; background-color: %s; border-radius: 6px; }"
    ".omni-bg-gray, .omni-bg-native { background: %s; background-color: %s; }",
    fg, fg, fg, secondary, tertiary, quaternary,
    card_bg, card_bg, primary_bg, primary_bg, secondary_bg, secondary_bg,
    tertiary_bg, tertiary_bg, quaternary_bg, quaternary_bg, secondary_bg, secondary_bg);
  omni_semantic_color_provider = gtk_css_provider_new();
  gtk_css_provider_load_from_string(omni_semantic_color_provider, css);
  gtk_style_context_add_provider_for_display(
      display,
      GTK_STYLE_PROVIDER(omni_semantic_color_provider),
      GTK_STYLE_PROVIDER_PRIORITY_APPLICATION + 10);
  g_free(css);
}

static void omni_install_css_once(void) {
  static gboolean installed = FALSE;
  if (installed) return;
  installed = TRUE;

  const char *css =
    ".omni-stack { padding: 0; }"
    ".omni-overlay { padding: 0; background: transparent; }"
    ".omni-shell { background: @window_bg_color; }"
    ".omni-header { min-height: 44px; padding: 8px 12px; border-bottom: 1px solid @borders; background: @headerbar_bg_color; }"
    ".omni-app-menu-surface { min-width: 228px; padding: 6px; border: 1px solid @borders; border-radius: 8px; background: @popover_bg_color; background-color: @popover_bg_color; color: @popover_fg_color; box-shadow: 0 8px 24px alpha(black,0.28); }"
    ".omni-app-menu-surface button { min-height: 38px; padding: 0 12px; border-radius: 6px; }"
    ".omni-title { font-weight: 700; }"
    ".omni-tab-strip { margin-top: 2px; margin-bottom: 4px; }"
    ".omni-selected-tab { min-height: 24px; padding: 2px 12px; border-radius: 7px 7px 0 0; font-weight: 600; background: @card_bg_color; border: 1px solid @borders; }"
    ".omni-inactive-tab { min-height: 24px; padding: 2px 12px; border-radius: 7px 7px 0 0; background: transparent; }"
    ".omni-body { padding: 0; }"
    ".card { border-radius: 10px; padding: 12px; margin: 0; background: @card_bg_color; }"
    ".adw-dialog { padding: 0; margin: 0; background: transparent; }"
    ".omni-sheet-surface { padding: 18px; margin: 18px; border-radius: 12px; border: 1px solid @borders; background: @popover_bg_color; background-color: @popover_bg_color; color: @window_fg_color; box-shadow: 0 12px 36px alpha(black,0.35); }"
    ".boxed-list { border-radius: 0; padding: 0; margin: 0; background: @view_bg_color; background-color: @view_bg_color; }"
    ".boxed-list row { min-height: 0; padding: 0; margin: 0; border-radius: 0; background: transparent; background-color: transparent; border-bottom: 1px solid @borders; }"
    ".boxed-list row:hover { background: alpha(@view_fg_color,0.035); background-color: alpha(@view_fg_color,0.035); }"
    ".boxed-list row:selected { background: alpha(@accent_bg_color,0.18); background-color: alpha(@accent_bg_color,0.18); }"
    ".boxed-list button { min-height: 0; padding: 0; margin: 0; border-radius: 0; border: 0; background: transparent; background-color: transparent; box-shadow: none; }"
    ".boxed-list button:hover { background: alpha(@view_fg_color,0.04); background-color: alpha(@view_fg_color,0.04); }"
    ".omni-plain-list { background: transparent; }"
    ".omni-plain-list row { min-height: 14px; padding: 0; background: transparent; border-bottom: 0; }"
    ".omni-plain-list row.omni-action-list-row { min-height: 24px; border-bottom: 1px solid @borders; }"
    ".omni-plain-list row:hover { background: transparent; }"
    ".omni-plain-list label { padding: 0 16px; font-family: 'DejaVu Sans Mono', 'Liberation Mono', Consolas, Menlo, Monaco, 'SF Mono', 'SFMono-Regular', monospace; font-size: 12px; font-weight: 400; }"
    ".omni-list-row-button { min-height: 24px; padding: 0; border-radius: 0; border: 0; background: transparent; background-color: transparent; box-shadow: none; }"
    ".omni-list-row-button:hover { background: alpha(@view_fg_color,0.06); }"
    ".omni-list-row-button label { padding: 0 16px; font-family: 'DejaVu Sans Mono', 'Liberation Mono', Consolas, Menlo, Monaco, 'SF Mono', 'SFMono-Regular', monospace; font-size: 12px; font-weight: 400; }"
    ".omni-complex-button { min-height: 0; padding: 0; margin: 0; border-radius: 0; border: 0; background: transparent; background-color: transparent; box-shadow: none; }"
    ".omni-complex-button:hover { background: alpha(@view_fg_color,0.04); background-color: alpha(@view_fg_color,0.04); }"
    ".omni-click-container { min-height: 0; padding: 0; margin: 0; border-radius: 0; border: 0; background: transparent; background-color: transparent; box-shadow: none; color: @view_fg_color; }"
    ".omni-complex-button { color: @view_fg_color; }"
    ".omni-click-container label, .omni-click-container image, .omni-complex-button label, .omni-complex-button image, .omni-text, .omni-text label, .omni-text image, .omni-symbol-image { color: @view_fg_color; }"
    ".omni-click-container:hover { background: alpha(@view_fg_color,0.04); background-color: alpha(@view_fg_color,0.04); }"
    ".omni-inline-link-button { min-height: 18px; min-width: 0; padding: 0 3px; margin: 0 1px; border-radius: 4px; background: transparent; background-color: transparent; box-shadow: none; color: #ff6600; }"
    ".omni-inline-link-button:hover { background: rgba(255,102,0,0.12); background-color: rgba(255,102,0,0.12); }"
    ".omni-inline-link-button label { padding: 0; color: inherit; }"
    ".omni-sidebar-list { background: @window_bg_color; padding: 8px 0; }"
    ".omni-sidebar-list row { min-height: 25px; padding: 0; border-radius: 6px; margin: 0 6px 1px 6px; background: transparent; background-color: transparent; }"
    ".omni-sidebar-list row:hover { background: transparent; }"
    ".omni-sidebar-list row:selected { background: @accent_bg_color; }"
    ".omni-sidebar-row-button { min-height: 25px; padding: 0; margin: 0 6px 1px 6px; border-radius: 6px; border: 0; background: transparent; background-color: transparent; box-shadow: none; }"
    ".omni-sidebar-row-button:hover { background: alpha(@view_fg_color,0.06); }"
    ".omni-sidebar-disclosure-button { min-width: 22px; min-height: 24px; padding: 0; border-radius: 6px; border: 0; background: transparent; background-color: transparent; box-shadow: none; }"
    ".omni-sidebar-disclosure-button:hover { background: alpha(@view_fg_color,0.08); }"
    ".omni-sidebar-row { padding: 1px 6px; }"
    ".omni-sidebar-label { font-size: 13px; font-weight: 600; line-height: 1.22; }"
    ".omni-sidebar-disclosure { min-width: 14px; opacity: 0.75; }"
    ".navigation-view { padding: 0; border-radius: 0; background: @window_bg_color; }"
    ".view { padding: 2px; }"
    ".accent { border-radius: 8px; padding: 6px 8px; background: @accent_bg_color; color: @accent_fg_color; }"
    ".omni-fg-clear, .omni-fg-clear label, .omni-fg-clear image { color: transparent; }"
    ".omni-fg-primary, .omni-fg-native, .omni-fg-card, .omni-fg-primary label, .omni-fg-native label, .omni-fg-card label, .omni-fg-primary image, .omni-fg-native image, .omni-fg-card image { color: @view_fg_color; }"
    ".omni-fg-orange, .omni-fg-orange label, .omni-fg-orange image { color: #ff9500; }"
    ".omni-fg-orange-muted, .omni-fg-orange-muted label, .omni-fg-orange-muted image { color: rgba(255,149,0,0.45); }"
    ".omni-fg-accent, .omni-fg-accent label, .omni-fg-accent image { color: @accent_color; }"
    ".omni-fg-secondary, .omni-fg-secondary label, .omni-fg-secondary image { color: alpha(@view_fg_color, 0.72); }"
    ".omni-fg-tertiary, .omni-fg-tertiary label, .omni-fg-tertiary image { color: alpha(@view_fg_color, 0.55); }"
    ".omni-fg-quaternary, .omni-fg-quaternary label, .omni-fg-quaternary image { color: alpha(@view_fg_color, 0.35); }"
    ".omni-fg-white, .omni-fg-white label, .omni-fg-white image { color: white; }"
    ".omni-fg-white-muted, .omni-fg-white-muted label, .omni-fg-white-muted image { color: rgba(255,255,255,0.55); }"
    ".omni-fg-black, .omni-fg-black label, .omni-fg-black image { color: black; }"
    ".omni-fg-black-muted, .omni-fg-black-muted label, .omni-fg-black-muted image { color: rgba(0,0,0,0.55); }"
    ".omni-fg-gray, .omni-fg-gray label, .omni-fg-gray image { color: #8e8e93; }"
    ".omni-fg-red, .omni-fg-red label, .omni-fg-red image { color: #ff453a; }"
    ".omni-fg-red-muted, .omni-fg-red-muted label, .omni-fg-red-muted image { color: rgba(255,69,58,0.55); }"
    ".omni-fg-yellow, .omni-fg-yellow label, .omni-fg-yellow image { color: #bf7f00; }"
    ".omni-fg-yellow-muted, .omni-fg-yellow-muted label, .omni-fg-yellow-muted image { color: rgba(191,127,0,0.55); }"
    ".omni-fg-green, .omni-fg-green label, .omni-fg-green image { color: #248a3d; }"
    ".omni-fg-green-muted, .omni-fg-green-muted label, .omni-fg-green-muted image { color: rgba(36,138,61,0.55); }"
    ".omni-fg-mint, .omni-fg-mint label, .omni-fg-mint image { color: #00a699; }"
    ".omni-fg-mint-muted, .omni-fg-mint-muted label, .omni-fg-mint-muted image { color: rgba(0,166,153,0.55); }"
    ".omni-fg-teal, .omni-fg-teal label, .omni-fg-teal image { color: #0a7f8f; }"
    ".omni-fg-teal-muted, .omni-fg-teal-muted label, .omni-fg-teal-muted image { color: rgba(10,127,143,0.55); }"
    ".omni-fg-cyan, .omni-fg-cyan label, .omni-fg-cyan image { color: #007a99; }"
    ".omni-fg-cyan-muted, .omni-fg-cyan-muted label, .omni-fg-cyan-muted image { color: rgba(0,122,153,0.55); }"
    ".omni-fg-blue, .omni-fg-blue label, .omni-fg-blue image { color: #0a84ff; }"
    ".omni-fg-blue-muted, .omni-fg-blue-muted label, .omni-fg-blue-muted image { color: rgba(10,132,255,0.55); }"
    ".omni-fg-indigo, .omni-fg-indigo label, .omni-fg-indigo image { color: #5e5ce6; }"
    ".omni-fg-indigo-muted, .omni-fg-indigo-muted label, .omni-fg-indigo-muted image { color: rgba(94,92,230,0.55); }"
    ".omni-fg-purple, .omni-fg-purple label, .omni-fg-purple image { color: #af52de; }"
    ".omni-fg-purple-muted, .omni-fg-purple-muted label, .omni-fg-purple-muted image { color: rgba(175,82,222,0.55); }"
    ".omni-fg-pink, .omni-fg-pink label, .omni-fg-pink image { color: #ff2d55; }"
    ".omni-fg-pink-muted, .omni-fg-pink-muted label, .omni-fg-pink-muted image { color: rgba(255,45,85,0.55); }"
    ".omni-fg-brown, .omni-fg-brown label, .omni-fg-brown image { color: #8e6e53; }"
    ".omni-fg-brown-muted, .omni-fg-brown-muted label, .omni-fg-brown-muted image { color: rgba(142,110,83,0.55); }"
    ".omni-bg-clear { background: transparent; background-color: transparent; }"
    ".omni-bg-orange { background: rgba(255,149,0,0.18); background-color: rgba(255,149,0,0.18); }"
    ".omni-bg-orange-muted { background: rgba(255,149,0,0.12); background-color: rgba(255,149,0,0.12); }"
    ".omni-bg-card { background: alpha(@view_fg_color, 0.10); background-color: alpha(@view_fg_color, 0.10); border-radius: 10px; }"
    ".omni-bg-accent { background: @accent_bg_color; background-color: @accent_bg_color; color: @accent_fg_color; border-radius: 6px; }"
    ".omni-bg-primary { background: alpha(@view_fg_color, 0.14); background-color: alpha(@view_fg_color, 0.14); border-radius: 6px; }"
    ".omni-bg-secondary { background: alpha(@view_fg_color, 0.10); background-color: alpha(@view_fg_color, 0.10); border-radius: 6px; }"
    ".omni-bg-tertiary { background: alpha(@view_fg_color, 0.08); background-color: alpha(@view_fg_color, 0.08); border-radius: 6px; }"
    ".omni-bg-quaternary { background: alpha(@view_fg_color, 0.06); background-color: alpha(@view_fg_color, 0.06); border-radius: 6px; }"
    ".omni-bg-red { background: rgba(255,69,58,0.18); background-color: rgba(255,69,58,0.18); }"
    ".omni-bg-red-muted { background: rgba(255,69,58,0.10); background-color: rgba(255,69,58,0.10); }"
    ".omni-bg-yellow { background: rgba(191,127,0,0.18); background-color: rgba(191,127,0,0.18); }"
    ".omni-bg-yellow-muted { background: rgba(191,127,0,0.10); background-color: rgba(191,127,0,0.10); }"
    ".omni-bg-green { background: rgba(36,138,61,0.18); background-color: rgba(36,138,61,0.18); }"
    ".omni-bg-green-muted { background: rgba(36,138,61,0.10); background-color: rgba(36,138,61,0.10); }"
    ".omni-bg-mint { background: rgba(0,166,153,0.18); background-color: rgba(0,166,153,0.18); }"
    ".omni-bg-mint-muted { background: rgba(0,166,153,0.10); background-color: rgba(0,166,153,0.10); }"
    ".omni-bg-teal { background: rgba(10,127,143,0.18); background-color: rgba(10,127,143,0.18); }"
    ".omni-bg-teal-muted { background: rgba(10,127,143,0.10); background-color: rgba(10,127,143,0.10); }"
    ".omni-bg-cyan { background: rgba(0,122,153,0.18); background-color: rgba(0,122,153,0.18); }"
    ".omni-bg-cyan-muted { background: rgba(0,122,153,0.10); background-color: rgba(0,122,153,0.10); }"
    ".omni-bg-blue { background: rgba(10,132,255,0.18); background-color: rgba(10,132,255,0.18); }"
    ".omni-bg-blue-muted { background: rgba(10,132,255,0.10); background-color: rgba(10,132,255,0.10); }"
    ".omni-bg-indigo { background: rgba(94,92,230,0.18); background-color: rgba(94,92,230,0.18); }"
    ".omni-bg-indigo-muted { background: rgba(94,92,230,0.10); background-color: rgba(94,92,230,0.10); }"
    ".omni-bg-purple { background: rgba(175,82,222,0.18); background-color: rgba(175,82,222,0.18); }"
    ".omni-bg-purple-muted { background: rgba(175,82,222,0.10); background-color: rgba(175,82,222,0.10); }"
    ".omni-bg-pink { background: rgba(255,45,85,0.18); background-color: rgba(255,45,85,0.18); }"
    ".omni-bg-pink-muted { background: rgba(255,45,85,0.10); background-color: rgba(255,45,85,0.10); }"
    ".omni-bg-brown { background: rgba(142,110,83,0.18); background-color: rgba(142,110,83,0.18); }"
    ".omni-bg-brown-muted { background: rgba(142,110,83,0.10); background-color: rgba(142,110,83,0.10); }"
    ".omni-bg-white { background: white; background-color: white; }"
    ".omni-bg-white-muted { background: rgba(255,255,255,0.12); background-color: rgba(255,255,255,0.12); }"
    ".omni-bg-black { background: black; background-color: black; }"
    ".omni-bg-black-muted { background: rgba(0,0,0,0.12); background-color: rgba(0,0,0,0.12); }"
    ".omni-bg-gray, .omni-bg-native { background: alpha(@view_fg_color, 0.10); background-color: alpha(@view_fg_color, 0.10); }"
    ".crt { }"
    ".omni-drawing-island { border-radius: 0; background: transparent; border: none; min-height: 0; }"
    ".omni-fill-orange { background: #ff9500; background-color: #ff9500; }"
    ".omni-fill-orange-subtle { background: rgba(255,149,0,0.15); background-color: rgba(255,149,0,0.15); }"
    ".omni-fill-gray { background: rgba(142,142,147,0.35); background-color: rgba(142,142,147,0.35); }"
    ".omni-fill-accent { background: @accent_bg_color; background-color: @accent_bg_color; }"
    "button { border-radius: 8px; font-weight: 600; }"
    ".omni-icon-button, .omni-icon-button:disabled { min-width: 38px; min-height: 34px; padding: 0; margin: 0; font-size: 16px; -gtk-icon-size: 16px; }"
    ".omni-icon-button image, .omni-icon-button:disabled image, .omni-icon-button label, .omni-icon-button:disabled label { min-width: 16px; min-height: 16px; margin: 0; padding: 0; }"
    ".omni-symbol-image { -gtk-icon-size: 16px; min-width: 16px; min-height: 16px; }"
    ".omni-go-button { min-width: 46px; min-height: 34px; padding: 0 12px; font-weight: 700; }"
    ".omni-segmented-control { margin: 0 4px; }"
    ".omni-segmented-control button { min-height: 30px; padding: 0 12px; border-radius: 0; }"
    ".omni-segmented-control button:first-child { border-radius: 8px 0 0 8px; }"
    ".omni-segmented-control button:last-child { border-radius: 0 8px 8px 0; }"
    ".omni-segmented-control button.omni-selected-segment { background: @accent_bg_color; background-color: @accent_bg_color; color: @accent_fg_color; }"
    ".omni-segmented-control button.omni-selected-segment image, .omni-segmented-control button.omni-selected-segment label { color: @accent_fg_color; }"
    "preferencesgroup { margin-bottom: 12px; }"
    "actionrow entry, actionrow dropdown { min-width: 220px; }"
    ".omni-color-menu-button { min-width: 42px; min-height: 30px; padding: 3px; }"
    ".omni-color-swatch-button { min-width: 30px; min-height: 24px; padding: 3px; }"
    ".omni-static-text-frame { background: @view_bg_color; background-color: @view_bg_color; }"
    ".omni-static-text, .omni-static-text text { font-family: 'DejaVu Sans Mono', 'Liberation Mono', Consolas, Menlo, Monaco, 'SF Mono', 'SFMono-Regular', monospace; font-size: 13px; color: @view_fg_color; background: @view_bg_color; background-color: @view_bg_color; }"
    ".omni-static-text { padding: 12px; }"
    ".omni-monospace-text { font-family: 'DejaVu Sans Mono', 'Liberation Mono', Consolas, Menlo, Monaco, 'SF Mono', 'SFMono-Regular', monospace; font-size: 13px; }"
    ".omni-sidebar-toggle { min-width: 36px; min-height: 34px; padding: 0; }"
    "entry, textview, menubutton { border-radius: 8px; }";

  GtkCssProvider *provider = gtk_css_provider_new();
  gtk_css_provider_load_from_string(provider, css);
  GdkDisplay *display = gdk_display_get_default();
  if (display) {
    gtk_style_context_add_provider_for_display(display, GTK_STYLE_PROVIDER(provider), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  }
  g_object_unref(provider);
  omni_install_dynamic_css_provider();
}

static void omni_apply_color_scheme_from_environment(void) {
  const char *scheme = g_getenv("OMNIUI_ADWAITA_COLOR_SCHEME");
  if (!scheme || !scheme[0]) {
    scheme = g_getenv("OMNIUI_COLOR_SCHEME");
  }
  if (!scheme || !scheme[0]) {
    const char *gtk_theme = g_getenv("GTK_THEME");
    if (gtk_theme && gtk_theme[0]) {
      char *lower_theme = g_ascii_strdown(gtk_theme, -1);
      if (lower_theme && g_strrstr(lower_theme, "dark")) {
        scheme = "dark";
      }
      g_free(lower_theme);
    }
  }
  if (!scheme || !scheme[0]) return;
  omni_adw_set_color_scheme(scheme);
}

void omni_adw_set_color_scheme(const char *scheme) {
  if (!scheme || !scheme[0]) return;
  AdwStyleManager *manager = adw_style_manager_get_default();
  GtkSettings *settings = gtk_settings_get_default();
  gboolean dark = FALSE;

  if (g_ascii_strcasecmp(scheme, "dark") == 0 || g_ascii_strcasecmp(scheme, "force-dark") == 0) {
    if (manager) adw_style_manager_set_color_scheme(manager, ADW_COLOR_SCHEME_FORCE_DARK);
    if (settings && g_object_class_find_property(G_OBJECT_GET_CLASS(settings), "gtk-interface-color-scheme")) {
      g_object_set(settings, "gtk-interface-color-scheme", GTK_INTERFACE_COLOR_SCHEME_DARK, NULL);
    }
    dark = TRUE;
  } else if (g_ascii_strcasecmp(scheme, "light") == 0 || g_ascii_strcasecmp(scheme, "force-light") == 0) {
    if (manager) adw_style_manager_set_color_scheme(manager, ADW_COLOR_SCHEME_FORCE_LIGHT);
    if (settings && g_object_class_find_property(G_OBJECT_GET_CLASS(settings), "gtk-interface-color-scheme")) {
      g_object_set(settings, "gtk-interface-color-scheme", GTK_INTERFACE_COLOR_SCHEME_LIGHT, NULL);
    }
    dark = FALSE;
  } else if (g_ascii_strcasecmp(scheme, "default") == 0 || g_ascii_strcasecmp(scheme, "system") == 0) {
    if (manager) adw_style_manager_set_color_scheme(manager, ADW_COLOR_SCHEME_DEFAULT);
    if (settings && g_object_class_find_property(G_OBJECT_GET_CLASS(settings), "gtk-interface-color-scheme")) {
      g_object_set(settings, "gtk-interface-color-scheme", GTK_INTERFACE_COLOR_SCHEME_DEFAULT, NULL);
    }
    dark = manager ? adw_style_manager_get_dark(manager) : FALSE;
  }
  omni_install_semantic_color_css(dark);
}

static void sync_header_entry(OmniAdwApp *app) {
  if (!app || !app->header_entry) return;
  const char *placeholder = app->header_entry_placeholder ? app->header_entry_placeholder : "";
  gtk_entry_set_placeholder_text(GTK_ENTRY(app->header_entry), app->header_entry_placeholder ? app->header_entry_placeholder : "");
  const char *next = app->header_entry_text ? app->header_entry_text : "";
  gboolean has_navigation_entry = app->header_entry_action_id > 0 || placeholder[0] || next[0];
  if (app->header_entry_row) gtk_widget_set_visible(app->header_entry_row, has_navigation_entry);
  if (app->header_title_label) gtk_widget_set_visible(app->header_title_label, !has_navigation_entry && app->tab_count <= 1);
  const char *current = gtk_editable_get_text(GTK_EDITABLE(app->header_entry));
  if (!current || strcmp(current, next) != 0) {
    g_object_set_data(G_OBJECT(app->header_entry), "omni-updating", GINT_TO_POINTER(1));
    gtk_editable_set_text(GTK_EDITABLE(app->header_entry), next);
    g_object_set_data(G_OBJECT(app->header_entry), "omni-updating", NULL);
  }
  g_object_set_data(G_OBJECT(app->header_entry), "omni-action-id", GINT_TO_POINTER(app->header_entry_action_id));
  g_object_set_data(G_OBJECT(app->header_entry), "omni-app", app);
  omni_accessible_label(app->header_entry, app->header_entry_placeholder && app->header_entry_placeholder[0] ? app->header_entry_placeholder : next);
  omni_accessible_placeholder(app->header_entry, app->header_entry_placeholder);
  omni_accessible_value_text(app->header_entry, next);
}

static void update_header_tab_strip(OmniAdwApp *app) {
  if (!app || !app->header_tab_strip) return;
  GtkWidget *child = gtk_widget_get_first_child(app->header_tab_strip);
  while (child) {
    GtkWidget *next = gtk_widget_get_next_sibling(child);
    gtk_box_remove(GTK_BOX(app->header_tab_strip), child);
    child = next;
  }
  if (app->tab_count <= 1) {
    gtk_widget_set_visible(app->header_tab_strip, FALSE);
    app->header_selected_tab = NULL;
    return;
  }

  gtk_widget_set_visible(app->header_tab_strip, TRUE);
  for (int32_t i = 0; i < app->tab_count; i++) {
    const gboolean active = i == app->active_tab;
    char title[96];
    if (i == 0) {
      snprintf(title, sizeof(title), "%s", app->title ? app->title : "OmniUI Adwaita");
    } else {
      snprintf(title, sizeof(title), "New Tab");
    }
    GtkWidget *tab = gtk_button_new_with_label(title);
    gtk_widget_add_css_class(tab, active ? "omni-selected-tab" : "omni-inactive-tab");
    gtk_widget_add_css_class(tab, "flat");
    gtk_widget_set_focusable(tab, TRUE);
    omni_accessible_label(tab, title);
    omni_accessible_description(tab, active ? "Selected tab" : "Inactive tab");
    omni_accessible_set_selected(tab, active);
    g_object_set_data(G_OBJECT(tab), "omni-tab-index", GINT_TO_POINTER(i));
    g_signal_connect(tab, "clicked", G_CALLBACK(on_header_tab_clicked), app);
    gtk_box_append(GTK_BOX(app->header_tab_strip), tab);
    if (active) app->header_selected_tab = tab;
  }
}

static void ensure_header_title_widget(OmniAdwApp *app) {
  if (!app || !app->header || app->header_title_box) return;
  app->header_title_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
  gtk_widget_set_hexpand(app->header_title_box, TRUE);
  gtk_widget_set_halign(app->header_title_box, GTK_ALIGN_FILL);
  omni_accessible_label(app->header_title_box, "Window toolbar");
  omni_accessible_role_description(app->header_title_box, "toolbar");

  app->header_tab_strip = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  gtk_widget_add_css_class(app->header_tab_strip, "omni-tab-strip");
  gtk_widget_set_halign(app->header_tab_strip, GTK_ALIGN_CENTER);
  gtk_widget_set_visible(app->header_tab_strip, FALSE);
  omni_accessible_label(app->header_tab_strip, "Tabs");
  omni_accessible_role_description(app->header_tab_strip, "tab list");
  gtk_box_append(GTK_BOX(app->header_title_box), app->header_tab_strip);
  update_header_tab_strip(app);

  app->header_title_label = gtk_label_new(app->title ? app->title : "OmniUI Adwaita");
  gtk_widget_add_css_class(app->header_title_label, "omni-title");
  gtk_widget_set_halign(app->header_title_label, GTK_ALIGN_CENTER);
  gtk_widget_set_valign(app->header_title_label, GTK_ALIGN_CENTER);
  omni_accessible_label(app->header_title_label, app->title ? app->title : "OmniUI Adwaita");
  gtk_box_append(GTK_BOX(app->header_title_box), app->header_title_label);

  app->header_entry_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  gtk_widget_set_hexpand(app->header_entry_row, TRUE);
  gtk_widget_set_halign(app->header_entry_row, GTK_ALIGN_FILL);
  omni_accessible_label(app->header_entry_row, "Navigation controls");
  omni_accessible_role_description(app->header_entry_row, "toolbar");

  app->header_sidebar_button = gtk_toggle_button_new();
  gtk_button_set_icon_name(GTK_BUTTON(app->header_sidebar_button), "adw-sidebar-symbolic");
  gtk_widget_add_css_class(app->header_sidebar_button, "flat");
  gtk_widget_add_css_class(app->header_sidebar_button, "omni-sidebar-toggle");
  gtk_widget_set_size_request(app->header_sidebar_button, 36, 34);
  gtk_widget_set_tooltip_text(app->header_sidebar_button, "Toggle Sidebar");
  gtk_widget_set_visible(app->header_sidebar_button, FALSE);
  gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(app->header_sidebar_button), TRUE);
  omni_accessible_label(app->header_sidebar_button, "Toggle Sidebar");
  omni_accessible_description(app->header_sidebar_button, "Shows or hides the sidebar");
  omni_accessible_set_expanded(app->header_sidebar_button, TRUE);
  g_signal_connect(app->header_sidebar_button, "toggled", G_CALLBACK(on_sidebar_toggle_toggled), app);
  adw_header_bar_pack_start(ADW_HEADER_BAR(app->header), app->header_sidebar_button);

  app->header_start_actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
  gtk_widget_set_valign(app->header_start_actions, GTK_ALIGN_CENTER);
  gtk_widget_set_visible(app->header_start_actions, FALSE);
  omni_accessible_label(app->header_start_actions, "Navigation actions");
  omni_accessible_role_description(app->header_start_actions, "toolbar");
  adw_header_bar_pack_start(ADW_HEADER_BAR(app->header), app->header_start_actions);

  app->header_end_actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
  gtk_widget_set_valign(app->header_end_actions, GTK_ALIGN_CENTER);
  gtk_widget_set_visible(app->header_end_actions, FALSE);
  omni_accessible_label(app->header_end_actions, "Window actions");
  omni_accessible_role_description(app->header_end_actions, "toolbar");
  adw_header_bar_pack_end(ADW_HEADER_BAR(app->header), app->header_end_actions);

  app->header_entry = gtk_entry_new();
  gtk_widget_add_css_class(app->header_entry, "omni-header-entry");
  gtk_widget_set_size_request(app->header_entry, 520, -1);
  gtk_widget_set_hexpand(app->header_entry, TRUE);
  gtk_widget_set_halign(app->header_entry, GTK_ALIGN_FILL);
  gtk_widget_set_vexpand(app->header_entry, FALSE);
  gtk_widget_set_valign(app->header_entry, GTK_ALIGN_CENTER);
  omni_accessible_label(app->header_entry, "Address");
  omni_accessible_description(app->header_entry, "Gopher URL");
  omni_accessible_placeholder(app->header_entry, "host:port/path");
  g_signal_connect(app->header_entry, "changed", G_CALLBACK(on_entry_changed), NULL);
  g_signal_connect(app->header_entry, "activate", G_CALLBACK(on_entry_activate), NULL);
  gtk_box_append(GTK_BOX(app->header_entry_row), app->header_entry);

  app->header_new_tab_button = NULL;

  gtk_box_append(GTK_BOX(app->header_title_box), app->header_entry_row);
  adw_header_bar_set_title_widget(ADW_HEADER_BAR(app->header), app->header_title_box);
  wire_actions(app->header_title_box, app);
  sync_header_entry(app);
}

static void on_app_preferences_action(GSimpleAction *action, GVariant *parameter, gpointer data) {
  (void)action;
  (void)parameter;
  request_settings_refresh_and_present((OmniAdwApp *)data);
}

static void on_app_about_action(GSimpleAction *action, GVariant *parameter, gpointer data) {
  (void)action;
  (void)parameter;
  present_about_dialog((OmniAdwApp *)data);
}

static void on_app_quit_action(GSimpleAction *action, GVariant *parameter, gpointer data) {
  (void)action;
  (void)parameter;
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app || !app->application) return;
  if (app->lifecycle_callback) {
    int32_t should_quit = app->lifecycle_callback(OMNI_ADW_LIFECYCLE_APP_QUIT_REQUEST, app->context);
    if (!should_quit) return;
  }
  g_application_quit(G_APPLICATION(app->application));
}

static gboolean omni_widget_is_or_descendant(GtkWidget *widget, GtkWidget *ancestor) {
  GtkWidget *current = widget;
  while (current) {
    if (current == ancestor) return TRUE;
    current = gtk_widget_get_parent(current);
  }
  return FALSE;
}

static gboolean omni_point_in_widget_bounds(GtkWidget *widget, GtkWidget *root, double x, double y) {
  if (!widget || !root || !gtk_widget_get_visible(widget)) return FALSE;
  graphene_rect_t bounds;
  if (!gtk_widget_compute_bounds(widget, root, &bounds)) return FALSE;
  return x >= bounds.origin.x &&
      y >= bounds.origin.y &&
      x <= bounds.origin.x + bounds.size.width &&
      y <= bounds.origin.y + bounds.size.height;
}

static void omni_app_menu_hide(OmniAdwApp *app) {
  if (!app || !app->app_menu_surface) return;
  gtk_widget_set_visible(app->app_menu_surface, FALSE);
  if (app->app_menu_button) {
    gtk_accessible_update_state(GTK_ACCESSIBLE(app->app_menu_button), GTK_ACCESSIBLE_STATE_EXPANDED, FALSE, -1);
  }
}

static void omni_app_menu_update_position(OmniAdwApp *app) {
  if (!app || !app->app_menu_button || !app->app_menu_surface || !app->root_overlay) return;
  int x = 12;
  int y = 58;
  graphene_rect_t bounds;
  if (gtk_widget_compute_bounds(app->app_menu_button, app->root_overlay, &bounds)) {
    x = (int)bounds.origin.x;
    y = (int)(bounds.origin.y + bounds.size.height + 6.0f);
  }
  int overlay_width = gtk_widget_get_width(app->root_overlay);
  const int menu_width = 240;
  if (overlay_width > 0 && x + menu_width > overlay_width - 8) {
    x = overlay_width - menu_width - 8;
  }
  if (x < 8) x = 8;
  if (y < 8) y = 8;
  gtk_widget_set_margin_start(app->app_menu_surface, x);
  gtk_widget_set_margin_top(app->app_menu_surface, y);
}

static void omni_app_menu_show(OmniAdwApp *app) {
  if (!app || !app->app_menu_surface) return;
  omni_app_menu_update_position(app);
  gtk_widget_set_visible(app->app_menu_surface, TRUE);
  gtk_widget_set_child_visible(app->app_menu_surface, TRUE);
  if (app->app_menu_button) {
    gtk_accessible_update_state(GTK_ACCESSIBLE(app->app_menu_button), GTK_ACCESSIBLE_STATE_EXPANDED, TRUE, -1);
  }
}

static void omni_app_menu_toggle(OmniAdwApp *app) {
  if (!app || !app->app_menu_surface) return;
  if (gtk_widget_get_visible(app->app_menu_surface)) {
    omni_app_menu_hide(app);
  } else {
    omni_app_menu_show(app);
  }
}

static void on_app_menu_button_clicked(GtkButton *button, gpointer data) {
  (void)button;
  omni_app_menu_toggle((OmniAdwApp *)data);
}

static gboolean omni_app_menu_request_settings_deferred(gpointer data) {
  request_settings_refresh_and_present((OmniAdwApp *)data);
  return G_SOURCE_REMOVE;
}

static void on_app_menu_preferences_clicked(GtkButton *button, gpointer data) {
  (void)button;
  OmniAdwApp *app = (OmniAdwApp *)data;
  omni_app_menu_hide(app);
  g_timeout_add(OMNI_MODAL_DISMISS_DELAY_MS, omni_app_menu_request_settings_deferred, app);
}

static void on_app_menu_about_clicked(GtkButton *button, gpointer data) {
  (void)button;
  OmniAdwApp *app = (OmniAdwApp *)data;
  omni_app_menu_hide(app);
  present_about_dialog(app);
}

static void on_app_menu_quit_clicked(GtkButton *button, gpointer data) {
  (void)button;
  OmniAdwApp *app = (OmniAdwApp *)data;
  omni_app_menu_hide(app);
  if (!app || !app->application) return;
  if (app->lifecycle_callback) {
    int32_t should_quit = app->lifecycle_callback(OMNI_ADW_LIFECYCLE_APP_QUIT_REQUEST, app->context);
    if (!should_quit) return;
  }
  g_application_quit(G_APPLICATION(app->application));
}

static GMenu *create_app_menu_model(OmniAdwApp *app) {
  GMenu *app_menu = g_menu_new();
  char about_label[160];
  snprintf(about_label, sizeof(about_label), "About %s", app && app->title ? app->title : "OmniUI Adwaita");
  g_menu_append(app_menu, about_label, "app.about");
  g_menu_append(app_menu, "Settings...", "app.preferences");
  g_menu_append(app_menu, "Quit", "app.quit");
  return app_menu;
}

static void install_application_actions(OmniAdwApp *app) {
  if (!app || !app->application) return;
  if (app->application_actions_installed) return;
  app->application_actions_installed = TRUE;
  const GActionEntry entries[] = {
    { "preferences", on_app_preferences_action, NULL, NULL, NULL },
    { "about", on_app_about_action, NULL, NULL, NULL },
    { "quit", on_app_quit_action, NULL, NULL, NULL },
  };
  g_action_map_add_action_entries(G_ACTION_MAP(app->application), entries, G_N_ELEMENTS(entries), app);

  const char *settings_accels[] = { "<Meta>comma", NULL };
  const char *quit_accels[] = { "<Meta>q", NULL };
  gtk_application_set_accels_for_action(GTK_APPLICATION(app->application), "app.preferences", settings_accels);
  gtk_application_set_accels_for_action(GTK_APPLICATION(app->application), "app.quit", quit_accels);

  GMenu *menubar = g_menu_new();
  GMenu *app_menu = create_app_menu_model(app);
  g_menu_append_submenu(menubar, app->title ? app->title : "OmniUI Adwaita", G_MENU_MODEL(app_menu));
  gtk_application_set_menubar(GTK_APPLICATION(app->application), G_MENU_MODEL(menubar));
  g_object_unref(app_menu);
  g_object_unref(menubar);
}

static GtkWidget *create_app_menu_surface(OmniAdwApp *app) {
  GtkWidget *menu_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
  gtk_widget_add_css_class(menu_box, "omni-app-menu-surface");
  gtk_widget_set_halign(menu_box, GTK_ALIGN_START);
  gtk_widget_set_valign(menu_box, GTK_ALIGN_START);
  gtk_widget_set_size_request(menu_box, 240, -1);
  gtk_widget_set_visible(menu_box, FALSE);
  omni_accessible_label(menu_box, "Application Menu");

  char about_label[160];
  snprintf(about_label, sizeof(about_label), "About %s", app && app->title ? app->title : "OmniUI Adwaita");

  GtkWidget *about_button = gtk_button_new_with_label(about_label);
  gtk_widget_add_css_class(about_button, "flat");
  gtk_widget_set_halign(about_button, GTK_ALIGN_FILL);
  gtk_widget_set_hexpand(about_button, TRUE);
  omni_accessible_description(about_button, "Shows app information");
  g_signal_connect(about_button, "clicked", G_CALLBACK(on_app_menu_about_clicked), app);
  gtk_box_append(GTK_BOX(menu_box), about_button);

  GtkWidget *settings_button = gtk_button_new_with_label("Settings...");
  gtk_widget_add_css_class(settings_button, "flat");
  gtk_widget_set_halign(settings_button, GTK_ALIGN_FILL);
  gtk_widget_set_hexpand(settings_button, TRUE);
  omni_accessible_description(settings_button, "Opens app settings");
  g_signal_connect(settings_button, "clicked", G_CALLBACK(on_app_menu_preferences_clicked), app);
  gtk_box_append(GTK_BOX(menu_box), settings_button);

  GtkWidget *quit_button = gtk_button_new_with_label("Quit");
  gtk_widget_add_css_class(quit_button, "flat");
  gtk_widget_set_halign(quit_button, GTK_ALIGN_FILL);
  gtk_widget_set_hexpand(quit_button, TRUE);
  omni_accessible_description(quit_button, "Quits the app");
  g_signal_connect(quit_button, "clicked", G_CALLBACK(on_app_menu_quit_clicked), app);
  gtk_box_append(GTK_BOX(menu_box), quit_button);

  return menu_box;
}

static void on_app_activate(GApplication *application, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  install_application_actions(app);
  if (!app->window) {
    omni_apply_color_scheme_from_environment();
    app->window = adw_application_window_new(GTK_APPLICATION(application));
    gtk_window_set_title(GTK_WINDOW(app->window), app->title);
    gtk_window_set_default_size(GTK_WINDOW(app->window), app->default_width, app->default_height);
    g_signal_connect(app->window, "close-request", G_CALLBACK(on_main_window_close_request), app);
    omni_accessible_label(app->window, app->title ? app->title : "OmniUI Adwaita");
    app->root_overlay = gtk_overlay_new();
    gtk_widget_add_css_class(app->root_overlay, "omni-root-overlay");
    omni_widget_expand(app->root_overlay, TRUE);
    app->shell = adw_toolbar_view_new();
    gtk_widget_add_css_class(app->shell, "omni-shell");
    omni_widget_expand(app->shell, TRUE);
    omni_accessible_label(app->shell, app->title ? app->title : "OmniUI Adwaita");

    app->header = adw_header_bar_new();
    gtk_widget_add_css_class(app->header, "omni-header");
    gtk_widget_set_size_request(app->header, -1, 64);
    omni_accessible_label(app->header, "Toolbar");
    omni_accessible_role_description(app->header, "toolbar");
    ensure_header_title_widget(app);

    app->command_button = gtk_menu_button_new();
    gtk_widget_set_visible(app->command_button, FALSE);
    gtk_menu_button_set_icon_name(GTK_MENU_BUTTON(app->command_button), "open-menu-symbolic");
    gtk_widget_add_css_class(app->command_button, "flat");
    gtk_widget_add_css_class(app->command_button, "omni-icon-button");
    gtk_widget_set_size_request(app->command_button, 38, 34);
    gtk_widget_set_tooltip_text(app->command_button, "Commands");
    omni_accessible_label(app->command_button, "Commands");
    omni_accessible_description(app->command_button, "Shows app commands");
    gtk_accessible_update_property(GTK_ACCESSIBLE(app->command_button), GTK_ACCESSIBLE_PROPERTY_HAS_POPUP, TRUE, -1);
    app->command_popover = gtk_popover_new();
    omni_accessible_label(app->command_popover, "Commands");
    gtk_menu_button_set_popover(GTK_MENU_BUTTON(app->command_button), app->command_popover);
    if (app->command_content) {
      gtk_popover_set_child(GTK_POPOVER(app->command_popover), app->command_content);
    }
    adw_header_bar_pack_end(ADW_HEADER_BAR(app->header), app->command_button);

    app->app_menu_button = gtk_menu_button_new();
    g_object_ref(app->app_menu_button);
    gtk_widget_set_visible(app->app_menu_button, TRUE);
    gtk_menu_button_set_icon_name(GTK_MENU_BUTTON(app->app_menu_button), "open-menu-symbolic");
    gtk_widget_add_css_class(app->app_menu_button, "flat");
    gtk_widget_add_css_class(app->app_menu_button, "omni-icon-button");
    gtk_widget_set_size_request(app->app_menu_button, 38, 34);
    gtk_widget_set_tooltip_text(app->app_menu_button, "Application Menu");
    omni_accessible_label(app->app_menu_button, "Application Menu");
    omni_accessible_description(app->app_menu_button, "Shows app settings and app information");
    gtk_accessible_update_property(GTK_ACCESSIBLE(app->app_menu_button), GTK_ACCESSIBLE_PROPERTY_HAS_POPUP, TRUE, -1);
    GMenu *app_menu = create_app_menu_model(app);
    gtk_menu_button_set_menu_model(GTK_MENU_BUTTON(app->app_menu_button), G_MENU_MODEL(app_menu));
    g_object_unref(app_menu);
    adw_header_bar_pack_start(ADW_HEADER_BAR(app->header), app->app_menu_button);

    app->body_slot = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_widget_add_css_class(app->body_slot, "omni-body");
    omni_widget_expand(app->body_slot, TRUE);
    omni_accessible_label(app->body_slot, "Content");
    omni_accessible_role_description(app->body_slot, "main content");
    adw_toolbar_view_add_top_bar(ADW_TOOLBAR_VIEW(app->shell), app->header);
    adw_toolbar_view_set_content(ADW_TOOLBAR_VIEW(app->shell), app->body_slot);

    if (!app->content) {
      app->content = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
      omni_accessible_label(app->content, "Content");
      omni_accessible_role_description(app->content, "main content");
    }
    if (app->body_slot && app->content) {
      gtk_box_append(GTK_BOX(app->body_slot), app->content);
    }
    adw_application_window_set_content(ADW_APPLICATION_WINDOW(app->window), app->shell);
    sync_sidebar_toggle(app);
    if (!app->key_controller) {
      app->key_controller = gtk_event_controller_key_new();
      gtk_event_controller_set_propagation_phase(app->key_controller, GTK_PHASE_CAPTURE);
      g_signal_connect(app->key_controller, "key-pressed", G_CALLBACK(on_key_pressed), app);
      g_signal_connect(app->key_controller, "key-released", G_CALLBACK(on_key_released), app);
      gtk_widget_add_controller(app->window, app->key_controller);
    }
    GtkGesture *click_controller = gtk_gesture_click_new();
    gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(click_controller), GTK_PHASE_CAPTURE);
    g_signal_connect(click_controller, "pressed", G_CALLBACK(on_window_click_pressed), app);
    g_signal_connect(click_controller, "released", G_CALLBACK(on_window_click_released), app);
    gtk_widget_add_controller(app->window, GTK_EVENT_CONTROLLER(click_controller));
    GtkEventController *motion_controller = gtk_event_controller_motion_new();
    gtk_event_controller_set_propagation_phase(motion_controller, GTK_PHASE_CAPTURE);
    g_signal_connect(motion_controller, "motion", G_CALLBACK(on_window_motion), app);
    gtk_widget_add_controller(app->window, motion_controller);
    GtkEventController *scroll_controller = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES);
    gtk_event_controller_set_propagation_phase(scroll_controller, GTK_PHASE_BUBBLE);
    g_signal_connect(scroll_controller, "scroll", G_CALLBACK(on_window_scroll), app);
    gtk_widget_add_controller(app->window, scroll_controller);
  }
  gtk_window_present(GTK_WINDOW(app->window));
  omni_macos_accessibility_schedule(app);
  if (app->present_settings_on_activate) {
    app->present_settings_on_activate = FALSE;
    request_settings_refresh_and_present(app);
  }
}

static void present_settings_window(OmniAdwApp *app) {
  if (!app || !app->settings_content) return;
  if (!app->settings_window) {
    app->settings_window = gtk_window_new();
    gtk_window_set_application(GTK_WINDOW(app->settings_window), GTK_APPLICATION(app->application));
    gtk_window_set_title(GTK_WINDOW(app->settings_window), "Settings");
    gtk_window_set_default_size(GTK_WINDOW(app->settings_window), 640, 420);
    gtk_window_set_decorated(GTK_WINDOW(app->settings_window), TRUE);
    gtk_window_set_modal(GTK_WINDOW(app->settings_window), FALSE);
    omni_accessible_label(app->settings_window, "Settings");
    if (app->window) {
      gtk_window_set_transient_for(GTK_WINDOW(app->settings_window), GTK_WINDOW(app->window));
    }
    g_signal_connect(app->settings_window, "close-request", G_CALLBACK(on_settings_close_request), app);
    gtk_window_set_child(GTK_WINDOW(app->settings_window), app->settings_content);
  }
  gtk_window_present(GTK_WINDOW(app->settings_window));
}

static gboolean present_settings_window_deferred(gpointer data) {
  present_settings_window((OmniAdwApp *)data);
  return G_SOURCE_REMOVE;
}

static void request_settings_refresh_and_present(OmniAdwApp *app) {
  if (!app) return;
  if (app->callback) {
    app->callback(OMNI_ADW_INTERNAL_PRESENT_SETTINGS_ACTION_ID, app->context);
    omni_flush_pending_ui(app);
    g_timeout_add(30, present_settings_window_deferred, app);
    return;
  }
  present_settings_window(app);
}

static void present_about_dialog(OmniAdwApp *app) {
  if (!app || !app->window) return;
  AdwDialog *dialog = adw_about_dialog_new();
  AdwAboutDialog *about = ADW_ABOUT_DIALOG(dialog);
  const char *name = app->title && app->title[0] ? app->title : "OmniUI Adwaita";
  adw_about_dialog_set_application_name(about, name);
  adw_about_dialog_set_developer_name(about, "OmniKit");
  adw_about_dialog_set_comments(about, "Native Adwaita renderer");
  adw_about_dialog_set_version(about, "Adwaita");
  omni_accessible_label(GTK_WIDGET(dialog), name);
  omni_accessible_description(GTK_WIDGET(dialog), "About this app");
  adw_dialog_present(dialog, app->window);
  omni_macos_accessibility_schedule(app);
}

static void on_settings_clicked(GtkButton *button, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(button), "omni-settings-button");
  request_settings_refresh_and_present(app);
}

static gboolean on_settings_close_request(GtkWindow *window, gpointer data) {
  gtk_widget_set_visible(GTK_WIDGET(window), FALSE);
  return TRUE;
}

static gboolean on_main_window_close_request(GtkWindow *window, gpointer data) {
  (void)window;
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app || !app->lifecycle_callback) return FALSE;
  int32_t should_quit = app->lifecycle_callback(OMNI_ADW_LIFECYCLE_MAIN_WINDOW_CLOSE_REQUEST, app->context);
  if (should_quit) return FALSE;
  if (app->window) gtk_widget_set_visible(app->window, FALSE);
  return TRUE;
}

static void on_clicked(GtkButton *button, gpointer data) {
  (void)data;
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(button), "omni-app");
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "omni-action-id"));
  int required_click_count = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "omni-required-click-count"));
  if (required_click_count > 1) return;
  if (app && app->callback) {
    omni_app_commit_active_text(app);
    omni_dispatch_action_callback(app, action_id);
    omni_flush_pending_ui(app);
  }
}

static void on_expander_expanded_notify(GObject *object, GParamSpec *pspec, gpointer data) {
  (void)pspec;
  (void)data;
  if (!ADW_IS_EXPANDER_ROW(object)) return;
  GtkWidget *widget = GTK_WIDGET(object);
  omni_accessible_set_expanded(widget, adw_expander_row_get_expanded(ADW_EXPANDER_ROW(object)));
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(object, "omni-app");
  int action_id = GPOINTER_TO_INT(g_object_get_data(object, "omni-action-id"));
  if (app && app->callback && action_id > 0) {
    app->callback(action_id, app->context);
    omni_flush_pending_ui(app);
  }
}

static void omni_grab_focus_if_ready(GtkWidget *widget) {
  if (!widget || !gtk_widget_get_focusable(widget)) return;
  if (GTK_IS_LIST_BOX_ROW(widget) && !GTK_IS_LIST_BOX(gtk_widget_get_parent(widget))) return;
  gtk_widget_grab_focus(widget);
}

static void on_required_click_released(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data) {
  (void)x;
  (void)y;
  GtkWidget *widget = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(gesture));
  if (!widget) return;
  int required_click_count = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-required-click-count"));
  if (required_click_count <= 1 || n_press != required_click_count) return;
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id"));
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(widget), "omni-app");
  if (app && app->callback && action_id > 0) {
    omni_dispatch_action_callback(app, action_id);
    omni_flush_pending_ui(app);
    gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_CLAIMED);
  }
}

static void on_toggled(GtkCheckButton *button, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(button), "omni-app");
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "omni-action-id"));
  gtk_accessible_update_state(
    GTK_ACCESSIBLE(button),
    GTK_ACCESSIBLE_STATE_CHECKED,
    gtk_check_button_get_active(button) ? GTK_ACCESSIBLE_TRISTATE_TRUE : GTK_ACCESSIBLE_TRISTATE_FALSE,
    -1
  );
  if (app && app->callback) {
    omni_dispatch_action_callback(app, action_id);
    omni_flush_pending_ui(app);
  }
}

static void on_switch_row_active_notify(GObject *object, GParamSpec *pspec, gpointer data) {
  (void)pspec;
  (void)data;
  if (!ADW_IS_SWITCH_ROW(object)) return;
  if (g_object_get_data(object, "omni-updating") != NULL) return;
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(object, "omni-app");
  int action_id = GPOINTER_TO_INT(g_object_get_data(object, "omni-action-id"));
  gtk_accessible_update_state(
    GTK_ACCESSIBLE(object),
    GTK_ACCESSIBLE_STATE_CHECKED,
    adw_switch_row_get_active(ADW_SWITCH_ROW(object)) ? GTK_ACCESSIBLE_TRISTATE_TRUE : GTK_ACCESSIBLE_TRISTATE_FALSE,
    -1
  );
  if (app && app->callback && action_id > 0) {
    app->callback(action_id, app->context);
    omni_flush_pending_ui(app);
  }
}

static gboolean sidebar_row_has_children(OmniStringListData *list, int32_t index) {
  if (!list || !list->depths || index < 0 || index >= list->count - 1) return FALSE;
  return list->depths[index + 1] > list->depths[index];
}

static char *sidebar_collapse_key(OmniStringListData *list, int32_t index) {
  if (!list || !list->labels || index < 0 || index >= list->count) return NULL;
  int32_t depth = list->depths ? list->depths[index] : 0;
  return g_strdup_printf("%d:%s", depth, list->labels[index] ? list->labels[index] : "");
}

static gboolean sidebar_index_is_visible(OmniStringListData *list, int32_t index) {
  if (!list || !list->depths || !list->collapsed || index < 0 || index >= list->count) return TRUE;
  int32_t depth = list->depths[index];
  for (int32_t i = index - 1; i >= 0; i--) {
    if (list->depths[i] < depth) {
      if (list->collapsed[i]) return FALSE;
      depth = list->depths[i];
      if (depth == 0) return TRUE;
    }
  }
  return TRUE;
}

static void sidebar_rebuild_visible_indices(OmniStringListData *list) {
  if (!list || !list->labels) return;
  int32_t previous_visible_count = list->visible_indices ? list->visible_count : 0;
  free(list->visible_indices);
  list->visible_indices = calloc((size_t)list->count, sizeof(int32_t));
  list->visible_count = 0;
  for (int32_t i = 0; i < list->count; i++) {
    if (sidebar_index_is_visible(list, i)) {
      list->visible_indices[list->visible_count++] = i;
    }
  }
  if (list->model) {
    g_list_model_items_changed(
      list->model,
      0,
      previous_visible_count > 0 ? (guint)previous_visible_count : 0,
      list->visible_count > 0 ? (guint)list->visible_count : 0
    );
  }
}

static int32_t sidebar_original_index_for_visible_position(OmniStringListData *list, guint position) {
  if (!list) return (int32_t)position;
  if (list->visible_indices && position < (guint)list->visible_count) {
    return list->visible_indices[position];
  }
  return (int32_t)position;
}

static void sidebar_update_row_disclosure(GtkWidget *row, OmniStringListData *list, int32_t index) {
  if (!row || !list || index < 0 || index >= list->count) return;
  GtkWidget *box = GTK_IS_LIST_BOX_ROW(row) ? gtk_list_box_row_get_child(GTK_LIST_BOX_ROW(row)) : row;
  if (!GTK_IS_BOX(box)) return;
  GtkWidget *disclosure_button = gtk_widget_get_first_child(box);
  if (!GTK_IS_BUTTON(disclosure_button)) return;
  GtkWidget *disclosure = gtk_button_get_child(GTK_BUTTON(disclosure_button));
  gboolean has_children = sidebar_row_has_children(list, index);
  gtk_widget_set_visible(disclosure_button, has_children);
  if (GTK_IS_LABEL(disclosure)) {
    gtk_label_set_text(GTK_LABEL(disclosure), has_children ? (list->collapsed && list->collapsed[index] ? "▸" : "▾") : "");
  }
  omni_accessible_label(disclosure_button, has_children ? (list->collapsed[index] ? "Expand" : "Collapse") : "");
  omni_accessible_set_expanded(disclosure_button, has_children && !list->collapsed[index]);
}

static void sidebar_apply_visibility_to_rows(GtkWidget *list_widget, OmniStringListData *list) {
  if (!list_widget || !list || !list->rows) return;
  for (int32_t i = 0; i < list->count; i++) {
    GtkWidget *row = list->rows[i];
    if (!row) continue;
    gtk_widget_set_visible(row, sidebar_index_is_visible(list, i));
    sidebar_update_row_disclosure(row, list, i);
  }
}

static void sidebar_apply_saved_collapse_state(GtkWidget *list_widget, OmniAdwApp *app) {
  if (!list_widget || !app || !app->sidebar_collapsed_items) return;
  OmniStringListData *list = (OmniStringListData *)g_object_get_data(G_OBJECT(list_widget), "omni-string-list-data");
  if (!list || !list->collapsed) return;
  gboolean changed = FALSE;
  for (int32_t i = 0; i < list->count; i++) {
    if (!sidebar_row_has_children(list, i)) continue;
    char *key = sidebar_collapse_key(list, i);
    gboolean saved = key ? g_hash_table_contains(app->sidebar_collapsed_items, key) : FALSE;
    if (key) g_free(key);
    if (list->collapsed[i] != saved) {
      list->collapsed[i] = saved;
      changed = TRUE;
    }
  }
  if (!changed) return;
  if (GTK_IS_LIST_VIEW(list_widget)) {
    sidebar_rebuild_visible_indices(list);
  } else if (GTK_IS_LIST_BOX(list_widget)) {
    sidebar_apply_visibility_to_rows(list_widget, list);
  }
}

static void on_string_list_setup(GtkSignalListItemFactory *factory, GtkListItem *list_item, gpointer data) {
  GtkWidget *button = gtk_button_new();
  gtk_widget_add_css_class(button, "omni-list-row-button");
  gtk_widget_set_hexpand(button, TRUE);
  gtk_widget_set_halign(button, GTK_ALIGN_FILL);
  gtk_widget_set_focus_on_click(button, TRUE);
  g_signal_connect(button, "clicked", G_CALLBACK(on_virtual_list_button_clicked), NULL);

  GtkWidget *label = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
  gtk_label_set_wrap(GTK_LABEL(label), FALSE);
  gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_END);
  gtk_widget_set_hexpand(label, TRUE);
  gtk_widget_set_halign(label, GTK_ALIGN_FILL);
  gtk_button_set_child(GTK_BUTTON(button), label);
  gtk_list_item_set_child(list_item, button);
}

static void on_string_list_bind(GtkSignalListItemFactory *factory, GtkListItem *list_item, gpointer data) {
  GtkWidget *button = gtk_list_item_get_child(list_item);
  gpointer item = gtk_list_item_get_item(list_item);
  if (!GTK_IS_BUTTON(button)) return;
  GtkWidget *label = gtk_button_get_child(GTK_BUTTON(button));
  if (!GTK_IS_LABEL(label)) return;
  guint position = gtk_list_item_get_position(list_item);
  GtkWidget *list_view = gtk_widget_get_ancestor(button, GTK_TYPE_LIST_VIEW);
  OmniStringListData *list = list_view ? (OmniStringListData *)g_object_get_data(G_OBJECT(list_view), "omni-string-list-data") : NULL;
  int32_t original = OMNI_IS_LIST_ROW_OBJECT(item)
    ? OMNI_LIST_ROW_OBJECT(item)->original_index
    : sidebar_original_index_for_visible_position(list, position);
  const char *text = "";
  if (list && list->labels && original >= 0 && original < list->count) {
    text = list->labels[original] ? list->labels[original] : "";
  } else if (GTK_IS_STRING_OBJECT(item)) {
    text = gtk_string_object_get_string(GTK_STRING_OBJECT(item));
  }
  int32_t action_id = list && list->action_ids && original >= 0 && original < list->count ? list->action_ids[original] : 0;
  double font_size = list && list->font_sizes && original >= 0 && original < list->count ? list->font_sizes[original] : 0.0;
  const char *font_weight = list && list->font_weights && original >= 0 && original < list->count ? list->font_weights[original] : "";
  int32_t font_italic = list && list->font_italics && original >= 0 && original < list->count ? list->font_italics[original] : 0;
  const char *css_classes = list && list->css_classes && original >= 0 && original < list->count ? list->css_classes[original] : "";
  int32_t count = list && list->visible_indices ? list->visible_count : (list ? list->count : 0);
  gboolean native_accessible = count <= OMNI_NATIVE_ACCESSIBILITY_ROW_UPDATE_LIMIT;

  gtk_label_set_text(GTK_LABEL(label), text ? text : "");
  omni_label_apply_font(GTK_LABEL(label), font_size, font_weight, font_italic != 0);
  omni_widget_replace_css_classes(label, "omni-row-css-classes", css_classes);
  omni_widget_replace_css_classes(button, "omni-row-css-classes", css_classes);
  if (native_accessible) {
    gtk_list_item_set_accessible_label(list_item, text ? text : "");
    gtk_list_item_set_accessible_description(list_item, action_id > 0 ? "Activates this list row" : "Static list row");
  }
  gtk_list_item_set_activatable(list_item, action_id > 0);
  gtk_list_item_set_selectable(list_item, action_id > 0);
  gtk_list_item_set_focusable(list_item, action_id > 0);
  g_object_set_data(G_OBJECT(button), "omni-action-id", GINT_TO_POINTER(action_id));
  gtk_widget_set_focusable(button, action_id > 0);
  omni_accessible_set_disabled(button, action_id <= 0);
  omni_accessible_set_selected(button, gtk_list_item_get_selected(list_item));
  omni_accessible_list_position(button, (int32_t)position + 1, count);
  omni_accessible_description(button, action_id > 0 ? "Activates this list row" : "Static list row");
  omni_accessible_label_with_native_update(button, text, native_accessible);
}

static void on_string_list_activate(GtkListView *view, guint position, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(view), "omni-app");
  OmniStringListData *list = (OmniStringListData *)g_object_get_data(G_OBJECT(view), "omni-string-list-data");
  int32_t original = sidebar_original_index_for_visible_position(list, position);
  if (!app || !app->callback || !list || original < 0 || original >= list->count) return;
  int32_t action_id = list->action_ids ? list->action_ids[original] : 0;
  if (action_id > 0) {
    omni_dispatch_action_callback(app, action_id);
    omni_flush_pending_ui(app);
  }
}

static void on_scroll_adjustment_value_changed(GtkAdjustment *adjustment, gpointer data) {
  (void)adjustment;
  omni_macos_accessibility_schedule_after_scroll((OmniAdwApp *)data);
}

static void on_virtual_list_button_clicked(GtkButton *button, gpointer data) {
  GtkWidget *widget = GTK_WIDGET(button);
  GtkWidget *list_view = gtk_widget_get_ancestor(widget, GTK_TYPE_LIST_VIEW);
  GtkWidget *list_box = list_view ? NULL : gtk_widget_get_ancestor(widget, GTK_TYPE_LIST_BOX);
  GtkWidget *list_widget = list_view ? list_view : list_box;
  OmniAdwApp *app = list_widget ? (OmniAdwApp *)g_object_get_data(G_OBJECT(list_widget), "omni-app") : NULL;
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "omni-action-id"));
  int required_click_count = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "omni-required-click-count"));
  if (required_click_count > 1) return;
  if (app && app->callback && action_id > 0) {
    omni_dispatch_action_callback(app, action_id);
    omni_flush_pending_ui(app);
  }
}

static void on_sidebar_disclosure_clicked(GtkButton *button, gpointer data) {
  GtkWidget *widget = GTK_WIDGET(button);
  GtkWidget *list_view = gtk_widget_get_ancestor(widget, GTK_TYPE_LIST_VIEW);
  GtkWidget *list_box = list_view ? NULL : gtk_widget_get_ancestor(widget, GTK_TYPE_LIST_BOX);
  GtkWidget *list_widget = list_view ? list_view : list_box;
  OmniStringListData *list = list_widget ? (OmniStringListData *)g_object_get_data(G_OBJECT(list_widget), "omni-string-list-data") : NULL;
  if (!list || !list->collapsed) return;
  int32_t index = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "omni-sidebar-index"));
  if (index < 0 || index >= list->count || !sidebar_row_has_children(list, index)) return;
  list->collapsed[index] = !list->collapsed[index];
  OmniAdwApp *app = list_widget ? (OmniAdwApp *)g_object_get_data(G_OBJECT(list_widget), "omni-app") : NULL;
  if (app && app->sidebar_collapsed_items) {
    char *key = sidebar_collapse_key(list, index);
    if (key) {
      if (list->collapsed[index]) {
        g_hash_table_replace(app->sidebar_collapsed_items, key, GINT_TO_POINTER(1));
      } else {
        g_hash_table_remove(app->sidebar_collapsed_items, key);
        g_free(key);
      }
    }
  }
  if (list_view) {
    sidebar_rebuild_visible_indices(list);
  } else if (list_box) {
    sidebar_apply_visibility_to_rows(list_box, list);
  }
  omni_macos_accessibility_schedule(app);
}

static void omni_sidebar_content_set_text(GtkWidget *button, const char *text, double font_size, const char *font_weight, gboolean font_italic, const char *css_classes) {
  GtkWidget *label = GTK_IS_BUTTON(button) ? gtk_button_get_child(GTK_BUTTON(button)) : NULL;
  if (GTK_IS_LABEL(label)) {
    gtk_label_set_text(GTK_LABEL(label), text ? text : "");
    omni_label_apply_font(GTK_LABEL(label), font_size, font_weight, font_italic);
    omni_widget_replace_css_classes(label, "omni-row-css-classes", css_classes);
    omni_widget_replace_css_classes(button, "omni-row-css-classes", css_classes);
  }
}

static GtkWidget *omni_sidebar_label_new(void) {
  GtkWidget *label = gtk_label_new("");
  gtk_widget_add_css_class(label, "omni-sidebar-label");
  gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
  gtk_label_set_wrap(GTK_LABEL(label), TRUE);
  gtk_label_set_wrap_mode(GTK_LABEL(label), PANGO_WRAP_WORD_CHAR);
  gtk_label_set_lines(GTK_LABEL(label), 3);
  gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_END);
  gtk_widget_set_hexpand(label, TRUE);
  gtk_widget_set_halign(label, GTK_ALIGN_FILL);
  return label;
}

static void on_sidebar_list_setup(GtkSignalListItemFactory *factory, GtkListItem *list_item, gpointer data) {
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  gtk_widget_add_css_class(box, "omni-sidebar-row");
  gtk_widget_set_hexpand(box, TRUE);
  gtk_widget_set_halign(box, GTK_ALIGN_FILL);

  GtkWidget *disclosure_button = gtk_button_new();
  gtk_widget_add_css_class(disclosure_button, "flat");
  gtk_widget_add_css_class(disclosure_button, "omni-sidebar-disclosure-button");
  gtk_widget_set_focus_on_click(disclosure_button, TRUE);
  g_signal_connect(disclosure_button, "clicked", G_CALLBACK(on_sidebar_disclosure_clicked), NULL);
  GtkWidget *disclosure = gtk_label_new("");
  gtk_widget_add_css_class(disclosure, "omni-sidebar-disclosure");
  gtk_label_set_xalign(GTK_LABEL(disclosure), 0.5f);
  gtk_button_set_child(GTK_BUTTON(disclosure_button), disclosure);
  gtk_box_append(GTK_BOX(box), disclosure_button);

  GtkWidget *button = gtk_button_new();
  gtk_widget_add_css_class(button, "omni-sidebar-row-button");
  gtk_widget_set_hexpand(button, TRUE);
  gtk_widget_set_halign(button, GTK_ALIGN_FILL);
  gtk_widget_set_focus_on_click(button, TRUE);
  g_signal_connect(button, "clicked", G_CALLBACK(on_virtual_list_button_clicked), NULL);
  gtk_button_set_child(GTK_BUTTON(button), omni_sidebar_label_new());
  gtk_box_append(GTK_BOX(box), button);

  gtk_list_item_set_child(list_item, box);
}

static void on_sidebar_list_bind(GtkSignalListItemFactory *factory, GtkListItem *list_item, gpointer data) {
  GtkWidget *box = gtk_list_item_get_child(list_item);
  gpointer item = gtk_list_item_get_item(list_item);
  if (!GTK_IS_BOX(box)) return;
  if (!OMNI_IS_LIST_ROW_OBJECT(item) && !GTK_IS_STRING_OBJECT(item)) return;
  GtkWidget *disclosure_button = gtk_widget_get_first_child(box);
  GtkWidget *button = disclosure_button ? gtk_widget_get_next_sibling(disclosure_button) : NULL;
  GtkWidget *disclosure = GTK_IS_BUTTON(disclosure_button) ? gtk_button_get_child(GTK_BUTTON(disclosure_button)) : NULL;
  if (!GTK_IS_BUTTON(disclosure_button) || !GTK_IS_BUTTON(button) || !GTK_IS_LABEL(disclosure)) return;

  guint position = gtk_list_item_get_position(list_item);
  OmniStringListData *list = (OmniStringListData *)data;
  int32_t original = OMNI_IS_LIST_ROW_OBJECT(item)
    ? OMNI_LIST_ROW_OBJECT(item)->original_index
    : sidebar_original_index_for_visible_position(list, position);
  const char *text = list && list->labels && original >= 0 && original < list->count
    ? list->labels[original]
    : (GTK_IS_STRING_OBJECT(item) ? gtk_string_object_get_string(GTK_STRING_OBJECT(item)) : "");
  int32_t depth = list && list->depths && original >= 0 && original < list->count ? list->depths[original] : 0;
  int32_t action_id = list && list->action_ids && original >= 0 && original < list->count ? list->action_ids[original] : 0;
  double font_size = list && list->font_sizes && original >= 0 && original < list->count ? list->font_sizes[original] : 0.0;
  const char *font_weight = list && list->font_weights && original >= 0 && original < list->count ? list->font_weights[original] : "";
  int32_t font_italic = list && list->font_italics && original >= 0 && original < list->count ? list->font_italics[original] : 0;
  const char *css_classes = list && list->css_classes && original >= 0 && original < list->count ? list->css_classes[original] : "";
  int32_t count = list && list->visible_indices ? list->visible_count : (list ? list->count : 0);
  gboolean native_accessible = count <= OMNI_NATIVE_ACCESSIBILITY_ROW_UPDATE_LIMIT;
  gboolean has_children = sidebar_row_has_children(list, original);
  if (depth < 0) depth = 0;
  if (depth > 8) depth = 8;

  gtk_widget_set_margin_start(box, depth * 16);
  gtk_widget_set_visible(disclosure_button, has_children);
  gtk_label_set_text(GTK_LABEL(disclosure), has_children ? (list->collapsed && list->collapsed[original] ? "▸" : "▾") : "");
  omni_sidebar_content_set_text(button, text ? text : "", font_size, font_weight, font_italic != 0, css_classes);
  if (native_accessible) {
    gtk_list_item_set_accessible_label(list_item, text ? text : "");
    gtk_list_item_set_accessible_description(list_item, has_children ? "Collapsible sidebar item" : (action_id > 0 ? "Sidebar item" : "Static sidebar item"));
  }
  gtk_list_item_set_activatable(list_item, FALSE);
  gtk_list_item_set_selectable(list_item, action_id > 0);
  gtk_list_item_set_focusable(list_item, action_id > 0 || has_children);
  g_object_set_data(G_OBJECT(disclosure_button), "omni-sidebar-index", GINT_TO_POINTER(original));
  g_object_set_data(G_OBJECT(button), "omni-action-id", GINT_TO_POINTER(action_id));
  gtk_widget_set_focusable(button, action_id > 0);
  gtk_widget_set_focusable(disclosure_button, has_children);
  omni_accessible_set_disabled(button, action_id <= 0);
  omni_accessible_set_disabled(disclosure_button, !has_children);
  omni_accessible_set_expanded(disclosure_button, has_children && !(list->collapsed && list->collapsed[original]));
  omni_accessible_set_selected(button, gtk_list_item_get_selected(list_item));
  omni_accessible_list_position(button, (int32_t)position + 1, count);
  omni_accessible_description(button, depth == 0 ? "Top-level sidebar item" : "Nested sidebar item");
  omni_accessible_description(disclosure_button, has_children ? "Expands or collapses this sidebar group" : "");
  omni_accessible_label(disclosure_button, has_children ? (list->collapsed && list->collapsed[original] ? "Expand" : "Collapse") : "");
  omni_accessible_label_with_native_update(button, text, native_accessible);
}

static void on_plain_list_row_activated(GtkListBox *box, GtkListBoxRow *row, gpointer data) {
  if (!box || !row) return;
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(box), "omni-app");
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(row), "omni-action-id"));
  if (app && app->callback && action_id > 0) {
    omni_dispatch_action_callback(app, action_id);
    omni_flush_pending_ui(app);
  }
}

static void on_sidebar_toggle_toggled(GtkToggleButton *button, gpointer data) {
  if (g_object_get_data(G_OBJECT(button), "omni-updating") != NULL) return;
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app || !app->active_split_view || !ADW_IS_OVERLAY_SPLIT_VIEW(app->active_split_view)) return;
  gboolean show_sidebar = gtk_toggle_button_get_active(button);
  app->sidebar_show_sidebar = show_sidebar;
  adw_overlay_split_view_set_show_sidebar(
    ADW_OVERLAY_SPLIT_VIEW(app->active_split_view),
    show_sidebar
  );
  omni_accessible_set_expanded(GTK_WIDGET(button), show_sidebar);
  gtk_accessible_update_state(
    GTK_ACCESSIBLE(button),
    GTK_ACCESSIBLE_STATE_PRESSED,
    show_sidebar ? GTK_ACCESSIBLE_TRISTATE_TRUE : GTK_ACCESSIBLE_TRISTATE_FALSE,
    -1
  );
  omni_macos_accessibility_schedule(app);
}

static void on_header_tab_clicked(GtkButton *button, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app || !button) return;
  int32_t index = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "omni-tab-index"));
  if (index < 0 || index >= app->tab_count || index == app->active_tab) return;
  app->active_tab = index;
  update_header_tab_strip(app);
  if (app->header_entry) {
    gtk_widget_grab_focus(app->header_entry);
  }
  omni_macos_accessibility_schedule(app);
}

static void on_split_show_sidebar_notify(GObject *object, GParamSpec *pspec, gpointer data) {
  (void)object;
  (void)pspec;
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (app && app->active_split_view && ADW_IS_OVERLAY_SPLIT_VIEW(app->active_split_view)) {
    app->sidebar_show_sidebar = adw_overlay_split_view_get_show_sidebar(ADW_OVERLAY_SPLIT_VIEW(app->active_split_view));
  }
  sync_sidebar_toggle(app);
  omni_macos_accessibility_schedule(app);
}

static void on_plain_list_row_pressed(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data) {
  if (n_press != 1) return;
  omni_record_click_start(gesture, x, y);
}

static int nearest_action_id_until(GtkWidget *widget, GtkWidget *stop) {
  GtkWidget *current = widget;
  while (current) {
    int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(current), "omni-action-id"));
    if (action_id > 0) return action_id;
    if (current == stop) break;
    current = gtk_widget_get_parent(current);
  }
  return 0;
}

static gboolean click_targets_different_nested_action(GtkWidget *controller_widget, double x, double y, int own_action_id) {
  if (!controller_widget || own_action_id <= 0) return FALSE;
  GtkWidget *picked = gtk_widget_pick(controller_widget, x, y, GTK_PICK_DEFAULT);
  int picked_action_id = nearest_action_id_until(picked, controller_widget);
  return picked_action_id > 0 && picked_action_id != own_action_id;
}

static void on_plain_list_row_released(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data) {
  if (!omni_click_is_stationary(gesture, x, y)) return;
  guint button = gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(gesture));
  if (button != GDK_BUTTON_PRIMARY) return;
  GtkWidget *controller_widget = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(gesture));
  GtkWidget *row_widget = NULL;
  if (GTK_IS_LIST_BOX(controller_widget)) {
    GtkWidget *picked = gtk_widget_pick(controller_widget, x, y, GTK_PICK_DEFAULT);
    while (picked && !GTK_IS_LIST_BOX_ROW(picked)) {
      picked = gtk_widget_get_parent(picked);
    }
    row_widget = picked;
  } else {
    row_widget = controller_widget;
    while (row_widget && !GTK_IS_LIST_BOX_ROW(row_widget)) {
      row_widget = gtk_widget_get_parent(row_widget);
    }
  }
  if (!row_widget) return;
  GtkWidget *box_widget = gtk_widget_get_parent(row_widget);
  while (box_widget && !GTK_IS_LIST_BOX(box_widget)) {
    box_widget = gtk_widget_get_parent(box_widget);
  }
  if (!box_widget) return;
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(box_widget), "omni-app");
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(row_widget), "omni-action-id"));
  if (click_targets_different_nested_action(controller_widget, x, y, action_id)) {
    return;
  }
  if (app && app->callback && action_id > 0) {
    omni_dispatch_action_callback(app, action_id);
    omni_flush_pending_ui(app);
    gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_CLAIMED);
  }
}

static void on_click_container_pressed(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data) {
  (void)data;
  if (n_press != 1) return;
  omni_record_click_start(gesture, x, y);
}

static void on_click_container_released(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data) {
  (void)n_press;
  (void)data;
  if (!omni_click_is_stationary(gesture, x, y)) return;
  guint button = gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(gesture));
  if (button != GDK_BUTTON_PRIMARY) return;
  GtkWidget *widget = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(gesture));
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id"));
  if (click_targets_different_nested_action(widget, x, y, action_id)) {
    return;
  }
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(widget), "omni-app");
  if (app && app->callback && action_id > 0) {
    omni_dispatch_action_callback(app, action_id);
    omni_flush_pending_ui(app);
    gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_CLAIMED);
  }
}

static void install_row_click_controller(GtkWidget *widget) {
  if (!widget) return;
  GtkGesture *click_controller = gtk_gesture_click_new();
  gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(click_controller), GTK_PHASE_CAPTURE);
  g_signal_connect(click_controller, "pressed", G_CALLBACK(on_plain_list_row_pressed), NULL);
  g_signal_connect(click_controller, "released", G_CALLBACK(on_plain_list_row_released), NULL);
  gtk_widget_add_controller(widget, GTK_EVENT_CONTROLLER(click_controller));
}

static void install_click_container_controller(GtkWidget *widget) {
  if (!widget) return;
  GtkGesture *click_controller = gtk_gesture_click_new();
  gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(click_controller), GTK_PHASE_BUBBLE);
  g_signal_connect(click_controller, "pressed", G_CALLBACK(on_click_container_pressed), NULL);
  g_signal_connect(click_controller, "released", G_CALLBACK(on_click_container_released), NULL);
  gtk_widget_add_controller(widget, GTK_EVENT_CONTROLLER(click_controller));
}

static gboolean omni_label_looks_iconic(const char *label) {
  if (!label || !label[0]) return FALSE;
  if (strcmp(label, "Go") == 0) return FALSE;
  int chars = g_utf8_strlen(label, -1);
  if (chars <= 0 || chars > 3) return FALSE;
  for (const char *p = label; p && *p; p = g_utf8_next_char(p)) {
    gunichar ch = g_utf8_get_char(p);
    if (g_unichar_isalnum(ch)) return FALSE;
  }
  return TRUE;
}

static gboolean omni_known_resource_symbolic_icon(const char *name) {
  if (!name || !name[0]) return FALSE;
  static const char *icons[] = {
    "adw-adaptive-preview-symbolic",
    "adw-application-exit-symbolic",
    "adw-avatar-default-symbolic",
    "adw-entry-apply-symbolic",
    "adw-entry-edit-symbolic",
    "adw-external-link-symbolic",
    "adw-mail-send-symbolic",
    "adw-rotate-acw-symbolic",
    "adw-rotate-cw-symbolic",
    "adw-screenshot-symbolic",
    "adw-sidebar-symbolic",
    "adw-tab-icon-missing-symbolic",
    "adw-tab-new-symbolic",
    "adw-tab-overflow-symbolic",
    "application-x-executable-symbolic",
    "audio-volume-high-symbolic",
    "audio-volume-low-symbolic",
    "audio-volume-medium-symbolic",
    "audio-volume-muted-symbolic",
    "bookmark-new-symbolic",
    "changes-prevent-symbolic",
    "check-symbolic",
    "dialog-error-symbolic",
    "dialog-information-symbolic",
    "dialog-question-symbolic",
    "dialog-warning-symbolic",
    "display-brightness-symbolic",
    "document-open-recent-symbolic",
    "document-open-symbolic",
    "document-save-as-symbolic",
    "document-save-symbolic",
    "drive-harddisk-symbolic",
    "edit-clear-symbolic",
    "edit-copy-symbolic",
    "edit-cut-symbolic",
    "edit-delete-symbolic",
    "edit-find-symbolic",
    "edit-paste-symbolic",
    "edit-redo-symbolic",
    "edit-select-all-symbolic",
    "edit-undo-symbolic",
    "emblem-documents-symbolic",
    "emblem-important-symbolic",
    "emblem-system-symbolic",
    "folder-documents-symbolic",
    "folder-download-symbolic",
    "folder-music-symbolic",
    "folder-new-symbolic",
    "folder-pictures-symbolic",
    "folder-publicshare-symbolic",
    "folder-remote-symbolic",
    "folder-symbolic",
    "folder-videos-symbolic",
    "go-down-symbolic",
    "go-next-symbolic",
    "go-previous-symbolic",
    "go-up-symbolic",
    "image-missing",
    "insert-image-symbolic",
    "list-add-symbolic",
    "list-remove-symbolic",
    "media-playback-pause-symbolic",
    "media-playback-start-symbolic",
    "media-playback-stop-symbolic",
    "media-record-symbolic",
    "network-server-symbolic",
    "network-workgroup-symbolic",
    "object-select-symbolic",
    "open-menu-symbolic",
    "pan-down-symbolic",
    "pan-end-symbolic",
    "pan-start-symbolic",
    "pan-up-symbolic",
    "process-working-symbolic",
    "starred-symbolic",
    "system-run-symbolic",
    "system-search-symbolic",
    "text-x-generic-symbolic",
    "user-home-symbolic",
    "user-trash-symbolic",
    "view-conceal-symbolic",
    "view-fullscreen-symbolic",
    "view-grid-symbolic",
    "view-list-symbolic",
    "view-more-symbolic",
    "view-refresh-symbolic",
    "view-reveal-symbolic",
    "view-sidebar-end-symbolic",
    "view-sidebar-start-symbolic",
    "window-close-symbolic",
    "window-maximize-symbolic",
    "window-minimize-symbolic",
    "window-restore-symbolic",
    "zoom-in-symbolic",
    "zoom-original-symbolic",
    "zoom-out-symbolic",
    NULL
  };
  for (const char **icon = icons; *icon; icon++) {
    if (strcmp(name, *icon) == 0) return TRUE;
  }
  return FALSE;
}

static const char *omni_available_symbolic_icon(const char *first, const char *second, const char *third) {
  const char *candidates[] = { first, second, third, NULL };
  GdkDisplay *display = gdk_display_get_default();
  GtkIconTheme *theme = display ? gtk_icon_theme_get_for_display(display) : NULL;
  for (const char **candidate = candidates; candidate && *candidate; candidate++) {
    if (!*candidate || !(*candidate)[0]) continue;
    if (!theme || gtk_icon_theme_has_icon(theme, *candidate) || omni_known_resource_symbolic_icon(*candidate)) {
      return *candidate;
    }
  }
  return NULL;
}

static const char *omni_symbolic_icon_name_for_system_name(const char *system_name) {
  if (!system_name || !system_name[0]) return NULL;
  if (strcmp(system_name, "checkmark") == 0 || strcmp(system_name, "checkmark.circle") == 0 || strcmp(system_name, "checkmark.circle.fill") == 0) return omni_available_symbolic_icon("object-select-symbolic", "adw-entry-apply-symbolic", "check-symbolic");
  if (strcmp(system_name, "xmark") == 0 || strcmp(system_name, "xmark.circle") == 0 || strcmp(system_name, "xmark.circle.fill") == 0) return omni_available_symbolic_icon("window-close-symbolic", "edit-clear-symbolic", NULL);
  if (strcmp(system_name, "plus") == 0 || strcmp(system_name, "plus.circle") == 0) return omni_available_symbolic_icon("list-add-symbolic", "adw-tab-new-symbolic", NULL);
  if (strcmp(system_name, "minus") == 0 || strcmp(system_name, "minus.circle") == 0) return omni_available_symbolic_icon("list-remove-symbolic", NULL, NULL);
  if (strcmp(system_name, "gear") == 0 || strcmp(system_name, "gearshape") == 0) return omni_available_symbolic_icon("emblem-system-symbolic", "system-run-symbolic", NULL);
  if (strcmp(system_name, "star") == 0 || strcmp(system_name, "star.fill") == 0) return omni_available_symbolic_icon("starred-symbolic", NULL, NULL);
  if (strcmp(system_name, "trash") == 0) return omni_available_symbolic_icon("user-trash-symbolic", "edit-delete-symbolic", NULL);
  if (strcmp(system_name, "pencil") == 0) return omni_available_symbolic_icon("adw-entry-edit-symbolic", NULL, NULL);
  if (strcmp(system_name, "magnifyingglass") == 0 || strcmp(system_name, "magnifyingglass.circle") == 0 || strcmp(system_name, "magnifyingglass.circle.fill") == 0 || strcmp(system_name, "doc.text.magnifyingglass") == 0) return omni_available_symbolic_icon("system-search-symbolic", "edit-find-symbolic", NULL);
  if (strcmp(system_name, "arrow.left") == 0 || strcmp(system_name, "chevron.left") == 0) return omni_available_symbolic_icon("go-previous-symbolic", "pan-start-symbolic", NULL);
  if (strcmp(system_name, "arrow.right") == 0 || strcmp(system_name, "chevron.right") == 0) return omni_available_symbolic_icon("go-next-symbolic", "pan-end-symbolic", NULL);
  if (strcmp(system_name, "arrow.up") == 0 || strcmp(system_name, "chevron.up") == 0) return omni_available_symbolic_icon("go-up-symbolic", "pan-up-symbolic", NULL);
  if (strcmp(system_name, "arrow.down") == 0 || strcmp(system_name, "chevron.down") == 0) return omni_available_symbolic_icon("go-down-symbolic", "pan-down-symbolic", NULL);
  if (strcmp(system_name, "arrow.clockwise") == 0) return omni_available_symbolic_icon("view-refresh-symbolic", "adw-rotate-cw-symbolic", NULL);
  if (strcmp(system_name, "house") == 0 || strcmp(system_name, "house.fill") == 0) return omni_available_symbolic_icon("user-home-symbolic", NULL, NULL);
  if (strcmp(system_name, "person") == 0 || strcmp(system_name, "person.fill") == 0) return omni_available_symbolic_icon("adw-avatar-default-symbolic", NULL, NULL);
  if (strcmp(system_name, "envelope") == 0 || strcmp(system_name, "envelope.fill") == 0) return omni_available_symbolic_icon("adw-mail-send-symbolic", NULL, NULL);
  if (strcmp(system_name, "terminal") == 0 || strcmp(system_name, "terminal.fill") == 0) return omni_available_symbolic_icon("application-x-executable-symbolic", "system-run-symbolic", NULL);
  if (strcmp(system_name, "doc") == 0 || strcmp(system_name, "doc.fill") == 0 || strcmp(system_name, "doc.text") == 0 || strcmp(system_name, "doc.richtext") == 0 || strcmp(system_name, "doc.plaintext") == 0 || strcmp(system_name, "doc.plaintext.fill") == 0 || strcmp(system_name, "book") == 0 || strcmp(system_name, "book.closed") == 0) return omni_available_symbolic_icon("text-x-generic-symbolic", "document-open-symbolic", "emblem-documents-symbolic");
  if (strcmp(system_name, "folder") == 0 || strcmp(system_name, "folder.fill") == 0) return omni_available_symbolic_icon("folder-symbolic", "folder-documents-symbolic", NULL);
  if (strcmp(system_name, "clock") == 0 || strcmp(system_name, "clock.fill") == 0 || strcmp(system_name, "calendar") == 0) return omni_available_symbolic_icon("document-open-recent-symbolic", NULL, NULL);
  if (strcmp(system_name, "exclamationmark.triangle") == 0 || strcmp(system_name, "exclamationmark.triangle.fill") == 0) return omni_available_symbolic_icon("dialog-warning-symbolic", "emblem-important-symbolic", NULL);
  if (strcmp(system_name, "info.circle") == 0 || strcmp(system_name, "info.circle.fill") == 0 || strcmp(system_name, "questionmark.circle") == 0) return omni_available_symbolic_icon("dialog-information-symbolic", "dialog-question-symbolic", NULL);
  if (strcmp(system_name, "eye") == 0 || strcmp(system_name, "eye.fill") == 0) return omni_available_symbolic_icon("view-reveal-symbolic", NULL, NULL);
  if (strcmp(system_name, "eye.slash") == 0) return omni_available_symbolic_icon("view-conceal-symbolic", "changes-prevent-symbolic", NULL);
  if (strcmp(system_name, "sun.max") == 0 || strcmp(system_name, "sun.max.fill") == 0) return omni_available_symbolic_icon("display-brightness-symbolic", NULL, NULL);
  if (strcmp(system_name, "paintbrush") == 0 || strcmp(system_name, "paintbrush.fill") == 0 || strcmp(system_name, "photo") == 0) return omni_available_symbolic_icon("insert-image-symbolic", NULL, NULL);
  if (strcmp(system_name, "wrench") == 0 || strcmp(system_name, "wrench.fill") == 0 || strcmp(system_name, "hammer") == 0 || strcmp(system_name, "hammer.fill") == 0) return omni_available_symbolic_icon("system-run-symbolic", NULL, NULL);
  if (strcmp(system_name, "chart.bar") == 0 || strcmp(system_name, "chart.bar.fill") == 0) return omni_available_symbolic_icon("view-list-symbolic", NULL, NULL);
  if (strcmp(system_name, "list.bullet") == 0 || strcmp(system_name, "sidebar.left") == 0 || strcmp(system_name, "sidebar.leading") == 0 || strcmp(system_name, "text.alignleft") == 0) return omni_available_symbolic_icon("open-menu-symbolic", "view-list-symbolic", NULL);
  if (strcmp(system_name, "play") == 0 || strcmp(system_name, "play.fill") == 0) return omni_available_symbolic_icon("media-playback-start-symbolic", NULL, NULL);
  if (strcmp(system_name, "pause") == 0 || strcmp(system_name, "pause.fill") == 0) return omni_available_symbolic_icon("media-playback-pause-symbolic", NULL, NULL);
  if (strcmp(system_name, "stop") == 0 || strcmp(system_name, "stop.fill") == 0) return omni_available_symbolic_icon("media-playback-stop-symbolic", NULL, NULL);
  if (strcmp(system_name, "speaker.wave.2") == 0 || strcmp(system_name, "speaker.wave.2.fill") == 0) return omni_available_symbolic_icon("audio-volume-high-symbolic", NULL, NULL);
  if (strcmp(system_name, "globe") == 0 || strcmp(system_name, "safari") == 0) return omni_available_symbolic_icon("network-workgroup-symbolic", "adw-external-link-symbolic", NULL);
  if (strcmp(system_name, "phone") == 0 || strcmp(system_name, "phone.fill") == 0 || strcmp(system_name, "bubble.right") == 0 || strcmp(system_name, "bubble.right.fill") == 0 || strcmp(system_name, "text.bubble") == 0 || strcmp(system_name, "text.bubble.fill") == 0) return omni_available_symbolic_icon("dialog-information-symbolic", NULL, NULL);
  if (strcmp(system_name, "bookmark") == 0 || strcmp(system_name, "bookmark.fill") == 0) return omni_available_symbolic_icon("bookmark-new-symbolic", NULL, NULL);
  if (strcmp(system_name, "link") == 0 || strcmp(system_name, "square.and.arrow.up") == 0) return omni_available_symbolic_icon("adw-external-link-symbolic", NULL, NULL);
  if (strcmp(system_name, "square.and.arrow.down") == 0) return omni_available_symbolic_icon("folder-download-symbolic", "document-save-symbolic", NULL);
  if (strcmp(system_name, "rectangle.split.2x1") == 0) return omni_available_symbolic_icon("widget-split-views-symbolic", "view-grid-symbolic", NULL);
  if (strcmp(system_name, "ellipsis.circle") == 0 || strcmp(system_name, "ellipsis.circle.fill") == 0) return omni_available_symbolic_icon("view-more-symbolic", NULL, NULL);
  return NULL;
}

static const char *omni_symbolic_icon_name_for_label(const char *label) {
  if (!label || !label[0]) return NULL;
  if (strcmp(label, "⌂") == 0 || g_ascii_strcasecmp(label, "Home") == 0) return omni_available_symbolic_icon("user-home-symbolic", "go-home-symbolic", NULL);
  if (strcmp(label, "‹") == 0 || g_ascii_strcasecmp(label, "Back") == 0) return omni_available_symbolic_icon("go-previous-symbolic", "pan-start-symbolic", NULL);
  if (strcmp(label, "›") == 0 || g_ascii_strcasecmp(label, "Forward") == 0) return omni_available_symbolic_icon("go-next-symbolic", "pan-end-symbolic", NULL);
  if (strcmp(label, "↻") == 0 || g_ascii_strcasecmp(label, "Refresh") == 0 || g_ascii_strcasecmp(label, "Reload") == 0 || g_ascii_strcasecmp(label, "Reload Page") == 0) return omni_available_symbolic_icon("view-refresh-symbolic", "emblem-synchronizing-symbolic", NULL);
  if (strcmp(label, "☰") == 0) return omni_available_symbolic_icon("open-menu-symbolic", "view-list-symbolic", NULL);
  if (strcmp(label, "▤") == 0 || g_ascii_strcasecmp(label, "Bookmarks") == 0 || g_ascii_strcasecmp(label, "Bookmarks and History") == 0) return omni_available_symbolic_icon("user-bookmarks-symbolic", "bookmark-new-symbolic", "x-office-address-book-symbolic");
  if (strcmp(label, "⚙") == 0 || g_ascii_strcasecmp(label, "Settings") == 0 || g_ascii_strcasecmp(label, "Preferences") == 0) return omni_available_symbolic_icon("emblem-system-symbolic", "preferences-system-symbolic", NULL);
  if (strcmp(label, "📄") == 0 || strcmp(label, "≣") == 0 || g_ascii_strcasecmp(label, "Reader Mode") == 0 || g_ascii_strcasecmp(label, "Exit Reader Mode") == 0) return omni_available_symbolic_icon("text-x-generic-symbolic", "x-office-document-symbolic", NULL);
  if (strcmp(label, "↗") == 0 || g_ascii_strcasecmp(label, "Open") == 0 || g_ascii_strcasecmp(label, "Open externally") == 0) return omni_available_symbolic_icon("adw-external-link-symbolic", "send-to-symbolic", "go-jump-symbolic");
  if (strcmp(label, "◆") == 0 || strcmp(label, "◇") == 0 || g_ascii_strcasecmp(label, "Bookmark") == 0 || g_ascii_strcasecmp(label, "Add Bookmark") == 0 || g_ascii_strcasecmp(label, "Remove Bookmark") == 0) return omni_available_symbolic_icon("bookmark-new-symbolic", "user-bookmarks-symbolic", NULL);
  if (strcmp(label, "🌐") == 0 || g_ascii_strcasecmp(label, "Open in Browser") == 0 || g_ascii_strcasecmp(label, "Browser") == 0) return omni_available_symbolic_icon("web-browser-symbolic", "applications-internet-symbolic", "network-workgroup-symbolic");
  if (g_ascii_strcasecmp(label, "Share") == 0) return omni_available_symbolic_icon("adw-share-symbolic", "emblem-shared-symbolic", "send-to-symbolic");
  if (strcmp(label, "◫") == 0) return omni_available_symbolic_icon("view-dual-symbolic", "view-grid-symbolic", "view-paged-symbolic");
  if (strcmp(label, "⊘") == 0) return omni_available_symbolic_icon("view-hidden-symbolic", "changes-prevent-symbolic", NULL);
  if (strcmp(label, "👁") == 0) return omni_available_symbolic_icon("view-visible-symbolic", "view-reveal-symbolic", NULL);
  if (strcmp(label, "⚠") == 0) return omni_available_symbolic_icon("dialog-warning-symbolic", "emblem-important-symbolic", NULL);
  if (strcmp(label, "+") == 0) return omni_available_symbolic_icon("adw-tab-new-symbolic", "list-add-symbolic", NULL);
  if (strcmp(label, "⌕") == 0 || strcmp(label, "🔍") == 0) return omni_available_symbolic_icon("system-search-symbolic", "edit-find-symbolic", NULL);
  if (strcmp(label, "✓") == 0) return omni_available_symbolic_icon("adw-entry-apply-symbolic", "object-select-symbolic", NULL);
  return NULL;
}

static const char *omni_accessible_label_for_symbolic_label(const char *label) {
  if (!label || !label[0]) return NULL;
  if (strcmp(label, "⌂") == 0 || g_ascii_strcasecmp(label, "Home") == 0) return "Home";
  if (strcmp(label, "‹") == 0 || g_ascii_strcasecmp(label, "Back") == 0) return "Back";
  if (strcmp(label, "›") == 0 || g_ascii_strcasecmp(label, "Forward") == 0) return "Forward";
  if (strcmp(label, "↻") == 0 || g_ascii_strcasecmp(label, "Refresh") == 0 || g_ascii_strcasecmp(label, "Reload") == 0 || g_ascii_strcasecmp(label, "Reload Page") == 0) return "Refresh";
  if (strcmp(label, "☰") == 0) return "Menu";
  if (strcmp(label, "▤") == 0 || g_ascii_strcasecmp(label, "Bookmarks") == 0 || g_ascii_strcasecmp(label, "Bookmarks and History") == 0) return "Bookmarks";
  if (strcmp(label, "⚙") == 0 || g_ascii_strcasecmp(label, "Settings") == 0 || g_ascii_strcasecmp(label, "Preferences") == 0) return "Settings";
  if (strcmp(label, "📄") == 0 || strcmp(label, "≣") == 0 || g_ascii_strcasecmp(label, "Reader Mode") == 0 || g_ascii_strcasecmp(label, "Exit Reader Mode") == 0) return "Reader Mode";
  if (strcmp(label, "↗") == 0 || g_ascii_strcasecmp(label, "Open") == 0 || g_ascii_strcasecmp(label, "Open externally") == 0) return "Open externally";
  if (strcmp(label, "◆") == 0 || strcmp(label, "◇") == 0 || g_ascii_strcasecmp(label, "Bookmark") == 0 || g_ascii_strcasecmp(label, "Add Bookmark") == 0 || g_ascii_strcasecmp(label, "Remove Bookmark") == 0) return "Bookmark";
  if (strcmp(label, "🌐") == 0 || g_ascii_strcasecmp(label, "Open in Browser") == 0 || g_ascii_strcasecmp(label, "Browser") == 0) return "Open in browser";
  if (g_ascii_strcasecmp(label, "Share") == 0) return "Share";
  if (strcmp(label, "◫") == 0) return "Split view";
  if (strcmp(label, "⊘") == 0) return "Hidden";
  if (strcmp(label, "👁") == 0) return "Visible";
  if (strcmp(label, "⚠") == 0) return "Warning";
  if (strcmp(label, "+") == 0) return "New tab";
  if (strcmp(label, "⌕") == 0 || strcmp(label, "🔍") == 0) return "Search";
  if (strcmp(label, "✓") == 0) return "Apply";
  return NULL;
}

static gboolean omni_button_set_symbolic_icon(GtkButton *button, const char *label) {
  const char *icon_name = omni_symbolic_icon_name_for_label(label);
  if (!button || !icon_name) return FALSE;
  GtkWidget *widget = GTK_WIDGET(button);
  GtkWidget *image = gtk_image_new_from_icon_name(icon_name);
  gtk_widget_set_size_request(image, 16, 16);
  gtk_widget_set_halign(image, GTK_ALIGN_CENTER);
  gtk_widget_set_valign(image, GTK_ALIGN_CENTER);
  gtk_button_set_child(button, image);
  gtk_widget_add_css_class(widget, "omni-icon-button");
  gtk_widget_set_size_request(widget, 38, 34);
  gtk_widget_set_halign(widget, GTK_ALIGN_CENTER);
  gtk_widget_set_valign(widget, GTK_ALIGN_CENTER);
  gtk_widget_set_tooltip_text(widget, omni_accessible_label_for_symbolic_label(label));
  return TRUE;
}

static void omni_button_set_label_or_symbolic_icon(GtkButton *button, const char *label) {
  const char *value = label ? label : "";
  if (!button) return;
  if (omni_button_set_symbolic_icon(button, value)) return;
  gtk_button_set_label(button, value);
}

static void on_scale_value_changed(GtkRange *range, gpointer data) {
  if (g_object_get_data(G_OBJECT(range), "omni-updating") != NULL) return;
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(range), "omni-app");
  if (!app) return;

  double previous = 0.0;
  double *previous_ptr = (double *)g_object_get_data(G_OBJECT(range), "omni-scale-value");
  if (previous_ptr) previous = *previous_ptr;
  double next = gtk_range_get_value(range);
  gtk_accessible_update_property(GTK_ACCESSIBLE(range), GTK_ACCESSIBLE_PROPERTY_VALUE_NOW, next, -1);

  int set_action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(range), "omni-set-action-id"));
  if (set_action_id > 0 && app->text_callback) {
    char value_text[G_ASCII_DTOSTR_BUF_SIZE];
    g_ascii_dtostr(value_text, sizeof(value_text), next);
    if (previous_ptr) *previous_ptr = next;
    app->text_callback(set_action_id, value_text, app->context);
    omni_flush_pending_ui(app);
    return;
  }

  if (!app->callback) return;

  int action_id = 0;
  if (next > previous) {
    action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(range), "omni-increment-action-id"));
  } else if (next < previous) {
    action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(range), "omni-decrement-action-id"));
  }

  if (previous_ptr) *previous_ptr = next;
  if (action_id > 0) {
    omni_dispatch_action_callback(app, action_id);
    omni_flush_pending_ui(app);
  }
}

static void on_spin_value_changed(GtkSpinButton *spin, gpointer data) {
  if (g_object_get_data(G_OBJECT(spin), "omni-updating") != NULL) return;
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(spin), "omni-app");
  if (!app || !app->callback) return;

  double previous = 0.0;
  double *previous_ptr = (double *)g_object_get_data(G_OBJECT(spin), "omni-spin-value");
  if (previous_ptr) previous = *previous_ptr;
  double next = gtk_spin_button_get_value(spin);
  gtk_accessible_update_property(GTK_ACCESSIBLE(spin), GTK_ACCESSIBLE_PROPERTY_VALUE_NOW, next, -1);

  int action_id = 0;
  if (next > previous) {
    action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(spin), "omni-increment-action-id"));
  } else if (next < previous) {
    action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(spin), "omni-decrement-action-id"));
  }

  if (previous_ptr) *previous_ptr = next;
  if (action_id > 0) {
    omni_dispatch_action_callback(app, action_id);
    omni_flush_pending_ui(app);
  }
}

static void omni_calendar_set_date(GtkCalendar *calendar, GDateTime *date) {
  if (!calendar || !date) return;
  gtk_calendar_set_year(calendar, g_date_time_get_year(date));
  gtk_calendar_set_month(calendar, g_date_time_get_month(date));
  gtk_calendar_set_day(calendar, g_date_time_get_day_of_month(date));
}

static void handle_calendar_date_changed(GtkCalendar *calendar) {
  if (g_object_get_data(G_OBJECT(calendar), "omni-updating") != NULL) return;
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(calendar), "omni-app");
  if (!app) return;

  gint64 previous = 0;
  gint64 *previous_ptr = (gint64 *)g_object_get_data(G_OBJECT(calendar), "omni-calendar-day");
  if (previous_ptr) previous = *previous_ptr;

  GDateTime *selected = gtk_calendar_get_date(calendar);
  if (!selected) return;
  int year = g_date_time_get_year(selected);
  int month = g_date_time_get_month(selected);
  int day = g_date_time_get_day_of_month(selected);
  gint64 next = (gint64)year * 10000 + (gint64)month * 100 + (gint64)day;
  GDateTime *local_noon = g_date_time_new_local(year, month, day, 12, 0, 0.0);
  gint64 timestamp = local_noon ? g_date_time_to_unix(local_noon) : g_date_time_to_unix(selected);
  if (local_noon) g_date_time_unref(local_noon);
  g_date_time_unref(selected);

  if (previous_ptr) *previous_ptr = next;
  int set_action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(calendar), "omni-set-action-id"));
  if (set_action_id > 0 && app->text_callback) {
    char *timestamp_text = g_strdup_printf("%lld", (long long)timestamp);
    app->text_callback(set_action_id, timestamp_text, app->context);
    g_free(timestamp_text);
    return;
  }

  int action_id = 0;
  if (next > previous) {
    action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(calendar), "omni-increment-action-id"));
  } else if (next < previous) {
    action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(calendar), "omni-decrement-action-id"));
  }
  if (app->callback && action_id > 0) {
    omni_dispatch_action_callback(app, action_id);
    omni_flush_pending_ui(app);
  }
}

static void on_calendar_date_notify(GObject *object, GParamSpec *pspec, gpointer data) {
  if (!GTK_IS_CALENDAR(object)) return;
  handle_calendar_date_changed(GTK_CALENDAR(object));
}

static GtkWidget *omni_first_descendant_matching(GtkWidget *widget, GType type) {
  if (!widget) return NULL;
  if (g_type_check_instance_is_a((GTypeInstance *)widget, type)) return widget;
  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child) {
    GtkWidget *found = omni_first_descendant_matching(child, type);
    if (found) return found;
    child = gtk_widget_get_next_sibling(child);
  }
  return NULL;
}

typedef struct {
  GdkRGBA color;
} OmniColorSwatchData;

typedef struct {
  GtkWidget *button;
  GtkWidget *popover;
  GtkWidget *red_scale;
  GtkWidget *green_scale;
  GtkWidget *blue_scale;
  GtkWidget *alpha_scale;
  int32_t set_action_id;
  gboolean supports_opacity;
  gboolean updating;
} OmniColorControlData;

static void omni_color_swatch_draw(GtkDrawingArea *area, cairo_t *cr, int width, int height, gpointer user_data) {
  (void)area;
  OmniColorSwatchData *data = (OmniColorSwatchData *)user_data;
  if (!data) return;
  double inset = 1.0;
  double w = width > 2 ? width - 2.0 : width;
  double h = height > 2 ? height - 2.0 : height;
  cairo_rectangle(cr, inset, inset, w, h);
  cairo_set_source_rgba(cr, data->color.red, data->color.green, data->color.blue, data->color.alpha);
  cairo_fill_preserve(cr);
  cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.35);
  cairo_set_line_width(cr, 1.0);
  cairo_stroke(cr);
}

static GtkWidget *omni_color_swatch_widget_new(const GdkRGBA *color, int width, int height) {
  GtkWidget *swatch = gtk_drawing_area_new();
  gtk_widget_set_size_request(swatch, width, height);
  gtk_drawing_area_set_content_width(GTK_DRAWING_AREA(swatch), width);
  gtk_drawing_area_set_content_height(GTK_DRAWING_AREA(swatch), height);
  OmniColorSwatchData *data = g_new0(OmniColorSwatchData, 1);
  if (data && color) data->color = *color;
  g_object_set_data(G_OBJECT(swatch), "omni-color-swatch-data", data);
  gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(swatch), omni_color_swatch_draw, data, g_free);
  return swatch;
}

static GtkWidget *omni_color_swatch_from_widget(GtkWidget *widget) {
  if (!widget) return NULL;
  if (g_object_get_data(G_OBJECT(widget), "omni-color-swatch-data") != NULL) return widget;
  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child) {
    GtkWidget *found = omni_color_swatch_from_widget(child);
    if (found) return found;
    child = gtk_widget_get_next_sibling(child);
  }
  return NULL;
}

static void omni_color_swatch_set_rgba(GtkWidget *widget, const GdkRGBA *color) {
  GtkWidget *swatch = omni_color_swatch_from_widget(widget);
  if (!swatch || !color) return;
  OmniColorSwatchData *data = (OmniColorSwatchData *)g_object_get_data(G_OBJECT(swatch), "omni-color-swatch-data");
  if (!data) return;
  data->color = *color;
  gtk_widget_queue_draw(swatch);
}

static OmniColorControlData *omni_color_control_data_from_widget(GtkWidget *widget) {
  if (!widget) return NULL;
  OmniColorControlData *data = (OmniColorControlData *)g_object_get_data(G_OBJECT(widget), "omni-color-control-data");
  if (data) return data;
  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child) {
    data = omni_color_control_data_from_widget(child);
    if (data) return data;
    child = gtk_widget_get_next_sibling(child);
  }
  return NULL;
}

static char *omni_color_raw_value_for_rgba(const GdkRGBA *color, gboolean supports_opacity) {
  if (!color) return g_strdup("black|1");
  char red[G_ASCII_DTOSTR_BUF_SIZE];
  char green[G_ASCII_DTOSTR_BUF_SIZE];
  char blue[G_ASCII_DTOSTR_BUF_SIZE];
  char alpha[G_ASCII_DTOSTR_BUF_SIZE];
  g_ascii_dtostr(red, sizeof(red), omni_unit_clamp(color->red));
  g_ascii_dtostr(green, sizeof(green), omni_unit_clamp(color->green));
  g_ascii_dtostr(blue, sizeof(blue), omni_unit_clamp(color->blue));
  g_ascii_dtostr(alpha, sizeof(alpha), supports_opacity ? omni_unit_clamp(color->alpha) : 1.0);
  return g_strdup_printf("rgb(%s,%s,%s)|%s", red, green, blue, alpha);
}

static void omni_color_scale_set_value(GtkWidget *scale, double value) {
  if (!GTK_IS_RANGE(scale)) return;
  g_object_set_data(G_OBJECT(scale), "omni-updating", GINT_TO_POINTER(1));
  gtk_range_set_value(GTK_RANGE(scale), omni_unit_clamp(value));
  gtk_accessible_update_property(GTK_ACCESSIBLE(scale), GTK_ACCESSIBLE_PROPERTY_VALUE_NOW, omni_unit_clamp(value), -1);
  g_object_set_data(G_OBJECT(scale), "omni-updating", NULL);
}

static void omni_color_control_read_rgba(OmniColorControlData *data, GdkRGBA *color) {
  if (!data || !color) return;
  omni_set_rgba(
    color,
    GTK_IS_RANGE(data->red_scale) ? gtk_range_get_value(GTK_RANGE(data->red_scale)) : 0.0,
    GTK_IS_RANGE(data->green_scale) ? gtk_range_get_value(GTK_RANGE(data->green_scale)) : 0.0,
    GTK_IS_RANGE(data->blue_scale) ? gtk_range_get_value(GTK_RANGE(data->blue_scale)) : 0.0,
    data->supports_opacity && GTK_IS_RANGE(data->alpha_scale) ? gtk_range_get_value(GTK_RANGE(data->alpha_scale)) : 1.0
  );
}

static void omni_color_control_set_rgba(OmniColorControlData *data, const GdkRGBA *color, gboolean update_scales) {
  if (!data || !color) return;
  data->updating = TRUE;
  omni_color_swatch_set_rgba(data->button, color);
  if (update_scales) {
    omni_color_scale_set_value(data->red_scale, color->red);
    omni_color_scale_set_value(data->green_scale, color->green);
    omni_color_scale_set_value(data->blue_scale, color->blue);
    omni_color_scale_set_value(data->alpha_scale, color->alpha);
  }
  char *raw = omni_color_raw_value_for_rgba(color, data->supports_opacity);
  omni_accessible_value_text(data->button, raw);
  g_free(raw);
  data->updating = FALSE;
}

static void omni_color_control_emit(OmniColorControlData *data, OmniAdwApp *app) {
  if (!data || !app || !app->text_callback || data->set_action_id <= 0) return;
  GdkRGBA color;
  omni_color_control_read_rgba(data, &color);
  char *raw = omni_color_raw_value_for_rgba(&color, data->supports_opacity);
  app->text_callback(data->set_action_id, raw, app->context);
  g_free(raw);
  omni_flush_pending_ui(app);
}

static void omni_color_button_set_rgba(GtkWidget *widget, const char *value) {
  GdkRGBA color;
  if (!omni_parse_semantic_color(value, &color)) {
    omni_set_rgba(&color, 53.0 / 255.0, 132.0 / 255.0, 228.0 / 255.0, 1.0);
  }
  OmniColorControlData *data = omni_color_control_data_from_widget(widget);
  if (data) {
    omni_color_control_set_rgba(data, &color, TRUE);
  } else {
    omni_color_swatch_set_rgba(widget, &color);
  }
  omni_accessible_value_text(widget, value);
}

static void on_color_channel_value_changed(GtkRange *range, gpointer user_data) {
  OmniColorControlData *data = (OmniColorControlData *)user_data;
  if (!data || data->updating || g_object_get_data(G_OBJECT(range), "omni-updating") != NULL) return;
  GdkRGBA color;
  omni_color_control_read_rgba(data, &color);
  omni_color_control_set_rgba(data, &color, FALSE);
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(range), "omni-app");
  if (!app && data->button) {
    app = (OmniAdwApp *)g_object_get_data(G_OBJECT(data->button), "omni-app");
  }
  omni_color_control_emit(data, app);
}

static void on_color_swatch_clicked(GtkButton *button, gpointer data) {
  OmniColorControlData *control = (OmniColorControlData *)data;
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(button), "omni-app");
  if (!app && control && control->button) {
    app = (OmniAdwApp *)g_object_get_data(G_OBJECT(control->button), "omni-app");
  }
  const char *value = (const char *)g_object_get_data(G_OBJECT(button), "omni-color-value");
  GdkRGBA color;
  if (!control || !value || !value[0] || !omni_parse_semantic_color(value, &color)) return;
  omni_color_control_set_rgba(control, &color, TRUE);
  if (GTK_IS_POPOVER(control->popover)) gtk_popover_popdown(GTK_POPOVER(control->popover));
  omni_color_control_emit(control, app);
}

static void on_calendar_pressed(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data) {
  (void)gesture;
  (void)n_press;
  (void)x;
  (void)y;
  (void)data;
}

static void on_dropdown_selected(GObject *object, GParamSpec *pspec, gpointer data) {
  GtkDropDown *dropdown = GTK_DROP_DOWN(object);
  if (g_object_get_data(G_OBJECT(dropdown), "omni-updating") != NULL) return;
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(dropdown), "omni-app");
  int32_t *action_ids = (int32_t *)g_object_get_data(G_OBJECT(dropdown), "omni-action-ids");
  int count = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(dropdown), "omni-action-count"));
  guint selected = gtk_drop_down_get_selected(dropdown);
  if (!app || !app->callback || !action_ids || selected == GTK_INVALID_LIST_POSITION || selected >= (guint)count) return;
  GListModel *model = gtk_drop_down_get_model(dropdown);
  if (GTK_IS_STRING_LIST(model)) {
    const char *label = gtk_string_list_get_string(GTK_STRING_LIST(model), selected);
    omni_accessible_value_text(GTK_WIDGET(dropdown), label);
  }
  int32_t action_id = action_ids[selected];
  if (action_id > 0) {
    omni_dispatch_action_callback(app, action_id);
    omni_flush_pending_ui(app);
  }
}

static void omni_entry_cancel_pending_text_commit(GtkWidget *widget) {
  if (!widget) return;
  guint source = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(widget), "omni-pending-text-source"));
  if (source != 0) {
    g_source_remove(source);
    g_object_set_data(G_OBJECT(widget), "omni-pending-text-source", NULL);
  }
}

static void omni_entry_commit_text_now(GtkWidget *widget) {
  if (!widget || !GTK_IS_EDITABLE(widget)) return;
  omni_entry_cancel_pending_text_commit(widget);
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(widget), "omni-app");
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id"));
  if (!app || !app->text_callback || action_id <= 0) return;
  const char *pending = (const char *)g_object_get_data(G_OBJECT(widget), "omni-pending-text-value");
  const char *text = pending ? pending : gtk_editable_get_text(GTK_EDITABLE(widget));
  if (!text) text = "";
  app->text_callback(action_id, text, app->context);
  g_object_set_data(G_OBJECT(widget), "omni-pending-text-value", NULL);
}

static GtkWidget *omni_entry_widget_for_editable(GtkEditable *editable) {
  if (!editable) return NULL;
  GtkWidget *widget = GTK_WIDGET(editable);
  GtkWidget *current = widget;
  while (current) {
    if (GTK_IS_ENTRY(current)) return current;
    current = gtk_widget_get_parent(current);
  }
  return widget;
}

static gboolean on_entry_text_commit_timeout(gpointer data) {
  GtkWidget *widget = GTK_WIDGET(data);
  if (widget) {
    g_object_set_data(G_OBJECT(widget), "omni-pending-text-source", NULL);
    omni_entry_commit_text_now(widget);
  }
  return G_SOURCE_REMOVE;
}

static void omni_entry_schedule_text_commit(GtkWidget *widget) {
  if (!widget || !GTK_IS_ENTRY(widget)) return;
  omni_entry_cancel_pending_text_commit(widget);
  const char *text = gtk_editable_get_text(GTK_EDITABLE(widget));
  g_object_set_data_full(G_OBJECT(widget), "omni-pending-text-value", g_strdup(text ? text : ""), g_free);
  guint source = g_timeout_add_full(
    G_PRIORITY_DEFAULT,
    OMNI_ENTRY_TEXT_COMMIT_DELAY_MS,
    on_entry_text_commit_timeout,
    g_object_ref(widget),
    g_object_unref
  );
  g_object_set_data(G_OBJECT(widget), "omni-pending-text-source", GUINT_TO_POINTER(source));
}

static void on_menu_option_clicked(GtkButton *button, gpointer data) {
  GtkPopover *popover = GTK_POPOVER(data);
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(button), "omni-app");
  if (!app) {
    GtkWidget *owner = GTK_WIDGET(g_object_get_data(G_OBJECT(button), "omni-owner"));
    if (owner) app = (OmniAdwApp *)g_object_get_data(G_OBJECT(owner), "omni-app");
  }
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "omni-action-id"));
  omni_accessible_value_text(GTK_WIDGET(button), gtk_button_get_label(button));
  if (popover) gtk_popover_popdown(popover);
  if (app && app->callback && action_id > 0) {
    omni_app_commit_active_text(app);
    omni_dispatch_action_callback(app, action_id);
    omni_flush_pending_ui(app);
  }
}

static void omni_context_menu_popover_owner_data_free(gpointer data) {
  GtkWidget *popover = (GtkWidget *)data;
  if (!popover) return;
  if (gtk_widget_get_parent(popover)) gtk_widget_unparent(popover);
  g_object_unref(popover);
}

static void on_context_menu_pressed(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data) {
  (void)data;
  if (n_press != 1) return;
  guint button = gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(gesture));
  if (button != GDK_BUTTON_SECONDARY) return;
  GtkWidget *owner = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(gesture));
  if (!owner) return;
  GtkPopover *popover = GTK_POPOVER(g_object_get_data(G_OBJECT(owner), "omni-context-menu-popover"));
  if (!popover) return;
  GdkRectangle rect = { (int)x, (int)y, 1, 1 };
  gtk_popover_set_pointing_to(popover, &rect);
  gtk_popover_popup(popover);
  gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_CLAIMED);
}

static gboolean widget_is_descendant_of(GtkWidget *widget, GtkWidget *ancestor) {
  GtkWidget *current = widget;
  while (current) {
    if (current == ancestor) return TRUE;
    current = gtk_widget_get_parent(current);
  }
  return FALSE;
}

static void on_entry_changed(GtkEditable *editable, gpointer data) {
  GtkWidget *widget = omni_entry_widget_for_editable(editable);
  if (!widget) return;
  if (g_object_get_data(G_OBJECT(widget), "omni-updating") != NULL) return;
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(widget), "omni-app");
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id"));
  if (app && action_id > 0) app->focused_action_id = action_id;
  omni_accessible_value_text(widget, gtk_editable_get_text(GTK_EDITABLE(widget)));
  omni_macos_accessibility_schedule(app);
  if (g_object_get_data(G_OBJECT(widget), "omni-modal-native-entry") != NULL) return;
  if (app && app->text_callback && action_id > 0) {
    if (app->modal_accessibility_root && widget_is_descendant_of(widget, app->modal_accessibility_root)) {
      omni_entry_cancel_pending_text_commit(widget);
      app->text_callback(action_id, gtk_editable_get_text(GTK_EDITABLE(widget)), app->context);
    } else {
      omni_entry_schedule_text_commit(widget);
    }
  }
}

static void on_entry_activate(GtkEntry *entry, gpointer data) {
  GtkWidget *widget = GTK_WIDGET(entry);
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(widget), "omni-app");
  if (!app || !app->key_callback) return;
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id"));
  if (action_id <= 0) action_id = app->focused_action_id;
  if (action_id > 0) app->focused_action_id = action_id;
  omni_entry_commit_text_now(widget);
  omni_dispatch_key_callback(app, action_id, 7, 0);
  omni_flush_pending_ui(app);
}

static void on_text_buffer_changed(GtkTextBuffer *buffer, gpointer data) {
  GtkWidget *text_view = GTK_WIDGET(data);
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(text_view), "omni-app");
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(text_view), "omni-action-id"));
  if (!app || !app->text_callback) return;

  GtkTextIter start;
  GtkTextIter end;
  gtk_text_buffer_get_start_iter(buffer, &start);
  gtk_text_buffer_get_end_iter(buffer, &end);
  char *text = gtk_text_buffer_get_text(buffer, &start, &end, FALSE);
  omni_accessible_value_text(text_view, text);
  omni_macos_accessibility_schedule(app);
  app->text_callback(action_id, text ? text : "", app->context);
  g_free(text);
}

static void on_focus_enter(GtkEventControllerFocus *controller, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  GtkWidget *widget = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(controller));
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id"));
  if (app && action_id > 0 && app->focused_action_id != action_id) {
    app->focused_action_id = action_id;
    if (app->focus_callback) app->focus_callback(action_id, app->context);
  }
}

static void on_text_widget_pressed(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  GtkWidget *widget = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(gesture));
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id"));
  if (app && action_id > 0 && app->focused_action_id != action_id) {
    app->focused_action_id = action_id;
    if (app->focus_callback) app->focus_callback(action_id, app->context);
  }
}

static GtkWidget *app_focused_native_text_widget(OmniAdwApp *app) {
  if (!app || !app->window) return NULL;
  GtkWidget *focus = gtk_window_get_focus(GTK_WINDOW(app->window));
  while (focus) {
    if (GTK_IS_ENTRY(focus) || GTK_IS_TEXT_VIEW(focus)) return focus;
    focus = gtk_widget_get_parent(focus);
  }
  return NULL;
}

gboolean omni_adw_app_handle_macos_text_input(void *app_ptr, const char *characters) {
  OmniAdwApp *app = (OmniAdwApp *)app_ptr;
  if (!app || !characters || !characters[0]) return FALSE;
  if (!g_utf8_validate(characters, -1, NULL)) return FALSE;
  for (const char *cursor = characters; cursor && *cursor; cursor = g_utf8_next_char(cursor)) {
    gunichar scalar = g_utf8_get_char(cursor);
    if (scalar < 32 || scalar == 127) return FALSE;
  }

  GtkWidget *native_text = app_focused_native_text_widget(app);
  if (!native_text || !GTK_IS_ENTRY(native_text)) return FALSE;

  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(native_text), "omni-action-id"));
  if (action_id > 0) app->focused_action_id = action_id;

  GtkEditable *editable = GTK_EDITABLE(native_text);
  int position = gtk_editable_get_position(editable);
  if (position < 0) position = (int)g_utf8_strlen(gtk_editable_get_text(editable), -1);
  gtk_editable_insert_text(editable, characters, -1, &position);
  gtk_editable_set_position(editable, position);
  return TRUE;
}

static GtkWidget *app_modal_native_text_widget(OmniAdwApp *app) {
  if (!app || !app->modal_dialog) return NULL;
  GtkWidget *entry = (GtkWidget *)g_object_get_data(G_OBJECT(app->modal_dialog), "omni-modal-entry");
  if (entry && (GTK_IS_ENTRY(entry) || GTK_IS_TEXT_VIEW(entry))) return entry;
  if (app->modal_accessibility_root) {
    GtkWidget *focused = find_focused_entry_widget(app->modal_accessibility_root);
    if (focused) return focused;
    GtkWidget *first = find_first_entry_widget(app->modal_accessibility_root);
    if (first) return first;
  }
  return NULL;
}

static void omni_app_commit_active_text(OmniAdwApp *app) {
  if (!app) return;
  GtkWidget *native_text = app_focused_native_text_widget(app);
  if (!native_text) native_text = app_modal_native_text_widget(app);
  if (native_text && GTK_IS_ENTRY(native_text)) {
    omni_entry_commit_text_now(native_text);
  }
}

static GtkWidget *controller_native_text_widget(GtkEventControllerKey *controller) {
  if (!controller) return NULL;
  GtkWidget *widget = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(controller));
  while (widget) {
    if (GTK_IS_ENTRY(widget) || GTK_IS_TEXT_VIEW(widget)) return widget;
    widget = gtk_widget_get_parent(widget);
  }
  return NULL;
}

static gboolean handle_entry_readline_key(OmniAdwApp *app, GtkWidget *widget, guint keyval, GdkModifierType state) {
  if (!app || !GTK_IS_ENTRY(widget) || (state & GDK_CONTROL_MASK) == 0) return FALSE;
  GtkEditable *editable = GTK_EDITABLE(widget);
  const char *text = gtk_editable_get_text(editable);
  if (!text) text = "";
  int pos = gtk_editable_get_position(editable);
  int chars = (int)g_utf8_strlen(text, -1);
  if (pos < 0) pos = 0;
  if (pos > chars) pos = chars;

  switch (keyval) {
    case GDK_KEY_a:
    case GDK_KEY_A:
      gtk_editable_set_position(editable, 0);
      return TRUE;
    case GDK_KEY_e:
    case GDK_KEY_E:
      gtk_editable_set_position(editable, -1);
      return TRUE;
    case GDK_KEY_k:
    case GDK_KEY_K: {
      const char *cut = g_utf8_offset_to_pointer(text, pos);
      char *next = g_strndup(text, (gsize)(cut - text));
      gtk_editable_set_text(editable, next ? next : "");
      gtk_editable_set_position(editable, pos);
      g_free(next);
      return TRUE;
    }
    case GDK_KEY_u:
    case GDK_KEY_U: {
      const char *keep = g_utf8_offset_to_pointer(text, pos);
      gtk_editable_set_text(editable, keep ? keep : "");
      gtk_editable_set_position(editable, 0);
      return TRUE;
    }
    default:
      return FALSE;
  }
}

static gboolean omni_entry_insert_printable_key(GtkWidget *widget, guint keyval, GdkModifierType state) {
  if (!GTK_IS_ENTRY(widget)) return FALSE;
  if ((state & (GDK_CONTROL_MASK | GDK_ALT_MASK | GDK_META_MASK | GDK_SUPER_MASK)) != 0) return FALSE;
  guint unicode = gdk_keyval_to_unicode(keyval);
  if (unicode < 32 || unicode == 127) return FALSE;

  char text[8] = {0};
  int length = g_unichar_to_utf8(unicode, text);
  if (length <= 0) return FALSE;
  text[length] = '\0';

  GtkEditable *editable = GTK_EDITABLE(widget);
  int position = gtk_editable_get_position(editable);
  if (position < 0) position = (int)g_utf8_strlen(gtk_editable_get_text(editable), -1);
  gtk_editable_insert_text(editable, text, length, &position);
  gtk_editable_set_position(editable, position);
  gtk_widget_grab_focus(widget);
  return TRUE;
}

static gboolean omni_adw_is_modifier_key(guint keyval) {
  switch (keyval) {
    case GDK_KEY_Shift_L:
    case GDK_KEY_Shift_R:
    case GDK_KEY_Control_L:
    case GDK_KEY_Control_R:
    case GDK_KEY_Alt_L:
    case GDK_KEY_Alt_R:
    case GDK_KEY_Meta_L:
    case GDK_KEY_Meta_R:
    case GDK_KEY_Super_L:
    case GDK_KEY_Super_R:
      return TRUE;
    default:
      return FALSE;
  }
}

static gboolean on_key_pressed(GtkEventControllerKey *controller, guint keyval, guint keycode, GdkModifierType state, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app || !app->key_callback) return FALSE;
  (void)keycode;

  if (!omni_adw_is_modifier_key(keyval) &&
      (state & (GDK_META_MASK | GDK_CONTROL_MASK | GDK_ALT_MASK | GDK_SUPER_MASK)) == 0) {
    GtkWidget *early_controller_text = controller_native_text_widget(controller);
    GtkWidget *early_focused_text = app_focused_native_text_widget(app);
    GtkWidget *early_modal_text = (!early_controller_text && !early_focused_text) ? app_modal_native_text_widget(app) : NULL;
    GtkWidget *early_native_text = early_controller_text ? early_controller_text : (early_focused_text ? early_focused_text : early_modal_text);
    if (early_native_text) {
      int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(early_native_text), "omni-action-id"));
      if (action_id <= 0) action_id = app->focused_action_id;
      int32_t native_kind = -1;
      switch (keyval) {
        case GDK_KEY_Return:
        case GDK_KEY_KP_Enter:
          native_kind = 7;
          break;
        case GDK_KEY_Escape:
          native_kind = 8;
          break;
        case GDK_KEY_Up:
          native_kind = 9;
          break;
        case GDK_KEY_Down:
          native_kind = 10;
          break;
        default:
          break;
      }
      if (native_kind >= 0) {
        if (native_kind == 7) omni_entry_commit_text_now(early_native_text);
        omni_dispatch_key_callback(app, action_id, native_kind, 0);
        omni_flush_pending_ui(app);
        return TRUE;
      }
      if (early_modal_text && omni_entry_insert_printable_key(early_native_text, keyval, state)) {
        if (action_id > 0) app->focused_action_id = action_id;
        return TRUE;
      }
      return FALSE;
    }
  }

  if (omni_adw_is_modifier_key(keyval)) {
    if (omni_adw_dispatch_native_event(app, OMNI_ADW_EVENT_FLAGS_CHANGED, 0, 0, 0, state, keyval)) return TRUE;
  } else if (omni_adw_dispatch_native_event(app, OMNI_ADW_EVENT_KEY_DOWN, 0, 0, 0, state, keyval)) {
    return TRUE;
  }

  if ((state & (GDK_META_MASK | GDK_CONTROL_MASK)) != 0 && keyval == GDK_KEY_comma) {
    request_settings_refresh_and_present(app);
    return TRUE;
  }

  GtkWidget *controller_text = controller_native_text_widget(controller);
  GtkWidget *focused_text = app_focused_native_text_widget(app);
  GtkWidget *modal_text = (!controller_text && !focused_text) ? app_modal_native_text_widget(app) : NULL;
  GtkWidget *native_text = controller_text ? controller_text : (focused_text ? focused_text : modal_text);
  if (native_text) {
    if (handle_entry_readline_key(app, native_text, keyval, state)) return TRUE;
    int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(native_text), "omni-action-id"));
    if (action_id <= 0) action_id = app->focused_action_id;
    int32_t native_kind = -1;
    switch (keyval) {
      case GDK_KEY_Return:
      case GDK_KEY_KP_Enter:
        native_kind = 7;
        break;
      case GDK_KEY_Escape:
        native_kind = 8;
        break;
      case GDK_KEY_Up:
        native_kind = 9;
        break;
      case GDK_KEY_Down:
        native_kind = 10;
        break;
      default:
        break;
    }
    if (native_kind >= 0) {
      if (native_kind == 7) omni_entry_commit_text_now(native_text);
      omni_dispatch_key_callback(app, action_id, native_kind, 0);
      omni_flush_pending_ui(app);
      return TRUE;
    }
    if (modal_text && omni_entry_insert_printable_key(native_text, keyval, state)) {
      if (action_id > 0) app->focused_action_id = action_id;
      return TRUE;
    }
    return FALSE;
  }

  if (keyval == GDK_KEY_Return || keyval == GDK_KEY_KP_Enter) {
    omni_dispatch_key_callback(app, app->focused_action_id > 0 ? app->focused_action_id : 0, 7, 0);
    omni_flush_pending_ui(app);
    return TRUE;
  }
  if (keyval == GDK_KEY_Escape) {
    omni_dispatch_key_callback(app, app->focused_action_id > 0 ? app->focused_action_id : 0, 8, 0);
    omni_flush_pending_ui(app);
    return TRUE;
  }

#if defined(__APPLE__)
  if (omni_macos_web_view_handle_key(keyval, state)) return TRUE;
#endif

  if (app->focused_action_id <= 0) return FALSE;

  if ((state & GDK_CONTROL_MASK) != 0) {
    GtkWidget *focused_widget = find_widget_for_action(app->window, app->focused_action_id);
    if (focused_widget && handle_entry_readline_key(app, focused_widget, keyval, state)) return TRUE;
  }

  int32_t kind = -1;
  uint32_t codepoint = 0;
  switch (keyval) {
    case GDK_KEY_BackSpace:
      kind = 1;
      break;
    case GDK_KEY_Delete:
      kind = 2;
      break;
    case GDK_KEY_Left:
      kind = 3;
      break;
    case GDK_KEY_Right:
      kind = 4;
      break;
    case GDK_KEY_Home:
      kind = 5;
      break;
    case GDK_KEY_End:
      kind = 6;
      break;
    case GDK_KEY_Up:
      kind = 9;
      break;
    case GDK_KEY_Down:
      kind = 10;
      break;
    default:
      if ((state & (GDK_CONTROL_MASK | GDK_ALT_MASK | GDK_META_MASK | GDK_SUPER_MASK)) == 0) {
        guint unicode = gdk_keyval_to_unicode(keyval);
        if (unicode >= 32 && unicode != 127) {
          kind = 0;
          codepoint = unicode;
        }
      }
      break;
  }

  if (kind < 0) return FALSE;
  omni_dispatch_key_callback(app, app->focused_action_id, kind, codepoint);
  return TRUE;
}

static void on_key_released(GtkEventControllerKey *controller, guint keyval, guint keycode, GdkModifierType state, gpointer data) {
  (void)controller;
  (void)keycode;
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app || !omni_adw_is_modifier_key(keyval)) return;
  omni_adw_dispatch_native_event(app, OMNI_ADW_EVENT_FLAGS_CHANGED, 0, 0, 0, state, keyval);
}

static void on_window_click_pressed(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data) {
  if (n_press != 1) return;
  OmniAdwApp *app = (OmniAdwApp *)data;
  guint button = gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(gesture));
  int32_t event_type = button == GDK_BUTTON_SECONDARY ? OMNI_ADW_EVENT_RIGHT_MOUSE_DOWN : OMNI_ADW_EVENT_LEFT_MOUSE_DOWN;
  GdkModifierType state = omni_adw_current_controller_state(GTK_EVENT_CONTROLLER(gesture));
  guint action_payload = 0;
  GtkWidget *window = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(gesture));
  GtkWidget *picked = window ? gtk_widget_pick(window, x, y, GTK_PICK_DEFAULT) : NULL;
  if (app && app->app_menu_surface && gtk_widget_get_visible(app->app_menu_surface)) {
    gboolean menu_hit = omni_point_in_widget_bounds(app->app_menu_surface, window, x, y);
    gboolean button_hit = omni_point_in_widget_bounds(app->app_menu_button, window, x, y);
    if (menu_hit) {
      omni_record_click_start(gesture, x, y);
      return;
    }
    if (!button_hit && !omni_widget_is_or_descendant(picked, app->app_menu_surface) &&
        !omni_widget_is_or_descendant(picked, app->app_menu_button)) {
      omni_app_menu_hide(app);
    }
  }
  gboolean native_interactive = omni_widget_or_parent_is_native_interactive(picked);
  if (native_interactive) {
    omni_record_click_start(gesture, x, y);
    return;
  }
  GtkWidget *action_widget = picked;
  if (button != GDK_BUTTON_PRIMARY) return;
  while (action_widget) {
    int drag_action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(action_widget), "omni-drag-source-action-id"));
    if (drag_action_id > 0) {
      action_payload = (guint)drag_action_id;
      break;
    }
    action_widget = gtk_widget_get_parent(action_widget);
  }
  action_widget = action_payload > 0 ? NULL : picked;
  while (action_widget) {
    int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(action_widget), "omni-action-id"));
    if (action_id > 0) {
      action_payload = (guint)action_id;
      break;
    }
    action_widget = gtk_widget_get_parent(action_widget);
  }
  if (omni_adw_dispatch_native_event(app, event_type, x, y, n_press, state, action_payload)) {
    if (!native_interactive) gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_CLAIMED);
    return;
  }
  omni_record_click_start(gesture, x, y);
}

static void on_window_click_released(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data) {
  if (!omni_click_is_stationary(gesture, x, y)) return;
  OmniAdwApp *app = (OmniAdwApp *)data;
  guint button = gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(gesture));
  GtkWidget *window = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(gesture));
  GtkWidget *picked = window ? gtk_widget_pick(window, x, y, GTK_PICK_DEFAULT) : NULL;
  if (app && app->app_menu_surface &&
      omni_point_in_widget_bounds(app->app_menu_surface, window, x, y)) {
    return;
  }
  gboolean native_interactive = omni_widget_or_parent_is_native_interactive(picked);
  if (native_interactive) return;
  if (button != GDK_BUTTON_PRIMARY) return;
  GtkWidget *action_widget = picked;
  while (action_widget) {
    int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(action_widget), "omni-action-id"));
    if (action_id > 0 && (GTK_IS_BUTTON(action_widget) || GTK_IS_CHECK_BUTTON(action_widget) || GTK_IS_MENU_BUTTON(action_widget))) {
      return;
    }
    if (action_id > 0 && GTK_IS_LIST_BOX_ROW(action_widget)) {
      int required_click_count = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(action_widget), "omni-required-click-count"));
      if (required_click_count <= 0) required_click_count = 1;
      if (required_click_count != n_press) return;
      if (app && app->callback) {
        omni_dispatch_action_callback(app, action_id);
        omni_flush_pending_ui(app);
        gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_CLAIMED);
        return;
      }
    }
    action_widget = gtk_widget_get_parent(action_widget);
  }
  // Modal outside-click handling belongs to the AdwDialog controller installed
  // on the sheet itself. Closing from the window capture phase makes ordinary
  // clicks on Search/Cancel buttons race with the dialog dismissal path.
}

static void on_window_motion(GtkEventControllerMotion *controller, double x, double y, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  GdkModifierType state = omni_adw_current_controller_state(GTK_EVENT_CONTROLLER(controller));
  omni_adw_dispatch_native_event(app, OMNI_ADW_EVENT_MOUSE_MOVED, x, y, 0, state, 0);
}

static gboolean on_window_scroll(GtkEventControllerScroll *controller, double dx, double dy, gpointer data) {
  GtkWidget *picked = omni_current_event_picked_widget(GTK_EVENT_CONTROLLER(controller));
  if (omni_widget_or_parent_is_native_scrollable(picked)) return FALSE;
  OmniAdwApp *app = (OmniAdwApp *)data;
  GdkModifierType state = omni_adw_current_controller_state(GTK_EVENT_CONTROLLER(controller));
  return omni_adw_dispatch_native_event(app, OMNI_ADW_EVENT_SCROLL_WHEEL, dx, dy, 0, state, 0);
}

static void wire_actions(GtkWidget *widget, OmniAdwApp *app) {
  if (!widget) return;
  if (GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id")) > 0 || g_object_get_data(G_OBJECT(widget), "omni-context-menu-popover") != NULL || GTK_IS_BUTTON(widget) || GTK_IS_CHECK_BUTTON(widget) || GTK_IS_ENTRY(widget) || GTK_IS_TEXT_VIEW(widget) || GTK_IS_DROP_DOWN(widget) || GTK_IS_COLOR_BUTTON(widget) || GTK_IS_MENU_BUTTON(widget) || GTK_IS_SCALE(widget) || GTK_IS_SPIN_BUTTON(widget) || GTK_IS_CALENDAR(widget) || GTK_IS_LIST_VIEW(widget) || GTK_IS_LIST_BOX(widget) || ADW_IS_ACTION_ROW(widget) || ADW_IS_EXPANDER_ROW(widget) || ADW_IS_SWITCH_ROW(widget)) {
    g_object_set_data(G_OBJECT(widget), "omni-app", app);
  }
  if (GTK_IS_LIST_VIEW(widget) || GTK_IS_LIST_BOX(widget)) {
    sidebar_apply_saved_collapse_state(widget, app);
  }
  if (ADW_IS_OVERLAY_SPLIT_VIEW(widget)) {
    app->active_split_view = widget;
    adw_overlay_split_view_set_show_sidebar(ADW_OVERLAY_SPLIT_VIEW(widget), app->sidebar_show_sidebar);
    if (!g_object_get_data(G_OBJECT(widget), "omni-sidebar-notify-installed")) {
      g_signal_connect(widget, "notify::show-sidebar", G_CALLBACK(on_split_show_sidebar_notify), app);
      g_object_set_data(G_OBJECT(widget), "omni-sidebar-notify-installed", GINT_TO_POINTER(1));
    }
  }
  if (GTK_IS_MENU_BUTTON(widget)) {
    GtkPopover *popover = gtk_menu_button_get_popover(GTK_MENU_BUTTON(widget));
    if (popover) {
      wire_actions(GTK_WIDGET(popover), app);
      wire_actions(gtk_popover_get_child(popover), app);
    }
  }
  if ((GTK_IS_ENTRY(widget) || GTK_IS_TEXT_VIEW(widget)) && !g_object_get_data(G_OBJECT(widget), "omni-focus-controller-installed")) {
    GtkEventController *focus_controller = gtk_event_controller_focus_new();
    g_signal_connect(focus_controller, "enter", G_CALLBACK(on_focus_enter), app);
    gtk_widget_add_controller(widget, focus_controller);
    GtkGesture *click_controller = gtk_gesture_click_new();
    g_signal_connect(click_controller, "pressed", G_CALLBACK(on_text_widget_pressed), app);
    gtk_widget_add_controller(widget, GTK_EVENT_CONTROLLER(click_controller));
    GtkEventController *key_controller = gtk_event_controller_key_new();
    gtk_event_controller_set_propagation_phase(key_controller, GTK_PHASE_CAPTURE);
    g_signal_connect(key_controller, "key-pressed", G_CALLBACK(on_key_pressed), app);
    g_signal_connect(key_controller, "key-released", G_CALLBACK(on_key_released), app);
    gtk_widget_add_controller(widget, key_controller);
    g_object_set_data(G_OBJECT(widget), "omni-focus-controller-installed", GINT_TO_POINTER(1));
  }
  if (GTK_IS_CALENDAR(widget) && !g_object_get_data(G_OBJECT(widget), "omni-scroll-capture-installed")) {
    GtkGesture *click_controller = gtk_gesture_click_new();
    gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(click_controller), GTK_PHASE_CAPTURE);
    g_signal_connect(click_controller, "pressed", G_CALLBACK(on_calendar_pressed), app);
    gtk_widget_add_controller(widget, GTK_EVENT_CONTROLLER(click_controller));
    g_object_set_data(G_OBJECT(widget), "omni-scroll-capture-installed", GINT_TO_POINTER(1));
  }
  if (GTK_IS_SCROLLED_WINDOW(widget) && !g_object_get_data(G_OBJECT(widget), "omni-macos-scroll-accessibility-installed")) {
    GtkAdjustment *vadjustment = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(widget));
    GtkAdjustment *hadjustment = gtk_scrolled_window_get_hadjustment(GTK_SCROLLED_WINDOW(widget));
    if (vadjustment) g_signal_connect(vadjustment, "value-changed", G_CALLBACK(on_scroll_adjustment_value_changed), app);
    if (hadjustment) g_signal_connect(hadjustment, "value-changed", G_CALLBACK(on_scroll_adjustment_value_changed), app);
    g_object_set_data(G_OBJECT(widget), "omni-macos-scroll-accessibility-installed", GINT_TO_POINTER(1));
  }
  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child) {
    wire_actions(child, app);
    child = gtk_widget_get_next_sibling(child);
  }
}

static GtkWidget *find_widget_for_action(GtkWidget *widget, int32_t action_id) {
  if (!widget || action_id <= 0) return NULL;
  int widget_action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id"));
  if (widget_action_id == action_id) return widget;

  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child) {
    GtkWidget *found = find_widget_for_action(child, action_id);
    if (found) return found;
    child = gtk_widget_get_next_sibling(child);
  }
  return NULL;
}

static GtkWidget *find_widget_for_name(GtkWidget *widget, const char *name) {
  if (!widget || !name || !name[0]) return NULL;
  const char *widget_name = gtk_widget_get_name(widget);
  if (widget_name && strcmp(widget_name, name) == 0) return widget;

  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child) {
    GtkWidget *found = find_widget_for_name(child, name);
    if (found) return found;
    child = gtk_widget_get_next_sibling(child);
  }
  return NULL;
}

static int32_t first_widget_action_id(GtkWidget *widget) {
  if (!widget) return 0;
  int32_t action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id"));
  if (action_id > 0) return action_id;

  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child) {
    action_id = first_widget_action_id(child);
    if (action_id > 0) return action_id;
    child = gtk_widget_get_next_sibling(child);
  }
  return 0;
}

static int32_t first_widget_required_click_count(GtkWidget *widget) {
  if (!widget) return 1;
  int32_t click_count = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-required-click-count"));
  if (click_count > 0) return click_count;

  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child) {
    click_count = first_widget_required_click_count(child);
    if (click_count > 1) return click_count;
    child = gtk_widget_get_next_sibling(child);
  }
  return 1;
}

static const char *first_widget_accessible_label(GtkWidget *widget) {
  if (!widget) return NULL;
  const char *label = (const char *)g_object_get_data(G_OBJECT(widget), "omni-accessible-label");
  if (label && label[0]) return label;

  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child) {
    label = first_widget_accessible_label(child);
    if (label && label[0]) return label;
    child = gtk_widget_get_next_sibling(child);
  }
  return NULL;
}

static int32_t first_action_id_with_accessible_label(GtkWidget *widget, const char *wanted) {
  if (!widget || !wanted || !wanted[0]) return 0;
  int32_t action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id"));
  const char *label = (const char *)g_object_get_data(G_OBJECT(widget), "omni-accessible-label");
  if (action_id > 0 && label && strcmp(label, wanted) == 0) return action_id;

  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child) {
    action_id = first_action_id_with_accessible_label(child, wanted);
    if (action_id > 0) return action_id;
    child = gtk_widget_get_next_sibling(child);
  }
  return 0;
}

#if defined(__APPLE__)
typedef struct {
  double x;
  double y;
} OmniAXPoint;

typedef struct {
  double width;
  double height;
} OmniAXSize;

typedef struct {
  OmniAXPoint origin;
  OmniAXSize size;
} OmniAXRect;

static char omni_macos_accessibility_widget_key;
static char omni_macos_accessibility_app_key;
static char omni_macos_accessibility_name_key;
static char omni_macos_accessibility_action_id_key;
static char omni_macos_accessibility_traits_key;
static char omni_macos_accessibility_value_key;

enum {
  OMNI_AX_TRAIT_ENTRY = 1 << 0,
  OMNI_AX_TRAIT_TEXT_VIEW = 1 << 1,
  OMNI_AX_TRAIT_DROPDOWN = 1 << 2,
  OMNI_AX_TRAIT_SCROLL_AREA = 1 << 3
};

static id omni_ns_string(const char *value);
static id omni_ns_string_or_empty(const char *value);
static id omni_ns_number(int value);
static int omni_ns_number_int(id value);
static id omni_ns_mutable_array(void);
static void omni_ns_array_add(id array, id object);
static const char *omni_macos_widget_value(GtkWidget *widget);
static gboolean omni_macos_accessibility_is_action_widget(GtkWidget *widget);

static OmniAXRect omni_ax_rect_make(double x, double y, double width, double height) {
  OmniAXRect rect;
  rect.origin.x = x;
  rect.origin.y = y;
  rect.size.width = width;
  rect.size.height = height;
  return rect;
}

static id omni_objc_send_id(id receiver, const char *selector) {
  if (!receiver || !selector) return nil;
  return ((id (*)(id, SEL))objc_msgSend)(receiver, sel_registerName(selector));
}

static void omni_objc_send_void_id(id receiver, const char *selector, id value) {
  if (!receiver || !selector) return;
  ((void (*)(id, SEL, id))objc_msgSend)(receiver, sel_registerName(selector), value);
}

static void omni_objc_send_void_bool(id receiver, const char *selector, BOOL value) {
  if (!receiver || !selector) return;
  ((void (*)(id, SEL, BOOL))objc_msgSend)(receiver, sel_registerName(selector), value);
}

static OmniAXRect omni_objc_send_rect(id receiver, const char *selector) {
  if (!receiver || !selector) return omni_ax_rect_make(0.0, 0.0, 0.0, 0.0);
  return ((OmniAXRect (*)(id, SEL))objc_msgSend)(receiver, sel_registerName(selector));
}

static OmniAdwApp *omni_app_for_widget(GtkWidget *widget) {
  GtkWidget *current = widget;
  while (current) {
    OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(current), "omni-app");
    if (app) return app;
    current = gtk_widget_get_parent(current);
  }
  return NULL;
}

static int omni_macos_accessibility_traits(id self) {
  return omni_ns_number_int(objc_getAssociatedObject(self, &omni_macos_accessibility_traits_key));
}

static int omni_macos_accessibility_action_id(id self) {
  return omni_ns_number_int(objc_getAssociatedObject(self, &omni_macos_accessibility_action_id_key));
}

static OmniAdwApp *omni_macos_accessibility_app(id self) {
  return (OmniAdwApp *)objc_getAssociatedObject(self, &omni_macos_accessibility_app_key);
}

static GtkWidget *omni_macos_accessibility_associated_widget(id self) {
  return (GtkWidget *)objc_getAssociatedObject(self, &omni_macos_accessibility_widget_key);
}

static gboolean omni_widget_tree_contains_pointer(GtkWidget *root, GtkWidget *needle) {
  if (!root || !needle) return FALSE;
  if (root == needle) return TRUE;
  GtkWidget *child = gtk_widget_get_first_child(root);
  while (child) {
    if (omni_widget_tree_contains_pointer(child, needle)) return TRUE;
    child = gtk_widget_get_next_sibling(child);
  }
  return FALSE;
}

static GtkWidget *omni_macos_accessibility_resolve_widget(id self) {
  OmniAdwApp *app = omni_macos_accessibility_app(self);
  if (!app) return NULL;
  GtkWidget *associated = omni_macos_accessibility_associated_widget(self);
  if (associated) {
    if (app->settings_window && omni_widget_tree_contains_pointer(app->settings_window, associated)) return associated;
    if (app->window && omni_widget_tree_contains_pointer(app->window, associated)) return associated;
    if (app->modal_accessibility_root && omni_widget_tree_contains_pointer(app->modal_accessibility_root, associated)) return associated;
    if (app->modal_dialog && omni_widget_tree_contains_pointer(GTK_WIDGET(app->modal_dialog), associated)) return associated;
  }
  int actionID = omni_macos_accessibility_action_id(self);

  if (actionID > 0) {
    if (app->settings_window && GTK_IS_WIDGET(app->settings_window)) {
      GtkWidget *found = find_widget_for_action(app->settings_window, actionID);
      if (found) return found;
    }
    if (app->modal_accessibility_root && GTK_IS_WIDGET(app->modal_accessibility_root)) {
      GtkWidget *found = find_widget_for_action(app->modal_accessibility_root, actionID);
      if (found) return found;
    }
    if (app->modal_dialog && GTK_IS_WIDGET(app->modal_dialog)) {
      GtkWidget *found = find_widget_for_action(GTK_WIDGET(app->modal_dialog), actionID);
      if (found) return found;
    }
    if (app->window) {
      GtkWidget *found = find_widget_for_action(app->window, actionID);
      if (found) return found;
    }
  }

  id nameObject = objc_getAssociatedObject(self, &omni_macos_accessibility_name_key);
  const char *name = nameObject ? ((const char *(*)(id, SEL))objc_msgSend)(nameObject, sel_registerName("UTF8String")) : NULL;
  if (name && name[0]) {
    if (app->settings_window && GTK_IS_WIDGET(app->settings_window)) {
      GtkWidget *found = find_widget_for_name(app->settings_window, name);
      if (found) return found;
    }
    if (app->modal_accessibility_root && GTK_IS_WIDGET(app->modal_accessibility_root)) {
      GtkWidget *found = find_widget_for_name(app->modal_accessibility_root, name);
      if (found) return found;
    }
    if (app->modal_dialog && GTK_IS_WIDGET(app->modal_dialog)) {
      GtkWidget *found = find_widget_for_name(GTK_WIDGET(app->modal_dialog), name);
      if (found) return found;
    }
    if (app->window) {
      GtkWidget *found = find_widget_for_name(app->window, name);
      if (found) return found;
    }
  }

  return NULL;
}

static double omni_macos_accessibility_clamp_adjustment(GtkAdjustment *adjustment, double value) {
  double lower = gtk_adjustment_get_lower(adjustment);
  double upper = gtk_adjustment_get_upper(adjustment);
  double page_size = gtk_adjustment_get_page_size(adjustment);
  double max_value = upper - page_size;
  if (max_value < lower) max_value = lower;
  if (value < lower) return lower;
  if (value > max_value) return max_value;
  return value;
}

static BOOL omni_macos_accessibility_scroll_adjustment(GtkAdjustment *adjustment, int direction) {
  if (!adjustment) return NO;
  double value = gtk_adjustment_get_value(adjustment);
  double page = gtk_adjustment_get_page_increment(adjustment);
  if (page <= 0.0) page = gtk_adjustment_get_page_size(adjustment) * 0.82;
  if (page <= 0.0) page = 160.0;
  double next = omni_macos_accessibility_clamp_adjustment(
    adjustment,
    value + (direction >= 0 ? page : -page)
  );
  if (next == value) return NO;
  gtk_adjustment_set_value(adjustment, next);
  return YES;
}

static BOOL omni_macos_accessibility_scroll_widget(GtkWidget *widget, int direction, gboolean horizontal) {
  if (!widget) return NO;
  if (g_object_get_data(G_OBJECT(widget), "omni-macos-web-view")) {
    if (horizontal) return omni_macos_web_view_widget_scroll(widget, direction >= 0 ? 320.0 : -320.0, 0.0) ? YES : NO;
    return omni_macos_web_view_widget_scroll_page(widget, direction) ? YES : NO;
  }
  if (!GTK_IS_SCROLLED_WINDOW(widget)) return NO;
  GtkAdjustment *adjustment = horizontal
    ? gtk_scrolled_window_get_hadjustment(GTK_SCROLLED_WINDOW(widget))
    : gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(widget));
  return omni_macos_accessibility_scroll_adjustment(adjustment, direction);
}

static BOOL omni_macos_accessibility_perform_scroll(id self, int direction, gboolean horizontal) {
  GtkWidget *widget = omni_macos_accessibility_associated_widget(self);
  BOOL didScroll = omni_macos_accessibility_scroll_widget(widget, direction, horizontal);
  if (!didScroll) {
    widget = omni_macos_accessibility_resolve_widget(self);
    didScroll = omni_macos_accessibility_scroll_widget(widget, direction, horizontal);
  }
  OmniAdwApp *app = omni_macos_accessibility_app(self);
  if (!app && widget) app = omni_app_for_widget(widget);
  if (didScroll && app) omni_macos_accessibility_schedule_after_scroll(app);
  return didScroll;
}

static BOOL omni_macos_accessibility_perform_scroll_down(id self, SEL _cmd) {
  (void)_cmd;
  return omni_macos_accessibility_perform_scroll(self, 1, FALSE);
}

static BOOL omni_macos_accessibility_perform_scroll_up(id self, SEL _cmd) {
  (void)_cmd;
  return omni_macos_accessibility_perform_scroll(self, -1, FALSE);
}

static BOOL omni_macos_accessibility_perform_scroll_right(id self, SEL _cmd) {
  (void)_cmd;
  return omni_macos_accessibility_perform_scroll(self, 1, TRUE);
}

static BOOL omni_macos_accessibility_perform_scroll_left(id self, SEL _cmd) {
  (void)_cmd;
  return omni_macos_accessibility_perform_scroll(self, -1, TRUE);
}

static BOOL omni_macos_accessibility_perform_increment(id self, SEL _cmd) {
  (void)_cmd;
  return omni_macos_accessibility_perform_scroll(self, 1, FALSE);
}

static BOOL omni_macos_accessibility_perform_decrement(id self, SEL _cmd) {
  (void)_cmd;
  return omni_macos_accessibility_perform_scroll(self, -1, FALSE);
}

static BOOL omni_macos_accessibility_perform_press(id self, SEL _cmd) {
  (void)_cmd;
  GtkWidget *widget = omni_macos_accessibility_resolve_widget(self);
  OmniAdwApp *app = omni_macos_accessibility_app(self);
  if (!widget) {
    int actionID = omni_macos_accessibility_action_id(self);
    if (!app || !app->callback || actionID <= 0) return NO;
    omni_dispatch_action_callback(app, actionID);
    omni_flush_pending_ui(app);
    return YES;
  }
  if (GTK_IS_ENTRY(widget) || GTK_IS_TEXT_VIEW(widget)) {
    gtk_widget_grab_focus(widget);
    return YES;
  }
  if (!app) app = omni_app_for_widget(widget);
  if (GTK_IS_BUTTON(widget)) {
    g_signal_emit_by_name(widget, "clicked");
    if (app) omni_flush_pending_ui(app);
    return YES;
  }
  if (GTK_IS_MENU_BUTTON(widget)) {
    gtk_menu_button_popup(GTK_MENU_BUTTON(widget));
    return YES;
  }
  if (GTK_IS_DROP_DOWN(widget)) {
    gtk_widget_grab_focus(widget);
    gtk_widget_activate(widget);
    if (app) omni_macos_accessibility_schedule(app);
    return YES;
  }
  if (GTK_IS_CHECK_BUTTON(widget)) {
    gboolean active = gtk_check_button_get_active(GTK_CHECK_BUTTON(widget));
    gtk_check_button_set_active(GTK_CHECK_BUTTON(widget), !active);
    if (app) omni_flush_pending_ui(app);
    return YES;
  }
  int actionID = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id"));
  if (!app || !app->callback || actionID <= 0) return NO;
  omni_dispatch_action_callback(app, actionID);
  omni_flush_pending_ui(app);
  return YES;
}

static void omni_macos_accessibility_set_value(id self, SEL _cmd, id value) {
  (void)_cmd;
  GtkWidget *widget = omni_macos_accessibility_resolve_widget(self);
  if (!widget || !value) return;
  const char *text = ((const char *(*)(id, SEL))objc_msgSend)(value, sel_registerName("UTF8String"));
  if (!text) text = "";
  int traits = omni_macos_accessibility_traits(self);
  if ((traits & OMNI_AX_TRAIT_ENTRY) && omni_entry_is_secure(widget)) {
    char *masked = omni_mask_text(text);
    objc_setAssociatedObject(self, &omni_macos_accessibility_value_key, omni_ns_string_or_empty(masked), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    free(masked);
  } else {
    objc_setAssociatedObject(self, &omni_macos_accessibility_value_key, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }
  if ((traits & OMNI_AX_TRAIT_ENTRY) && GTK_IS_EDITABLE(widget)) {
    gtk_editable_set_text(GTK_EDITABLE(widget), text);
    gtk_widget_grab_focus(widget);
    omni_accessible_value_text(widget, text);
    OmniAdwApp *app = omni_macos_accessibility_app(self);
    if (!app) app = omni_app_for_widget(widget);
    omni_entry_commit_text_now(widget);
    if (app) omni_macos_accessibility_schedule(app);
  } else if ((traits & OMNI_AX_TRAIT_TEXT_VIEW) && GTK_IS_TEXT_VIEW(widget)) {
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(widget));
    gtk_text_buffer_set_text(buffer, text, -1);
    gtk_widget_grab_focus(widget);
    omni_accessible_value_text(widget, text);
    OmniAdwApp *app = omni_macos_accessibility_app(self);
    if (!app) app = omni_app_for_widget(widget);
    int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id"));
    if (app && app->text_callback && action_id > 0) app->text_callback(action_id, text, app->context);
    if (app) omni_macos_accessibility_schedule(app);
  } else if ((traits & OMNI_AX_TRAIT_DROPDOWN) && GTK_IS_DROP_DOWN(widget)) {
    GListModel *model = gtk_drop_down_get_model(GTK_DROP_DOWN(widget));
    if (!GTK_IS_STRING_LIST(model)) return;
    guint count = g_list_model_get_n_items(model);
    for (guint i = 0; i < count; i++) {
      const char *item = gtk_string_list_get_string(GTK_STRING_LIST(model), i);
      if (item && strcmp(item, text) == 0) {
        OmniAdwApp *app = omni_macos_accessibility_app(self);
        if (!app) app = omni_app_for_widget(widget);
        int32_t action_id = 0;
        int32_t *action_ids = (int32_t *)g_object_get_data(G_OBJECT(widget), "omni-action-ids");
        int action_count = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-count"));
        if (action_ids && i < (guint)action_count) action_id = action_ids[i];
        if (gtk_drop_down_get_selected(GTK_DROP_DOWN(widget)) != i) {
          g_object_set_data(G_OBJECT(widget), "omni-updating", GINT_TO_POINTER(1));
          gtk_drop_down_set_selected(GTK_DROP_DOWN(widget), i);
          g_object_set_data(G_OBJECT(widget), "omni-updating", NULL);
        }
        omni_accessible_value_text(widget, item);
        if (app && app->callback && action_id > 0) {
          omni_dispatch_action_callback(app, action_id);
          omni_flush_pending_ui(app);
        } else if (app) {
          omni_macos_accessibility_schedule(app);
        }
        break;
      }
    }
  }
}

static id omni_macos_accessibility_value(id self, SEL _cmd) {
  (void)_cmd;
  GtkWidget *widget = omni_macos_accessibility_resolve_widget(self);
  int traits = omni_macos_accessibility_traits(self);
  if (widget && (traits & OMNI_AX_TRAIT_ENTRY) && GTK_IS_EDITABLE(widget)) {
    if (omni_entry_is_secure(widget)) {
      const char *masked = omni_macos_widget_value(widget);
      return omni_ns_string_or_empty(masked);
    }
    return omni_ns_string_or_empty(gtk_editable_get_text(GTK_EDITABLE(widget)));
  }
  if (widget && (traits & OMNI_AX_TRAIT_TEXT_VIEW) && GTK_IS_TEXT_VIEW(widget)) {
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(widget));
    GtkTextIter start;
    GtkTextIter end;
    gtk_text_buffer_get_start_iter(buffer, &start);
    gtk_text_buffer_get_end_iter(buffer, &end);
    char *text = gtk_text_buffer_get_text(buffer, &start, &end, FALSE);
    id value = omni_ns_string_or_empty(text);
    g_free(text);
    return value;
  }
  if (widget && (traits & OMNI_AX_TRAIT_DROPDOWN) && GTK_IS_DROP_DOWN(widget)) {
    const char *value = omni_macos_widget_value(widget);
    return omni_ns_string_or_empty(value);
  }
  return objc_getAssociatedObject(self, &omni_macos_accessibility_value_key);
}

static BOOL omni_macos_accessibility_is_attribute_settable(id self, SEL _cmd, id attribute) {
  (void)_cmd;
  if (!attribute) return NO;
  const char *name = ((const char *(*)(id, SEL))objc_msgSend)(attribute, sel_registerName("UTF8String"));
  if (!name || strcmp(name, "AXValue") != 0) return NO;
  int traits = omni_macos_accessibility_traits(self);
  return (traits & (OMNI_AX_TRAIT_ENTRY | OMNI_AX_TRAIT_TEXT_VIEW | OMNI_AX_TRAIT_DROPDOWN)) != 0;
}

static id omni_macos_accessibility_attribute_value(id self, SEL _cmd, id attribute) {
  (void)_cmd;
  if (!attribute) return nil;
  const char *name = ((const char *(*)(id, SEL))objc_msgSend)(attribute, sel_registerName("UTF8String"));
  if (name && strcmp(name, "AXValue") == 0) {
    return omni_macos_accessibility_value(self, sel_registerName("accessibilityValue"));
  }
  return nil;
}

static void omni_macos_accessibility_set_attribute_value(id self, SEL _cmd, id value, id attribute) {
  (void)_cmd;
  if (!attribute) return;
  const char *name = ((const char *(*)(id, SEL))objc_msgSend)(attribute, sel_registerName("UTF8String"));
  if (name && strcmp(name, "AXValue") == 0) {
    omni_macos_accessibility_set_value(self, sel_registerName("setAccessibilityValue:"), value);
  }
}

static id omni_macos_accessibility_attribute_names(id self, SEL _cmd) {
  (void)_cmd;
  id names = omni_ns_mutable_array();
  if (!names) return nil;
  omni_ns_array_add(names, omni_ns_string("AXRole"));
  omni_ns_array_add(names, omni_ns_string("AXTitle"));
  omni_ns_array_add(names, omni_ns_string("AXDescription"));
  omni_ns_array_add(names, omni_ns_string("AXHelp"));
  omni_ns_array_add(names, omni_ns_string("AXEnabled"));
  omni_ns_array_add(names, omni_ns_string("AXFocused"));
  omni_ns_array_add(names, omni_ns_string("AXIdentifier"));
  omni_ns_array_add(names, omni_ns_string("AXParent"));
  omni_ns_array_add(names, omni_ns_string("AXPosition"));
  omni_ns_array_add(names, omni_ns_string("AXSize"));
  int traits = omni_macos_accessibility_traits(self);
  if ((traits & (OMNI_AX_TRAIT_ENTRY | OMNI_AX_TRAIT_TEXT_VIEW | OMNI_AX_TRAIT_DROPDOWN)) != 0) {
    omni_ns_array_add(names, omni_ns_string("AXValue"));
  }
  if ((traits & OMNI_AX_TRAIT_SCROLL_AREA) != 0) {
    omni_ns_array_add(names, omni_ns_string("AXVerticalScrollBar"));
    omni_ns_array_add(names, omni_ns_string("AXHorizontalScrollBar"));
  }
  return names;
}

static void omni_macos_accessibility_add_action_name(id actions, const char *name) {
  id value = omni_ns_string(name);
  if (value) omni_ns_array_add(actions, value);
}

static const char *omni_macos_accessibility_action_name(id action) {
  return action ? ((const char *(*)(id, SEL))objc_msgSend)(action, sel_registerName("UTF8String")) : NULL;
}

static gboolean omni_macos_accessibility_widget_can_press(GtkWidget *widget) {
  if (!widget) return FALSE;
  return omni_macos_accessibility_is_action_widget(widget) ||
    GTK_IS_EDITABLE(widget) ||
    GTK_IS_TEXT_VIEW(widget) ||
    GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id")) > 0;
}

static id omni_macos_accessibility_action_names(id self, SEL _cmd) {
  (void)_cmd;
  id actions = omni_ns_mutable_array();
  GtkWidget *widget = omni_macos_accessibility_resolve_widget(self);
  if (!widget) widget = omni_macos_accessibility_associated_widget(self);
  int traits = omni_macos_accessibility_traits(self);
  if ((traits & OMNI_AX_TRAIT_SCROLL_AREA) != 0) {
    omni_macos_accessibility_add_action_name(actions, "AXScrollDown");
    omni_macos_accessibility_add_action_name(actions, "AXScrollUp");
    omni_macos_accessibility_add_action_name(actions, "AXScrollRight");
    omni_macos_accessibility_add_action_name(actions, "AXScrollLeft");
    omni_macos_accessibility_add_action_name(actions, "AXIncrement");
    omni_macos_accessibility_add_action_name(actions, "AXDecrement");
  }
  if (omni_macos_accessibility_widget_can_press(widget)) {
    omni_macos_accessibility_add_action_name(actions, "AXPress");
  }
  return actions;
}

static void omni_macos_accessibility_perform_action(id self, SEL _cmd, id action) {
  (void)_cmd;
  const char *name = omni_macos_accessibility_action_name(action);
  if (!name) return;
  if (strcmp(name, "AXScrollDown") == 0) {
    (void)omni_macos_accessibility_perform_scroll(self, 1, FALSE);
  } else if (strcmp(name, "AXScrollUp") == 0) {
    (void)omni_macos_accessibility_perform_scroll(self, -1, FALSE);
  } else if (strcmp(name, "AXScrollRight") == 0) {
    (void)omni_macos_accessibility_perform_scroll(self, 1, TRUE);
  } else if (strcmp(name, "AXScrollLeft") == 0) {
    (void)omni_macos_accessibility_perform_scroll(self, -1, TRUE);
  } else if (strcmp(name, "AXIncrement") == 0) {
    (void)omni_macos_accessibility_perform_scroll(self, 1, FALSE);
  } else if (strcmp(name, "AXDecrement") == 0) {
    (void)omni_macos_accessibility_perform_scroll(self, -1, FALSE);
  } else if (strcmp(name, "AXPress") == 0) {
    (void)omni_macos_accessibility_perform_press(self, sel_registerName("accessibilityPerformPress"));
  }
}

static id omni_macos_accessibility_element_class(void) {
  static id elementClass = nil;
  if (elementClass) return elementClass;
  Class baseClass = (Class)objc_getClass("NSAccessibilityElement");
  Class customClass = objc_allocateClassPair(baseClass, "OmniAdwaitaAccessibilityElement", 0);
  if (customClass) {
    class_addMethod(
      customClass,
      sel_registerName("accessibilityPerformPress"),
      (IMP)omni_macos_accessibility_perform_press,
      "c@:"
    );
    class_addMethod(
      customClass,
      sel_registerName("accessibilityActionNames"),
      (IMP)omni_macos_accessibility_action_names,
      "@@:"
    );
    class_addMethod(
      customClass,
      sel_registerName("accessibilityPerformAction:"),
      (IMP)omni_macos_accessibility_perform_action,
      "v@:@"
    );
    class_addMethod(
      customClass,
      sel_registerName("accessibilityPerformScrollDown"),
      (IMP)omni_macos_accessibility_perform_scroll_down,
      "c@:"
    );
    class_addMethod(
      customClass,
      sel_registerName("accessibilityPerformScrollUp"),
      (IMP)omni_macos_accessibility_perform_scroll_up,
      "c@:"
    );
    class_addMethod(
      customClass,
      sel_registerName("accessibilityPerformScrollRight"),
      (IMP)omni_macos_accessibility_perform_scroll_right,
      "c@:"
    );
    class_addMethod(
      customClass,
      sel_registerName("accessibilityPerformScrollLeft"),
      (IMP)omni_macos_accessibility_perform_scroll_left,
      "c@:"
    );
    class_addMethod(
      customClass,
      sel_registerName("accessibilityPerformIncrement"),
      (IMP)omni_macos_accessibility_perform_increment,
      "c@:"
    );
    class_addMethod(
      customClass,
      sel_registerName("accessibilityPerformDecrement"),
      (IMP)omni_macos_accessibility_perform_decrement,
      "c@:"
    );
    class_addMethod(
      customClass,
      sel_registerName("setAccessibilityValue:"),
      (IMP)omni_macos_accessibility_set_value,
      "v@:@"
    );
    class_addMethod(
      customClass,
      sel_registerName("accessibilityValue"),
      (IMP)omni_macos_accessibility_value,
      "@@:"
    );
	    class_addMethod(
	      customClass,
	      sel_registerName("accessibilityIsAttributeSettable:"),
	      (IMP)omni_macos_accessibility_is_attribute_settable,
	      "c@:@"
	    );
	    class_addMethod(
	      customClass,
	      sel_registerName("isAccessibilityAttributeSettable:"),
	      (IMP)omni_macos_accessibility_is_attribute_settable,
	      "c@:@"
	    );
	    class_addMethod(
	      customClass,
	      sel_registerName("accessibilityAttributeValue:"),
	      (IMP)omni_macos_accessibility_attribute_value,
	      "@@:@"
	    );
	    class_addMethod(
	      customClass,
	      sel_registerName("accessibilityAttributeNames"),
	      (IMP)omni_macos_accessibility_attribute_names,
	      "@@:"
	    );
	    class_addMethod(
	      customClass,
	      sel_registerName("accessibilitySetValue:forAttribute:"),
	      (IMP)omni_macos_accessibility_set_attribute_value,
	      "v@:@@"
	    );
	    class_addMethod(
	      customClass,
	      sel_registerName("setAccessibilityValue:forAttribute:"),
	      (IMP)omni_macos_accessibility_set_attribute_value,
	      "v@:@@"
	    );
    objc_registerClassPair(customClass);
    elementClass = (id)customClass;
  } else {
    elementClass = (id)objc_getClass("OmniAdwaitaAccessibilityElement");
  }
  return elementClass ? elementClass : (id)baseClass;
}

static id omni_ns_string(const char *value) {
  if (!value || !value[0]) return nil;
  id stringClass = (id)objc_getClass("NSString");
  return ((id (*)(id, SEL, const char *))objc_msgSend)(stringClass, sel_registerName("stringWithUTF8String:"), value);
}

static id omni_ns_string_or_empty(const char *value) {
  id stringClass = (id)objc_getClass("NSString");
  if (!stringClass) return nil;
  return ((id (*)(id, SEL, const char *))objc_msgSend)(stringClass, sel_registerName("stringWithUTF8String:"), value ? value : "");
}

static id omni_ns_number(int value) {
  id numberClass = (id)objc_getClass("NSNumber");
  if (!numberClass) return nil;
  return ((id (*)(id, SEL, int))objc_msgSend)(numberClass, sel_registerName("numberWithInt:"), value);
}

static int omni_ns_number_int(id value) {
  if (!value) return 0;
  return ((int (*)(id, SEL))objc_msgSend)(value, sel_registerName("intValue"));
}

static id omni_ns_mutable_array(void) {
  id arrayClass = (id)objc_getClass("NSMutableArray");
  return omni_objc_send_id(arrayClass, "array");
}

static void omni_ns_array_add(id array, id object) {
  if (!array || !object) return;
  ((void (*)(id, SEL, id))objc_msgSend)(array, sel_registerName("addObject:"), object);
}

static id omni_macos_accessibility_window(OmniAdwApp *app) {
  id nsApp = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSApplication"), sel_registerName("sharedApplication"));
  id keyWindow = omni_objc_send_id(nsApp, "keyWindow");
  if (keyWindow) return keyWindow;
  id windows = omni_objc_send_id(nsApp, "windows");
  unsigned long count = windows ? ((unsigned long (*)(id, SEL))objc_msgSend)(windows, sel_registerName("count")) : 0;
  const char *wantedTitle = app && app->title ? app->title : NULL;
  for (unsigned long i = 0; i < count; i++) {
    id window = ((id (*)(id, SEL, unsigned long))objc_msgSend)(windows, sel_registerName("objectAtIndex:"), i);
    if (!wantedTitle || !wantedTitle[0]) return window;
    id title = omni_objc_send_id(window, "title");
    const char *titleText = title ? ((const char *(*)(id, SEL))objc_msgSend)(title, sel_registerName("UTF8String")) : NULL;
    if (titleText && strcmp(titleText, wantedTitle) == 0) return window;
  }
  return nil;
}

static const char *omni_macos_accessibility_role(GtkWidget *widget) {
  if (!widget) return "AXGroup";
  if (g_object_get_data(G_OBJECT(widget), "omni-macos-web-view")) return "AXScrollArea";
  if (GTK_IS_EDITABLE(widget)) return "AXTextField";
  if (GTK_IS_TEXT_VIEW(widget)) return "AXTextArea";
  if (GTK_IS_CHECK_BUTTON(widget)) return "AXCheckBox";
  if (GTK_IS_DROP_DOWN(widget)) return "AXPopUpButton";
  if (GTK_IS_BUTTON(widget) || GTK_IS_MENU_BUTTON(widget)) return "AXButton";
  if (GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id")) > 0) return "AXButton";
  if (GTK_IS_LIST_BOX_ROW(widget) && GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id")) > 0) return "AXButton";
  if (GTK_IS_LIST_BOX_ROW(widget)) return "AXRow";
  if (GTK_IS_SCROLLED_WINDOW(widget)) return "AXScrollArea";
  if (GTK_IS_LIST_VIEW(widget) || GTK_IS_LIST_BOX(widget)) return "AXList";
  if (GTK_IS_LABEL(widget)) return "AXStaticText";
  if (GTK_IS_SEPARATOR(widget)) return "AXSplitter";
  return "AXGroup";
}

static gboolean omni_macos_accessibility_is_action_widget(GtkWidget *widget) {
  if (!widget) return FALSE;
  if (GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id")) > 0) return TRUE;
  return GTK_IS_BUTTON(widget) || GTK_IS_MENU_BUTTON(widget) || GTK_IS_DROP_DOWN(widget) || GTK_IS_CHECK_BUTTON(widget);
}

static gboolean omni_macos_accessibility_has_exported_action_ancestor(GtkWidget *widget) {
  GtkWidget *parent = widget ? gtk_widget_get_parent(widget) : NULL;
  while (parent) {
    if (omni_macos_accessibility_is_action_widget(parent)) return TRUE;
    if (GTK_IS_LIST_BOX_ROW(parent) && GPOINTER_TO_INT(g_object_get_data(G_OBJECT(parent), "omni-action-id")) > 0) return TRUE;
    parent = gtk_widget_get_parent(parent);
  }
  return FALSE;
}

static gboolean omni_macos_accessibility_has_exported_row_ancestor(GtkWidget *widget) {
  GtkWidget *parent = widget ? gtk_widget_get_parent(widget) : NULL;
  while (parent) {
    if (GTK_IS_LIST_BOX_ROW(parent)) return TRUE;
    if (GTK_IS_LIST_VIEW(parent) || GTK_IS_LIST_BOX(parent)) return FALSE;
    parent = gtk_widget_get_parent(parent);
  }
  return FALSE;
}

static gboolean omni_macos_accessibility_should_export(GtkWidget *widget) {
  if (!widget || !gtk_widget_get_visible(widget) || !gtk_widget_get_mapped(widget)) return FALSE;
  if (g_object_get_data(G_OBJECT(widget), "omni-macos-web-view")) return TRUE;
  if (GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id")) > 0) return TRUE;
  if (GTK_IS_EDITABLE(widget) || GTK_IS_TEXT_VIEW(widget) || GTK_IS_BUTTON(widget) || GTK_IS_MENU_BUTTON(widget) || GTK_IS_DROP_DOWN(widget) || GTK_IS_CHECK_BUTTON(widget)) return TRUE;
  if (GTK_IS_SCROLLED_WINDOW(widget) || GTK_IS_LIST_VIEW(widget) || GTK_IS_LIST_BOX(widget) || GTK_IS_LIST_BOX_ROW(widget)) return TRUE;
  const char *label = (const char *)g_object_get_data(G_OBJECT(widget), "omni-accessible-label");
  if (label != NULL) {
    if (GTK_IS_LABEL(widget) && omni_macos_accessibility_has_exported_action_ancestor(widget)) return FALSE;
    if (GTK_IS_LABEL(widget) && omni_macos_accessibility_has_exported_row_ancestor(widget)) return FALSE;
    if (GTK_IS_LABEL(widget)) return TRUE;
    return FALSE;
  }
  return FALSE;
}

static const char *omni_macos_widget_label(GtkWidget *widget) {
  const char *label = widget ? (const char *)g_object_get_data(G_OBJECT(widget), "omni-accessible-label") : NULL;
  if (label && label[0]) return label;
  if (GTK_IS_BUTTON(widget)) {
    label = gtk_button_get_label(GTK_BUTTON(widget));
    if (label && label[0]) return label;
  }
  if (GTK_IS_CHECK_BUTTON(widget)) {
    label = gtk_check_button_get_label(GTK_CHECK_BUTTON(widget));
    if (label && label[0]) return label;
  }
  if (GTK_IS_ENTRY(widget)) {
    label = gtk_entry_get_placeholder_text(GTK_ENTRY(widget));
    if (label && label[0]) return label;
  }
  if (GTK_IS_LABEL(widget)) {
    label = gtk_label_get_text(GTK_LABEL(widget));
    if (label && label[0]) return label;
  }
  return first_widget_accessible_label(widget);
}

static const char *omni_macos_widget_value(GtkWidget *widget) {
  if (GTK_IS_EDITABLE(widget)) {
    if (omni_entry_is_secure(widget)) {
      const char *masked = (const char *)g_object_get_data(G_OBJECT(widget), "omni-accessible-value");
      return masked && masked[0] ? masked : NULL;
    }
    return gtk_editable_get_text(GTK_EDITABLE(widget));
  }
  const char *value = (const char *)g_object_get_data(G_OBJECT(widget), "omni-accessible-value");
  return value && value[0] ? value : NULL;
}

static void omni_macos_accessibility_add_widget(
  GtkWidget *widget,
  GtkWidget *root,
  id parent,
  id elements,
  OmniAXRect windowFrame,
  OmniAXRect contentFrame,
  int *count
) {
  if (!widget || !root || !elements || !count || *count >= OMNI_MACOS_ACCESSIBILITY_MAX_ELEMENTS) return;
  if (!gtk_widget_get_visible(widget)) return;

  if (gtk_widget_get_mapped(widget) && omni_macos_accessibility_should_export(widget)) {
    graphene_rect_t bounds;
    if (gtk_widget_compute_bounds(widget, root, &bounds) && bounds.size.width >= 2.0f && bounds.size.height >= 2.0f) {
      const char *label = omni_macos_widget_label(widget);
      if (label && label[0]) {
        double x = windowFrame.origin.x + contentFrame.origin.x + bounds.origin.x;
        double y = windowFrame.origin.y + contentFrame.origin.y + contentFrame.size.height - bounds.origin.y - bounds.size.height;
        OmniAXRect frame = omni_ax_rect_make(x, y, bounds.size.width, bounds.size.height);
        id elementClass = omni_macos_accessibility_element_class();
        id element = ((id (*)(id, SEL, id, OmniAXRect, id, id))objc_msgSend)(
          elementClass,
          sel_registerName("accessibilityElementWithRole:frame:label:parent:"),
          omni_ns_string(omni_macos_accessibility_role(widget)),
          frame,
          omni_ns_string(label),
          parent
        );
        if (element) {
          const char *description = (const char *)g_object_get_data(G_OBJECT(widget), "omni-accessible-description");
          const char *name = gtk_widget_get_name(widget);
          const char *value = omni_macos_widget_value(widget);
          int actionID = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id"));
          int traits = 0;
          if (GTK_IS_EDITABLE(widget)) traits |= OMNI_AX_TRAIT_ENTRY;
          if (GTK_IS_TEXT_VIEW(widget)) traits |= OMNI_AX_TRAIT_TEXT_VIEW;
          if (GTK_IS_DROP_DOWN(widget)) traits |= OMNI_AX_TRAIT_DROPDOWN;
          if (GTK_IS_SCROLLED_WINDOW(widget) || g_object_get_data(G_OBJECT(widget), "omni-macos-web-view")) traits |= OMNI_AX_TRAIT_SCROLL_AREA;
          OmniAdwApp *widgetApp = omni_app_for_widget(widget);
          objc_setAssociatedObject(element, &omni_macos_accessibility_widget_key, (id)widget, OBJC_ASSOCIATION_ASSIGN);
          objc_setAssociatedObject(element, &omni_macos_accessibility_app_key, (id)widgetApp, OBJC_ASSOCIATION_ASSIGN);
          objc_setAssociatedObject(element, &omni_macos_accessibility_action_id_key, omni_ns_number(actionID), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
          objc_setAssociatedObject(element, &omni_macos_accessibility_traits_key, omni_ns_number(traits), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
          if (name && name[0]) {
            objc_setAssociatedObject(element, &omni_macos_accessibility_name_key, omni_ns_string(name), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
          }
          if (description && description[0]) omni_objc_send_void_id(element, "setAccessibilityHelp:", omni_ns_string(description));
          if (name && name[0]) omni_objc_send_void_id(element, "setAccessibilityIdentifier:", omni_ns_string(name));
          if (GTK_IS_EDITABLE(widget) || GTK_IS_TEXT_VIEW(widget) || (value && value[0])) {
            objc_setAssociatedObject(element, &omni_macos_accessibility_value_key, omni_ns_string_or_empty(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
          }
          omni_objc_send_void_bool(element, "setAccessibilityEnabled:", gtk_widget_get_sensitive(widget) && actionID >= 0);
          omni_objc_send_void_bool(element, "setAccessibilitySelected:", GTK_IS_LIST_BOX_ROW(widget) && gtk_list_box_row_is_selected(GTK_LIST_BOX_ROW(widget)));
          if (traits & OMNI_AX_TRAIT_SCROLL_AREA) {
            omni_objc_send_void_id(element, "setAccessibilityRoleDescription:", omni_ns_string("scroll area"));
          } else if (GTK_IS_DROP_DOWN(widget)) {
            omni_objc_send_void_id(element, "setAccessibilityRoleDescription:", omni_ns_string("pop-up button"));
          } else if (GTK_IS_BUTTON(widget) || GTK_IS_MENU_BUTTON(widget) || GTK_IS_CHECK_BUTTON(widget) || GTK_IS_LIST_BOX_ROW(widget)) {
            omni_objc_send_void_id(element, "setAccessibilityRoleDescription:", omni_ns_string(actionID > 0 ? "button" : "row"));
          }
          omni_ns_array_add(elements, element);
          *count += 1;
        }
      }
    }
  }

  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child && *count < OMNI_MACOS_ACCESSIBILITY_MAX_ELEMENTS) {
    omni_macos_accessibility_add_widget(child, root, parent, elements, windowFrame, contentFrame, count);
    child = gtk_widget_get_next_sibling(child);
  }
}

static void omni_macos_accessibility_sync(OmniAdwApp *app) {
  if (!app || !app->window) return;
  id window = omni_macos_accessibility_window(app);
  id contentView = omni_objc_send_id(window, "contentView");
  if (!window || !contentView) return;

  OmniAXRect windowFrame = omni_objc_send_rect(window, "frame");
  OmniAXRect contentFrame = omni_objc_send_rect(contentView, "frame");
  if (contentFrame.size.width <= 0.0 || contentFrame.size.height <= 0.0) return;

  id elements = omni_ns_mutable_array();
  int count = 0;
  gboolean exported_modal = FALSE;
  if (app->modal_accessibility_root && GTK_IS_WIDGET(app->modal_accessibility_root)) {
    omni_macos_accessibility_add_widget(app->modal_accessibility_root, app->modal_accessibility_root, window, elements, windowFrame, contentFrame, &count);
    exported_modal = TRUE;
  } else if (app->modal_dialog) {
    if (GTK_IS_WIDGET(app->modal_dialog)) {
      omni_macos_accessibility_add_widget(GTK_WIDGET(app->modal_dialog), GTK_WIDGET(app->modal_dialog), window, elements, windowFrame, contentFrame, &count);
      exported_modal = TRUE;
    }
  }
  if (!exported_modal) {
    omni_macos_accessibility_add_widget(app->window, app->window, window, elements, windowFrame, contentFrame, &count);
  }

  omni_objc_send_void_bool(contentView, "setAccessibilityElement:", YES);
  omni_objc_send_void_id(contentView, "setAccessibilityRole:", omni_ns_string("AXGroup"));
  omni_objc_send_void_id(contentView, "setAccessibilityLabel:", omni_ns_string("GTK content"));
  omni_objc_send_void_id(contentView, "setAccessibilityChildren:", elements);
  omni_objc_send_void_id(contentView, "setAccessibilityChildrenInNavigationOrder:", elements);
}

static gboolean omni_macos_accessibility_sync_idle(gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (app) app->macos_accessibility_sync_source = 0;
  omni_macos_accessibility_sync(app);
  return G_SOURCE_REMOVE;
}

static void omni_macos_accessibility_cancel_pending(OmniAdwApp *app) {
  if (!app || app->macos_accessibility_sync_source == 0) return;
  g_source_remove(app->macos_accessibility_sync_source);
  app->macos_accessibility_sync_source = 0;
}

static void omni_macos_accessibility_schedule(OmniAdwApp *app) {
  if (!app) return;
  omni_macos_accessibility_cancel_pending(app);
  app->macos_accessibility_sync_source = g_idle_add(omni_macos_accessibility_sync_idle, app);
}

static gboolean omni_macos_accessibility_sync_delayed(gpointer data) {
  omni_macos_accessibility_schedule((OmniAdwApp *)data);
  return G_SOURCE_REMOVE;
}

static void omni_macos_accessibility_schedule_after_map(OmniAdwApp *app) {
  if (!app) return;
  omni_macos_accessibility_schedule(app);
  g_timeout_add(75, omni_macos_accessibility_sync_delayed, app);
  g_timeout_add(200, omni_macos_accessibility_sync_delayed, app);
}

static void omni_macos_accessibility_schedule_after_scroll(OmniAdwApp *app) {
  if (!app) return;
  if (app->macos_accessibility_sync_source != 0) return;
  GSource *source = g_timeout_source_new(350);
  g_source_set_callback(source, omni_macos_accessibility_sync_idle, app, NULL);
  app->macos_accessibility_sync_source = g_source_attach(source, NULL);
  g_source_unref(source);
}
#else
static void omni_macos_accessibility_sync(OmniAdwApp *app) {
  (void)app;
}

static void omni_macos_accessibility_cancel_pending(OmniAdwApp *app) {
  (void)app;
}

static void omni_macos_accessibility_schedule(OmniAdwApp *app) {
  (void)app;
}

static void omni_macos_accessibility_schedule_after_map(OmniAdwApp *app) {
  (void)app;
}

static void omni_macos_accessibility_schedule_after_scroll(OmniAdwApp *app) {
  (void)app;
}
#endif

OmniAdwApp *omni_adw_app_new(const char *app_id, const char *title, omni_adw_action_callback callback, omni_adw_text_callback text_callback, omni_adw_key_callback key_callback, omni_adw_focus_callback focus_callback, void *context) {
  omni_install_log_filter_once();
  gtk_init();
  adw_init();
  omni_install_css_once();
  if (g_getenv("OMNIKIT_ADWAITA_ENTRY_TRACE")) g_printerr("[OmniKit CAdwaita] after css\n");
  OmniAdwApp *app = calloc(1, sizeof(OmniAdwApp));
  app->title = omni_strdup(title);
  app->callback = callback;
  app->text_callback = text_callback;
  app->key_callback = key_callback;
  app->focus_callback = focus_callback;
  app->context = context;
  app->default_width = 1100;
  app->default_height = 760;
  app->sidebar_show_sidebar = TRUE;
  app->sidebar_collapsed_items = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
  app->tab_count = 1;
  app->active_tab = 0;
  app->application = adw_application_new(app_id ? app_id : "dev.omnikit.OmniUIAdwaita", G_APPLICATION_DEFAULT_FLAGS);
  g_signal_connect(app->application, "activate", G_CALLBACK(on_app_activate), app);
  return app;
}

void omni_adw_app_share_url(OmniAdwApp *app, const char *url) {
  if (!app || !url || !url[0]) return;
#if defined(__APPLE__)
  id nsString = omni_ns_string(url);
  id urlClass = (id)objc_getClass("NSURL");
  id nsURL = nsString ? ((id (*)(id, SEL, id))objc_msgSend)(urlClass, sel_registerName("URLWithString:"), nsString) : nil;
  if (nsURL) {
    id arrayClass = (id)objc_getClass("NSArray");
    id items = ((id (*)(id, SEL, id))objc_msgSend)(arrayClass, sel_registerName("arrayWithObject:"), nsURL);
    id pickerClass = (id)objc_getClass("NSSharingServicePicker");
    id picker = pickerClass ? ((id (*)(id, SEL))objc_msgSend)(pickerClass, sel_registerName("alloc")) : nil;
    picker = picker ? ((id (*)(id, SEL, id))objc_msgSend)(picker, sel_registerName("initWithItems:"), items) : nil;
    id window = omni_macos_accessibility_window(app);
    id contentView = omni_objc_send_id(window, "contentView");
    if (picker && contentView) {
      OmniAXRect bounds = omni_objc_send_rect(contentView, "bounds");
      OmniAXRect anchor = omni_ax_rect_make(bounds.size.width - 72.0, 18.0, 44.0, 34.0);
      ((void (*)(id, SEL, OmniAXRect, id, long))objc_msgSend)(picker, sel_registerName("showRelativeToRect:ofView:preferredEdge:"), anchor, contentView, 1L);
      return;
    }
  }
#endif
#if defined(__linux__)
  {
    char *argv[] = { "xdg-open", (char *)url, NULL };
    GError *error = NULL;
    if (g_spawn_async(NULL, argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, &error)) {
      return;
    }
    if (error) g_error_free(error);
  }
#endif
  if (app->window) {
    gtk_show_uri(GTK_WINDOW(app->window), url, GDK_CURRENT_TIME);
  }
}

int32_t omni_adw_app_run(OmniAdwApp *app, int32_t argc, char **argv) {
  if (!app) return 1;
  return g_application_run(G_APPLICATION(app->application), argc, argv);
}

void omni_adw_app_set_event_callback(OmniAdwApp *app, omni_adw_event_callback event_callback) {
  if (!app) return;
  app->event_callback = event_callback;
}

void omni_adw_app_set_lifecycle_callback(OmniAdwApp *app, omni_adw_lifecycle_callback lifecycle_callback) {
  if (!app) return;
  app->lifecycle_callback = lifecycle_callback;
}

static gboolean omni_adw_tick_bridge_fire(gpointer data) {
  OmniAdwTickBridge *bridge = (OmniAdwTickBridge *)data;
  if (bridge && bridge->callback) bridge->callback(bridge->context);
  return G_SOURCE_CONTINUE;
}

uint32_t omni_adw_app_add_tick_callback(OmniAdwApp *app, int32_t interval_ms, omni_adw_tick_callback callback, void *context) {
  (void)app;
  if (!callback) return 0;
  OmniAdwTickBridge *bridge = calloc(1, sizeof(OmniAdwTickBridge));
  if (!bridge) return 0;
  bridge->callback = callback;
  bridge->context = context;
  return g_timeout_add_full(
      G_PRIORITY_DEFAULT,
      interval_ms > 0 ? (guint)interval_ms : 16,
      omni_adw_tick_bridge_fire,
      bridge,
      free);
}

void omni_adw_app_remove_tick_callback(uint32_t source_id) {
  if (source_id != 0) g_source_remove((guint)source_id);
}

void omni_adw_app_free(OmniAdwApp *app) {
  if (!app) return;
  if (app->pending_ui_flush_source != 0) g_source_remove(app->pending_ui_flush_source);
  if (app->macos_accessibility_sync_source != 0) g_source_remove(app->macos_accessibility_sync_source);
  if (app->modal_dismiss_source != 0) g_source_remove(app->modal_dismiss_source);
  if (app->modal_dialog) adw_dialog_force_close(app->modal_dialog);
  if (app->settings_window) gtk_window_destroy(GTK_WINDOW(app->settings_window));
  if (app->app_menu_button) g_object_unref(app->app_menu_button);
  if (app->application) g_object_unref(app->application);
  if (app->sidebar_collapsed_items) g_hash_table_destroy(app->sidebar_collapsed_items);
  free(app->title);
  free(app->header_entry_placeholder);
  free(app->header_entry_text);
  free(app);
}

void omni_adw_app_set_default_size(OmniAdwApp *app, int32_t width, int32_t height) {
  if (!app) return;
  if (width > 0) app->default_width = width;
  if (height > 0) app->default_height = height;
  if (app->window) {
    gtk_window_set_default_size(GTK_WINDOW(app->window), app->default_width, app->default_height);
  }
}

void omni_adw_app_present_main_window(OmniAdwApp *app) {
  if (!app || !app->window) return;
  gtk_window_present(GTK_WINDOW(app->window));
}

void omni_adw_app_set_cursor(OmniAdwApp *app, const char *cursor_name) {
  if (!app || !app->window) return;
  const char *name = NULL;
  if (cursor_name && cursor_name[0] && strcmp(cursor_name, "default") != 0) {
    name = cursor_name;
  }
  gtk_widget_set_cursor_from_name(app->window, name);
}

void omni_adw_app_set_header_title(OmniAdwApp *app, const char *title) {
  if (!app || !title || !title[0]) return;
  if (app->title && strcmp(app->title, title) == 0) return;
  free(app->title);
  app->title = omni_strdup(title);
  if (app->window) {
    gtk_window_set_title(GTK_WINDOW(app->window), app->title);
    omni_accessible_label(app->window, app->title);
  }
  if (app->header_title_label) {
    gtk_label_set_text(GTK_LABEL(app->header_title_label), app->title);
    omni_accessible_label(app->header_title_label, app->title);
  }
  update_header_tab_strip(app);
}

void omni_adw_app_set_header_entry(OmniAdwApp *app, const char *placeholder, const char *text, int32_t action_id) {
  if (!app) return;
  free(app->header_entry_placeholder);
  free(app->header_entry_text);
  app->header_entry_placeholder = omni_strdup(placeholder ? placeholder : "");
  app->header_entry_text = omni_strdup(text ? text : "");
  app->header_entry_action_id = action_id;
  if (app->header) {
    ensure_header_title_widget(app);
    sync_header_entry(app);
  }
}

static void omni_clear_header_action_box(GtkWidget *box) {
  if (!box) return;
  GtkWidget *child = gtk_widget_get_first_child(box);
  while (child) {
    GtkWidget *next = gtk_widget_get_next_sibling(child);
    gtk_box_remove(GTK_BOX(box), child);
    child = next;
  }
}

static GtkWidget *omni_create_header_action_button(OmniAdwApp *app, const char *label, int32_t action_id, gboolean selected, const char *description) {
  if (!app || !label || !label[0]) return NULL;
  GtkWidget *button = gtk_button_new();
  const char *icon_name = omni_symbolic_icon_name_for_label(label);
  const char *accessible = omni_accessible_label_for_symbolic_label(label);
  if (icon_name) {
    gtk_button_set_icon_name(GTK_BUTTON(button), icon_name);
    gtk_widget_add_css_class(button, "omni-icon-button");
  } else {
    gtk_button_set_label(GTK_BUTTON(button), label);
  }
  gtk_widget_add_css_class(button, "flat");
  gtk_widget_set_focusable(button, TRUE);
  gtk_widget_set_valign(button, GTK_ALIGN_CENTER);
  gtk_widget_set_tooltip_text(button, accessible ? accessible : label);
  omni_accessible_label(button, accessible ? accessible : label);
  omni_accessible_description(button, description ? description : "Toolbar action");
  if (selected) {
    gtk_widget_add_css_class(button, "omni-selected-segment");
    omni_accessible_set_selected(button, TRUE);
  }
  if (action_id > 0) {
    g_object_set_data(G_OBJECT(button), "omni-app", app);
    g_object_set_data(G_OBJECT(button), "omni-action-id", GINT_TO_POINTER(action_id));
    g_signal_connect(button, "clicked", G_CALLBACK(on_clicked), NULL);
  } else {
    gtk_widget_set_sensitive(button, FALSE);
    omni_accessible_set_disabled(button, TRUE);
  }
  return button;
}

static void omni_append_header_action(GtkWidget *box, OmniAdwApp *app, const char *label, int32_t action_id) {
  if (!box) return;
  GtkWidget *button = omni_create_header_action_button(app, label, action_id, FALSE, "Toolbar action");
  if (!button) return;
  gtk_box_append(GTK_BOX(box), button);
}

static int32_t omni_append_header_segmented_actions(GtkWidget *box, OmniAdwApp *app, const char **labels, const int32_t *action_ids, const int32_t *placements, const int32_t *styles, int32_t start, int32_t count) {
  if (!box || !app || start >= count) return 0;
  int32_t placement = placements ? placements[start] : 1;
  GtkWidget *group = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_add_css_class(group, "linked");
  gtk_widget_add_css_class(group, "omni-segmented-control");
  gtk_widget_set_valign(group, GTK_ALIGN_CENTER);
  omni_accessible_label(group, "View mode");
  omni_accessible_role_description(group, "segmented control");

  int32_t appended = 0;
  for (int32_t i = start; i < count; i++) {
    int32_t style = styles ? styles[i] : 0;
    int32_t item_placement = placements ? placements[i] : 1;
    if ((style & OMNI_HEADER_ACTION_SEGMENTED) == 0 || item_placement != placement) break;
    const char *label = labels ? labels[i] : NULL;
    int32_t action_id = action_ids ? action_ids[i] : 0;
    gboolean selected = (style & OMNI_HEADER_ACTION_SELECTED) != 0;
    GtkWidget *button = omni_create_header_action_button(app, label, action_id, selected, selected ? "Selected segmented control item" : "Segmented control item");
    if (button) {
      gtk_box_append(GTK_BOX(group), button);
      appended++;
    }
  }

  if (appended > 0) {
    gtk_box_append(GTK_BOX(box), group);
  } else {
    g_object_unref(group);
  }
  return appended;
}

void omni_adw_app_set_header_actions(OmniAdwApp *app, const char **labels, const int32_t *action_ids, const int32_t *placements, const int32_t *styles, int32_t count) {
  if (!app) return;
  if (app->header) ensure_header_title_widget(app);
  omni_clear_header_action_box(app->header_start_actions);
  omni_clear_header_action_box(app->header_end_actions);
  int32_t start_count = 0;
  int32_t end_count = 0;
  for (int32_t i = 0; i < count;) {
    const char *label = labels ? labels[i] : NULL;
    int32_t action_id = action_ids ? action_ids[i] : 0;
    int32_t placement = placements ? placements[i] : 1;
    int32_t style = styles ? styles[i] : 0;
    if ((style & OMNI_HEADER_ACTION_SEGMENTED) != 0) {
      GtkWidget *target = placement == 0 ? app->header_start_actions : app->header_end_actions;
      int32_t appended = omni_append_header_segmented_actions(target, app, labels, action_ids, placements, styles, i, count);
      if (placement == 0) {
        start_count += appended;
      } else {
        end_count += appended;
      }
      i += appended > 0 ? appended : 1;
      continue;
    }
    if (placement == 0) {
      omni_append_header_action(app->header_start_actions, app, label, action_id);
      start_count++;
    } else {
      omni_append_header_action(app->header_end_actions, app, label, action_id);
      end_count++;
    }
    i++;
  }
  if (app->header_start_actions) gtk_widget_set_visible(app->header_start_actions, start_count > 0);
  if (app->header_end_actions) gtk_widget_set_visible(app->header_end_actions, end_count > 0);
  omni_macos_accessibility_schedule(app);
}

void omni_adw_app_set_settings(OmniAdwApp *app, OmniAdwNode *settings) {
  if (!app || !settings) return;
  gboolean settings_was_visible = FALSE;
  if (app->settings_window) {
    settings_was_visible = gtk_widget_get_visible(app->settings_window);
    gtk_window_set_child(GTK_WINDOW(app->settings_window), NULL);
  }
  app->settings_content = settings->widget;
  omni_widget_expand(app->settings_content, TRUE);
  gtk_widget_set_margin_top(app->settings_content, 18);
  gtk_widget_set_margin_bottom(app->settings_content, 18);
  gtk_widget_set_margin_start(app->settings_content, 18);
  gtk_widget_set_margin_end(app->settings_content, 18);
  wire_actions(app->settings_content, app);
  if (app->settings_window) {
    gtk_window_set_child(GTK_WINDOW(app->settings_window), app->settings_content);
    if (settings_was_visible) {
      gtk_window_present(GTK_WINDOW(app->settings_window));
    }
  }
  settings->widget = NULL;
  omni_adw_node_free(settings);
}

void omni_adw_app_present_settings(OmniAdwApp *app) {
  present_settings_window(app);
}

void omni_adw_app_present_settings_on_activate(OmniAdwApp *app, int32_t enabled) {
  if (!app) return;
  app->present_settings_on_activate = enabled ? TRUE : FALSE;
}

void omni_adw_app_set_commands(OmniAdwApp *app, OmniAdwNode *commands) {
  if (!app || !commands) return;
  app->command_content = commands->widget;
  gtk_widget_set_margin_top(app->command_content, 8);
  gtk_widget_set_margin_bottom(app->command_content, 8);
  gtk_widget_set_margin_start(app->command_content, 8);
  gtk_widget_set_margin_end(app->command_content, 8);
  wire_actions(app->command_content, app);
  if (app->command_popover) {
    gtk_popover_set_child(GTK_POPOVER(app->command_popover), app->command_content);
  }
  if (app->command_button) {
    gtk_widget_set_visible(app->command_button, TRUE);
  }
  commands->widget = NULL;
  omni_adw_node_free(commands);
}

void omni_adw_app_set_root(OmniAdwApp *app, OmniAdwNode *root) {
  omni_adw_app_set_root_focused(app, root, 0);
}

void omni_adw_app_set_root_focused(OmniAdwApp *app, OmniAdwNode *root, int32_t focused_action_id) {
  if (!app || !root) return;
  app->focused_action_id = focused_action_id;
  app->content = root->widget;
  omni_widget_expand(app->content, TRUE);
  gtk_widget_set_margin_top(app->content, 0);
  gtk_widget_set_margin_bottom(app->content, 0);
  gtk_widget_set_margin_start(app->content, 0);
  gtk_widget_set_margin_end(app->content, 0);
  app->active_split_view = NULL;
  wire_actions(app->content, app);
  sync_sidebar_toggle(app);
  if (app->window) {
    gtk_window_set_focus(GTK_WINDOW(app->window), NULL);
    if (app->body_slot) {
      GtkWidget *old_child = gtk_widget_get_first_child(app->body_slot);
      while (old_child) {
        GtkWidget *next = gtk_widget_get_next_sibling(old_child);
        gtk_box_remove(GTK_BOX(app->body_slot), old_child);
        old_child = next;
      }
      gtk_box_append(GTK_BOX(app->body_slot), app->content);
    } else {
      adw_application_window_set_content(ADW_APPLICATION_WINDOW(app->window), app->content);
    }
    if (!app->key_controller) {
      app->key_controller = gtk_event_controller_key_new();
      gtk_event_controller_set_propagation_phase(app->key_controller, GTK_PHASE_CAPTURE);
      g_signal_connect(app->key_controller, "key-pressed", G_CALLBACK(on_key_pressed), app);
      g_signal_connect(app->key_controller, "key-released", G_CALLBACK(on_key_released), app);
      gtk_widget_add_controller(app->window, app->key_controller);
    }
  }
  GtkWidget *focused = find_widget_for_action(app->content, focused_action_id);
  omni_grab_focus_if_ready(focused);
  omni_queue_widget_and_ancestors_redraw(app->content);
  if (app->window) omni_queue_widget_redraw(app->window);
  omni_macos_accessibility_schedule(app);
  root->widget = NULL;
  omni_adw_node_free(root);
}

typedef struct {
  GPtrArray *labels;
  GArray *action_ids;
  GPtrArray *button_labels;
} OmniModalSummary;

static void free_modal_summary(OmniModalSummary *summary) {
  if (!summary) return;
  if (summary->labels) g_ptr_array_free(summary->labels, TRUE);
  if (summary->button_labels) g_ptr_array_free(summary->button_labels, TRUE);
  if (summary->action_ids) g_array_free(summary->action_ids, TRUE);
  free(summary);
}

static void collect_modal_summary(GtkWidget *widget, OmniModalSummary *summary) {
  if (!widget || !summary) return;
  if (GTK_IS_BUTTON(widget)) {
    const char *label = gtk_button_get_label(GTK_BUTTON(widget));
    int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id"));
    if (label && label[0] && action_id > 0) {
      g_ptr_array_add(summary->button_labels, omni_strdup(label));
      g_array_append_val(summary->action_ids, action_id);
    }
    return;
  }
  if (GTK_IS_LABEL(widget)) {
    const char *label = gtk_label_get_text(GTK_LABEL(widget));
    if (label && label[0] && summary->labels->len < 4) {
      g_ptr_array_add(summary->labels, omni_strdup(label));
    }
  }

  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child) {
    collect_modal_summary(child, summary);
    child = gtk_widget_get_next_sibling(child);
  }
}

static OmniModalSummary *modal_summary_new(GtkWidget *source) {
  OmniModalSummary *summary = calloc(1, sizeof(OmniModalSummary));
  if (!summary) return NULL;
  summary->labels = g_ptr_array_new_with_free_func(free);
  summary->action_ids = g_array_new(FALSE, FALSE, sizeof(int));
  summary->button_labels = g_ptr_array_new_with_free_func(free);
  collect_modal_summary(source, summary);
  return summary;
}

static void on_alert_response(AdwAlertDialog *dialog, const char *response, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  OmniModalSummary *summary = (OmniModalSummary *)g_object_get_data(G_OBJECT(dialog), "omni-modal-summary");
  if (app && app->callback && summary && response && response[0] == 'r') {
    int index = atoi(response + 1);
    if (index >= 0 && index < (int)summary->action_ids->len) {
      int action_id = g_array_index(summary->action_ids, int, index);
      omni_dispatch_action_callback(app, action_id);
    }
  }
  if (app && app->modal_dialog == ADW_DIALOG(dialog)) {
    app->modal_dialog = NULL;
    app->modal_accessibility_root = NULL;
    app->modal_close_action_id = 0;
    app->modal_force_closing = FALSE;
#if defined(__APPLE__)
    omni_macos_web_view_set_modal_occlusion(FALSE);
#endif
  }
}

static gboolean modal_button_label_is_close(const char *label);
static gboolean modal_button_label_is_cancel(const char *label);

static int modal_close_action_id(OmniModalSummary *summary) {
  if (!summary) return 0;
  for (guint i = 0; i < summary->button_labels->len; i++) {
    const char *label = (const char *)g_ptr_array_index(summary->button_labels, i);
    if (modal_button_label_is_close(label)) {
      return g_array_index(summary->action_ids, int, i);
    }
  }
  return 0;
}

static int modal_cancel_action_id(OmniModalSummary *summary) {
  if (!summary) return 0;
  for (guint i = 0; i < summary->button_labels->len; i++) {
    const char *label = (const char *)g_ptr_array_index(summary->button_labels, i);
    if (modal_button_label_is_cancel(label)) {
      return g_array_index(summary->action_ids, int, i);
    }
  }
  return 0;
}

static GtkWidget *find_first_entry_widget(GtkWidget *widget) {
  if (!widget) return NULL;
  if (GTK_IS_ENTRY(widget)) return widget;
  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child) {
    GtkWidget *found = find_first_entry_widget(child);
    if (found) return found;
    child = gtk_widget_get_next_sibling(child);
  }
  return NULL;
}

static GtkWidget *find_focused_entry_widget(GtkWidget *widget) {
  if (!widget) return NULL;
  if (GTK_IS_ENTRY(widget) && gtk_widget_has_focus(widget)) return widget;
  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child) {
    GtkWidget *found = find_focused_entry_widget(child);
    if (found) return found;
    child = gtk_widget_get_next_sibling(child);
  }
  return NULL;
}

static gboolean modal_button_label_is_close(const char *label) {
  return label && (g_ascii_strcasecmp(label, "Close") == 0 || g_ascii_strcasecmp(label, "Done") == 0);
}

static gboolean modal_button_label_is_cancel(const char *label) {
  return label && g_ascii_strcasecmp(label, "Cancel") == 0;
}

static void on_sheet_closed(AdwDialog *dialog, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app) return;
  if (app->modal_dialog != dialog) return;
  int action_id = app->modal_close_action_id;
  gboolean force_closing = app->modal_force_closing;
  app->modal_dialog = NULL;
  app->modal_accessibility_root = NULL;
  app->modal_close_action_id = 0;
  app->modal_force_closing = FALSE;
#if defined(__APPLE__)
  omni_macos_web_view_set_modal_occlusion(FALSE);
#endif
  if (!force_closing && action_id > 0 && app->callback) {
    omni_dispatch_action_callback(app, action_id);
    omni_flush_pending_ui(app);
  }
}

static void on_sheet_close_attempt(AdwDialog *dialog, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app || app->modal_close_action_id <= 0) return;
  adw_dialog_close(dialog);
}

static gboolean widget_contains_scrolled_window(GtkWidget *widget) {
  if (!widget || !GTK_IS_WIDGET(widget)) return FALSE;
  if (GTK_IS_SCROLLED_WINDOW(widget)) return TRUE;
  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child) {
    if (widget_contains_scrolled_window(child)) return TRUE;
    child = gtk_widget_get_next_sibling(child);
  }
  return FALSE;
}

static GtkWidget *omni_sheet_surface_new(gboolean fills_height) {
  GtkWidget *surface = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_add_css_class(surface, "omni-sheet-surface");
  gtk_widget_set_hexpand(surface, TRUE);
  gtk_widget_set_halign(surface, GTK_ALIGN_FILL);
  gtk_widget_set_vexpand(surface, fills_height ? TRUE : FALSE);
  gtk_widget_set_valign(surface, fills_height ? GTK_ALIGN_FILL : GTK_ALIGN_CENTER);
  omni_accessible_label(surface, "Sheet");
  omni_accessible_description(surface, "Modal sheet");
  return surface;
}

static gboolean omni_focus_widget_idle(gpointer data) {
  GtkWidget *widget = GTK_WIDGET(data);
  if (widget && GTK_IS_WIDGET(widget)) {
    gtk_widget_grab_focus(widget);
  }
  g_object_unref(widget);
  return G_SOURCE_REMOVE;
}

static void omni_schedule_focus_widget(GtkWidget *widget) {
  if (!widget || !GTK_IS_WIDGET(widget)) return;
  g_idle_add(omni_focus_widget_idle, g_object_ref(widget));
}

static gboolean update_presented_sheet_dialog(OmniAdwApp *app, OmniAdwNode *modal) {
  if (!app || !app->modal_dialog || !modal || !modal->widget) return FALSE;
  wire_actions(modal->widget, app);
  gboolean fills_height = widget_contains_scrolled_window(modal->widget);
  if (fills_height && !ADW_IS_ALERT_DIALOG(app->modal_dialog)) {
    adw_dialog_set_content_height(app->modal_dialog, 560);
  }
  GtkWidget *surface = omni_sheet_surface_new(fills_height);
  gtk_box_append(GTK_BOX(surface), modal->widget);
  modal->widget = NULL;
  if (ADW_IS_ALERT_DIALOG(app->modal_dialog)) {
    adw_alert_dialog_set_extra_child(ADW_ALERT_DIALOG(app->modal_dialog), surface);
  } else {
    adw_dialog_set_child(app->modal_dialog, surface);
  }
  g_object_set_data(G_OBJECT(app->modal_dialog), "omni-sheet-content-widget", surface);
  app->modal_accessibility_root = surface;
  omni_macos_accessibility_schedule_after_map(app);
  return TRUE;
}

static void present_sheet_dialog(OmniAdwApp *app, OmniAdwNode *modal, OmniModalSummary *summary, int close_action_id) {
  int effective_close_action_id = close_action_id > 0 ? close_action_id : modal_cancel_action_id(summary);
  AdwDialog *dialog = adw_dialog_new();
  adw_dialog_set_title(dialog, "Sheet");
  adw_dialog_set_can_close(dialog, TRUE);
  adw_dialog_set_content_width(dialog, 520);
  adw_dialog_set_presentation_mode(dialog, ADW_DIALOG_FLOATING);
  omni_accessible_label(GTK_WIDGET(dialog), "Sheet");
  omni_accessible_description(GTK_WIDGET(dialog), "Modal sheet");
  gtk_accessible_update_property(GTK_ACCESSIBLE(dialog), GTK_ACCESSIBLE_PROPERTY_MODAL, TRUE, -1);
  app->modal_dialog = dialog;
  app->modal_close_action_id = effective_close_action_id;
  app->modal_force_closing = FALSE;
#if defined(__APPLE__)
  omni_macos_web_view_set_modal_occlusion(TRUE);
#endif
  wire_actions(modal->widget, app);

  gboolean fills_height = widget_contains_scrolled_window(modal->widget);
  if (fills_height) {
    adw_dialog_set_content_height(dialog, 560);
  }
  GtkWidget *surface = omni_sheet_surface_new(fills_height);
  gtk_box_append(GTK_BOX(surface), modal->widget);
  modal->widget = NULL;
  GtkWidget *sheet_entry = find_first_entry_widget(surface);
  if (sheet_entry && GTK_IS_WIDGET(sheet_entry)) {
    g_object_ref(sheet_entry);
  } else {
    sheet_entry = NULL;
  }
  adw_dialog_set_child(dialog, surface);
  g_object_set_data(G_OBJECT(dialog), "omni-sheet-content-widget", surface);
  app->modal_accessibility_root = surface;

  g_signal_connect(dialog, "close-attempt", G_CALLBACK(on_sheet_close_attempt), app);
  g_signal_connect(dialog, "closed", G_CALLBACK(on_sheet_closed), app);
  if (app->window) {
    adw_dialog_present(dialog, app->window);
    if (sheet_entry) {
      int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sheet_entry), "omni-action-id"));
      if (action_id > 0) {
        app->focused_action_id = action_id;
        if (app->focus_callback) app->focus_callback(action_id, app->context);
      }
      adw_dialog_set_focus(dialog, sheet_entry);
      omni_schedule_focus_widget(sheet_entry);
      g_object_unref(sheet_entry);
    }
    omni_macos_accessibility_schedule_after_map(app);
  }
  free_modal_summary(summary);
}

void omni_adw_app_present_modal(OmniAdwApp *app, OmniAdwNode *modal, const char *title) {
  if (!app || !modal) return;
  if (app->modal_dialog) {
    if (update_presented_sheet_dialog(app, modal)) {
      omni_adw_node_free(modal);
      return;
    }
    omni_adw_node_free(modal);
    return;
  }
  omni_adw_app_dismiss_modal(app);
  OmniModalSummary *summary = modal_summary_new(modal->widget);
  int close_action_id = modal_close_action_id(summary);
  if (close_action_id > 0 || find_first_entry_widget(modal->widget)) {
    present_sheet_dialog(app, modal, summary, close_action_id);
    omni_adw_node_free(modal);
    return;
  }
  const char *heading = summary && summary->labels->len > 0 ? (const char *)g_ptr_array_index(summary->labels, 0) : (title && title[0] ? title : "Presentation");
  const char *body = summary && summary->labels->len > 1 ? (const char *)g_ptr_array_index(summary->labels, 1) : NULL;
  AdwDialog *base_dialog = adw_alert_dialog_new(heading, body);
  AdwAlertDialog *dialog = ADW_ALERT_DIALOG(base_dialog);
  omni_accessible_label(GTK_WIDGET(base_dialog), heading);
  if (body && body[0]) omni_accessible_description(GTK_WIDGET(base_dialog), body);
  gtk_accessible_update_property(GTK_ACCESSIBLE(base_dialog), GTK_ACCESSIBLE_PROPERTY_MODAL, TRUE, -1);
  if (summary) {
    for (guint i = 0; i < summary->button_labels->len; i++) {
      char response_id[16];
      snprintf(response_id, sizeof(response_id), "r%u", i);
      const char *label = (const char *)g_ptr_array_index(summary->button_labels, i);
      adw_alert_dialog_add_response(dialog, response_id, label);
    }
    if (summary->button_labels->len > 0) {
      adw_alert_dialog_set_default_response(dialog, "r0");
      adw_alert_dialog_set_close_response(dialog, "r0");
    }
    g_object_set_data_full(G_OBJECT(dialog), "omni-modal-summary", summary, (GDestroyNotify)free_modal_summary);
  }
  g_signal_connect(dialog, "response", G_CALLBACK(on_alert_response), app);
  app->modal_dialog = base_dialog;
#if defined(__APPLE__)
  omni_macos_web_view_set_modal_occlusion(TRUE);
#endif
  if (app->window) {
    adw_dialog_present(base_dialog, app->window);
    omni_macos_accessibility_schedule(app);
  }
  omni_adw_node_free(modal);
}

static void omni_adw_app_dismiss_modal_now(OmniAdwApp *app) {
  if (!app || !app->modal_dialog) return;
  GtkWidget *modal_text = app_modal_native_text_widget(app);
  if (modal_text && GTK_IS_EDITABLE(modal_text)) {
    omni_entry_cancel_pending_text_commit(modal_text);
  }
  omni_macos_accessibility_cancel_pending(app);
  app->modal_accessibility_root = NULL;
  app->modal_force_closing = TRUE;
  adw_dialog_close(app->modal_dialog);
#if defined(__APPLE__)
  omni_macos_web_view_set_modal_occlusion(FALSE);
#endif
}

static gboolean omni_adw_app_dismiss_modal_idle(gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app) return G_SOURCE_REMOVE;
  app->modal_dismiss_source = 0;
  omni_adw_app_dismiss_modal_now(app);
  return G_SOURCE_REMOVE;
}

void omni_adw_app_dismiss_modal(OmniAdwApp *app) {
  if (!app || !app->modal_dialog) return;
  if (omni_native_dispatch_depth > 0) {
    app->modal_force_closing = TRUE;
    if (app->modal_dismiss_source == 0) {
      app->modal_dismiss_source = g_timeout_add(OMNI_MODAL_DISMISS_DELAY_MS, omni_adw_app_dismiss_modal_idle, app);
    }
    return;
  }
  omni_adw_app_dismiss_modal_now(app);
}

static gboolean omni_text_needs_scrollable_static_view(const char *value) {
  if (!value) return FALSE;
  size_t length = strlen(value);
  if (length > 16384) return TRUE;
  if (g_str_has_prefix(value, "Loading web content")) return TRUE;
  if (g_str_has_prefix(value, "Web content\n")) return TRUE;
  if (g_str_has_prefix(value, "Terminal\n")) return TRUE;
  return FALSE;
}

static GtkTextView *omni_text_view_from_static_text_widget(GtkWidget *widget) {
  if (!widget) return NULL;
  if (GTK_IS_TEXT_VIEW(widget)) return GTK_TEXT_VIEW(widget);
  if (GTK_IS_SCROLLED_WINDOW(widget)) {
    GtkWidget *child = gtk_scrolled_window_get_child(GTK_SCROLLED_WINDOW(widget));
    if (GTK_IS_TEXT_VIEW(child)) return GTK_TEXT_VIEW(child);
  }
  return NULL;
}

static void omni_update_static_text_view(GtkTextView *view, const char *value) {
  if (!view) return;
  const char *text = value ? value : "";
  GtkTextBuffer *buffer = gtk_text_view_get_buffer(view);
  GtkTextIter start;
  GtkTextIter end;
  gtk_text_buffer_get_start_iter(buffer, &start);
  gtk_text_buffer_get_end_iter(buffer, &end);
  char *existing = gtk_text_buffer_get_text(buffer, &start, &end, FALSE);
  if (!existing || strcmp(existing, text) != 0) {
    gtk_text_buffer_set_text(buffer, text, -1);
  }
  omni_accessible_value_text(GTK_WIDGET(view), text);
  omni_accessible_label(GTK_WIDGET(view), text);
  g_free(existing);
}

static OmniAdwNode *omni_adw_scrollable_text_node_new(const char *text) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  const char *value = text ? text : "";

  GtkWidget *text_view = gtk_text_view_new();
  gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(text_view), GTK_WRAP_WORD_CHAR);
  gtk_text_view_set_editable(GTK_TEXT_VIEW(text_view), FALSE);
  gtk_text_view_set_cursor_visible(GTK_TEXT_VIEW(text_view), FALSE);
  gtk_text_view_set_monospace(GTK_TEXT_VIEW(text_view), TRUE);
  omni_update_static_text_view(GTK_TEXT_VIEW(text_view), value);
  gtk_widget_add_css_class(text_view, "omni-static-text");
  gtk_widget_set_hexpand(text_view, TRUE);
  gtk_widget_set_vexpand(text_view, TRUE);
  gtk_widget_set_halign(text_view, GTK_ALIGN_FILL);
  gtk_widget_set_valign(text_view, GTK_ALIGN_FILL);
  omni_accessible_read_only(text_view, TRUE);
  omni_accessible_multi_line(text_view, TRUE);

  GtkWidget *scroll = gtk_scrolled_window_new();
  gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll), GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
  gtk_scrolled_window_set_propagate_natural_height(GTK_SCROLLED_WINDOW(scroll), FALSE);
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), text_view);
  gtk_widget_add_css_class(scroll, "omni-static-text-frame");
  gtk_widget_set_hexpand(scroll, TRUE);
  gtk_widget_set_vexpand(scroll, TRUE);
  gtk_widget_set_halign(scroll, GTK_ALIGN_FILL);
  gtk_widget_set_valign(scroll, GTK_ALIGN_FILL);
  omni_accessible_label(scroll, value);
  omni_accessible_value_text(scroll, value);
  node->widget = scroll;
  return node;
}

static GtkWidget *omni_adw_app_find_widget_by_name(OmniAdwApp *app, const char *name) {
  if (!app || !name || !name[0]) return NULL;
  GtkWidget *widget = app->content ? find_widget_for_name(app->content, name) : NULL;
  if (!widget && app->modal_accessibility_root) {
    widget = find_widget_for_name(app->modal_accessibility_root, name);
  }
  if (!widget && app->modal_dialog && GTK_IS_WIDGET(app->modal_dialog)) {
    widget = find_widget_for_name(GTK_WIDGET(app->modal_dialog), name);
  }
  return widget;
}

int32_t omni_adw_app_update_node(OmniAdwApp *app, const char *semantic_id, int32_t kind, const char *text, int32_t active) {
  if (!app || !semantic_id) return 0;
  char *name = omni_sanitized_widget_name(semantic_id);
  GtkWidget *widget = omni_adw_app_find_widget_by_name(app, name);
  free(name);
  if (!widget) return 0;

  const char *value = text ? text : "";
  switch (kind) {
    case 0:
      if (GTK_IS_LABEL(widget)) {
        gtk_label_set_text(GTK_LABEL(widget), value);
        omni_accessible_label(widget, value);
      } else {
        GtkTextView *view = omni_text_view_from_static_text_widget(widget);
        if (!view) return 0;
        omni_update_static_text_view(view, value);
        omni_accessible_label(widget, value);
        omni_accessible_value_text(widget, value);
      }
      break;
    case 1:
      if (!GTK_IS_BUTTON(widget)) return 0;
      omni_button_set_label_or_symbolic_icon(GTK_BUTTON(widget), value);
      {
        const char *accessible_value = omni_accessible_label_for_symbolic_label(value);
        omni_accessible_label(widget, accessible_value ? accessible_value : value);
      }
      break;
    case 2:
      if (ADW_IS_SWITCH_ROW(widget)) {
        g_object_set_data(G_OBJECT(widget), "omni-updating", GINT_TO_POINTER(1));
        adw_switch_row_set_active(ADW_SWITCH_ROW(widget), active != 0);
        g_object_set_data(G_OBJECT(widget), "omni-updating", NULL);
        adw_preferences_row_set_title(ADW_PREFERENCES_ROW(widget), value);
        omni_accessible_label(widget, value);
        gtk_accessible_update_state(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_STATE_CHECKED, active ? GTK_ACCESSIBLE_TRISTATE_TRUE : GTK_ACCESSIBLE_TRISTATE_FALSE, -1);
        break;
      }
      if (!GTK_IS_CHECK_BUTTON(widget)) return 0;
      gtk_check_button_set_label(GTK_CHECK_BUTTON(widget), value);
      gtk_check_button_set_active(GTK_CHECK_BUTTON(widget), active != 0);
      omni_accessible_label(widget, value);
      gtk_accessible_update_state(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_STATE_CHECKED, active ? GTK_ACCESSIBLE_TRISTATE_TRUE : GTK_ACCESSIBLE_TRISTATE_FALSE, -1);
      break;
    case 3:
      {
        GtkWidget *entry = GTK_IS_ENTRY(widget) ? widget : omni_first_descendant_matching(widget, GTK_TYPE_ENTRY);
        if (!GTK_IS_ENTRY(entry)) return 0;
        if (strcmp(gtk_editable_get_text(GTK_EDITABLE(entry)), value) != 0) {
          gtk_editable_set_text(GTK_EDITABLE(entry), value);
        }
        omni_accessible_value_text(entry, value);
      }
      break;
    case 4:
      if (!GTK_IS_TEXT_VIEW(widget)) return 0;
      {
        GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(widget));
        GtkTextIter start;
        GtkTextIter end;
        gtk_text_buffer_get_start_iter(buffer, &start);
        gtk_text_buffer_get_end_iter(buffer, &end);
        char *existing = gtk_text_buffer_get_text(buffer, &start, &end, FALSE);
        if (!existing || strcmp(existing, value) != 0) {
          gtk_text_buffer_set_text(buffer, value, -1);
        }
        omni_accessible_value_text(widget, value);
        g_free(existing);
      }
      break;
    case 5:
      if (GTK_IS_MENU_BUTTON(widget)) {
        char **labels = (char **)g_object_get_data(G_OBJECT(widget), "omni-labels");
        int count = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-count"));
        for (int i = 0; i < count; i++) {
          const char *label = labels && labels[i] ? labels[i] : "";
          if (strcmp(label, value) == 0) {
            gtk_menu_button_set_label(GTK_MENU_BUTTON(widget), label);
            omni_accessible_value_text(widget, label);
            break;
          }
        }
        break;
      }
      if (!GTK_IS_DROP_DOWN(widget)) {
        GtkWidget *dropdown = omni_first_descendant_matching(widget, GTK_TYPE_DROP_DOWN);
        if (!GTK_IS_DROP_DOWN(dropdown)) return 0;
        widget = dropdown;
      }
      {
        GListModel *model = gtk_drop_down_get_model(GTK_DROP_DOWN(widget));
        if (!GTK_IS_STRING_LIST(model)) return 0;
        guint count = g_list_model_get_n_items(model);
        for (guint i = 0; i < count; i++) {
          const char *item = gtk_string_list_get_string(GTK_STRING_LIST(model), i);
          if (item && strcmp(item, value) == 0) {
            if (gtk_drop_down_get_selected(GTK_DROP_DOWN(widget)) != i) {
              g_object_set_data(G_OBJECT(widget), "omni-updating", GINT_TO_POINTER(1));
              gtk_drop_down_set_selected(GTK_DROP_DOWN(widget), i);
              g_object_set_data(G_OBJECT(widget), "omni-updating", NULL);
            }
            omni_accessible_value_text(widget, item);
            break;
          }
        }
      }
      break;
    case 11:
      {
        const char *color_value = value;
        const char *label_value = "";
        char *copy = omni_strdup(value);
        char *newline = copy ? strchr(copy, '\n') : NULL;
        if (newline) {
          *newline = '\0';
          color_value = copy;
          label_value = newline + 1;
        }
        omni_color_button_set_rgba(widget, color_value);
        if (ADW_IS_ACTION_ROW(widget) && label_value && label_value[0]) {
          adw_preferences_row_set_title(ADW_PREFERENCES_ROW(widget), label_value);
          omni_accessible_label(widget, label_value);
        }
        if (copy) free(copy);
      }
      break;
    case 6:
      if (!GTK_IS_PROGRESS_BAR(widget)) return 0;
      {
        char *endptr = NULL;
        double fraction = strtod(value, &endptr);
        if (fraction < 0.0) fraction = 0.0;
        if (fraction > 1.0) fraction = 1.0;
        const char *label = endptr && *endptr == '\n' ? endptr + 1 : "";
        gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(widget), fraction);
        gtk_progress_bar_set_show_text(GTK_PROGRESS_BAR(widget), TRUE);
        gtk_accessible_update_property(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_PROPERTY_VALUE_NOW, fraction, -1);
        if (label[0]) {
          gtk_progress_bar_set_text(GTK_PROGRESS_BAR(widget), label);
          gtk_widget_set_tooltip_text(widget, label);
          omni_accessible_label(widget, label);
          omni_accessible_value_text(widget, label);
        }
      }
      break;
    case 7:
      if (!GTK_IS_SCALE(widget)) return 0;
      {
        char *endptr = NULL;
        double value_number = strtod(value, &endptr);
        GtkAdjustment *adjustment = gtk_range_get_adjustment(GTK_RANGE(widget));
        if (adjustment) {
          double lower = gtk_adjustment_get_lower(adjustment);
          double upper = gtk_adjustment_get_upper(adjustment);
          if (value_number < lower) value_number = lower;
          if (value_number > upper) value_number = upper;
        }
        g_object_set_data(G_OBJECT(widget), "omni-updating", GINT_TO_POINTER(1));
        gtk_range_set_value(GTK_RANGE(widget), value_number);
        double *stored_value = (double *)g_object_get_data(G_OBJECT(widget), "omni-scale-value");
        if (stored_value) *stored_value = value_number;
        g_object_set_data(G_OBJECT(widget), "omni-updating", NULL);
        gtk_accessible_update_property(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_PROPERTY_VALUE_NOW, value_number, -1);
        if (endptr && *endptr == '\n' && endptr[1]) {
          gtk_widget_set_tooltip_text(widget, endptr + 1);
          omni_accessible_label(widget, endptr + 1);
        }
      }
      break;
    case 8:
      if (!GTK_IS_SPIN_BUTTON(widget)) return 0;
      {
        char *endptr = NULL;
        double value_number = strtod(value, &endptr);
        g_object_set_data(G_OBJECT(widget), "omni-updating", GINT_TO_POINTER(1));
        gtk_spin_button_set_value(GTK_SPIN_BUTTON(widget), value_number);
        double *stored_value = (double *)g_object_get_data(G_OBJECT(widget), "omni-spin-value");
        if (stored_value) *stored_value = value_number;
        g_object_set_data(G_OBJECT(widget), "omni-updating", NULL);
        gtk_accessible_update_property(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_PROPERTY_VALUE_NOW, value_number, -1);
        if (endptr && *endptr == '\n' && endptr[1]) {
          gtk_widget_set_tooltip_text(widget, endptr + 1);
          omni_accessible_label(widget, endptr + 1);
        }
      }
      break;
    case 9:
      if (!GTK_IS_BOX(widget)) return 0;
      {
        char *first_end = NULL;
        double timestamp = strtod(value, &first_end);
        const char *date_value = first_end && *first_end == '\n' ? first_end + 1 : value;
        const char *date_label = "";
        const char *endptr = strchr(date_value, '\n');
        char *owned_value = NULL;
        if (endptr) {
          owned_value = g_strndup(date_value, (gsize)(endptr - date_value));
          date_value = owned_value ? owned_value : "";
          date_label = endptr + 1;
        }
        GtkWidget *child = gtk_widget_get_first_child(widget);
        if (GTK_IS_LABEL(child)) {
          if (date_label && date_label[0]) {
            char *combined = g_strdup_printf("%s: %s", date_label, date_value);
            gtk_label_set_text(GTK_LABEL(child), combined);
            gtk_widget_set_tooltip_text(widget, combined);
            g_free(combined);
          } else {
            gtk_label_set_text(GTK_LABEL(child), date_value);
            gtk_widget_set_tooltip_text(widget, date_value);
          }
        }
        GtkWidget *control = child ? gtk_widget_get_next_sibling(child) : NULL;
        if (GTK_IS_MENU_BUTTON(control)) {
          gtk_menu_button_set_label(GTK_MENU_BUTTON(control), date_value);
          omni_accessible_value_text(control, date_value);
        }
        omni_accessible_value_text(widget, date_value);
        GtkWidget *calendar = NULL;
        if (GTK_IS_CALENDAR(control)) {
          calendar = control;
        } else if (GTK_IS_MENU_BUTTON(control)) {
          GtkPopover *popover = gtk_menu_button_get_popover(GTK_MENU_BUTTON(control));
          GtkWidget *popover_child = popover ? gtk_popover_get_child(popover) : NULL;
          if (GTK_IS_CALENDAR(popover_child)) {
            calendar = popover_child;
          }
        }
        if (GTK_IS_CALENDAR(calendar)) {
          GDateTime *dt = g_date_time_new_from_unix_local((gint64)timestamp);
          if (dt) {
            g_object_set_data(G_OBJECT(calendar), "omni-updating", GINT_TO_POINTER(1));
            omni_calendar_set_date(GTK_CALENDAR(calendar), dt);
            gint64 *stored_day = (gint64 *)g_object_get_data(G_OBJECT(calendar), "omni-calendar-day");
            if (stored_day) {
              *stored_day = (gint64)g_date_time_get_year(dt) * 10000 +
                (gint64)g_date_time_get_month(dt) * 100 +
                (gint64)g_date_time_get_day_of_month(dt);
            }
            g_object_set_data(G_OBJECT(calendar), "omni-updating", NULL);
            g_date_time_unref(dt);
          }
        }
        g_free(owned_value);
      }
      break;
    case 10:
      if (!GTK_IS_SCROLLED_WINDOW(widget)) return 0;
      {
        double rows = strtod(value, NULL);
        double pixels = omni_semantic_scroll_to_pixels(rows);
        gboolean vertical = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-scroll-vertical")) != 0;
        GtkAdjustment *adjustment = vertical
          ? gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(widget))
          : gtk_scrolled_window_get_hadjustment(GTK_SCROLLED_WINDOW(widget));
        schedule_adjustment_restore(adjustment, pixels);
      }
      break;
    default:
      return 0;
  }
  if (value[0] && kind != 10) {
    gtk_widget_set_tooltip_text(widget, value);
  }
  omni_queue_widget_and_ancestors_redraw(widget);
  omni_macos_accessibility_schedule(app);
  return 1;
}

int32_t omni_adw_app_replace_node(OmniAdwApp *app, const char *semantic_id, OmniAdwNode *replacement, int32_t focused_action_id) {
  if (!app || !semantic_id || !replacement || !replacement->widget) return 0;
  char *name = omni_sanitized_widget_name(semantic_id);
  GtkWidget *target = omni_adw_app_find_widget_by_name(app, name);
  free(name);
  if (!target) return 0;

  GtkWidget *replacement_widget = replacement->widget;
  replacement->widget = NULL;
  omni_adw_node_free(replacement);
  app->focused_action_id = focused_action_id;

  if (target == app->content) {
    app->content = replacement_widget;
    omni_widget_expand(app->content, TRUE);
    gtk_widget_set_margin_top(app->content, 0);
    gtk_widget_set_margin_bottom(app->content, 0);
    gtk_widget_set_margin_start(app->content, 0);
    gtk_widget_set_margin_end(app->content, 0);
    if (app->window) {
      gtk_window_set_focus(GTK_WINDOW(app->window), NULL);
      if (app->body_slot) {
        GtkWidget *old_child = gtk_widget_get_first_child(app->body_slot);
        while (old_child) {
          GtkWidget *next = gtk_widget_get_next_sibling(old_child);
          gtk_box_remove(GTK_BOX(app->body_slot), old_child);
          old_child = next;
        }
        gtk_box_append(GTK_BOX(app->body_slot), app->content);
      } else {
        adw_application_window_set_content(ADW_APPLICATION_WINDOW(app->window), app->content);
      }
    }
  } else {
    GtkWidget *parent = gtk_widget_get_parent(target);
    if (!parent) return 0;

    if (GTK_IS_BOX(parent)) {
      GtkWidget *previous = gtk_widget_get_prev_sibling(target);
      if (previous) {
        gtk_box_insert_child_after(GTK_BOX(parent), replacement_widget, previous);
      } else {
        gtk_box_prepend(GTK_BOX(parent), replacement_widget);
      }
      gtk_box_remove(GTK_BOX(parent), target);
    } else if (GTK_IS_LIST_BOX_ROW(parent)) {
      gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(parent), replacement_widget);
    } else if (GTK_IS_PANED(parent)) {
      if (gtk_paned_get_start_child(GTK_PANED(parent)) == target) {
        gtk_paned_set_start_child(GTK_PANED(parent), replacement_widget);
      } else if (gtk_paned_get_end_child(GTK_PANED(parent)) == target) {
        gtk_paned_set_end_child(GTK_PANED(parent), replacement_widget);
      } else {
        return 0;
      }
    } else if (ADW_IS_NAVIGATION_PAGE(parent)) {
      adw_navigation_page_set_child(ADW_NAVIGATION_PAGE(parent), replacement_widget);
    } else if (GTK_IS_SCROLLED_WINDOW(parent)) {
      gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(parent), replacement_widget);
    } else {
      return 0;
    }
  }

  app->active_split_view = NULL;
  wire_actions(app->content, app);
  sync_sidebar_toggle(app);

  GtkWidget *focused = find_widget_for_action(app->content, focused_action_id);
  omni_grab_focus_if_ready(focused);
  omni_queue_widget_and_ancestors_redraw(replacement_widget);
  if (app->content) omni_queue_widget_redraw(app->content);
  if (app->window) omni_queue_widget_redraw(app->window);
  omni_macos_accessibility_schedule(app);
  return 1;
}

OmniAdwNode *omni_adw_box_new(int32_t vertical, int32_t spacing) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_box_new(vertical ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL, spacing);
  gtk_widget_add_css_class(node->widget, "omni-stack");
  omni_widget_expand(node->widget, FALSE);
  omni_accessible_role_description(node->widget, vertical ? "vertical group" : "horizontal group");
  return node;
}

OmniAdwNode *omni_adw_flow_new(int32_t horizontal_spacing, int32_t vertical_spacing) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_flow_box_new();
  gtk_flow_box_set_selection_mode(GTK_FLOW_BOX(node->widget), GTK_SELECTION_NONE);
  gtk_flow_box_set_column_spacing(GTK_FLOW_BOX(node->widget), horizontal_spacing);
  gtk_flow_box_set_row_spacing(GTK_FLOW_BOX(node->widget), vertical_spacing);
  gtk_flow_box_set_min_children_per_line(GTK_FLOW_BOX(node->widget), 1);
  gtk_widget_add_css_class(node->widget, "omni-flow");
  omni_widget_expand(node->widget, FALSE);
  omni_accessible_role_description(node->widget, "flow group");
  return node;
}

void omni_adw_box_set_homogeneous(OmniAdwNode *node, int32_t homogeneous) {
  if (!node || !node->widget || !GTK_IS_BOX(node->widget)) return;
  gtk_box_set_homogeneous(GTK_BOX(node->widget), homogeneous != 0);
}

OmniAdwNode *omni_adw_overlay_new(void) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_overlay_new();
  gtk_widget_add_css_class(node->widget, "omni-overlay");
  omni_widget_expand(node->widget, TRUE);
  omni_accessible_role_description(node->widget, "overlay group");
  return node;
}

OmniAdwNode *omni_adw_list_new(void) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_list_box_new();
  gtk_list_box_set_selection_mode(GTK_LIST_BOX(node->widget), GTK_SELECTION_NONE);
  gtk_list_box_set_activate_on_single_click(GTK_LIST_BOX(node->widget), TRUE);
  gtk_widget_add_css_class(node->widget, "boxed-list");
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  omni_accessible_label(node->widget, "List");
  omni_accessible_role_description(node->widget, "list");
  return node;
}

OmniAdwNode *omni_adw_string_list_new(const char **labels, const int32_t *action_ids, const double *font_sizes, const char **font_weights, const int32_t *font_italics, const char **css_classes, int32_t count) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  OmniStringListData *data = calloc(1, sizeof(OmniStringListData));
  if (data && count > 0) {
    data->count = count;
    data->labels = calloc((size_t)count, sizeof(char *));
    data->action_ids = calloc((size_t)count, sizeof(int32_t));
    data->font_sizes = calloc((size_t)count, sizeof(double));
    data->font_weights = calloc((size_t)count, sizeof(char *));
    data->font_italics = calloc((size_t)count, sizeof(int32_t));
    data->css_classes = calloc((size_t)count, sizeof(char *));
  }
  for (int32_t i = 0; i < count; i++) {
    const char *label = labels && labels[i] ? labels[i] : "";
    if (data && data->labels) data->labels[i] = omni_strdup(label);
    if (data && data->action_ids) data->action_ids[i] = action_ids ? action_ids[i] : 0;
    if (data && data->font_sizes) data->font_sizes[i] = font_sizes ? font_sizes[i] : 0.0;
    if (data && data->font_weights) data->font_weights[i] = omni_strdup(font_weights && font_weights[i] ? font_weights[i] : "");
    if (data && data->font_italics) data->font_italics[i] = font_italics ? font_italics[i] : 0;
    if (data && data->css_classes) data->css_classes[i] = omni_strdup(css_classes && css_classes[i] ? css_classes[i] : "");
  }

  OmniListModel *model = omni_list_model_new(data);
  g_object_ref(model);
  GtkSelectionModel *selection = GTK_SELECTION_MODEL(gtk_single_selection_new(G_LIST_MODEL(model)));
  GtkListItemFactory *factory = gtk_signal_list_item_factory_new();
  g_signal_connect(factory, "setup", G_CALLBACK(on_string_list_setup), NULL);
  g_signal_connect(factory, "bind", G_CALLBACK(on_string_list_bind), NULL);

  node->widget = gtk_list_view_new(selection, factory);
  gtk_list_view_set_single_click_activate(GTK_LIST_VIEW(node->widget), TRUE);
  gtk_widget_add_css_class(node->widget, "boxed-list");
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_vexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  gtk_widget_set_valign(node->widget, GTK_ALIGN_FILL);
  omni_accessible_label(node->widget, "Content list");
  omni_accessible_description(node->widget, "Virtualized list");
  omni_accessible_role_description(node->widget, "list");
  g_object_set_data(G_OBJECT(node->widget), "omni-string-list-data", data);
  g_object_set_data_full(G_OBJECT(node->widget), "omni-list-model", model, g_object_unref);
  g_signal_connect(node->widget, "activate", G_CALLBACK(on_string_list_activate), NULL);
  return node;
}

OmniAdwNode *omni_adw_plain_list_new(const char **labels, const int32_t *action_ids, const double *font_sizes, const char **font_weights, const int32_t *font_italics, const char **css_classes, int32_t count) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_list_box_new();
  gtk_list_box_set_selection_mode(GTK_LIST_BOX(node->widget), GTK_SELECTION_NONE);
  gtk_list_box_set_activate_on_single_click(GTK_LIST_BOX(node->widget), TRUE);
  gtk_widget_add_css_class(node->widget, "omni-plain-list");
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_vexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  gtk_widget_set_valign(node->widget, GTK_ALIGN_FILL);
  omni_accessible_label(node->widget, "Content list");
  omni_accessible_role_description(node->widget, "list");
  g_signal_connect(node->widget, "row-activated", G_CALLBACK(on_plain_list_row_activated), NULL);
  install_row_click_controller(node->widget);

  for (int32_t i = 0; i < count; i++) {
    const char *text = labels && labels[i] ? labels[i] : "";
    int32_t action_id = action_ids ? action_ids[i] : 0;
    GtkWidget *row = gtk_list_box_row_new();
    GtkWidget *label = gtk_label_new(text);
    omni_label_apply_font(
      GTK_LABEL(label),
      font_sizes ? font_sizes[i] : 0.0,
      font_weights && font_weights[i] ? font_weights[i] : "",
      font_italics && font_italics[i] != 0
    );
    omni_widget_add_css_classes(label, css_classes && css_classes[i] ? css_classes[i] : "");
    gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
    gtk_label_set_wrap(GTK_LABEL(label), FALSE);
    gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_NONE);
    gtk_widget_add_css_class(label, "omni-monospace-text");
    gtk_widget_set_hexpand(label, TRUE);
    gtk_widget_set_halign(label, GTK_ALIGN_FILL);
    if (action_id > 0) {
      gtk_widget_add_css_class(row, "omni-action-list-row");
      GtkWidget *button = gtk_button_new();
      gtk_widget_add_css_class(button, "omni-list-row-button");
      gtk_widget_set_hexpand(button, TRUE);
      gtk_widget_set_halign(button, GTK_ALIGN_FILL);
      gtk_widget_set_focus_on_click(button, TRUE);
      gtk_button_set_child(GTK_BUTTON(button), label);
      omni_widget_add_css_classes(button, css_classes && css_classes[i] ? css_classes[i] : "");
      g_object_set_data(G_OBJECT(button), "omni-action-id", GINT_TO_POINTER(action_id));
      g_signal_connect(button, "clicked", G_CALLBACK(on_virtual_list_button_clicked), NULL);
      omni_accessible_label(button, text);
      omni_accessible_description(button, "Activates this list row");
      gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), button);
    } else {
      gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), label);
    }
    omni_accessible_label(row, text);
    omni_accessible_description(row, "List row");
    omni_accessible_list_position(row, i + 1, count);
    omni_accessible_label(label, text);
    g_object_set_data(G_OBJECT(row), "omni-action-id", GINT_TO_POINTER(action_id));
    gtk_list_box_row_set_activatable(GTK_LIST_BOX_ROW(row), FALSE);
    gtk_widget_set_focusable(row, action_id > 0);
    gtk_widget_set_sensitive(row, TRUE);
    omni_accessible_set_disabled(row, action_id <= 0);
    if (action_id > 0) {
      install_row_click_controller(row);
      install_row_click_controller(label);
    }
    gtk_list_box_append(GTK_LIST_BOX(node->widget), row);
  }
  return node;
}

OmniAdwNode *omni_adw_sidebar_list_new(const char **labels, const int32_t *action_ids, const int32_t *depths, const double *font_sizes, const char **font_weights, const int32_t *font_italics, const char **css_classes, int32_t count) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  OmniStringListData *data = calloc(1, sizeof(OmniStringListData));
  if (data && count > 0) {
    data->count = count;
    data->labels = calloc((size_t)count, sizeof(char *));
    data->action_ids = calloc((size_t)count, sizeof(int32_t));
    data->depths = calloc((size_t)count, sizeof(int32_t));
    data->font_sizes = calloc((size_t)count, sizeof(double));
    data->font_weights = calloc((size_t)count, sizeof(char *));
    data->font_italics = calloc((size_t)count, sizeof(int32_t));
    data->css_classes = calloc((size_t)count, sizeof(char *));
    data->collapsed = calloc((size_t)count, sizeof(gboolean));
    for (int32_t i = 0; i < count; i++) {
      data->labels[i] = omni_strdup(labels && labels[i] ? labels[i] : "");
      if (data->action_ids) data->action_ids[i] = action_ids ? action_ids[i] : 0;
      if (data->depths) data->depths[i] = depths ? depths[i] : 0;
      if (data->font_sizes) data->font_sizes[i] = font_sizes ? font_sizes[i] : 0.0;
      if (data->font_weights) data->font_weights[i] = omni_strdup(font_weights && font_weights[i] ? font_weights[i] : "");
      if (data->font_italics) data->font_italics[i] = font_italics ? font_italics[i] : 0;
      if (data->css_classes) data->css_classes[i] = omni_strdup(css_classes && css_classes[i] ? css_classes[i] : "");
    }
    for (int32_t i = 0; i < count; i++) {
      if (sidebar_row_has_children(data, i) && data->depths && data->depths[i] > 0) {
        data->collapsed[i] = TRUE;
      }
    }
  }
  if (count >= 128) {
    sidebar_rebuild_visible_indices(data);
    OmniListModel *model = omni_list_model_new(data);
    g_object_ref(model);

    GtkSelectionModel *selection = GTK_SELECTION_MODEL(gtk_single_selection_new(G_LIST_MODEL(model)));
    GtkListItemFactory *factory = gtk_signal_list_item_factory_new();
    g_signal_connect(factory, "setup", G_CALLBACK(on_sidebar_list_setup), NULL);
    g_signal_connect(factory, "bind", G_CALLBACK(on_sidebar_list_bind), data);

    node->widget = gtk_list_view_new(selection, factory);
    gtk_list_view_set_single_click_activate(GTK_LIST_VIEW(node->widget), TRUE);
    gtk_widget_add_css_class(node->widget, "omni-sidebar-list");
    gtk_widget_set_hexpand(node->widget, TRUE);
    gtk_widget_set_vexpand(node->widget, TRUE);
    gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
    gtk_widget_set_valign(node->widget, GTK_ALIGN_FILL);
    omni_accessible_label(node->widget, "Sidebar");
    omni_accessible_description(node->widget, "Virtualized sidebar outline");
    omni_accessible_role_description(node->widget, "sidebar list");
    g_object_set_data(G_OBJECT(node->widget), "omni-string-list-data", data);
    g_object_set_data_full(G_OBJECT(node->widget), "omni-list-model", model, g_object_unref);
    g_signal_connect(node->widget, "activate", G_CALLBACK(on_string_list_activate), NULL);
    return node;
  }

  node->widget = gtk_list_box_new();
  gtk_list_box_set_selection_mode(GTK_LIST_BOX(node->widget), GTK_SELECTION_SINGLE);
  gtk_list_box_set_activate_on_single_click(GTK_LIST_BOX(node->widget), TRUE);
  gtk_widget_add_css_class(node->widget, "omni-sidebar-list");
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_vexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  gtk_widget_set_valign(node->widget, GTK_ALIGN_FILL);
  omni_accessible_label(node->widget, "Sidebar");
  omni_accessible_description(node->widget, "Sidebar outline");
  omni_accessible_role_description(node->widget, "sidebar list");
  if (data) {
    data->rows = calloc((size_t)count, sizeof(GtkWidget *));
    g_object_set_data_full(G_OBJECT(node->widget), "omni-string-list-data", data, free_string_list_data);
  }
  g_signal_connect(node->widget, "row-activated", G_CALLBACK(on_plain_list_row_activated), NULL);
  install_row_click_controller(node->widget);

  for (int32_t i = 0; i < count; i++) {
    const char *text = labels && labels[i] ? labels[i] : "";
    int32_t depth = depths ? depths[i] : 0;
    if (depth < 0) depth = 0;
    if (depth > 8) depth = 8;

    GtkWidget *row = gtk_list_box_row_new();
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    gtk_widget_add_css_class(box, "omni-sidebar-row");
    gtk_widget_set_hexpand(box, TRUE);
    gtk_widget_set_halign(box, GTK_ALIGN_FILL);
    gtk_widget_set_margin_start(box, depth * 16);

    GtkWidget *disclosure_button = gtk_button_new();
    gtk_widget_add_css_class(disclosure_button, "flat");
    gtk_widget_add_css_class(disclosure_button, "omni-sidebar-disclosure-button");
    gtk_widget_set_focus_on_click(disclosure_button, TRUE);
    g_object_set_data(G_OBJECT(disclosure_button), "omni-sidebar-index", GINT_TO_POINTER(i));
    g_signal_connect(disclosure_button, "clicked", G_CALLBACK(on_sidebar_disclosure_clicked), NULL);

    GtkWidget *disclosure = gtk_label_new("");
    gtk_widget_add_css_class(disclosure, "omni-sidebar-disclosure");
    gtk_label_set_xalign(GTK_LABEL(disclosure), 0.5f);
    gtk_button_set_child(GTK_BUTTON(disclosure_button), disclosure);
    gtk_box_append(GTK_BOX(box), disclosure_button);

    GtkWidget *button = gtk_button_new();
    gtk_widget_add_css_class(button, "omni-sidebar-row-button");
    gtk_widget_set_hexpand(button, TRUE);
    gtk_widget_set_halign(button, GTK_ALIGN_FILL);
    gtk_widget_set_focus_on_click(button, TRUE);
    g_signal_connect(button, "clicked", G_CALLBACK(on_virtual_list_button_clicked), NULL);
    gtk_button_set_child(GTK_BUTTON(button), omni_sidebar_label_new());
    omni_sidebar_content_set_text(
      button,
      text,
      font_sizes ? font_sizes[i] : 0.0,
      font_weights && font_weights[i] ? font_weights[i] : "",
      font_italics && font_italics[i] != 0,
      css_classes && css_classes[i] ? css_classes[i] : ""
    );
    gtk_box_append(GTK_BOX(box), button);

    gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), box);
    if (data && data->rows) data->rows[i] = row;
    omni_accessible_label(row, text);
    omni_accessible_description(row, depth == 0 ? "Top-level sidebar item" : "Nested sidebar item");
    omni_accessible_list_position(row, i + 1, count);
    gboolean has_children = sidebar_row_has_children(data, i);
    gtk_widget_set_visible(disclosure_button, has_children);
    gtk_label_set_text(GTK_LABEL(disclosure), has_children ? "▾" : "");
    omni_accessible_label(disclosure_button, has_children ? "Collapse" : "");
    omni_accessible_description(disclosure_button, has_children ? "Expands or collapses this sidebar group" : "");
    omni_accessible_set_expanded(disclosure_button, has_children);
    int32_t action_id = action_ids ? action_ids[i] : 0;
    g_object_set_data(G_OBJECT(button), "omni-action-id", GINT_TO_POINTER(action_id));
    gtk_list_box_row_set_activatable(GTK_LIST_BOX_ROW(row), FALSE);
    gtk_widget_set_focusable(row, action_id > 0 || has_children);
    gtk_widget_set_sensitive(row, TRUE);
    gtk_widget_set_focusable(button, action_id > 0);
    gtk_widget_set_focusable(disclosure_button, has_children);
    omni_accessible_set_disabled(button, action_id <= 0);
    omni_accessible_set_disabled(disclosure_button, !has_children);
    if (action_id > 0) {
      omni_accessible_label(button, text);
      omni_accessible_description(button, depth == 0 ? "Top-level sidebar item" : "Nested sidebar item");
    }
    gtk_list_box_append(GTK_LIST_BOX(node->widget), row);
  }
  if (data && data->rows) {
    sidebar_apply_visibility_to_rows(node->widget, data);
  }
  return node;
}

OmniAdwNode *omni_adw_form_new(void) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  gtk_widget_add_css_class(node->widget, "card");
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_vexpand(node->widget, FALSE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  omni_accessible_label(node->widget, "Form");
  omni_accessible_role_description(node->widget, "form");
  return node;
}

OmniAdwNode *omni_adw_split_new(void) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = adw_overlay_split_view_new();
  gtk_widget_add_css_class(node->widget, "navigation-view");
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_vexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  gtk_widget_set_valign(node->widget, GTK_ALIGN_FILL);
  adw_overlay_split_view_set_sidebar_position(ADW_OVERLAY_SPLIT_VIEW(node->widget), GTK_PACK_START);
  adw_overlay_split_view_set_show_sidebar(ADW_OVERLAY_SPLIT_VIEW(node->widget), TRUE);
  adw_overlay_split_view_set_enable_show_gesture(ADW_OVERLAY_SPLIT_VIEW(node->widget), TRUE);
  adw_overlay_split_view_set_enable_hide_gesture(ADW_OVERLAY_SPLIT_VIEW(node->widget), TRUE);
  adw_overlay_split_view_set_min_sidebar_width(ADW_OVERLAY_SPLIT_VIEW(node->widget), 280);
  adw_overlay_split_view_set_max_sidebar_width(ADW_OVERLAY_SPLIT_VIEW(node->widget), 420);
  adw_overlay_split_view_set_sidebar_width_fraction(ADW_OVERLAY_SPLIT_VIEW(node->widget), 0.32);
  omni_accessible_label(node->widget, "Navigation split view");
  omni_accessible_description(node->widget, "Sidebar and content");
  omni_accessible_role_description(node->widget, "navigation split view");
  return node;
}

OmniAdwNode *omni_adw_text_new(const char *text) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  const char *value = text ? text : "";
  if (omni_text_needs_scrollable_static_view(value)) {
    free(node);
    node = omni_adw_scrollable_text_node_new(value);
  } else {
    node->widget = gtk_label_new(value);
    gtk_widget_add_css_class(node->widget, "omni-text");
    gtk_label_set_xalign(GTK_LABEL(node->widget), 0.0f);
    gtk_label_set_wrap(GTK_LABEL(node->widget), TRUE);
    omni_accessible_role_description(node->widget, "text");
  }
  if (strstr(value, "  ") || strstr(value, "#") == value || strstr(value, "```") == value || strstr(value, "- ") == value || strstr(value, "* ") == value) {
    gtk_widget_add_css_class(node->widget, "omni-monospace-text");
  }
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  omni_accessible_label(node->widget, value);
  return node;
}

void omni_adw_node_set_text_wrap(OmniAdwNode *node, int32_t wrap) {
  if (!node || !node->widget || !GTK_IS_LABEL(node->widget)) return;
  gtk_label_set_wrap(GTK_LABEL(node->widget), wrap != 0);
  gtk_label_set_ellipsize(GTK_LABEL(node->widget), wrap != 0 ? PANGO_ELLIPSIZE_NONE : PANGO_ELLIPSIZE_END);
}

OmniAdwNode *omni_adw_symbol_image_new(const char *system_name, const char *fallback_text, const char *alternative_text) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  const char *icon_name = omni_symbolic_icon_name_for_system_name(system_name);
  const char *alt = alternative_text && alternative_text[0]
      ? alternative_text
      : (fallback_text && fallback_text[0] ? fallback_text : (system_name ? system_name : "Image"));
  if (icon_name) {
    node->widget = gtk_image_new_from_icon_name(icon_name);
    gtk_widget_set_size_request(node->widget, 16, 16);
    gtk_widget_set_halign(node->widget, GTK_ALIGN_CENTER);
    gtk_widget_set_valign(node->widget, GTK_ALIGN_CENTER);
    gtk_widget_add_css_class(node->widget, "omni-symbol-image");
    omni_accessible_label(node->widget, alt);
    gtk_widget_set_tooltip_text(node->widget, alt);
    return node;
  }

  node->widget = gtk_label_new(alt);
  gtk_widget_add_css_class(node->widget, "omni-text");
  gtk_label_set_xalign(GTK_LABEL(node->widget), 0.0f);
  omni_accessible_label(node->widget, alt);
  return node;
}

OmniAdwNode *omni_adw_web_view_new(const char *url, const char *fallback_text, void *native_view) {
  GtkWidget *web_view = omni_create_webkit_web_view(url, native_view);
  if (!web_view) {
    return omni_adw_scrollable_text_node_new(fallback_text && fallback_text[0] ? fallback_text : (url ? url : "Web content unavailable"));
  }

  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = web_view;
  return node;
}

OmniAdwNode *omni_adw_web_view_new_ex(
    const char *identity,
    const char *url,
    const char *html,
    const char *base_url,
    const char *fallback_text,
    const char **request_header_names,
    const char **request_header_values,
    int32_t request_header_count,
    const char *application_name,
    const char *custom_user_agent,
    double page_zoom,
    int32_t allows_back_forward_navigation_gestures,
    int32_t javascript_can_open_windows,
    int32_t javascript_enabled,
    double minimum_font_size,
    int32_t is_inspectable,
    int32_t allows_inline_media_playback,
    int32_t media_playback_requires_user_gesture,
    const char **script_sources,
    const int32_t *script_injection_times,
    const int32_t *script_main_frame_only,
    int32_t script_count,
    const char **content_rule_identifiers,
    const char **content_rule_sources,
    int32_t content_rule_count,
    const char **message_handler_names,
    int32_t message_handler_count,
    const char **cookie_names,
    const char **cookie_values,
    const char **cookie_domains,
    const char **cookie_paths,
    const double *cookie_expires_at,
    const int32_t *cookie_secure,
    const int32_t *cookie_http_only,
    int32_t cookie_count,
    const char *accessibility_label,
    const char *accessibility_description,
    void *native_view,
    omni_adw_web_message_callback message_callback,
    omni_adw_web_navigation_callback navigation_callback,
    omni_adw_web_policy_callback policy_callback,
    omni_adw_web_response_policy_callback response_policy_callback,
    omni_adw_web_download_destination_callback download_destination_callback,
    omni_adw_web_title_callback title_callback,
    omni_adw_web_progress_callback progress_callback,
    omni_adw_web_cookie_callback cookie_callback,
    omni_adw_web_script_dialog_callback script_dialog_callback,
    void *callback_context) {
  GtkWidget *web_view = NULL;
#if defined(__APPLE__)
  if ((url && url[0]) || (html && html[0])) {
    web_view = omni_macos_web_view_new_ex(
        identity,
        url,
        html,
        base_url,
        request_header_names,
        request_header_values,
        request_header_count,
        application_name,
        custom_user_agent,
        page_zoom,
        allows_back_forward_navigation_gestures,
        javascript_can_open_windows,
        javascript_enabled,
        minimum_font_size,
        is_inspectable,
        allows_inline_media_playback,
        media_playback_requires_user_gesture,
        native_view,
        script_sources,
        script_injection_times,
        script_main_frame_only,
        script_count,
        content_rule_identifiers,
        content_rule_sources,
        content_rule_count,
        message_handler_names,
        message_handler_count,
        accessibility_label,
        accessibility_description,
        message_callback,
        navigation_callback,
        policy_callback,
        response_policy_callback,
        download_destination_callback,
        title_callback,
        progress_callback,
        cookie_callback,
        script_dialog_callback,
        callback_context);
  }
#elif defined(__linux__)
  web_view = omni_create_webkit_web_view_ex(
      identity,
      url,
      html,
      base_url,
      request_header_names,
      request_header_values,
      request_header_count,
      application_name,
      custom_user_agent,
      page_zoom,
      allows_back_forward_navigation_gestures,
      javascript_can_open_windows,
      javascript_enabled,
      minimum_font_size,
      is_inspectable,
      allows_inline_media_playback,
      media_playback_requires_user_gesture,
      script_sources,
      script_injection_times,
      script_main_frame_only,
      script_count,
      content_rule_identifiers,
      content_rule_sources,
      content_rule_count,
      message_handler_names,
      message_handler_count,
      cookie_names,
      cookie_values,
      cookie_domains,
      cookie_paths,
      cookie_expires_at,
      cookie_secure,
      cookie_http_only,
      cookie_count,
      accessibility_label,
      accessibility_description,
      message_callback,
      navigation_callback,
      policy_callback,
      response_policy_callback,
      download_destination_callback,
      title_callback,
      progress_callback,
      cookie_callback,
      script_dialog_callback,
      callback_context);
#else
  (void)identity; (void)html; (void)base_url; (void)request_header_names; (void)request_header_values; (void)request_header_count; (void)application_name; (void)custom_user_agent; (void)page_zoom; (void)allows_back_forward_navigation_gestures;
  (void)javascript_can_open_windows; (void)javascript_enabled; (void)minimum_font_size; (void)is_inspectable; (void)allows_inline_media_playback; (void)media_playback_requires_user_gesture; (void)script_sources; (void)script_injection_times; (void)script_main_frame_only;
  (void)script_count; (void)content_rule_identifiers; (void)content_rule_sources; (void)content_rule_count; (void)message_handler_names; (void)message_handler_count; (void)cookie_names; (void)cookie_values;
  (void)cookie_domains; (void)cookie_paths; (void)cookie_expires_at; (void)cookie_secure; (void)cookie_http_only; (void)cookie_count; (void)accessibility_label;
  (void)accessibility_description; (void)native_view; (void)message_callback; (void)navigation_callback; (void)policy_callback; (void)response_policy_callback; (void)download_destination_callback; (void)title_callback; (void)progress_callback; (void)cookie_callback; (void)script_dialog_callback; (void)callback_context;
#endif
  if (!web_view) {
    return omni_adw_scrollable_text_node_new(fallback_text && fallback_text[0] ? fallback_text : (url ? url : "Web content unavailable"));
  }

  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = web_view;
  return node;
}

OmniAdwNode *omni_adw_button_new(const char *label, int32_t action_id) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  const char *value = label ? label : "Button";
  node->widget = gtk_button_new_with_label(value);
  omni_button_set_label_or_symbolic_icon(GTK_BUTTON(node->widget), value);
  gtk_widget_set_halign(node->widget, omni_label_looks_iconic(value) ? GTK_ALIGN_CENTER : GTK_ALIGN_START);
  gtk_widget_set_vexpand(node->widget, FALSE);
  gtk_widget_set_valign(node->widget, GTK_ALIGN_CENTER);
  if (omni_label_looks_iconic(value)) {
    gtk_widget_add_css_class(node->widget, "omni-icon-button");
    gtk_widget_set_size_request(node->widget, 38, 34);
  } else if (strcmp(value, "Go") == 0) {
    gtk_widget_add_css_class(node->widget, "omni-go-button");
    gtk_widget_set_size_request(node->widget, 46, 34);
  }
  gtk_widget_set_focusable(node->widget, action_id > 0);
  const char *accessible_value = omni_accessible_label_for_symbolic_label(value);
  omni_accessible_label(node->widget, accessible_value ? accessible_value : value);
  omni_accessible_description(node->widget, action_id > 0 ? "Button" : "Disabled button");
  omni_accessible_set_disabled(node->widget, action_id <= 0);
  g_object_set_data(G_OBJECT(node->widget), "omni-action-id", GINT_TO_POINTER(action_id));
  g_signal_connect(node->widget, "clicked", G_CALLBACK(on_clicked), NULL);
  return node;
}

static void omni_widget_add_css_classes(GtkWidget *widget, const char *css_classes) {
  if (!widget || !css_classes || !css_classes[0]) return;
  char *copy = omni_strdup(css_classes);
  char *token = strtok(copy, " ");
  while (token) {
    gtk_widget_add_css_class(widget, token);
    token = strtok(NULL, " ");
  }
  free(copy);
}

static void omni_widget_remove_css_classes(GtkWidget *widget, const char *css_classes) {
  if (!widget || !css_classes || !css_classes[0]) return;
  char *copy = omni_strdup(css_classes);
  char *token = strtok(copy, " ");
  while (token) {
    gtk_widget_remove_css_class(widget, token);
    token = strtok(NULL, " ");
  }
  free(copy);
}

static void omni_widget_replace_css_classes(GtkWidget *widget, const char *storage_key, const char *css_classes) {
  if (!widget || !storage_key) return;
  const char *previous = (const char *)g_object_get_data(G_OBJECT(widget), storage_key);
  if (previous && previous[0]) {
    omni_widget_remove_css_classes(widget, previous);
  }
  if (css_classes && css_classes[0]) {
    omni_widget_add_css_classes(widget, css_classes);
    g_object_set_data_full(G_OBJECT(widget), storage_key, omni_strdup(css_classes), free);
  } else {
    g_object_set_data(G_OBJECT(widget), storage_key, NULL);
  }
}

OmniAdwNode *omni_adw_click_container_new(const char *label, int32_t action_id) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_button_new();
  gtk_widget_add_css_class(node->widget, "omni-click-container");
  gtk_widget_add_css_class(node->widget, "flat");
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  gtk_widget_set_focusable(node->widget, action_id > 0);
  g_object_set_data(G_OBJECT(node->widget), "omni-action-id", GINT_TO_POINTER(action_id));
  omni_accessible_label(node->widget, label && label[0] ? label : "Action");
  omni_accessible_description(node->widget, action_id > 0 ? "Button" : "Disabled button");
  omni_accessible_set_disabled(node->widget, action_id <= 0);
  g_signal_connect(node->widget, "clicked", G_CALLBACK(on_clicked), NULL);
  return node;
}

OmniAdwNode *omni_adw_inline_button_new(const char *label, int32_t action_id, const char *css_classes) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  const char *value = label ? label : "Button";
  node->widget = gtk_button_new_with_label(value);
  gtk_widget_add_css_class(node->widget, "flat");
  gtk_widget_add_css_class(node->widget, "omni-inline-link-button");
  omni_widget_add_css_classes(node->widget, css_classes);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_START);
  gtk_widget_set_valign(node->widget, GTK_ALIGN_CENTER);
  gtk_widget_set_focusable(node->widget, action_id > 0);
  g_object_set_data(G_OBJECT(node->widget), "omni-action-id", GINT_TO_POINTER(action_id));
  omni_accessible_label(node->widget, value);
  omni_accessible_description(node->widget, action_id > 0 ? "Inline button" : "Disabled inline button");
  omni_accessible_set_disabled(node->widget, action_id <= 0);
  g_signal_connect(node->widget, "clicked", G_CALLBACK(on_clicked), NULL);
  return node;
}

OmniAdwNode *omni_adw_context_menu_new(const char **labels, const int32_t *action_ids, int32_t count) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_add_css_class(node->widget, "omni-context-menu-region");
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);

  if (count > 0) {
    GtkWidget *popover = gtk_popover_new();
    GtkWidget *menu_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    gtk_widget_add_css_class(menu_box, "menu");
    gtk_widget_set_margin_top(menu_box, 6);
    gtk_widget_set_margin_bottom(menu_box, 6);
    gtk_widget_set_margin_start(menu_box, 6);
    gtk_widget_set_margin_end(menu_box, 6);
    for (int32_t i = 0; i < count; i++) {
      const char *label = labels && labels[i] ? labels[i] : "";
      int32_t action_id = action_ids ? action_ids[i] : 0;
      GtkWidget *button = gtk_button_new_with_label(label);
      gtk_widget_add_css_class(button, "flat");
      gtk_widget_set_hexpand(button, TRUE);
      gtk_widget_set_halign(button, GTK_ALIGN_FILL);
      gtk_widget_set_focusable(button, action_id > 0);
      g_object_set_data(G_OBJECT(button), "omni-action-id", GINT_TO_POINTER(action_id));
      g_object_set_data(G_OBJECT(button), "omni-owner", node->widget);
      omni_accessible_label(button, label);
      omni_accessible_description(button, action_id > 0 ? "Context menu item" : "Disabled context menu item");
      omni_accessible_set_disabled(button, action_id <= 0);
      g_signal_connect(button, "clicked", G_CALLBACK(on_menu_option_clicked), popover);
      gtk_box_append(GTK_BOX(menu_box), button);
    }
    gtk_popover_set_child(GTK_POPOVER(popover), menu_box);
    gtk_widget_set_parent(popover, node->widget);
    gtk_accessible_update_property(GTK_ACCESSIBLE(node->widget), GTK_ACCESSIBLE_PROPERTY_HAS_POPUP, TRUE, -1);
    g_object_set_data_full(
        G_OBJECT(node->widget),
        "omni-context-menu-popover",
        g_object_ref(popover),
        omni_context_menu_popover_owner_data_free);

    GtkGesture *click_controller = gtk_gesture_click_new();
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(click_controller), GDK_BUTTON_SECONDARY);
    gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(click_controller), GTK_PHASE_CAPTURE);
    g_signal_connect(click_controller, "pressed", G_CALLBACK(on_context_menu_pressed), NULL);
    gtk_widget_add_controller(node->widget, GTK_EVENT_CONTROLLER(click_controller));
  }

  return node;
}

OmniAdwNode *omni_adw_toggle_new(const char *label, int32_t active, int32_t action_id) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_check_button_new_with_label(label ? label : "");
  gtk_widget_set_halign(node->widget, GTK_ALIGN_START);
  gtk_widget_set_vexpand(node->widget, FALSE);
  gtk_widget_set_valign(node->widget, GTK_ALIGN_CENTER);
  gtk_check_button_set_active(GTK_CHECK_BUTTON(node->widget), active != 0);
  omni_accessible_label(node->widget, label);
  gtk_accessible_update_state(GTK_ACCESSIBLE(node->widget), GTK_ACCESSIBLE_STATE_CHECKED, active ? GTK_ACCESSIBLE_TRISTATE_TRUE : GTK_ACCESSIBLE_TRISTATE_FALSE, -1);
  g_object_set_data(G_OBJECT(node->widget), "omni-action-id", GINT_TO_POINTER(action_id));
  g_signal_connect(node->widget, "toggled", G_CALLBACK(on_toggled), NULL);
  return node;
}

OmniAdwNode *omni_adw_entry_new(const char *placeholder, const char *text, int32_t action_id) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_entry_new();
  gtk_widget_set_size_request(node->widget, 360, -1);
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_vexpand(node->widget, FALSE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  gtk_widget_set_valign(node->widget, GTK_ALIGN_CENTER);
  gtk_entry_set_placeholder_text(GTK_ENTRY(node->widget), placeholder ? placeholder : "");
  gtk_editable_set_text(GTK_EDITABLE(node->widget), text ? text : "");
  omni_accessible_label(node->widget, placeholder && placeholder[0] ? placeholder : text);
  omni_accessible_placeholder(node->widget, placeholder);
  omni_accessible_value_text(node->widget, text);
  g_object_set_data(G_OBJECT(node->widget), "omni-action-id", GINT_TO_POINTER(action_id));
  g_signal_connect(node->widget, "changed", G_CALLBACK(on_entry_changed), NULL);
  g_signal_connect(node->widget, "activate", G_CALLBACK(on_entry_activate), NULL);
  return node;
}

OmniAdwNode *omni_adw_secure_entry_new(const char *placeholder, const char *text, int32_t action_id) {
  OmniAdwNode *node = omni_adw_entry_new(placeholder, text, action_id);
  if (node && node->widget && GTK_IS_ENTRY(node->widget)) {
    gtk_entry_set_visibility(GTK_ENTRY(node->widget), FALSE);
    gtk_entry_set_invisible_char(GTK_ENTRY(node->widget), 0x2022);
    omni_accessible_value_text(node->widget, text);
  }
  return node;
}

OmniAdwNode *omni_adw_image_new(const uint8_t *data, int32_t length, const char *alternative_text) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  const char *alt = alternative_text ? alternative_text : "Image";
  if (!data || length <= 0) {
    node->widget = gtk_label_new(alt);
    gtk_label_set_xalign(GTK_LABEL(node->widget), 0.0f);
    omni_accessible_label(node->widget, alt);
    return node;
  }

  GBytes *bytes = g_bytes_new(data, (gsize)length);
  GError *error = NULL;
  GdkTexture *texture = gdk_texture_new_from_bytes(bytes, &error);
  g_bytes_unref(bytes);
  if (!texture) {
    if (error) g_error_free(error);
    node->widget = gtk_label_new(alt);
    gtk_label_set_xalign(GTK_LABEL(node->widget), 0.0f);
    omni_accessible_label(node->widget, alt);
    return node;
  }

  node->widget = gtk_picture_new_for_paintable(GDK_PAINTABLE(texture));
  gtk_picture_set_content_fit(GTK_PICTURE(node->widget), GTK_CONTENT_FIT_COVER);
  gtk_picture_set_can_shrink(GTK_PICTURE(node->widget), TRUE);
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_vexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  gtk_widget_set_valign(node->widget, GTK_ALIGN_FILL);
  gtk_widget_add_css_class(node->widget, "omni-image");
  gtk_picture_set_alternative_text(GTK_PICTURE(node->widget), alt);
  omni_accessible_label(node->widget, alt);
  g_object_unref(texture);
  return node;
}

OmniAdwNode *omni_adw_text_view_new(const char *text, int32_t action_id) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_text_view_new();
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_vexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  gtk_widget_set_valign(node->widget, GTK_ALIGN_FILL);
  gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(node->widget), GTK_WRAP_WORD_CHAR);
  gtk_text_view_set_monospace(GTK_TEXT_VIEW(node->widget), FALSE);
  gtk_widget_set_size_request(node->widget, -1, 96);
  GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(node->widget));
  gtk_text_buffer_set_text(buffer, text ? text : "", -1);
  omni_accessible_label(node->widget, text);
  omni_accessible_multi_line(node->widget, TRUE);
  omni_accessible_value_text(node->widget, text);
  g_object_set_data(G_OBJECT(node->widget), "omni-action-id", GINT_TO_POINTER(action_id));
  g_signal_connect(buffer, "changed", G_CALLBACK(on_text_buffer_changed), node->widget);
  return node;
}

OmniAdwNode *omni_adw_dropdown_new(const char *title, const char *value, const char **labels, const int32_t *action_ids, int32_t count, int32_t expanded) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  GtkStringList *model = gtk_string_list_new(NULL);
  guint selected_index = GTK_INVALID_LIST_POSITION;
  for (int32_t i = 0; i < count; i++) {
    const char *label = labels && labels[i] ? labels[i] : "";
    gtk_string_list_append(model, label);
    if (value && strcmp(value, label) == 0) selected_index = (guint)i;
  }
  node->widget = gtk_drop_down_new(G_LIST_MODEL(model), NULL);
  if (selected_index != GTK_INVALID_LIST_POSITION) {
    g_object_set_data(G_OBJECT(node->widget), "omni-updating", GINT_TO_POINTER(1));
    gtk_drop_down_set_selected(GTK_DROP_DOWN(node->widget), selected_index);
    g_object_set_data(G_OBJECT(node->widget), "omni-updating", NULL);
  }
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_vexpand(node->widget, FALSE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  gtk_widget_set_valign(node->widget, GTK_ALIGN_CENTER);
  g_signal_connect(node->widget, "notify::selected", G_CALLBACK(on_dropdown_selected), NULL);
  const char *selected_label = selected_index != GTK_INVALID_LIST_POSITION && labels && labels[selected_index] ? labels[selected_index] : "";
  omni_accessible_label(node->widget, title && title[0] ? title : "Select");
  omni_accessible_value_text(node->widget, selected_label);
  gtk_accessible_update_property(GTK_ACCESSIBLE(node->widget), GTK_ACCESSIBLE_PROPERTY_HAS_POPUP, TRUE, -1);
  if (title && title[0]) {
    gtk_widget_set_tooltip_text(node->widget, title);
  }
  int32_t *ids = NULL;
  if (count > 0) {
    ids = calloc((size_t)count, sizeof(int32_t));
    for (int32_t i = 0; i < count; i++) ids[i] = action_ids ? action_ids[i] : 0;
  }
  g_object_set_data_full(G_OBJECT(node->widget), "omni-action-ids", ids, free);
  char **label_copies = calloc((size_t)count + 1, sizeof(char *));
  for (int32_t i = 0; i < count; i++) {
    label_copies[i] = omni_strdup(labels && labels[i] ? labels[i] : "");
  }
  g_object_set_data_full(G_OBJECT(node->widget), "omni-labels", label_copies, free_label_array);
  g_object_set_data(G_OBJECT(node->widget), "omni-action-count", GINT_TO_POINTER(count));
  if (expanded) {
    gtk_widget_grab_focus(node->widget);
  }
  return node;
}

OmniAdwNode *omni_adw_segmented_new(const char *title, const char **labels, const int32_t *action_ids, int32_t selected_index, int32_t count) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  if (!node) return NULL;
  GtkWidget *group = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_add_css_class(group, "linked");
  gtk_widget_add_css_class(group, "omni-segmented-control");
  gtk_widget_set_valign(group, GTK_ALIGN_CENTER);
  omni_accessible_label(group, title && title[0] ? title : "Segmented control");
  omni_accessible_role_description(group, "segmented control");

  for (int32_t i = 0; i < count; i++) {
    const char *label = labels && labels[i] ? labels[i] : "";
    if (!label[0]) continue;
    int32_t action_id = action_ids ? action_ids[i] : 0;
    GtkWidget *button = gtk_button_new_with_label(label);
    gtk_widget_add_css_class(button, "flat");
    gtk_widget_set_focusable(button, action_id > 0);
    gtk_widget_set_valign(button, GTK_ALIGN_CENTER);
    omni_accessible_label(button, label);
    omni_accessible_description(button, i == selected_index ? "Selected segmented control item" : "Segmented control item");
    if (i == selected_index) {
      gtk_widget_add_css_class(button, "omni-selected-segment");
      omni_accessible_set_selected(button, TRUE);
    }
    if (action_id > 0) {
      g_object_set_data(G_OBJECT(button), "omni-action-id", GINT_TO_POINTER(action_id));
      g_signal_connect(button, "clicked", G_CALLBACK(on_clicked), NULL);
    } else {
      gtk_widget_set_sensitive(button, FALSE);
      omni_accessible_set_disabled(button, TRUE);
    }
    gtk_box_append(GTK_BOX(group), button);
  }

  node->widget = group;
  return node;
}

OmniAdwNode *omni_adw_progress_new(const char *label, double fraction) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_progress_bar_new();
  if (fraction < 0.0) fraction = 0.0;
  if (fraction > 1.0) fraction = 1.0;
  gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(node->widget), fraction);
  gtk_progress_bar_set_show_text(GTK_PROGRESS_BAR(node->widget), TRUE);
  if (label && label[0]) {
    gtk_progress_bar_set_text(GTK_PROGRESS_BAR(node->widget), label);
    omni_accessible_label(node->widget, label);
    omni_accessible_value_text(node->widget, label);
    gtk_widget_set_tooltip_text(node->widget, label);
  }
  gtk_accessible_update_property(
    GTK_ACCESSIBLE(node->widget),
    GTK_ACCESSIBLE_PROPERTY_VALUE_MIN, 0.0,
    GTK_ACCESSIBLE_PROPERTY_VALUE_MAX, 1.0,
    GTK_ACCESSIBLE_PROPERTY_VALUE_NOW, fraction,
    -1
  );
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  return node;
}

OmniAdwNode *omni_adw_scale_new(const char *label, double value, double lower, double upper, double step, int32_t set_action_id, int32_t decrement_action_id, int32_t increment_action_id) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  if (upper <= lower) upper = lower + 1.0;
  if (step <= 0.0) step = (upper - lower) / 10.0;
  if (value < lower) value = lower;
  if (value > upper) value = upper;
  node->widget = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, lower, upper, step);
  gtk_range_set_value(GTK_RANGE(node->widget), value);
  gtk_scale_set_draw_value(GTK_SCALE(node->widget), TRUE);
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  if (label && label[0]) {
    omni_accessible_label(node->widget, label);
    gtk_widget_set_tooltip_text(node->widget, label);
  }
  gtk_accessible_update_property(
    GTK_ACCESSIBLE(node->widget),
    GTK_ACCESSIBLE_PROPERTY_VALUE_MIN, lower,
    GTK_ACCESSIBLE_PROPERTY_VALUE_MAX, upper,
    GTK_ACCESSIBLE_PROPERTY_VALUE_NOW, value,
    -1
  );
  g_object_set_data(G_OBJECT(node->widget), "omni-set-action-id", GINT_TO_POINTER(set_action_id));
  g_object_set_data(G_OBJECT(node->widget), "omni-decrement-action-id", GINT_TO_POINTER(decrement_action_id));
  g_object_set_data(G_OBJECT(node->widget), "omni-increment-action-id", GINT_TO_POINTER(increment_action_id));
  double *stored_value = malloc(sizeof(double));
  if (stored_value) {
    *stored_value = value;
    g_object_set_data_full(G_OBJECT(node->widget), "omni-scale-value", stored_value, free);
  }
  g_signal_connect(node->widget, "value-changed", G_CALLBACK(on_scale_value_changed), NULL);
  return node;
}

OmniAdwNode *omni_adw_spin_new(const char *label, double value, int32_t decrement_action_id, int32_t increment_action_id) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_spin_button_new_with_range(-1000000.0, 1000000.0, 1.0);
  gtk_spin_button_set_value(GTK_SPIN_BUTTON(node->widget), value);
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  if (label && label[0]) {
    omni_accessible_label(node->widget, label);
    gtk_widget_set_tooltip_text(node->widget, label);
  }
  gtk_accessible_update_property(GTK_ACCESSIBLE(node->widget), GTK_ACCESSIBLE_PROPERTY_VALUE_NOW, value, -1);
  g_object_set_data(G_OBJECT(node->widget), "omni-decrement-action-id", GINT_TO_POINTER(decrement_action_id));
  g_object_set_data(G_OBJECT(node->widget), "omni-increment-action-id", GINT_TO_POINTER(increment_action_id));
  double *stored_value = malloc(sizeof(double));
  if (stored_value) {
    *stored_value = value;
    g_object_set_data_full(G_OBJECT(node->widget), "omni-spin-value", stored_value, free);
  }
  g_signal_connect(node->widget, "value-changed", G_CALLBACK(on_spin_value_changed), NULL);
  return node;
}

OmniAdwNode *omni_adw_date_new(const char *label, const char *value, double timestamp, int32_t set_action_id, int32_t decrement_action_id, int32_t increment_action_id) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
  const char *date_label = label && label[0] ? label : "Date";
  const char *date_value = value ? value : "";
  char *combined = g_strdup_printf("%s: %s", date_label, date_value);
  GtkWidget *caption = gtk_label_new(combined);
  gtk_label_set_xalign(GTK_LABEL(caption), 0.0f);
  GtkWidget *button = gtk_menu_button_new();
  gtk_menu_button_set_label(GTK_MENU_BUTTON(button), date_value);
  omni_accessible_label(button, date_label);
  omni_accessible_value_text(button, date_value);
  gtk_accessible_update_property(GTK_ACCESSIBLE(button), GTK_ACCESSIBLE_PROPERTY_HAS_POPUP, TRUE, -1);
  GtkWidget *popover = gtk_popover_new();
  GtkWidget *calendar = gtk_calendar_new();
  gtk_widget_set_focusable(calendar, FALSE);
  omni_accessible_label(calendar, date_label);
  GDateTime *dt = g_date_time_new_from_unix_local((gint64)timestamp);
  if (dt) {
    omni_calendar_set_date(GTK_CALENDAR(calendar), dt);
  }
  gtk_widget_set_hexpand(box, TRUE);
  gtk_widget_set_halign(box, GTK_ALIGN_FILL);
  gtk_widget_set_hexpand(caption, TRUE);
  gtk_widget_set_halign(caption, GTK_ALIGN_FILL);
  gtk_widget_set_hexpand(button, TRUE);
  gtk_widget_set_halign(button, GTK_ALIGN_FILL);
  gtk_widget_set_hexpand(calendar, TRUE);
  gtk_widget_set_halign(calendar, GTK_ALIGN_FILL);
  gtk_popover_set_child(GTK_POPOVER(popover), calendar);
  gtk_menu_button_set_popover(GTK_MENU_BUTTON(button), GTK_WIDGET(popover));
  gtk_box_append(GTK_BOX(box), caption);
  gtk_box_append(GTK_BOX(box), button);
  g_object_set_data(G_OBJECT(calendar), "omni-set-action-id", GINT_TO_POINTER(set_action_id));
  g_object_set_data(G_OBJECT(calendar), "omni-decrement-action-id", GINT_TO_POINTER(decrement_action_id));
  g_object_set_data(G_OBJECT(calendar), "omni-increment-action-id", GINT_TO_POINTER(increment_action_id));
  gint64 *stored_day = malloc(sizeof(gint64));
  if (stored_day) {
    if (dt) {
      *stored_day = (gint64)g_date_time_get_year(dt) * 10000 +
        (gint64)g_date_time_get_month(dt) * 100 +
        (gint64)g_date_time_get_day_of_month(dt);
    } else {
      *stored_day = 0;
    }
    g_object_set_data_full(G_OBJECT(calendar), "omni-calendar-day", stored_day, free);
  }
  if (dt) g_date_time_unref(dt);
  g_signal_connect(calendar, "notify::day", G_CALLBACK(on_calendar_date_notify), NULL);
  g_signal_connect(calendar, "notify::month", G_CALLBACK(on_calendar_date_notify), NULL);
  g_signal_connect(calendar, "notify::year", G_CALLBACK(on_calendar_date_notify), NULL);
  omni_accessible_label(box, combined);
  omni_accessible_value_text(box, date_value);
  gtk_widget_set_tooltip_text(box, combined);
  g_free(combined);
  node->widget = box;
  return node;
}

OmniAdwNode *omni_adw_action_row_new(const char *title, const char *subtitle) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  if (!node) return NULL;
  node->widget = adw_action_row_new();
  adw_preferences_row_set_title(ADW_PREFERENCES_ROW(node->widget), title && title[0] ? title : "Setting");
  if (subtitle && subtitle[0]) {
    adw_action_row_set_subtitle(ADW_ACTION_ROW(node->widget), subtitle);
  }
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  omni_accessible_label(node->widget, title && title[0] ? title : "Setting");
  omni_accessible_value_text(node->widget, subtitle);
  return node;
}

OmniAdwNode *omni_adw_switch_row_new(const char *title, int32_t active, int32_t action_id) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  if (!node) return NULL;
  node->widget = adw_switch_row_new();
  adw_preferences_row_set_title(ADW_PREFERENCES_ROW(node->widget), title && title[0] ? title : "Setting");
  adw_switch_row_set_active(ADW_SWITCH_ROW(node->widget), active != 0);
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  omni_accessible_label(node->widget, title && title[0] ? title : "Setting");
  gtk_accessible_update_state(GTK_ACCESSIBLE(node->widget), GTK_ACCESSIBLE_STATE_CHECKED, active ? GTK_ACCESSIBLE_TRISTATE_TRUE : GTK_ACCESSIBLE_TRISTATE_FALSE, -1);
  g_object_set_data(G_OBJECT(node->widget), "omni-action-id", GINT_TO_POINTER(action_id));
  g_signal_connect(node->widget, "notify::active", G_CALLBACK(on_switch_row_active_notify), NULL);
  return node;
}

OmniAdwNode *omni_adw_color_button_new(const char *label, const char *value, int32_t supports_opacity, int32_t set_action_id) {
  gboolean has_label = label && label[0];
  OmniAdwNode *node = has_label ? omni_adw_action_row_new(label, "") : calloc(1, sizeof(OmniAdwNode));
  if (!node) return NULL;

  GdkRGBA color;
  if (!omni_parse_semantic_color(value, &color)) {
    omni_set_rgba(&color, 53.0 / 255.0, 132.0 / 255.0, 228.0 / 255.0, 1.0);
  }

  GtkWidget *button = gtk_menu_button_new();
  gtk_widget_add_css_class(button, "omni-color-menu-button");
  gtk_widget_set_valign(button, GTK_ALIGN_CENTER);
  gtk_widget_set_halign(button, GTK_ALIGN_END);
  gtk_widget_set_tooltip_text(button, has_label ? label : "Color");
  gtk_menu_button_set_child(GTK_MENU_BUTTON(button), omni_color_swatch_widget_new(&color, 28, 18));
  omni_accessible_label(button, has_label ? label : "Color");
  omni_accessible_value_text(button, value);

  GtkWidget *popover = gtk_popover_new();
  OmniColorControlData *control = g_new0(OmniColorControlData, 1);
  if (control) {
    control->button = button;
    control->popover = popover;
    control->set_action_id = set_action_id;
    control->supports_opacity = supports_opacity != 0;
    g_object_set_data_full(G_OBJECT(button), "omni-color-control-data", control, g_free);
    if (node->widget && node->widget != button) {
      g_object_set_data(G_OBJECT(node->widget), "omni-color-control-data", control);
    }
  }

  GtkWidget *content = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
  gtk_widget_set_margin_top(content, 10);
  gtk_widget_set_margin_bottom(content, 10);
  gtk_widget_set_margin_start(content, 10);
  gtk_widget_set_margin_end(content, 10);

  GtkWidget *sliders = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  const char *channel_names[] = {"Red", "Green", "Blue", "Opacity"};
  double channel_values[] = {color.red, color.green, color.blue, color.alpha};
  GtkWidget **channel_scales[] = {
    control ? &control->red_scale : NULL,
    control ? &control->green_scale : NULL,
    control ? &control->blue_scale : NULL,
    control ? &control->alpha_scale : NULL,
  };
  int channel_count = supports_opacity ? 4 : 3;
  for (int i = 0; i < channel_count; i++) {
    GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *caption = gtk_label_new(channel_names[i]);
    gtk_widget_set_size_request(caption, 58, -1);
    gtk_label_set_xalign(GTK_LABEL(caption), 0.0f);
    GtkWidget *scale = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 0.0, 1.0, 0.01);
    gtk_scale_set_draw_value(GTK_SCALE(scale), TRUE);
    gtk_scale_set_digits(GTK_SCALE(scale), 2);
    gtk_range_set_value(GTK_RANGE(scale), omni_unit_clamp(channel_values[i]));
    gtk_widget_set_size_request(scale, 180, -1);
    gtk_widget_set_hexpand(scale, TRUE);
    gtk_widget_set_halign(scale, GTK_ALIGN_FILL);
    omni_accessible_label(scale, channel_names[i]);
    gtk_accessible_update_property(GTK_ACCESSIBLE(scale), GTK_ACCESSIBLE_PROPERTY_VALUE_NOW, omni_unit_clamp(channel_values[i]), -1);
    if (channel_scales[i]) *channel_scales[i] = scale;
    if (control) g_signal_connect(scale, "value-changed", G_CALLBACK(on_color_channel_value_changed), control);
    gtk_box_append(GTK_BOX(row), caption);
    gtk_box_append(GTK_BOX(row), scale);
    gtk_box_append(GTK_BOX(sliders), row);
  }
  gtk_box_append(GTK_BOX(content), sliders);

  GtkWidget *separator = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
  gtk_box_append(GTK_BOX(content), separator);

  GtkWidget *grid = gtk_grid_new();
  gtk_grid_set_row_spacing(GTK_GRID(grid), 6);
  gtk_grid_set_column_spacing(GTK_GRID(grid), 6);

  const char *names[] = {"Black", "White", "Gray", "Red", "Orange", "Yellow", "Green", "Blue", "Purple"};
  const char *values[] = {"black|1", "white|1", "gray|1", "red|1", "orange|1", "yellow|1", "green|1", "blue|1", "purple|1"};
  int count = (int)(sizeof(values) / sizeof(values[0]));
  for (int i = 0; i < count; i++) {
    GdkRGBA swatch_color;
    if (!omni_parse_semantic_color(values[i], &swatch_color)) {
      omni_set_rgba(&swatch_color, 53.0 / 255.0, 132.0 / 255.0, 228.0 / 255.0, 1.0);
    }
    GtkWidget *swatch_button = gtk_button_new();
    gtk_widget_add_css_class(swatch_button, "flat");
    gtk_widget_add_css_class(swatch_button, "omni-color-swatch-button");
    gtk_button_set_child(GTK_BUTTON(swatch_button), omni_color_swatch_widget_new(&swatch_color, 22, 16));
    gtk_widget_set_tooltip_text(swatch_button, names[i]);
    omni_accessible_label(swatch_button, names[i]);
    omni_accessible_value_text(swatch_button, values[i]);
    g_object_set_data_full(G_OBJECT(swatch_button), "omni-color-value", g_strdup(values[i]), g_free);
    g_signal_connect(swatch_button, "clicked", G_CALLBACK(on_color_swatch_clicked), control);
    gtk_grid_attach(GTK_GRID(grid), swatch_button, i % 3, i / 3, 1, 1);
  }

  gtk_box_append(GTK_BOX(content), grid);
  gtk_popover_set_child(GTK_POPOVER(popover), content);
  gtk_menu_button_set_popover(GTK_MENU_BUTTON(button), popover);
  if (has_label) {
    adw_action_row_add_suffix(ADW_ACTION_ROW(node->widget), button);
    adw_action_row_set_activatable_widget(ADW_ACTION_ROW(node->widget), button);
  } else {
    node->widget = button;
    gtk_widget_set_hexpand(node->widget, FALSE);
    gtk_widget_set_halign(node->widget, GTK_ALIGN_START);
  }
  return node;
}

OmniAdwNode *omni_adw_expander_new(const char *title, int32_t expanded, int32_t action_id) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  if (!node) return NULL;
  node->widget = adw_expander_row_new();
  adw_preferences_row_set_title(ADW_PREFERENCES_ROW(node->widget), title && title[0] ? title : "Details");
  adw_expander_row_set_enable_expansion(ADW_EXPANDER_ROW(node->widget), TRUE);
  adw_expander_row_set_expanded(ADW_EXPANDER_ROW(node->widget), expanded != 0);
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  omni_accessible_label(node->widget, title && title[0] ? title : "Details");
  omni_accessible_set_expanded(node->widget, expanded != 0);
  g_object_set_data(G_OBJECT(node->widget), "omni-action-id", GINT_TO_POINTER(action_id));
  g_signal_connect(node->widget, "notify::expanded", G_CALLBACK(on_expander_expanded_notify), NULL);
  return node;
}

OmniAdwNode *omni_adw_preferences_group_new(const char *title, const char *description) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  if (!node) return NULL;
  node->widget = adw_preferences_group_new();
  if (title && title[0]) {
    adw_preferences_group_set_title(ADW_PREFERENCES_GROUP(node->widget), title);
    omni_accessible_label(node->widget, title);
  }
  if (description && description[0]) {
    adw_preferences_group_set_description(ADW_PREFERENCES_GROUP(node->widget), description);
    omni_accessible_description(node->widget, description);
  }
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  return node;
}

OmniAdwNode *omni_adw_status_page_new(const char *title, const char *description) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  if (!node) return NULL;
  node->widget = adw_status_page_new();
  adw_status_page_set_icon_name(ADW_STATUS_PAGE(node->widget), "dialog-information-symbolic");
  adw_status_page_set_title(ADW_STATUS_PAGE(node->widget), title && title[0] ? title : "No Content");
  if (description && description[0]) {
    adw_status_page_set_description(ADW_STATUS_PAGE(node->widget), description);
  }
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  gtk_widget_set_vexpand(node->widget, TRUE);
  gtk_widget_set_valign(node->widget, GTK_ALIGN_FILL);
  omni_accessible_label(node->widget, title && title[0] ? title : "No Content");
  omni_accessible_description(node->widget, description);
  return node;
}

OmniAdwNode *omni_adw_scroll_new(int32_t vertical, double offset) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_scrolled_window_new();
  gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(node->widget), vertical ? GTK_POLICY_NEVER : GTK_POLICY_AUTOMATIC, vertical ? GTK_POLICY_AUTOMATIC : GTK_POLICY_NEVER);
  gtk_scrolled_window_set_propagate_natural_height(GTK_SCROLLED_WINDOW(node->widget), FALSE);
  gtk_scrolled_window_set_propagate_natural_width(GTK_SCROLLED_WINDOW(node->widget), FALSE);
  g_object_set_data(G_OBJECT(node->widget), "omni-scroll-vertical", GINT_TO_POINTER(vertical != 0));
  if (offset > 0.0) {
    double *stored_offset = malloc(sizeof(double));
    if (stored_offset) {
      *stored_offset = omni_semantic_scroll_to_pixels(offset);
      g_object_set_data_full(G_OBJECT(node->widget), "omni-scroll-offset", stored_offset, free);
    }
  }
  omni_widget_expand(node->widget, vertical != 0);
  omni_accessible_label(node->widget, vertical ? "Vertical scroll area" : "Horizontal scroll area");
  gtk_accessible_update_property(
    GTK_ACCESSIBLE(node->widget),
    GTK_ACCESSIBLE_PROPERTY_ORIENTATION, vertical ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL,
    -1
  );
  return node;
}

OmniAdwNode *omni_adw_separator_new(void) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
  omni_accessible_role_description(node->widget, "separator");
  return node;
}

static double omni_unit_clamp(double value) {
  if (value < 0.0) return 0.0;
  if (value > 1.0) return 1.0;
  return value;
}

static void omni_set_rgba(GdkRGBA *color, double red, double green, double blue, double alpha) {
  if (!color) return;
  color->red = omni_unit_clamp(red);
  color->green = omni_unit_clamp(green);
  color->blue = omni_unit_clamp(blue);
  color->alpha = omni_unit_clamp(alpha);
}

static gboolean omni_named_semantic_color(const char *name, GdkRGBA *color) {
  if (!name || !name[0] || !color) return FALSE;
  AdwStyleManager *manager = adw_style_manager_get_default();
  gboolean dark = manager ? adw_style_manager_get_dark(manager) : FALSE;

  if (g_ascii_strcasecmp(name, "clear") == 0) {
    omni_set_rgba(color, 0.0, 0.0, 0.0, 0.0);
  } else if (g_ascii_strcasecmp(name, "primary") == 0 || g_ascii_strcasecmp(name, "native") == 0) {
    omni_set_rgba(color, dark ? 245.0 / 255.0 : 29.0 / 255.0, dark ? 245.0 / 255.0 : 29.0 / 255.0, dark ? 247.0 / 255.0 : 31.0 / 255.0, 1.0);
  } else if (g_ascii_strcasecmp(name, "secondary") == 0) {
    omni_set_rgba(color, dark ? 245.0 / 255.0 : 29.0 / 255.0, dark ? 245.0 / 255.0 : 29.0 / 255.0, dark ? 247.0 / 255.0 : 31.0 / 255.0, 0.72);
  } else if (g_ascii_strcasecmp(name, "tertiary") == 0) {
    omni_set_rgba(color, dark ? 245.0 / 255.0 : 29.0 / 255.0, dark ? 245.0 / 255.0 : 29.0 / 255.0, dark ? 247.0 / 255.0 : 31.0 / 255.0, 0.55);
  } else if (g_ascii_strcasecmp(name, "quaternary") == 0) {
    omni_set_rgba(color, dark ? 245.0 / 255.0 : 29.0 / 255.0, dark ? 245.0 / 255.0 : 29.0 / 255.0, dark ? 247.0 / 255.0 : 31.0 / 255.0, 0.35);
  } else if (g_ascii_strcasecmp(name, "accentColor") == 0 || g_ascii_strcasecmp(name, "tint") == 0) {
    omni_set_rgba(color, 53.0 / 255.0, 132.0 / 255.0, 228.0 / 255.0, 1.0);
  } else if (g_ascii_strcasecmp(name, "black") == 0) {
    omni_set_rgba(color, 0.0, 0.0, 0.0, 1.0);
  } else if (g_ascii_strcasecmp(name, "white") == 0) {
    omni_set_rgba(color, 1.0, 1.0, 1.0, 1.0);
  } else if (g_ascii_strcasecmp(name, "gray") == 0 || g_ascii_strcasecmp(name, "grey") == 0) {
    omni_set_rgba(color, 142.0 / 255.0, 142.0 / 255.0, 147.0 / 255.0, 1.0);
  } else if (g_ascii_strcasecmp(name, "red") == 0) {
    omni_set_rgba(color, 1.0, 69.0 / 255.0, 58.0 / 255.0, 1.0);
  } else if (g_ascii_strcasecmp(name, "orange") == 0) {
    omni_set_rgba(color, 1.0, 149.0 / 255.0, 0.0, 1.0);
  } else if (g_ascii_strcasecmp(name, "yellow") == 0) {
    omni_set_rgba(color, 191.0 / 255.0, 127.0 / 255.0, 0.0, 1.0);
  } else if (g_ascii_strcasecmp(name, "green") == 0) {
    omni_set_rgba(color, 36.0 / 255.0, 138.0 / 255.0, 61.0 / 255.0, 1.0);
  } else if (g_ascii_strcasecmp(name, "mint") == 0) {
    omni_set_rgba(color, 0.0, 166.0 / 255.0, 153.0 / 255.0, 1.0);
  } else if (g_ascii_strcasecmp(name, "teal") == 0) {
    omni_set_rgba(color, 10.0 / 255.0, 127.0 / 255.0, 143.0 / 255.0, 1.0);
  } else if (g_ascii_strcasecmp(name, "cyan") == 0) {
    omni_set_rgba(color, 0.0, 122.0 / 255.0, 153.0 / 255.0, 1.0);
  } else if (g_ascii_strcasecmp(name, "blue") == 0) {
    omni_set_rgba(color, 10.0 / 255.0, 132.0 / 255.0, 1.0, 1.0);
  } else if (g_ascii_strcasecmp(name, "indigo") == 0) {
    omni_set_rgba(color, 94.0 / 255.0, 92.0 / 255.0, 230.0 / 255.0, 1.0);
  } else if (g_ascii_strcasecmp(name, "purple") == 0) {
    omni_set_rgba(color, 175.0 / 255.0, 82.0 / 255.0, 222.0 / 255.0, 1.0);
  } else if (g_ascii_strcasecmp(name, "pink") == 0) {
    omni_set_rgba(color, 1.0, 45.0 / 255.0, 85.0 / 255.0, 1.0);
  } else if (g_ascii_strcasecmp(name, "brown") == 0) {
    omni_set_rgba(color, 142.0 / 255.0, 110.0 / 255.0, 83.0 / 255.0, 1.0);
  } else {
    return FALSE;
  }
  return TRUE;
}

static gboolean omni_parse_rgb_function(const char *base, GdkRGBA *color) {
  if (!base || !color) return FALSE;
  gboolean has_inline_alpha = FALSE;
  const char *rgb = strstr(base, "rgba(");
  if (rgb) {
    rgb += 5;
    has_inline_alpha = TRUE;
  } else {
    rgb = strstr(base, "rgb(");
    if (!rgb) return FALSE;
    rgb += 4;
  }
  if (!rgb) return FALSE;

  char *end = NULL;
  double red = g_ascii_strtod(rgb, &end);
  if (!end || *end != ',') return FALSE;
  double green = g_ascii_strtod(end + 1, &end);
  if (!end || *end != ',') return FALSE;
  double blue = g_ascii_strtod(end + 1, &end);
  double alpha = 1.0;
  if (has_inline_alpha && end && *end == ',') {
    alpha = g_ascii_strtod(end + 1, &end);
    if (alpha > 1.0) alpha /= 255.0;
  }

  if (red > 1.0 || green > 1.0 || blue > 1.0) {
    red /= 255.0;
    green /= 255.0;
    blue /= 255.0;
  }
  omni_set_rgba(color, red, green, blue, alpha);
  return TRUE;
}

static gboolean omni_parse_hsb_function(const char *base, GdkRGBA *color) {
  if (!base || !color) return FALSE;
  const char *hsb = strstr(base, "hsb(");
  if (!hsb) return FALSE;
  hsb += 4;

  char *end = NULL;
  double hue = g_ascii_strtod(hsb, &end);
  if (!end || *end != ',') return FALSE;
  double saturation = omni_unit_clamp(g_ascii_strtod(end + 1, &end));
  if (!end || *end != ',') return FALSE;
  double brightness = omni_unit_clamp(g_ascii_strtod(end + 1, &end));

  while (hue < 0.0) hue += 1.0;
  while (hue >= 1.0) hue -= 1.0;
  if (saturation <= 0.0) {
    omni_set_rgba(color, brightness, brightness, brightness, 1.0);
    return TRUE;
  }

  double sector = hue * 6.0;
  int index = (int)sector;
  double fraction = sector - (double)index;
  double p = brightness * (1.0 - saturation);
  double q = brightness * (1.0 - saturation * fraction);
  double t = brightness * (1.0 - saturation * (1.0 - fraction));

  switch (index % 6) {
    case 0: omni_set_rgba(color, brightness, t, p, 1.0); break;
    case 1: omni_set_rgba(color, q, brightness, p, 1.0); break;
    case 2: omni_set_rgba(color, p, brightness, t, 1.0); break;
    case 3: omni_set_rgba(color, p, q, brightness, 1.0); break;
    case 4: omni_set_rgba(color, t, p, brightness, 1.0); break;
    default: omni_set_rgba(color, brightness, p, q, 1.0); break;
  }
  return TRUE;
}

static gboolean omni_parse_semantic_color(const char *raw, GdkRGBA *color) {
  if (!raw || !raw[0] || !color) return FALSE;
  char *base = omni_strdup(raw);
  double alpha_multiplier = 1.0;

  char *alpha = strrchr(base, '|');
  if (alpha) {
    *alpha = '\0';
    alpha++;
    if (alpha[0]) {
      alpha_multiplier = omni_unit_clamp(g_ascii_strtod(alpha, NULL));
    }
  }

  gboolean parsed = omni_parse_rgb_function(base, color) ||
    omni_parse_hsb_function(base, color) ||
    omni_named_semantic_color(base, color) ||
    gdk_rgba_parse(color, base);
  free(base);
  if (!parsed) return FALSE;

  color->alpha = omni_unit_clamp(color->alpha * alpha_multiplier);
  return TRUE;
}

static void omni_adw_gradient_data_free(gpointer user_data) {
  OmniAdwGradientData *data = user_data;
  if (!data) return;
  g_free(data->stops);
  g_free(data);
}

static void omni_adw_gradient_draw(GtkDrawingArea *area, cairo_t *cr, int width, int height, gpointer user_data) {
  (void)area;
  OmniAdwGradientData *data = user_data;
  if (!data || !data->stops || data->count <= 0 || !cr || width <= 0 || height <= 0) return;

  if (data->count == 1) {
    GdkRGBA color = data->stops[0];
    cairo_set_source_rgba(cr, color.red, color.green, color.blue, color.alpha);
    cairo_rectangle(cr, 0.0, 0.0, (double)width, (double)height);
    cairo_fill(cr);
    return;
  }

  double x0 = data->start_x * (double)width;
  double y0 = data->start_y * (double)height;
  double x1 = data->end_x * (double)width;
  double y1 = data->end_y * (double)height;
  if (x0 == x1 && y0 == y1) {
    y1 = (double)height;
  }

  gboolean radial = data->start_x == data->end_x && data->end_y > 1.0;
  double radius = width > height ? (double)width * 0.8 : (double)height * 0.8;
  cairo_pattern_t *pattern = radial
    ? cairo_pattern_create_radial(x0, y0, 0.0, x0, y0, radius)
    : cairo_pattern_create_linear(x0, y0, x1, y1);
  if (!pattern) return;
  for (int32_t i = 0; i < data->count; i++) {
    double offset = data->count <= 1 ? 0.0 : (double)i / (double)(data->count - 1);
    GdkRGBA color = data->stops[i];
    cairo_pattern_add_color_stop_rgba(pattern, offset, color.red, color.green, color.blue, color.alpha);
  }
  cairo_rectangle(cr, 0.0, 0.0, (double)width, (double)height);
  cairo_set_source(cr, pattern);
  cairo_fill(cr);
  cairo_pattern_destroy(pattern);
}

OmniAdwNode *omni_adw_drawing_new(const char *label, const char *fill_color) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_drawing_area_new();
  gtk_widget_set_size_request(node->widget, 1, 1);
  gtk_widget_set_can_target(node->widget, FALSE);
  gtk_widget_set_focusable(node->widget, FALSE);
  gtk_widget_add_css_class(node->widget, "omni-drawing-island");
  GdkRGBA parsed = {0};
  if (fill_color && fill_color[0] && omni_parse_semantic_color(fill_color, &parsed) && parsed.alpha > 0.0) {
    OmniAdwGradientData *data = calloc(1, sizeof(OmniAdwGradientData));
    if (data) {
      data->stops = g_new0(GdkRGBA, 1);
      if (data->stops) {
        data->stops[0] = parsed;
        data->count = 1;
        gtk_drawing_area_set_content_width(GTK_DRAWING_AREA(node->widget), 1);
        gtk_drawing_area_set_content_height(GTK_DRAWING_AREA(node->widget), 1);
        gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(node->widget), omni_adw_gradient_draw, data, omni_adw_gradient_data_free);
      } else {
        g_free(data);
      }
    }
  }
  omni_accessible_label(node->widget, label ? label : "OmniUI drawing island");
  gtk_widget_set_tooltip_text(node->widget, label ? label : "OmniUI drawing island");
  return node;
}

static OmniAdwGradientData *omni_adw_gradient_data_new(const char **colors, int32_t color_count, double start_x, double start_y, double end_x, double end_y) {
  OmniAdwGradientData *data = calloc(1, sizeof(OmniAdwGradientData));
  if (!data) return NULL;
  int32_t capacity = color_count > 0 ? color_count : 1;
  data->stops = g_new0(GdkRGBA, capacity);
  data->start_x = start_x;
  data->start_y = start_y;
  data->end_x = end_x;
  data->end_y = end_y;
  if (!data->stops) {
    omni_adw_gradient_data_free(data);
    return NULL;
  }

  for (int32_t i = 0; i < color_count; i++) {
    GdkRGBA parsed = {0};
    if (colors && colors[i] && omni_parse_semantic_color(colors[i], &parsed)) {
      data->stops[data->count++] = parsed;
    }
  }
  if (data->count == 0) {
    omni_set_rgba(&data->stops[data->count++], 0.0, 0.0, 0.0, 0.0);
  }
  return data;
}

OmniAdwNode *omni_adw_gradient_new(const char *label, const char **colors, int32_t color_count, double start_x, double start_y, double end_x, double end_y) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_drawing_area_new();
  gtk_widget_set_size_request(node->widget, 1, 1);
  gtk_widget_set_can_target(node->widget, FALSE);
  gtk_widget_set_focusable(node->widget, FALSE);
  gtk_widget_add_css_class(node->widget, "omni-drawing-island");
  omni_widget_expand(node->widget, TRUE);

  OmniAdwGradientData *data = omni_adw_gradient_data_new(colors, color_count, start_x, start_y, end_x, end_y);
  if (data) {
    gtk_drawing_area_set_content_width(GTK_DRAWING_AREA(node->widget), 1);
    gtk_drawing_area_set_content_height(GTK_DRAWING_AREA(node->widget), 1);
    gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(node->widget), omni_adw_gradient_draw, data, omni_adw_gradient_data_free);
  }

  omni_accessible_label(node->widget, label ? label : "OmniUI gradient");
  gtk_widget_set_tooltip_text(node->widget, label ? label : "OmniUI gradient");
  return node;
}

OmniAdwNode *omni_adw_frame_new(const char *css_classes, int32_t spacing) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_box_new(GTK_ORIENTATION_VERTICAL, spacing);
  gboolean clips_native_children = FALSE;
  gboolean pass_through_overlay = FALSE;
  if (css_classes && css_classes[0]) {
    char *copy = omni_strdup(css_classes);
    char *token = strtok(copy, " ");
    while (token) {
      gtk_widget_add_css_class(node->widget, token);
      if (strcmp(token, "omni-clip") == 0) clips_native_children = TRUE;
      if (strcmp(token, "omni-crt-overlay") == 0) pass_through_overlay = TRUE;
      token = strtok(NULL, " ");
    }
    free(copy);
  }
  if (pass_through_overlay) {
    gtk_widget_set_can_target(node->widget, FALSE);
    gtk_widget_set_focusable(node->widget, FALSE);
    omni_widget_expand(node->widget, TRUE);
  }
  if (clips_native_children) {
    gtk_widget_set_overflow(node->widget, GTK_OVERFLOW_HIDDEN);
    g_object_set_data(G_OBJECT(node->widget), "omni-native-clip", GINT_TO_POINTER(1));
  }
  omni_widget_expand(node->widget, FALSE);
  return node;
}

void omni_adw_node_apply_layout(OmniAdwNode *node, int32_t width, int32_t height, int32_t min_width, int32_t min_height, int32_t margin_top, int32_t margin_start, int32_t margin_bottom, int32_t margin_end, double opacity) {
  if (!node || !node->widget) return;
  if (width >= 0) {
    g_object_set_data(G_OBJECT(node->widget), "omni-explicit-width", GINT_TO_POINTER(1));
  }
  if (height >= 0) {
    g_object_set_data(G_OBJECT(node->widget), "omni-explicit-height", GINT_TO_POINTER(1));
  }

  int current_width = -1;
  int current_height = -1;
  gtk_widget_get_size_request(node->widget, &current_width, &current_height);
  int request_width = width >= 0 ? width : (min_width >= 0 ? min_width : current_width);
  int request_height = height >= 0 ? height : (min_height >= 0 ? min_height : current_height);
  if (request_width >= 0 || request_height >= 0) {
    gtk_widget_set_size_request(node->widget, request_width >= 0 ? request_width : -1, request_height >= 0 ? request_height : -1);
    if (GTK_IS_OVERLAY(node->widget)) {
      GtkWidget *base_child = gtk_overlay_get_child(GTK_OVERLAY(node->widget));
      if (base_child) {
        int child_width = request_width >= 0 && !omni_widget_has_explicit_width(base_child) ? request_width : -1;
        int child_height = request_height >= 0 && !omni_widget_has_explicit_height(base_child) ? request_height : -1;
        if (child_width >= 0 || child_height >= 0) {
          omni_widget_set_layout_size_recursive(base_child, child_width, child_height);
        }
      }
    }
  }
  if (margin_top >= 0) gtk_widget_set_margin_top(node->widget, margin_top);
  if (margin_start >= 0) gtk_widget_set_margin_start(node->widget, margin_start);
  if (margin_bottom >= 0) gtk_widget_set_margin_bottom(node->widget, margin_bottom);
  if (margin_end >= 0) gtk_widget_set_margin_end(node->widget, margin_end);
  if (opacity >= 0.0 && opacity <= 1.0) {
    gtk_widget_set_opacity(node->widget, opacity);
  }
}

void omni_adw_node_set_expand(OmniAdwNode *node, int32_t horizontal, int32_t vertical) {
  if (!node || !node->widget) return;
  if (horizontal >= 0) {
    gtk_widget_set_hexpand(node->widget, horizontal != 0);
    gtk_widget_set_halign(node->widget, horizontal != 0 ? GTK_ALIGN_FILL : GTK_ALIGN_START);
  }
  if (vertical >= 0) {
    gtk_widget_set_vexpand(node->widget, vertical != 0);
    gtk_widget_set_valign(node->widget, vertical != 0 ? GTK_ALIGN_FILL : GTK_ALIGN_CENTER);
  }
}

void omni_adw_node_set_visible(OmniAdwNode *node, int32_t visible) {
  if (!node || !node->widget) return;
  gtk_widget_set_visible(node->widget, visible != 0);
}

void omni_adw_node_set_sensitive(OmniAdwNode *node, int32_t sensitive) {
  if (!node || !node->widget) return;
  gtk_widget_set_sensitive(node->widget, sensitive != 0);
  omni_accessible_set_disabled(node->widget, sensitive == 0);
}

void omni_adw_node_set_required_click_count(OmniAdwNode *node, int32_t click_count) {
  if (!node || !node->widget) return;
  int32_t required = click_count > 1 ? click_count : 1;
  g_object_set_data(G_OBJECT(node->widget), "omni-required-click-count", GINT_TO_POINTER(required));
  if (required > 1 && !g_object_get_data(G_OBJECT(node->widget), "omni-required-click-controller-installed")) {
    GtkGesture *click_controller = gtk_gesture_click_new();
    gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(click_controller), GTK_PHASE_CAPTURE);
    g_signal_connect(click_controller, "released", G_CALLBACK(on_required_click_released), NULL);
    gtk_widget_add_controller(node->widget, GTK_EVENT_CONTROLLER(click_controller));
    g_object_set_data(G_OBJECT(node->widget), "omni-required-click-controller-installed", GINT_TO_POINTER(1));
  }
}

void omni_adw_node_set_drag_source_action(OmniAdwNode *node, int32_t action_id) {
  if (!node || !node->widget) return;
  g_object_set_data(G_OBJECT(node->widget), "omni-drag-source-action-id", GINT_TO_POINTER(action_id > 0 ? action_id : 0));
}

void omni_adw_node_set_metadata(OmniAdwNode *node, const char *semantic_id, const char *label) {
  if (!node || !node->widget) return;
  if (semantic_id && semantic_id[0]) {
    char *copy = omni_sanitized_widget_name(semantic_id);
    gtk_widget_set_name(node->widget, copy);
    free(copy);
  }
  if (label && label[0]) {
    omni_accessible_label(node->widget, label);
  }
}

void omni_adw_node_set_accessibility_description(OmniAdwNode *node, const char *description) {
  if (!node || !node->widget || !description || !description[0]) return;
  omni_accessible_description(node->widget, description);
  gtk_widget_set_tooltip_text(node->widget, description);
}

void omni_adw_node_set_accessibility_value(OmniAdwNode *node, const char *value) {
  if (!node || !node->widget || !value || !value[0]) return;
  omni_accessible_value_text(node->widget, value);
}

void omni_adw_node_apply_font(OmniAdwNode *node, double size, const char *weight, int32_t italic) {
  if (!node || !node->widget) return;
  omni_widget_apply_font_recursive(node->widget, size, weight, italic != 0);
}

void omni_adw_node_add_css_class(OmniAdwNode *node, const char *css_class) {
  if (!node || !node->widget || !css_class || !css_class[0]) return;
  omni_widget_add_css_classes(node->widget, css_class);
}

void omni_adw_node_append(OmniAdwNode *parent, OmniAdwNode *child) {
  omni_adw_node_append_overlay(parent, child, "center");
}

void omni_adw_node_append_overlay(OmniAdwNode *parent, OmniAdwNode *child, const char *alignment) {
  if (!parent || !child || !parent->widget || !child->widget) return;
  if (GTK_IS_BOX(parent->widget)) {
    gtk_box_append(GTK_BOX(parent->widget), child->widget);
  } else if (GTK_IS_FLOW_BOX(parent->widget)) {
    gtk_flow_box_append(GTK_FLOW_BOX(parent->widget), child->widget);
  } else if (GTK_IS_OVERLAY(parent->widget)) {
    if (!gtk_overlay_get_child(GTK_OVERLAY(parent->widget))) {
      omni_widget_expand(child->widget, TRUE);
      gtk_overlay_set_child(GTK_OVERLAY(parent->widget), child->widget);
      omni_overlay_install_size_sync(parent->widget);
      omni_overlay_sync_base_child_size(parent->widget);
    } else {
      omni_overlay_prepare_child(child->widget, alignment);
      gtk_overlay_add_overlay(GTK_OVERLAY(parent->widget), child->widget);
    }
  } else if (GTK_IS_LIST_BOX(parent->widget)) {
    GtkWidget *row = gtk_list_box_row_new();
    gtk_widget_set_hexpand(child->widget, TRUE);
    gtk_widget_set_halign(child->widget, GTK_ALIGN_FILL);
    gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), child->widget);
    int action_id = first_widget_action_id(child->widget);
    if (action_id > 0) {
      g_object_set_data(G_OBJECT(row), "omni-action-id", GINT_TO_POINTER(action_id));
      int required_click_count = first_widget_required_click_count(child->widget);
      g_object_set_data(G_OBJECT(row), "omni-required-click-count", GINT_TO_POINTER(required_click_count));
      gtk_list_box_row_set_activatable(GTK_LIST_BOX_ROW(row), TRUE);
      gtk_widget_set_focusable(row, TRUE);
      const char *label = first_widget_accessible_label(child->widget);
      if (label && label[0]) {
        omni_accessible_label(row, label);
        omni_accessible_description(row, "List row");
      }
      install_row_click_controller(row);
      install_row_click_controller(child->widget);
    }
    gtk_list_box_append(GTK_LIST_BOX(parent->widget), row);
  } else if (ADW_IS_PREFERENCES_GROUP(parent->widget)) {
    gtk_widget_set_hexpand(child->widget, TRUE);
    gtk_widget_set_halign(child->widget, GTK_ALIGN_FILL);
    adw_preferences_group_add(ADW_PREFERENCES_GROUP(parent->widget), child->widget);
  } else if (ADW_IS_EXPANDER_ROW(parent->widget)) {
    gtk_widget_set_hexpand(child->widget, TRUE);
    gtk_widget_set_halign(child->widget, GTK_ALIGN_FILL);
    adw_expander_row_add_row(ADW_EXPANDER_ROW(parent->widget), child->widget);
  } else if (ADW_IS_ACTION_ROW(parent->widget)) {
    gtk_widget_set_valign(child->widget, GTK_ALIGN_CENTER);
    gtk_widget_set_halign(child->widget, GTK_ALIGN_END);
    if (GTK_IS_ENTRY(child->widget) || GTK_IS_DROP_DOWN(child->widget)) {
      gtk_widget_set_size_request(child->widget, 220, -1);
    }
    adw_action_row_add_suffix(ADW_ACTION_ROW(parent->widget), child->widget);
    if (GTK_IS_BUTTON(child->widget) || GTK_IS_ENTRY(child->widget) || GTK_IS_DROP_DOWN(child->widget) || GTK_IS_COLOR_BUTTON(child->widget)) {
      adw_action_row_set_activatable_widget(ADW_ACTION_ROW(parent->widget), child->widget);
    }
  } else if (ADW_IS_STATUS_PAGE(parent->widget)) {
    adw_status_page_set_child(ADW_STATUS_PAGE(parent->widget), child->widget);
  } else if (GTK_IS_PANED(parent->widget)) {
    if (!gtk_paned_get_start_child(GTK_PANED(parent->widget))) {
      gtk_paned_set_start_child(GTK_PANED(parent->widget), child->widget);
    } else if (!gtk_paned_get_end_child(GTK_PANED(parent->widget))) {
      gtk_paned_set_end_child(GTK_PANED(parent->widget), child->widget);
    }
  } else if (ADW_IS_OVERLAY_SPLIT_VIEW(parent->widget)) {
    const gboolean sidebar = parent->split_child_count == 0;
    GtkWidget *child_widget = child->widget;
    omni_widget_expand(child_widget, TRUE);
    if (sidebar) {
      gtk_widget_set_size_request(child_widget, 280, -1);
      adw_overlay_split_view_set_sidebar(ADW_OVERLAY_SPLIT_VIEW(parent->widget), child_widget);
    } else if (parent->split_child_count == 1) {
      adw_overlay_split_view_set_content(ADW_OVERLAY_SPLIT_VIEW(parent->widget), child_widget);
    }
    parent->split_child_count += 1;
  } else if (ADW_IS_NAVIGATION_SPLIT_VIEW(parent->widget)) {
    const gboolean sidebar = parent->split_child_count == 0;
    GtkWidget *child_widget = child->widget;
    omni_widget_expand(child_widget, TRUE);
    AdwNavigationPage *page = adw_navigation_page_new(child_widget, sidebar ? "Sidebar" : "Content");
    if (sidebar) {
      gtk_widget_set_size_request(child_widget, 280, -1);
      adw_navigation_split_view_set_sidebar(ADW_NAVIGATION_SPLIT_VIEW(parent->widget), page);
    } else if (parent->split_child_count == 1) {
      adw_navigation_split_view_set_content(ADW_NAVIGATION_SPLIT_VIEW(parent->widget), page);
    }
    parent->split_child_count += 1;
  } else if (GTK_IS_SCROLLED_WINDOW(parent->widget)) {
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(parent->widget), child->widget);
    apply_initial_scroll_offset(GTK_SCROLLED_WINDOW(parent->widget));
  } else if (GTK_IS_BUTTON(parent->widget)) {
    gtk_widget_add_css_class(parent->widget, "flat");
    gtk_widget_add_css_class(parent->widget, "omni-complex-button");
    gtk_widget_set_hexpand(parent->widget, TRUE);
    gtk_widget_set_halign(parent->widget, GTK_ALIGN_FILL);
    gtk_widget_set_hexpand(child->widget, TRUE);
    gtk_widget_set_halign(child->widget, GTK_ALIGN_FILL);
    gtk_button_set_child(GTK_BUTTON(parent->widget), child->widget);
    const char *label = (const char *)g_object_get_data(G_OBJECT(parent->widget), "omni-accessible-label");
    if (label && label[0]) {
      gtk_accessible_update_property(GTK_ACCESSIBLE(parent->widget), GTK_ACCESSIBLE_PROPERTY_LABEL, label, -1);
    }
  }
  child->widget = NULL;
  omni_adw_node_free(child);
}

void omni_adw_node_free(OmniAdwNode *node) {
  if (!node) return;
  free(node);
}
