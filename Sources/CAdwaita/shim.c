#include "CAdwaita.h"

#include <adwaita.h>
#include <gdk/gdkkeysyms.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct OmniAdwApp {
  AdwApplication *application;
  GtkWidget *window;
  GtkWidget *shell;
  GtkWidget *body_slot;
  GtkWidget *header;
  GtkWidget *header_title_box;
  GtkWidget *header_title_label;
  GtkWidget *header_entry_row;
  GtkWidget *header_entry;
  GtkWidget *header_new_tab_button;
  GtkWidget *content;
  GtkWidget *settings_window;
  GtkWidget *settings_content;
  GtkWidget *command_button;
  GtkWidget *command_popover;
  GtkWidget *command_content;
  AdwDialog *modal_dialog;
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
  void *context;
  int32_t focused_action_id;
  int32_t default_width;
  int32_t default_height;
  GtkEventController *key_controller;
  GHashTable *scroll_offsets;
};

struct OmniAdwNode {
  GtkWidget *widget;
  int32_t split_child_count;
};

typedef struct {
  char **labels;
  int32_t *action_ids;
  int32_t count;
} OmniStringListData;

static char *omni_strdup(const char *s) {
  if (!s) return strdup("");
  return strdup(s);
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
    free(list->labels);
  }
  free(list->action_ids);
  free(list);
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

static void omni_accessible_label(GtkWidget *widget, const char *label) {
  if (!widget || !label || !label[0]) return;
  gtk_accessible_update_property(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_PROPERTY_LABEL, label, -1);
}

static void omni_flush_pending_ui(OmniAdwApp *app) {
  if (app && app->window) gtk_widget_queue_draw(app->window);
  while (g_main_context_pending(NULL)) {
    g_main_context_iteration(NULL, FALSE);
  }
}

static void present_settings_window(OmniAdwApp *app);
static void on_settings_clicked(GtkButton *button, gpointer data);
static gboolean on_settings_close_request(GtkWindow *window, gpointer data);
static gboolean on_key_pressed(GtkEventControllerKey *controller, guint keyval, guint keycode, GdkModifierType state, gpointer data);
static void on_window_click_pressed(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data);
static void on_entry_changed(GtkEditable *editable, gpointer data);
static void wire_actions(GtkWidget *widget, OmniAdwApp *app);
static void on_string_list_setup(GtkSignalListItemFactory *factory, GtkListItem *list_item, gpointer data);
static void on_string_list_bind(GtkSignalListItemFactory *factory, GtkListItem *list_item, gpointer data);
static void on_string_list_activate(GtkListView *view, guint position, gpointer data);
static void on_plain_list_row_activated(GtkListBox *box, GtkListBoxRow *row, gpointer data);

static char *omni_scroll_index_key(int index) {
  char buffer[64];
  snprintf(buffer, sizeof(buffer), "__omni_scroll_%d", index);
  return omni_strdup(buffer);
}

static void collect_scroll_offsets_indexed(GtkWidget *widget, GHashTable *offsets, int *index) {
  if (!widget || !offsets) return;
  if (GTK_IS_SCROLLED_WINDOW(widget)) {
    int current_index = index ? (*index)++ : 0;
    const char *name = gtk_widget_get_name(widget);
    GtkAdjustment *adjustment = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(widget));
    if (adjustment) {
      double current_value = gtk_adjustment_get_value(adjustment);
      char *index_key = omni_scroll_index_key(current_index);
      double *indexed_value = malloc(sizeof(double));
      if (index_key && indexed_value) {
        *indexed_value = current_value;
        g_hash_table_replace(offsets, index_key, indexed_value);
      } else {
        free(index_key);
        free(indexed_value);
      }
    }
    if (name && name[0] && adjustment) {
      double *value = malloc(sizeof(double));
      if (value) {
        *value = gtk_adjustment_get_value(adjustment);
        g_hash_table_replace(offsets, omni_strdup(name), value);
      }
    }
  }
  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child) {
    collect_scroll_offsets_indexed(child, offsets, index);
    child = gtk_widget_get_next_sibling(child);
  }
}

static void collect_scroll_offsets(GtkWidget *widget, GHashTable *offsets) {
  int index = 0;
  collect_scroll_offsets_indexed(widget, offsets, &index);
}

static void restore_scroll_offsets_indexed(GtkWidget *widget, GHashTable *offsets, int *index) {
  if (!widget || !offsets) return;
  if (GTK_IS_SCROLLED_WINDOW(widget)) {
    int current_index = index ? (*index)++ : 0;
    const char *name = gtk_widget_get_name(widget);
    GtkAdjustment *adjustment = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(widget));
    double *preserved_value = name && name[0] ? (double *)g_hash_table_lookup(offsets, name) : NULL;
    char *index_key = omni_scroll_index_key(current_index);
    double *indexed_value = index_key ? (double *)g_hash_table_lookup(offsets, index_key) : NULL;
    double *semantic_value = (double *)g_object_get_data(G_OBJECT(widget), "omni-scroll-offset");
    gboolean has_semantic_target = semantic_value && *semantic_value > 0.0;
    double value = has_semantic_target ? *semantic_value : (preserved_value ? *preserved_value : (indexed_value ? *indexed_value : 0.0));
    if (adjustment && (has_semantic_target || preserved_value || indexed_value)) {
      double upper = gtk_adjustment_get_upper(adjustment);
      double page = gtk_adjustment_get_page_size(adjustment);
      double max = upper > page ? upper - page : 0;
      double clamped = value < 0 ? 0 : (value > max ? max : value);
      gtk_adjustment_set_value(adjustment, clamped);
    }
    free(index_key);
  }
  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child) {
    restore_scroll_offsets_indexed(child, offsets, index);
    child = gtk_widget_get_next_sibling(child);
  }
}

static void restore_scroll_offsets(GtkWidget *widget, GHashTable *offsets) {
  int index = 0;
  restore_scroll_offsets_indexed(widget, offsets, &index);
}

typedef struct {
  GtkWidget *widget;
  GHashTable *offsets;
} OmniScrollRestoreRequest;

typedef struct {
  GtkAdjustment *adjustment;
  double value;
} OmniAdjustmentRestoreRequest;

static gboolean restore_scroll_offsets_idle(gpointer data) {
  OmniScrollRestoreRequest *request = (OmniScrollRestoreRequest *)data;
  if (!request) return G_SOURCE_REMOVE;
  restore_scroll_offsets(request->widget, request->offsets);
  if (request->widget) g_object_unref(request->widget);
  if (request->offsets) g_hash_table_unref(request->offsets);
  free(request);
  return G_SOURCE_REMOVE;
}

static OmniScrollRestoreRequest *scroll_restore_request_new(GtkWidget *widget, GHashTable *offsets) {
  if (!widget || !offsets) return NULL;
  OmniScrollRestoreRequest *request = calloc(1, sizeof(OmniScrollRestoreRequest));
  if (!request) return NULL;
  request->widget = g_object_ref(widget);
  request->offsets = g_hash_table_ref(offsets);
  return request;
}

static void schedule_scroll_offset_restore(GtkWidget *widget, GHashTable *offsets) {
  if (!widget || !offsets) return;
  OmniScrollRestoreRequest *request = scroll_restore_request_new(widget, offsets);
  if (request) {
    g_idle_add(restore_scroll_offsets_idle, request);
  }
  guint delays[] = {50, 150, 300, 750, 1500};
  for (guint i = 0; i < sizeof(delays) / sizeof(delays[0]); i++) {
    OmniScrollRestoreRequest *settled_request = scroll_restore_request_new(widget, offsets);
    if (settled_request) {
      g_timeout_add(delays[i], restore_scroll_offsets_idle, settled_request);
    }
  }
}

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

static void schedule_adjustment_restore(GtkAdjustment *adjustment, double value, guint delay_ms) {
  if (!adjustment) return;
  OmniAdjustmentRestoreRequest *request = calloc(1, sizeof(OmniAdjustmentRestoreRequest));
  if (!request) return;
  request->adjustment = g_object_ref(adjustment);
  request->value = value;
  if (delay_ms == 0) {
    g_idle_add(restore_adjustment_value, request);
  } else {
    g_timeout_add(delay_ms, restore_adjustment_value, request);
  }
}

static void schedule_scrolled_window_adjustment_restores(GtkWidget *widget) {
  if (!widget) return;
  if (GTK_IS_SCROLLED_WINDOW(widget)) {
    GtkAdjustment *adjustment = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(widget));
    if (adjustment) {
      double value = gtk_adjustment_get_value(adjustment);
      schedule_adjustment_restore(adjustment, value, 0);
      schedule_adjustment_restore(adjustment, value, 50);
      schedule_adjustment_restore(adjustment, value, 150);
      schedule_adjustment_restore(adjustment, value, 300);
      schedule_adjustment_restore(adjustment, value, 750);
      schedule_adjustment_restore(adjustment, value, 1500);
    }
  }
  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child) {
    schedule_scrolled_window_adjustment_restores(child);
    child = gtk_widget_get_next_sibling(child);
  }
}

static void preserve_app_scroll_offsets(OmniAdwApp *app) {
  if (!app || !app->content || !app->scroll_offsets) return;
  collect_scroll_offsets(app->content, app->scroll_offsets);
}

static void restore_app_scroll_offsets(OmniAdwApp *app) {
  if (!app || !app->content || !app->scroll_offsets) return;
  restore_scroll_offsets(app->content, app->scroll_offsets);
  schedule_scroll_offset_restore(app->content, app->scroll_offsets);
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

static GtkScrolledWindow *nearest_scrolled_window(GtkWidget *widget) {
  GtkWidget *current = widget;
  while (current) {
    if (GTK_IS_SCROLLED_WINDOW(current)) return GTK_SCROLLED_WINDOW(current);
    current = gtk_widget_get_parent(current);
  }
  return NULL;
}

static GtkWidget *nearest_calendar(GtkWidget *widget) {
  GtkWidget *current = widget;
  while (current) {
    if (GTK_IS_CALENDAR(current)) return current;
    current = gtk_widget_get_parent(current);
  }
  return NULL;
}

static double omni_semantic_scroll_to_pixels(double offset) {
  // OmniUI runtime scroll offsets are measured in terminal-style layout rows.
  // GTK adjustments are pixels, so use a conservative row height that matches
  // the native control density closely enough for ScrollViewReader targets.
  return offset * 28.0;
}

static void omni_install_css_once(void) {
  static gboolean installed = FALSE;
  if (installed) return;
  installed = TRUE;

  const char *css =
    ".omni-stack { padding: 0; }"
    ".omni-shell { background: @window_bg_color; }"
    ".omni-header { min-height: 44px; padding: 8px 12px; border-bottom: 1px solid alpha(@borders, 0.65); background: alpha(@headerbar_bg_color, 1.0); }"
    ".omni-title { font-weight: 700; }"
    ".omni-body { padding: 0; }"
    ".card { border-radius: 10px; padding: 12px; margin: 4px 0; background: alpha(@card_bg_color, 0.82); }"
    ".adw-dialog { padding: 18px; margin: 10px 24px; border: 1px solid alpha(@borders, 0.45); background: alpha(@dialog_bg_color, 0.96); }"
    ".boxed-list { border-radius: 0; padding: 0; margin: 0; background: transparent; }"
    ".omni-plain-list { background: transparent; }"
    ".omni-plain-list row { min-height: 22px; padding: 0 0; background: transparent; }"
    ".omni-plain-list row:hover { background: alpha(@accent_bg_color, 0.10); }"
    ".omni-plain-list label { padding: 1px 4px; font-weight: 500; }"
    ".navigation-view { padding: 0; border-radius: 0; background: @window_bg_color; }"
    ".view { padding: 2px; }"
    ".accent { border-radius: 8px; padding: 6px 8px; background: alpha(@accent_bg_color, 0.18); }"
    ".crt { }"
    ".omni-drawing-island { border-radius: 8px; background: alpha(@accent_bg_color, 0.18); border: 1px solid alpha(@accent_bg_color, 0.55); min-height: 64px; }"
    "button { border-radius: 8px; font-weight: 600; }"
    "entry, textview, menubutton { border-radius: 8px; }";

  GtkCssProvider *provider = gtk_css_provider_new();
  gtk_css_provider_load_from_string(provider, css);
  GdkDisplay *display = gdk_display_get_default();
  if (display) {
    gtk_style_context_add_provider_for_display(display, GTK_STYLE_PROVIDER(provider), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  }
  g_object_unref(provider);
}

static void omni_apply_color_scheme_from_environment(void) {
  const char *scheme = g_getenv("OMNIUI_ADWAITA_COLOR_SCHEME");
  if (!scheme || !scheme[0]) {
    scheme = g_getenv("OMNIUI_COLOR_SCHEME");
  }
  if (!scheme || !scheme[0]) return;

  AdwStyleManager *manager = adw_style_manager_get_default();
  if (!manager) return;

  if (g_ascii_strcasecmp(scheme, "dark") == 0 || g_ascii_strcasecmp(scheme, "force-dark") == 0) {
    adw_style_manager_set_color_scheme(manager, ADW_COLOR_SCHEME_FORCE_DARK);
  } else if (g_ascii_strcasecmp(scheme, "light") == 0 || g_ascii_strcasecmp(scheme, "force-light") == 0) {
    adw_style_manager_set_color_scheme(manager, ADW_COLOR_SCHEME_FORCE_LIGHT);
  } else if (g_ascii_strcasecmp(scheme, "default") == 0 || g_ascii_strcasecmp(scheme, "system") == 0) {
    adw_style_manager_set_color_scheme(manager, ADW_COLOR_SCHEME_DEFAULT);
  }
}

static void sync_header_entry(OmniAdwApp *app) {
  if (!app || !app->header_entry) return;
  gtk_entry_set_placeholder_text(GTK_ENTRY(app->header_entry), app->header_entry_placeholder ? app->header_entry_placeholder : "");
  const char *next = app->header_entry_text ? app->header_entry_text : "";
  const char *current = gtk_editable_get_text(GTK_EDITABLE(app->header_entry));
  if (!current || strcmp(current, next) != 0) {
    g_object_set_data(G_OBJECT(app->header_entry), "omni-updating", GINT_TO_POINTER(1));
    gtk_editable_set_text(GTK_EDITABLE(app->header_entry), next);
    g_object_set_data(G_OBJECT(app->header_entry), "omni-updating", NULL);
  }
  g_object_set_data(G_OBJECT(app->header_entry), "omni-action-id", GINT_TO_POINTER(app->header_entry_action_id));
  g_object_set_data(G_OBJECT(app->header_entry), "omni-app", app);
  omni_accessible_label(app->header_entry, app->header_entry_placeholder && app->header_entry_placeholder[0] ? app->header_entry_placeholder : next);
}

static void ensure_header_title_widget(OmniAdwApp *app) {
  if (!app || !app->header || app->header_title_box) return;
  app->header_title_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
  gtk_widget_set_hexpand(app->header_title_box, TRUE);
  gtk_widget_set_halign(app->header_title_box, GTK_ALIGN_FILL);
  app->header_title_label = gtk_label_new(app->title ? app->title : "OmniUI Adwaita");
  gtk_widget_add_css_class(app->header_title_label, "omni-title");
  gtk_box_append(GTK_BOX(app->header_title_box), app->header_title_label);

  app->header_entry_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  gtk_widget_set_hexpand(app->header_entry_row, TRUE);
  gtk_widget_set_halign(app->header_entry_row, GTK_ALIGN_FILL);

  app->header_entry = gtk_entry_new();
  gtk_widget_add_css_class(app->header_entry, "omni-header-entry");
  gtk_widget_set_size_request(app->header_entry, 520, -1);
  gtk_widget_set_hexpand(app->header_entry, TRUE);
  gtk_widget_set_halign(app->header_entry, GTK_ALIGN_FILL);
  gtk_widget_set_vexpand(app->header_entry, FALSE);
  gtk_widget_set_valign(app->header_entry, GTK_ALIGN_CENTER);
  g_signal_connect(app->header_entry, "changed", G_CALLBACK(on_entry_changed), NULL);
  gtk_box_append(GTK_BOX(app->header_entry_row), app->header_entry);

  app->header_new_tab_button = gtk_button_new_with_label("+");
  gtk_widget_add_css_class(app->header_new_tab_button, "flat");
  gtk_widget_set_vexpand(app->header_new_tab_button, FALSE);
  gtk_widget_set_valign(app->header_new_tab_button, GTK_ALIGN_CENTER);
  omni_accessible_label(app->header_new_tab_button, "New tab");
  gtk_box_append(GTK_BOX(app->header_entry_row), app->header_new_tab_button);

  gtk_box_append(GTK_BOX(app->header_title_box), app->header_entry_row);
  adw_header_bar_set_title_widget(ADW_HEADER_BAR(app->header), app->header_title_box);
  wire_actions(app->header_entry, app);
  sync_header_entry(app);
}

static void on_app_activate(GApplication *application, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app->window) {
    omni_apply_color_scheme_from_environment();
    app->window = adw_application_window_new(GTK_APPLICATION(application));
    gtk_window_set_title(GTK_WINDOW(app->window), app->title);
    gtk_window_set_default_size(GTK_WINDOW(app->window), app->default_width, app->default_height);
    app->shell = adw_toolbar_view_new();
    gtk_widget_add_css_class(app->shell, "omni-shell");
    omni_widget_expand(app->shell, TRUE);

    app->header = adw_header_bar_new();
    gtk_widget_add_css_class(app->header, "omni-header");
    gtk_widget_set_size_request(app->header, -1, 64);
    ensure_header_title_widget(app);

    app->command_button = gtk_menu_button_new();
    gtk_widget_set_visible(app->command_button, FALSE);
    gtk_menu_button_set_label(GTK_MENU_BUTTON(app->command_button), "Commands");
    app->command_popover = gtk_popover_new();
    gtk_menu_button_set_popover(GTK_MENU_BUTTON(app->command_button), app->command_popover);
    if (app->command_content) {
      gtk_popover_set_child(GTK_POPOVER(app->command_popover), app->command_content);
    }
    adw_header_bar_pack_end(ADW_HEADER_BAR(app->header), app->command_button);

    app->body_slot = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_widget_add_css_class(app->body_slot, "omni-body");
    omni_widget_expand(app->body_slot, TRUE);
    adw_toolbar_view_add_top_bar(ADW_TOOLBAR_VIEW(app->shell), app->header);
    adw_toolbar_view_set_content(ADW_TOOLBAR_VIEW(app->shell), app->body_slot);

    if (!app->content) {
      app->content = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    }
    if (app->body_slot && app->content) {
      gtk_box_append(GTK_BOX(app->body_slot), app->content);
    }
    adw_application_window_set_content(ADW_APPLICATION_WINDOW(app->window), app->shell);
    if (!app->key_controller) {
      app->key_controller = gtk_event_controller_key_new();
      gtk_event_controller_set_propagation_phase(app->key_controller, GTK_PHASE_CAPTURE);
      g_signal_connect(app->key_controller, "key-pressed", G_CALLBACK(on_key_pressed), app);
      gtk_widget_add_controller(app->window, app->key_controller);
    }
    GtkGesture *click_controller = gtk_gesture_click_new();
    gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(click_controller), GTK_PHASE_CAPTURE);
    g_signal_connect(click_controller, "pressed", G_CALLBACK(on_window_click_pressed), app);
    gtk_widget_add_controller(app->window, GTK_EVENT_CONTROLLER(click_controller));
  }
  gtk_window_present(GTK_WINDOW(app->window));
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
    if (app->window) {
      gtk_window_set_transient_for(GTK_WINDOW(app->settings_window), GTK_WINDOW(app->window));
    }
    g_signal_connect(app->settings_window, "close-request", G_CALLBACK(on_settings_close_request), app);
    gtk_window_set_child(GTK_WINDOW(app->settings_window), app->settings_content);
  }
  gtk_window_present(GTK_WINDOW(app->settings_window));
}

static void on_settings_clicked(GtkButton *button, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(button), "omni-settings-button");
  present_settings_window(app);
}

static gboolean on_settings_close_request(GtkWindow *window, gpointer data) {
  gtk_widget_set_visible(GTK_WIDGET(window), FALSE);
  return TRUE;
}

static void on_clicked(GtkButton *button, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(button), "omni-app");
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "omni-action-id"));
  if (app && app->callback) {
    app->callback(action_id, app->context);
    omni_flush_pending_ui(app);
  }
}

static void on_toggled(GtkCheckButton *button, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(button), "omni-app");
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "omni-action-id"));
  if (app && app->callback) {
    app->callback(action_id, app->context);
    omni_flush_pending_ui(app);
  }
}

static void on_string_list_setup(GtkSignalListItemFactory *factory, GtkListItem *list_item, gpointer data) {
  GtkWidget *label = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
  gtk_label_set_wrap(GTK_LABEL(label), TRUE);
  gtk_widget_set_hexpand(label, TRUE);
  gtk_widget_set_halign(label, GTK_ALIGN_FILL);
  gtk_list_item_set_child(list_item, label);
}

static void on_string_list_bind(GtkSignalListItemFactory *factory, GtkListItem *list_item, gpointer data) {
  GtkWidget *label = gtk_list_item_get_child(list_item);
  gpointer item = gtk_list_item_get_item(list_item);
  if (!GTK_IS_LABEL(label) || !GTK_IS_STRING_OBJECT(item)) return;
  const char *text = gtk_string_object_get_string(GTK_STRING_OBJECT(item));
  gtk_label_set_text(GTK_LABEL(label), text ? text : "");
  omni_accessible_label(label, text);
}

static void on_string_list_activate(GtkListView *view, guint position, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(view), "omni-app");
  OmniStringListData *list = (OmniStringListData *)g_object_get_data(G_OBJECT(view), "omni-string-list-data");
  if (!app || !app->callback || !list || position >= (guint)list->count) return;
  int32_t action_id = list->action_ids ? list->action_ids[position] : 0;
  if (action_id > 0) {
    app->callback(action_id, app->context);
    omni_flush_pending_ui(app);
  }
}

static void on_plain_list_row_activated(GtkListBox *box, GtkListBoxRow *row, gpointer data) {
  if (!box || !row) return;
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(box), "omni-app");
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(row), "omni-action-id"));
  if (app && app->callback && action_id > 0) {
    app->callback(action_id, app->context);
    omni_flush_pending_ui(app);
  }
}

static void on_scale_value_changed(GtkRange *range, gpointer data) {
  if (g_object_get_data(G_OBJECT(range), "omni-updating") != NULL) return;
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(range), "omni-app");
  if (!app || !app->callback) return;

  double previous = 0.0;
  double *previous_ptr = (double *)g_object_get_data(G_OBJECT(range), "omni-scale-value");
  if (previous_ptr) previous = *previous_ptr;
  double next = gtk_range_get_value(range);

  int action_id = 0;
  if (next > previous) {
    action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(range), "omni-increment-action-id"));
  } else if (next < previous) {
    action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(range), "omni-decrement-action-id"));
  }

  if (previous_ptr) *previous_ptr = next;
  if (action_id > 0) {
    app->callback(action_id, app->context);
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

  int action_id = 0;
  if (next > previous) {
    action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(spin), "omni-increment-action-id"));
  } else if (next < previous) {
    action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(spin), "omni-decrement-action-id"));
  }

  if (previous_ptr) *previous_ptr = next;
  if (action_id > 0) {
    app->callback(action_id, app->context);
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
    app->callback(action_id, app->context);
    omni_flush_pending_ui(app);
  }
}

static void on_calendar_date_notify(GObject *object, GParamSpec *pspec, gpointer data) {
  if (!GTK_IS_CALENDAR(object)) return;
  handle_calendar_date_changed(GTK_CALENDAR(object));
}

static void on_calendar_pressed(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (app && app->content && app->scroll_offsets) {
    collect_scroll_offsets(app->content, app->scroll_offsets);
  }
  GtkWidget *widget = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(gesture));
  GtkScrolledWindow *scrolled = nearest_scrolled_window(widget);
  GtkAdjustment *adjustment = scrolled ? gtk_scrolled_window_get_vadjustment(scrolled) : NULL;
  if (adjustment) {
    double value = gtk_adjustment_get_value(adjustment);
    schedule_adjustment_restore(adjustment, value, 0);
    schedule_adjustment_restore(adjustment, value, 50);
    schedule_adjustment_restore(adjustment, value, 150);
    schedule_adjustment_restore(adjustment, value, 300);
  }
}

static void on_dropdown_selected(GObject *object, GParamSpec *pspec, gpointer data) {
  GtkDropDown *dropdown = GTK_DROP_DOWN(object);
  if (g_object_get_data(G_OBJECT(dropdown), "omni-updating") != NULL) return;
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(dropdown), "omni-app");
  int32_t *action_ids = (int32_t *)g_object_get_data(G_OBJECT(dropdown), "omni-action-ids");
  int count = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(dropdown), "omni-action-count"));
  guint selected = gtk_drop_down_get_selected(dropdown);
  if (!app || !app->callback || !action_ids || selected == GTK_INVALID_LIST_POSITION || selected >= (guint)count) return;
  int32_t action_id = action_ids[selected];
  if (action_id > 0) {
    app->callback(action_id, app->context);
    omni_flush_pending_ui(app);
  }
}

static void on_menu_option_clicked(GtkButton *button, gpointer data) {
  GtkPopover *popover = GTK_POPOVER(data);
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(button), "omni-app");
  if (!app) {
    GtkWidget *owner = GTK_WIDGET(g_object_get_data(G_OBJECT(button), "omni-owner"));
    if (owner) app = (OmniAdwApp *)g_object_get_data(G_OBJECT(owner), "omni-app");
  }
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "omni-action-id"));
  if (popover) gtk_popover_popdown(popover);
  if (app && app->callback && action_id > 0) {
    app->callback(action_id, app->context);
    omni_flush_pending_ui(app);
  }
}

static void on_entry_changed(GtkEditable *editable, gpointer data) {
  if (g_object_get_data(G_OBJECT(editable), "omni-updating") != NULL) return;
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(editable), "omni-app");
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(editable), "omni-action-id"));
  if (app && app->text_callback) {
    preserve_app_scroll_offsets(app);
    app->text_callback(action_id, gtk_editable_get_text(editable), app->context);
    restore_app_scroll_offsets(app);
  }
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
  preserve_app_scroll_offsets(app);
  app->text_callback(action_id, text ? text : "", app->context);
  restore_app_scroll_offsets(app);
  g_free(text);
}

static void on_focus_enter(GtkEventControllerFocus *controller, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  GtkWidget *widget = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(controller));
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id"));
  if (app && action_id > 0 && app->focused_action_id != action_id) {
    preserve_app_scroll_offsets(app);
    app->focused_action_id = action_id;
    if (app->focus_callback) app->focus_callback(action_id, app->context);
    restore_app_scroll_offsets(app);
  }
}

static void on_text_widget_pressed(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  GtkWidget *widget = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(gesture));
  int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id"));
  if (app && action_id > 0 && app->focused_action_id != action_id) {
    preserve_app_scroll_offsets(app);
    app->focused_action_id = action_id;
    if (app->focus_callback) app->focus_callback(action_id, app->context);
    restore_app_scroll_offsets(app);
  }
}

static gboolean on_key_pressed(GtkEventControllerKey *controller, guint keyval, guint keycode, GdkModifierType state, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app || !app->key_callback) return FALSE;

  if ((state & (GDK_META_MASK | GDK_CONTROL_MASK)) != 0 && keyval == GDK_KEY_comma) {
    present_settings_window(app);
    return TRUE;
  }

  if (keyval == GDK_KEY_Return || keyval == GDK_KEY_KP_Enter) {
    preserve_app_scroll_offsets(app);
    app->key_callback(0, 7, 0, app->context);
    restore_app_scroll_offsets(app);
    return TRUE;
  }
  if (keyval == GDK_KEY_Escape) {
    preserve_app_scroll_offsets(app);
    app->key_callback(0, 8, 0, app->context);
    restore_app_scroll_offsets(app);
    return TRUE;
  }

  if (app_focus_is_native_text_widget(app)) return FALSE;

  if (app->focused_action_id <= 0) return FALSE;

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
  preserve_app_scroll_offsets(app);
  app->key_callback(app->focused_action_id, kind, codepoint, app->context);
  restore_app_scroll_offsets(app);
  return TRUE;
}

static void on_window_click_pressed(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  GtkWidget *window = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(gesture));
  GtkWidget *picked = window ? gtk_widget_pick(window, x, y, GTK_PICK_DEFAULT) : NULL;
  GtkWidget *calendar = nearest_calendar(picked);
  if (app && app->content) {
    schedule_scrolled_window_adjustment_restores(app->content);
  }
  GtkScrolledWindow *scrolled = nearest_scrolled_window(picked);
  if (scrolled || calendar) {
    if (app && app->content && app->scroll_offsets) {
      collect_scroll_offsets(app->content, app->scroll_offsets);
    }
    GtkAdjustment *adjustment = scrolled ? gtk_scrolled_window_get_vadjustment(scrolled) : NULL;
    if (adjustment) {
      double value = gtk_adjustment_get_value(adjustment);
      schedule_adjustment_restore(adjustment, value, 0);
      schedule_adjustment_restore(adjustment, value, 50);
      schedule_adjustment_restore(adjustment, value, 150);
      schedule_adjustment_restore(adjustment, value, 300);
      schedule_adjustment_restore(adjustment, value, 750);
      schedule_adjustment_restore(adjustment, value, 1500);
    }
  }
  if (!app || !app->modal_dialog || app->modal_close_action_id <= 0) return;
  adw_dialog_close(app->modal_dialog);
}

static void wire_actions(GtkWidget *widget, OmniAdwApp *app) {
  if (!widget) return;
  if (GTK_IS_BUTTON(widget) || GTK_IS_CHECK_BUTTON(widget) || GTK_IS_ENTRY(widget) || GTK_IS_TEXT_VIEW(widget) || GTK_IS_DROP_DOWN(widget) || GTK_IS_MENU_BUTTON(widget) || GTK_IS_SCALE(widget) || GTK_IS_SPIN_BUTTON(widget) || GTK_IS_CALENDAR(widget) || GTK_IS_LIST_VIEW(widget) || GTK_IS_LIST_BOX(widget)) {
    g_object_set_data(G_OBJECT(widget), "omni-app", app);
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

OmniAdwApp *omni_adw_app_new(const char *app_id, const char *title, omni_adw_action_callback callback, omni_adw_text_callback text_callback, omni_adw_key_callback key_callback, omni_adw_focus_callback focus_callback, void *context) {
  gtk_init();
  adw_init();
  omni_install_css_once();
  OmniAdwApp *app = calloc(1, sizeof(OmniAdwApp));
  app->title = omni_strdup(title);
  app->callback = callback;
  app->text_callback = text_callback;
  app->key_callback = key_callback;
  app->focus_callback = focus_callback;
  app->context = context;
  app->default_width = 1100;
  app->default_height = 760;
  app->scroll_offsets = g_hash_table_new_full(g_str_hash, g_str_equal, free, free);
  app->application = adw_application_new(app_id ? app_id : "dev.omnikit.OmniUIAdwaita", G_APPLICATION_DEFAULT_FLAGS);
  g_signal_connect(app->application, "activate", G_CALLBACK(on_app_activate), app);
  return app;
}

int32_t omni_adw_app_run(OmniAdwApp *app, int32_t argc, char **argv) {
  if (!app) return 1;
  return g_application_run(G_APPLICATION(app->application), argc, argv);
}

void omni_adw_app_free(OmniAdwApp *app) {
  if (!app) return;
  if (app->modal_dialog) adw_dialog_force_close(app->modal_dialog);
  if (app->settings_window) gtk_window_destroy(GTK_WINDOW(app->settings_window));
  if (app->application) g_object_unref(app->application);
  if (app->scroll_offsets) g_hash_table_destroy(app->scroll_offsets);
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

void omni_adw_app_set_settings(OmniAdwApp *app, OmniAdwNode *settings) {
  if (!app || !settings) return;
  if (app->settings_window) {
    gtk_window_destroy(GTK_WINDOW(app->settings_window));
    app->settings_window = NULL;
  }
  app->settings_content = settings->widget;
  omni_widget_expand(app->settings_content, TRUE);
  gtk_widget_set_margin_top(app->settings_content, 18);
  gtk_widget_set_margin_bottom(app->settings_content, 18);
  gtk_widget_set_margin_start(app->settings_content, 18);
  gtk_widget_set_margin_end(app->settings_content, 18);
  wire_actions(app->settings_content, app);
  settings->widget = NULL;
  omni_adw_node_free(settings);
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
  GtkWidget *previous_content = app->content;
  if (previous_content && app->scroll_offsets) {
    collect_scroll_offsets(previous_content, app->scroll_offsets);
  }
  app->focused_action_id = focused_action_id;
  app->content = root->widget;
  omni_widget_expand(app->content, TRUE);
  gtk_widget_set_margin_top(app->content, 0);
  gtk_widget_set_margin_bottom(app->content, 0);
  gtk_widget_set_margin_start(app->content, 0);
  gtk_widget_set_margin_end(app->content, 0);
  wire_actions(app->content, app);
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
      gtk_widget_add_controller(app->window, app->key_controller);
    }
  }
  restore_scroll_offsets(app->content, app->scroll_offsets);
  schedule_scroll_offset_restore(app->content, app->scroll_offsets);
  GtkWidget *focused = find_widget_for_action(app->content, focused_action_id);
  if (focused && gtk_widget_get_focusable(focused)) {
    gtk_widget_grab_focus(focused);
  }
  restore_scroll_offsets(app->content, app->scroll_offsets);
  schedule_scroll_offset_restore(app->content, app->scroll_offsets);
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
      app->callback(action_id, app->context);
    }
  }
  if (app && app->modal_dialog == ADW_DIALOG(dialog)) {
    app->modal_dialog = NULL;
  }
}

static int modal_close_action_id(OmniModalSummary *summary) {
  if (!summary) return 0;
  for (guint i = 0; i < summary->button_labels->len; i++) {
    const char *label = (const char *)g_ptr_array_index(summary->button_labels, i);
    if (label && strcmp(label, "Close") == 0) {
      return g_array_index(summary->action_ids, int, i);
    }
  }
  return 0;
}

static void on_sheet_closed(AdwDialog *dialog, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app) return;
  int action_id = app->modal_close_action_id;
  gboolean force_closing = app->modal_force_closing;
  if (app->modal_dialog == dialog) {
    app->modal_dialog = NULL;
    app->modal_close_action_id = 0;
    app->modal_force_closing = FALSE;
  }
  if (!force_closing && action_id > 0 && app->callback) {
    app->callback(action_id, app->context);
  }
}

static void on_sheet_close_attempt(AdwDialog *dialog, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app || app->modal_close_action_id <= 0) return;
  adw_dialog_close(dialog);
}

static void on_sheet_click_pressed(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app || !app->modal_dialog || app->modal_close_action_id <= 0) return;
  AdwDialog *dialog = app->modal_dialog;
  GtkWidget *child = adw_dialog_get_child(dialog);
  GtkWidget *picked = gtk_widget_pick(GTK_WIDGET(dialog), x, y, GTK_PICK_DEFAULT);
  gboolean inside_child = child && picked && (picked == child || gtk_widget_is_ancestor(picked, child));
  if (!inside_child) {
    adw_dialog_close(dialog);
  }
}

static void present_sheet_dialog(OmniAdwApp *app, OmniAdwNode *modal, OmniModalSummary *summary, int close_action_id) {
  AdwDialog *dialog = adw_dialog_new();
  adw_dialog_set_title(dialog, "Sheet");
  adw_dialog_set_can_close(dialog, close_action_id > 0);
  adw_dialog_set_content_width(dialog, 560);
  adw_dialog_set_content_height(dialog, 360);
  adw_dialog_set_presentation_mode(dialog, ADW_DIALOG_FLOATING);
  app->modal_dialog = dialog;
  app->modal_close_action_id = close_action_id;
  app->modal_force_closing = FALSE;
  wire_actions(modal->widget, app);
  adw_dialog_set_child(dialog, modal->widget);
  modal->widget = NULL;
  GtkGesture *click_controller = gtk_gesture_click_new();
  gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(click_controller), GTK_PHASE_CAPTURE);
  g_signal_connect(click_controller, "pressed", G_CALLBACK(on_sheet_click_pressed), app);
  gtk_widget_add_controller(GTK_WIDGET(dialog), GTK_EVENT_CONTROLLER(click_controller));
  g_signal_connect(dialog, "close-attempt", G_CALLBACK(on_sheet_close_attempt), app);
  g_signal_connect(dialog, "closed", G_CALLBACK(on_sheet_closed), app);
  if (app->window) {
    adw_dialog_present(dialog, app->window);
  }
  free_modal_summary(summary);
}

void omni_adw_app_present_modal(OmniAdwApp *app, OmniAdwNode *modal, const char *title) {
  if (!app || !modal) return;
  omni_adw_app_dismiss_modal(app);
  OmniModalSummary *summary = modal_summary_new(modal->widget);
  int close_action_id = modal_close_action_id(summary);
  if (close_action_id > 0) {
    present_sheet_dialog(app, modal, summary, close_action_id);
    omni_adw_node_free(modal);
    return;
  }
  const char *heading = summary && summary->labels->len > 0 ? (const char *)g_ptr_array_index(summary->labels, 0) : (title && title[0] ? title : "Presentation");
  const char *body = summary && summary->labels->len > 1 ? (const char *)g_ptr_array_index(summary->labels, 1) : NULL;
  AdwDialog *base_dialog = adw_alert_dialog_new(heading, body);
  AdwAlertDialog *dialog = ADW_ALERT_DIALOG(base_dialog);
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
  if (app->window) {
    adw_dialog_present(base_dialog, app->window);
  }
  omni_adw_node_free(modal);
}

void omni_adw_app_dismiss_modal(OmniAdwApp *app) {
  if (!app || !app->modal_dialog) return;
  app->modal_force_closing = TRUE;
  adw_dialog_force_close(app->modal_dialog);
  app->modal_dialog = NULL;
  app->modal_close_action_id = 0;
  app->modal_force_closing = FALSE;
}

int32_t omni_adw_app_update_node(OmniAdwApp *app, const char *semantic_id, int32_t kind, const char *text, int32_t active) {
  if (!app || !app->content || !semantic_id) return 0;
  char *name = omni_sanitized_widget_name(semantic_id);
  GtkWidget *widget = find_widget_for_name(app->content, name);
  free(name);
  if (!widget) return 0;
  if (app->scroll_offsets && kind != 9) {
    collect_scroll_offsets(app->content, app->scroll_offsets);
  }

  const char *value = text ? text : "";
  switch (kind) {
    case 0:
      if (!GTK_IS_LABEL(widget)) return 0;
      gtk_label_set_text(GTK_LABEL(widget), value);
      break;
    case 1:
      if (!GTK_IS_BUTTON(widget)) return 0;
      gtk_button_set_label(GTK_BUTTON(widget), value);
      break;
    case 2:
      if (!GTK_IS_CHECK_BUTTON(widget)) return 0;
      gtk_check_button_set_label(GTK_CHECK_BUTTON(widget), value);
      gtk_check_button_set_active(GTK_CHECK_BUTTON(widget), active != 0);
      break;
    case 3:
      if (!GTK_IS_ENTRY(widget)) return 0;
      if (strcmp(gtk_editable_get_text(GTK_EDITABLE(widget)), value) != 0) {
        gtk_editable_set_text(GTK_EDITABLE(widget), value);
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
            break;
          }
        }
        break;
      }
      if (!GTK_IS_DROP_DOWN(widget)) return 0;
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
            break;
          }
        }
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
        if (label[0]) {
          gtk_progress_bar_set_text(GTK_PROGRESS_BAR(widget), label);
          gtk_widget_set_tooltip_text(widget, label);
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
        if (endptr && *endptr == '\n' && endptr[1]) {
          gtk_widget_set_tooltip_text(widget, endptr + 1);
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
        if (endptr && *endptr == '\n' && endptr[1]) {
          gtk_widget_set_tooltip_text(widget, endptr + 1);
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
        }
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
    default:
      return 0;
  }
  if (value[0]) {
    gtk_widget_set_tooltip_text(widget, value);
  }
  restore_scroll_offsets(app->content, app->scroll_offsets);
  schedule_scroll_offset_restore(app->content, app->scroll_offsets);
  return 1;
}

int32_t omni_adw_app_replace_node(OmniAdwApp *app, const char *semantic_id, OmniAdwNode *replacement, int32_t focused_action_id) {
  if (!app || !app->content || !semantic_id || !replacement || !replacement->widget) return 0;
  char *name = omni_sanitized_widget_name(semantic_id);
  GtkWidget *target = find_widget_for_name(app->content, name);
  free(name);
  if (!target) return 0;

  if (app->scroll_offsets) {
    collect_scroll_offsets(app->content, app->scroll_offsets);
  }

  GtkWidget *replacement_widget = replacement->widget;
  replacement->widget = NULL;
  omni_adw_node_free(replacement);
  wire_actions(replacement_widget, app);
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
      g_object_ref(target);
      gtk_box_remove(GTK_BOX(parent), target);
      if (previous) {
        gtk_box_insert_child_after(GTK_BOX(parent), replacement_widget, previous);
      } else {
        gtk_box_prepend(GTK_BOX(parent), replacement_widget);
      }
      g_object_unref(target);
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

  restore_scroll_offsets(app->content, app->scroll_offsets);
  schedule_scroll_offset_restore(app->content, app->scroll_offsets);
  GtkWidget *focused = find_widget_for_action(app->content, focused_action_id);
  if (focused && gtk_widget_get_focusable(focused)) {
    gtk_widget_grab_focus(focused);
  }
  return 1;
}

OmniAdwNode *omni_adw_box_new(int32_t vertical, int32_t spacing) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_box_new(vertical ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL, spacing);
  gtk_widget_add_css_class(node->widget, "omni-stack");
  omni_widget_expand(node->widget, vertical != 0);
  return node;
}

OmniAdwNode *omni_adw_list_new(void) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_list_box_new();
  gtk_list_box_set_selection_mode(GTK_LIST_BOX(node->widget), GTK_SELECTION_NONE);
  gtk_widget_add_css_class(node->widget, "boxed-list");
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  return node;
}

OmniAdwNode *omni_adw_string_list_new(const char **labels, const int32_t *action_ids, int32_t count) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  GtkStringList *strings = gtk_string_list_new(NULL);
  OmniStringListData *data = calloc(1, sizeof(OmniStringListData));
  if (data && count > 0) {
    data->count = count;
    data->labels = calloc((size_t)count, sizeof(char *));
    data->action_ids = calloc((size_t)count, sizeof(int32_t));
  }
  for (int32_t i = 0; i < count; i++) {
    const char *label = labels && labels[i] ? labels[i] : "";
    gtk_string_list_append(strings, label);
    if (data && data->labels) data->labels[i] = omni_strdup(label);
    if (data && data->action_ids) data->action_ids[i] = action_ids ? action_ids[i] : 0;
  }

  GtkSelectionModel *selection = GTK_SELECTION_MODEL(gtk_single_selection_new(G_LIST_MODEL(strings)));
  GtkListItemFactory *factory = gtk_signal_list_item_factory_new();
  g_signal_connect(factory, "setup", G_CALLBACK(on_string_list_setup), NULL);
  g_signal_connect(factory, "bind", G_CALLBACK(on_string_list_bind), NULL);

  node->widget = gtk_list_view_new(selection, factory);
  gtk_widget_add_css_class(node->widget, "boxed-list");
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  g_object_set_data_full(G_OBJECT(node->widget), "omni-string-list-data", data, free_string_list_data);
  g_signal_connect(node->widget, "activate", G_CALLBACK(on_string_list_activate), NULL);
  return node;
}

OmniAdwNode *omni_adw_plain_list_new(const char **labels, const int32_t *action_ids, int32_t count) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_list_box_new();
  gtk_list_box_set_selection_mode(GTK_LIST_BOX(node->widget), GTK_SELECTION_NONE);
  gtk_widget_add_css_class(node->widget, "omni-plain-list");
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  g_signal_connect(node->widget, "row-activated", G_CALLBACK(on_plain_list_row_activated), NULL);

  for (int32_t i = 0; i < count; i++) {
    const char *text = labels && labels[i] ? labels[i] : "";
    GtkWidget *row = gtk_list_box_row_new();
    GtkWidget *label = gtk_label_new(text);
    gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
    gtk_label_set_wrap(GTK_LABEL(label), TRUE);
    gtk_widget_set_hexpand(label, TRUE);
    gtk_widget_set_halign(label, GTK_ALIGN_FILL);
    gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), label);
    omni_accessible_label(row, text);
    int32_t action_id = action_ids ? action_ids[i] : 0;
    g_object_set_data(G_OBJECT(row), "omni-action-id", GINT_TO_POINTER(action_id));
    gtk_widget_set_sensitive(row, action_id > 0);
    gtk_list_box_append(GTK_LIST_BOX(node->widget), row);
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
  return node;
}

OmniAdwNode *omni_adw_split_new(void) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = adw_navigation_split_view_new();
  gtk_widget_add_css_class(node->widget, "navigation-view");
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_vexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  gtk_widget_set_valign(node->widget, GTK_ALIGN_FILL);
  adw_navigation_split_view_set_collapsed(ADW_NAVIGATION_SPLIT_VIEW(node->widget), FALSE);
  adw_navigation_split_view_set_show_content(ADW_NAVIGATION_SPLIT_VIEW(node->widget), TRUE);
  return node;
}

OmniAdwNode *omni_adw_text_new(const char *text) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  const char *value = text ? text : "";
  if (strlen(value) > 16384) {
    node->widget = gtk_text_view_new();
    gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(node->widget), GTK_WRAP_WORD_CHAR);
    gtk_text_view_set_editable(GTK_TEXT_VIEW(node->widget), FALSE);
    gtk_text_view_set_cursor_visible(GTK_TEXT_VIEW(node->widget), FALSE);
    gtk_text_view_set_monospace(GTK_TEXT_VIEW(node->widget), FALSE);
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(node->widget));
    gtk_text_buffer_set_text(buffer, value, -1);
    gtk_widget_add_css_class(node->widget, "omni-static-text");
  } else {
    node->widget = gtk_label_new(value);
    gtk_label_set_xalign(GTK_LABEL(node->widget), 0.0f);
    gtk_label_set_wrap(GTK_LABEL(node->widget), TRUE);
  }
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  omni_accessible_label(node->widget, value);
  return node;
}

OmniAdwNode *omni_adw_button_new(const char *label, int32_t action_id) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_button_new_with_label(label ? label : "Button");
  gtk_widget_set_halign(node->widget, GTK_ALIGN_START);
  gtk_widget_set_vexpand(node->widget, FALSE);
  gtk_widget_set_valign(node->widget, GTK_ALIGN_CENTER);
  omni_accessible_label(node->widget, label);
  g_object_set_data(G_OBJECT(node->widget), "omni-action-id", GINT_TO_POINTER(action_id));
  g_signal_connect(node->widget, "clicked", G_CALLBACK(on_clicked), NULL);
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
  g_object_set_data(G_OBJECT(node->widget), "omni-action-id", GINT_TO_POINTER(action_id));
  g_signal_connect(node->widget, "changed", G_CALLBACK(on_entry_changed), NULL);
  return node;
}

OmniAdwNode *omni_adw_secure_entry_new(const char *placeholder, const char *text, int32_t action_id) {
  OmniAdwNode *node = omni_adw_entry_new(placeholder, text, action_id);
  if (node && node->widget && GTK_IS_ENTRY(node->widget)) {
    gtk_entry_set_visibility(GTK_ENTRY(node->widget), FALSE);
    gtk_entry_set_invisible_char(GTK_ENTRY(node->widget), 0x2022);
  }
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
  g_object_set_data(G_OBJECT(node->widget), "omni-action-id", GINT_TO_POINTER(action_id));
  g_signal_connect(buffer, "changed", G_CALLBACK(on_text_buffer_changed), node->widget);
  return node;
}

OmniAdwNode *omni_adw_dropdown_new(const char *title, const char *value, const char **labels, const int32_t *action_ids, int32_t count) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_menu_button_new();
  GtkWidget *popover = gtk_popover_new();
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
  gtk_popover_set_child(GTK_POPOVER(popover), box);
  const char *selected_label = NULL;
  for (int32_t i = 0; i < count; i++) {
    const char *label = labels && labels[i] ? labels[i] : "";
    GtkWidget *item = gtk_button_new_with_label(label);
    gtk_widget_set_halign(item, GTK_ALIGN_FILL);
    gtk_widget_set_hexpand(item, TRUE);
    omni_accessible_label(item, label);
    g_object_set_data(G_OBJECT(item), "omni-owner", node->widget);
    g_object_set_data(G_OBJECT(item), "omni-action-id", GINT_TO_POINTER(action_ids ? action_ids[i] : 0));
    g_signal_connect(item, "clicked", G_CALLBACK(on_menu_option_clicked), popover);
    gtk_box_append(GTK_BOX(box), item);
    if (value && strcmp(value, label) == 0) selected_label = label;
  }
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_vexpand(node->widget, FALSE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  gtk_widget_set_valign(node->widget, GTK_ALIGN_CENTER);
  gtk_menu_button_set_label(GTK_MENU_BUTTON(node->widget), selected_label ? selected_label : (title && title[0] ? title : "Select"));
  gtk_menu_button_set_popover(GTK_MENU_BUTTON(node->widget), popover);
  omni_accessible_label(node->widget, title && title[0] ? title : selected_label);
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
    gtk_widget_set_tooltip_text(node->widget, label);
  }
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  return node;
}

OmniAdwNode *omni_adw_scale_new(const char *label, double value, double lower, double upper, double step, int32_t decrement_action_id, int32_t increment_action_id) {
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
  GtkWidget *popover = gtk_popover_new();
  GtkWidget *calendar = gtk_calendar_new();
  gtk_widget_set_focusable(calendar, FALSE);
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
  gtk_widget_set_tooltip_text(box, combined);
  g_free(combined);
  node->widget = box;
  return node;
}

OmniAdwNode *omni_adw_scroll_new(int32_t vertical, double offset) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_scrolled_window_new();
  gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(node->widget), vertical ? GTK_POLICY_NEVER : GTK_POLICY_AUTOMATIC, vertical ? GTK_POLICY_AUTOMATIC : GTK_POLICY_NEVER);
  gtk_scrolled_window_set_propagate_natural_height(GTK_SCROLLED_WINDOW(node->widget), FALSE);
  gtk_scrolled_window_set_propagate_natural_width(GTK_SCROLLED_WINDOW(node->widget), FALSE);
  if (offset > 0.0) {
    double *stored_offset = malloc(sizeof(double));
    if (stored_offset) {
      *stored_offset = omni_semantic_scroll_to_pixels(offset);
      g_object_set_data_full(G_OBJECT(node->widget), "omni-scroll-offset", stored_offset, free);
    }
  }
  omni_widget_expand(node->widget, vertical != 0);
  return node;
}

OmniAdwNode *omni_adw_separator_new(void) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
  return node;
}

OmniAdwNode *omni_adw_drawing_new(const char *label) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_drawing_area_new();
  gtk_widget_set_size_request(node->widget, 96, 64);
  gtk_widget_add_css_class(node->widget, "omni-drawing-island");
  omni_accessible_label(node->widget, label ? label : "OmniUI drawing island");
  gtk_widget_set_tooltip_text(node->widget, label ? label : "OmniUI drawing island");
  return node;
}

OmniAdwNode *omni_adw_frame_new(const char *css_classes, int32_t spacing) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_box_new(GTK_ORIENTATION_VERTICAL, spacing);
  if (css_classes && css_classes[0]) {
    char *copy = omni_strdup(css_classes);
    char *token = strtok(copy, " ");
    while (token) {
      gtk_widget_add_css_class(node->widget, token);
      token = strtok(NULL, " ");
    }
    free(copy);
  }
  omni_widget_expand(node->widget, TRUE);
  return node;
}

void omni_adw_node_apply_layout(OmniAdwNode *node, int32_t width, int32_t height, int32_t min_width, int32_t min_height, int32_t margin_top, int32_t margin_start, int32_t margin_bottom, int32_t margin_end, double opacity) {
  if (!node || !node->widget) return;
  int request_width = width > 0 ? width : min_width;
  int request_height = height > 0 ? height : min_height;
  if (request_width > 0 || request_height > 0) {
    gtk_widget_set_size_request(node->widget, request_width > 0 ? request_width : -1, request_height > 0 ? request_height : -1);
  }
  if (margin_top >= 0) gtk_widget_set_margin_top(node->widget, margin_top);
  if (margin_start >= 0) gtk_widget_set_margin_start(node->widget, margin_start);
  if (margin_bottom >= 0) gtk_widget_set_margin_bottom(node->widget, margin_bottom);
  if (margin_end >= 0) gtk_widget_set_margin_end(node->widget, margin_end);
  if (opacity >= 0.0 && opacity <= 1.0) {
    gtk_widget_set_opacity(node->widget, opacity);
  }
}

void omni_adw_node_set_sensitive(OmniAdwNode *node, int32_t sensitive) {
  if (!node || !node->widget) return;
  gtk_widget_set_sensitive(node->widget, sensitive != 0);
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

void omni_adw_node_append(OmniAdwNode *parent, OmniAdwNode *child) {
  if (!parent || !child || !parent->widget || !child->widget) return;
  if (GTK_IS_BOX(parent->widget)) {
    gtk_box_append(GTK_BOX(parent->widget), child->widget);
  } else if (GTK_IS_LIST_BOX(parent->widget)) {
    GtkWidget *row = gtk_list_box_row_new();
    gtk_widget_set_hexpand(child->widget, TRUE);
    gtk_widget_set_halign(child->widget, GTK_ALIGN_FILL);
    gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), child->widget);
    gtk_list_box_append(GTK_LIST_BOX(parent->widget), row);
  } else if (GTK_IS_PANED(parent->widget)) {
    if (!gtk_paned_get_start_child(GTK_PANED(parent->widget))) {
      gtk_paned_set_start_child(GTK_PANED(parent->widget), child->widget);
    } else if (!gtk_paned_get_end_child(GTK_PANED(parent->widget))) {
      gtk_paned_set_end_child(GTK_PANED(parent->widget), child->widget);
    }
  } else if (ADW_IS_NAVIGATION_SPLIT_VIEW(parent->widget)) {
    const gboolean sidebar = parent->split_child_count == 0;
    GtkWidget *child_widget = child->widget;
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
  }
  child->widget = NULL;
  omni_adw_node_free(child);
}

void omni_adw_node_free(OmniAdwNode *node) {
  if (!node) return;
  free(node);
}
