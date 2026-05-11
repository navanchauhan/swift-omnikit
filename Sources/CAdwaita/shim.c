#include "CAdwaita.h"

#include <adwaita.h>
#include <gdk/gdkkeysyms.h>
#if defined(__APPLE__)
#include <objc/message.h>
#include <objc/objc.h>
#include <objc/runtime.h>
#endif
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
  GtkWidget *header_tab_strip;
  GtkWidget *header_selected_tab;
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
  guint macos_accessibility_sync_source;
};

struct OmniAdwNode {
  GtkWidget *widget;
  int32_t split_child_count;
};

typedef struct {
  char **labels;
  int32_t *action_ids;
  int32_t *depths;
  gboolean *collapsed;
  int32_t *visible_indices;
  int32_t visible_count;
  int32_t count;
  GtkStringList *string_list;
  GtkWidget **rows;
} OmniStringListData;

typedef struct {
  double x;
  double y;
} OmniClickStart;

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
  }
  free(list->labels);
  free(list->action_ids);
  free(list->depths);
  free(list->collapsed);
  free(list->visible_indices);
  free(list->rows);
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

static gboolean omni_cached_bool_update(GtkWidget *widget, const char *key, gboolean value) {
  if (!widget || !key) return FALSE;
  int next = value ? 1 : 2;
  int current = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), key));
  if (current == next) return FALSE;
  g_object_set_data(G_OBJECT(widget), key, GINT_TO_POINTER(next));
  return TRUE;
}

static void omni_accessible_label(GtkWidget *widget, const char *label) {
  if (!widget || !label || !label[0]) return;
  const char *current = (const char *)g_object_get_data(G_OBJECT(widget), "omni-accessible-label");
  if (current && strcmp(current, label) == 0) return;
  g_object_set_data_full(G_OBJECT(widget), "omni-accessible-label", omni_strdup(label), free);
  gtk_accessible_update_property(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_PROPERTY_LABEL, label, -1);
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
  const char *current = (const char *)g_object_get_data(G_OBJECT(widget), "omni-accessible-value");
  if (current && strcmp(current, value) == 0) return;
  g_object_set_data_full(G_OBJECT(widget), "omni-accessible-value", omni_strdup(value), free);
  gtk_accessible_update_property(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_PROPERTY_VALUE_TEXT, value, -1);
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

static void omni_flush_pending_ui(OmniAdwApp *app) {
  if (app && app->window) gtk_widget_queue_draw(app->window);
  while (g_main_context_pending(NULL)) {
    g_main_context_iteration(NULL, FALSE);
  }
  omni_macos_accessibility_cancel_pending(app);
  omni_macos_accessibility_sync(app);
}

static void present_settings_window(OmniAdwApp *app);
static void present_about_dialog(OmniAdwApp *app);
static void install_application_actions(OmniAdwApp *app);
static void on_settings_clicked(GtkButton *button, gpointer data);
static gboolean on_settings_close_request(GtkWindow *window, gpointer data);
static gboolean on_key_pressed(GtkEventControllerKey *controller, guint keyval, guint keycode, GdkModifierType state, gpointer data);
static void on_window_click_pressed(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data);
static void on_window_click_released(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data);
static void on_sidebar_toggle_toggled(GtkToggleButton *button, gpointer data);
static void on_split_show_sidebar_notify(GObject *object, GParamSpec *pspec, gpointer data);
static void on_new_tab_clicked(GtkButton *button, gpointer data);
static void on_header_tab_clicked(GtkButton *button, gpointer data);
static void on_entry_changed(GtkEditable *editable, gpointer data);
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

static void omni_install_css_once(void) {
  static gboolean installed = FALSE;
  if (installed) return;
  installed = TRUE;

  const char *css =
    ".omni-stack { padding: 0; }"
    ".omni-shell { background: @window_bg_color; }"
    ".omni-header { min-height: 44px; padding: 8px 12px; border-bottom: 1px solid alpha(@borders, 0.65); background: alpha(@headerbar_bg_color, 1.0); }"
    ".omni-title { font-weight: 700; }"
    ".omni-tab-strip { margin-top: 2px; margin-bottom: 4px; }"
    ".omni-selected-tab { min-height: 24px; padding: 2px 12px; border-radius: 7px 7px 0 0; font-weight: 600; background: alpha(@card_bg_color, 0.85); border: 1px solid alpha(@borders, 0.70); }"
    ".omni-inactive-tab { min-height: 24px; padding: 2px 12px; border-radius: 7px 7px 0 0; background: transparent; }"
    ".omni-body { padding: 0; }"
    ".card { border-radius: 10px; padding: 12px; margin: 4px 0; background: alpha(@card_bg_color, 0.82); }"
    ".adw-dialog { padding: 0; margin: 0; background: transparent; }"
    ".omni-sheet-surface { padding: 18px 20px 12px 20px; margin: 0; border-radius: 18px; border: 1px solid rgba(255,255,255,0.24); background: #303036; background-color: #303036; color: #f6f6f7; box-shadow: 0 24px 72px rgba(0,0,0,0.55); }"
    ".boxed-list { border-radius: 0; padding: 0; margin: 0; background: transparent; }"
    ".omni-plain-list { background: transparent; }"
    ".omni-plain-list row { min-height: 24px; padding: 0 0; background: transparent; border-bottom: 1px solid alpha(@borders, 0.16); }"
    ".omni-plain-list row:hover { background: transparent; }"
    ".omni-plain-list label { padding: 2px 6px; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size: 13px; font-weight: 500; }"
    ".omni-list-row-button { min-height: 24px; padding: 0; border-radius: 0; background: transparent; box-shadow: none; }"
    ".omni-list-row-button:hover { background: alpha(@view_fg_color, 0.06); }"
    ".omni-list-row-button label { padding: 2px 6px; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size: 13px; font-weight: 500; }"
    ".omni-sidebar-list { background: alpha(@window_bg_color, 0.98); padding: 8px 0; }"
    ".omni-sidebar-list row { min-height: 25px; padding: 0; border-radius: 6px; margin: 0 6px 1px 6px; }"
    ".omni-sidebar-list row:hover { background: transparent; }"
    ".omni-sidebar-list row:selected { background: alpha(@accent_bg_color, 0.24); }"
    ".omni-sidebar-row-button { min-height: 25px; padding: 0; margin: 0 6px 1px 6px; border-radius: 6px; background: transparent; box-shadow: none; }"
    ".omni-sidebar-row-button:hover { background: alpha(@view_fg_color, 0.06); }"
    ".omni-sidebar-disclosure-button { min-width: 22px; min-height: 24px; padding: 0; border-radius: 6px; background: transparent; box-shadow: none; }"
    ".omni-sidebar-disclosure-button:hover { background: alpha(@view_fg_color, 0.08); }"
    ".omni-sidebar-row { padding: 1px 6px; }"
    ".omni-sidebar-label { font-size: 13px; font-weight: 600; }"
    ".omni-sidebar-disclosure { min-width: 14px; opacity: 0.75; }"
    ".navigation-view { padding: 0; border-radius: 0; background: @window_bg_color; }"
    ".view { padding: 2px; }"
    ".accent { border-radius: 8px; padding: 6px 8px; background: alpha(@accent_bg_color, 0.18); }"
    ".crt { }"
    ".omni-drawing-island { border-radius: 8px; background: alpha(@accent_bg_color, 0.18); border: 1px solid alpha(@accent_bg_color, 0.55); min-height: 64px; }"
    "button { border-radius: 8px; font-weight: 600; }"
    ".omni-icon-button { min-width: 38px; min-height: 34px; padding: 0; font-size: 16px; }"
    ".omni-go-button { min-width: 46px; min-height: 34px; padding: 0 12px; font-weight: 700; }"
    ".omni-static-text text, .omni-static-text { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size: 13px; }"
    ".omni-monospace-text { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size: 13px; }"
    ".omni-sidebar-toggle { min-width: 36px; min-height: 34px; padding: 0; }"
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
  gtk_box_append(GTK_BOX(app->header_entry_row), app->header_entry);

  app->header_new_tab_button = gtk_button_new();
  gtk_button_set_icon_name(GTK_BUTTON(app->header_new_tab_button), "adw-tab-new-symbolic");
  gtk_widget_add_css_class(app->header_new_tab_button, "flat");
  gtk_widget_add_css_class(app->header_new_tab_button, "omni-icon-button");
  gtk_widget_set_size_request(app->header_new_tab_button, 38, 34);
  gtk_widget_set_tooltip_text(app->header_new_tab_button, "New tab");
  gtk_widget_set_vexpand(app->header_new_tab_button, FALSE);
  gtk_widget_set_valign(app->header_new_tab_button, GTK_ALIGN_CENTER);
  omni_accessible_label(app->header_new_tab_button, "New tab");
  omni_accessible_description(app->header_new_tab_button, "Opens a new tab");
  g_signal_connect(app->header_new_tab_button, "clicked", G_CALLBACK(on_new_tab_clicked), app);
  gtk_box_append(GTK_BOX(app->header_entry_row), app->header_new_tab_button);

  gtk_box_append(GTK_BOX(app->header_title_box), app->header_entry_row);
  adw_header_bar_set_title_widget(ADW_HEADER_BAR(app->header), app->header_title_box);
  wire_actions(app->header_title_box, app);
  sync_header_entry(app);
}

static void on_app_preferences_action(GSimpleAction *action, GVariant *parameter, gpointer data) {
  (void)action;
  (void)parameter;
  present_settings_window((OmniAdwApp *)data);
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
  if (app && app->application) g_application_quit(G_APPLICATION(app->application));
}

static void on_app_new_tab_action(GSimpleAction *action, GVariant *parameter, gpointer data) {
  (void)action;
  (void)parameter;
  on_new_tab_clicked(NULL, data);
}

static void install_application_actions(OmniAdwApp *app) {
  if (!app || !app->application) return;
  const GActionEntry entries[] = {
    { "preferences", on_app_preferences_action, NULL, NULL, NULL },
    { "about", on_app_about_action, NULL, NULL, NULL },
    { "new-tab", on_app_new_tab_action, NULL, NULL, NULL },
    { "quit", on_app_quit_action, NULL, NULL, NULL },
  };
  g_action_map_add_action_entries(G_ACTION_MAP(app->application), entries, G_N_ELEMENTS(entries), app);

  const char *settings_accels[] = { "<Meta>comma", NULL };
  const char *new_tab_accels[] = { "<Meta>t", NULL };
  const char *quit_accels[] = { "<Meta>q", NULL };
  gtk_application_set_accels_for_action(GTK_APPLICATION(app->application), "app.preferences", settings_accels);
  gtk_application_set_accels_for_action(GTK_APPLICATION(app->application), "app.new-tab", new_tab_accels);
  gtk_application_set_accels_for_action(GTK_APPLICATION(app->application), "app.quit", quit_accels);

  GMenu *menubar = g_menu_new();
  GMenu *app_menu = g_menu_new();
  char about_label[160];
  snprintf(about_label, sizeof(about_label), "About %s", app->title ? app->title : "OmniUI Adwaita");
  g_menu_append(app_menu, about_label, "app.about");
  g_menu_append(app_menu, "Settings...", "app.preferences");
  g_menu_append(app_menu, "New Tab", "app.new-tab");
  g_menu_append(app_menu, "Quit", "app.quit");
  g_menu_append_submenu(menubar, app->title ? app->title : "OmniUI Adwaita", G_MENU_MODEL(app_menu));
  gtk_application_set_menubar(GTK_APPLICATION(app->application), G_MENU_MODEL(menubar));
  g_object_unref(app_menu);
  g_object_unref(menubar);
}

static void on_app_activate(GApplication *application, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app->window) {
    omni_apply_color_scheme_from_environment();
    app->window = adw_application_window_new(GTK_APPLICATION(application));
    gtk_window_set_title(GTK_WINDOW(app->window), app->title);
    gtk_window_set_default_size(GTK_WINDOW(app->window), app->default_width, app->default_height);
    omni_accessible_label(app->window, app->title ? app->title : "OmniUI Adwaita");
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
      gtk_widget_add_controller(app->window, app->key_controller);
    }
    GtkGesture *click_controller = gtk_gesture_click_new();
    gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(click_controller), GTK_PHASE_CAPTURE);
    g_signal_connect(click_controller, "pressed", G_CALLBACK(on_window_click_pressed), app);
    g_signal_connect(click_controller, "released", G_CALLBACK(on_window_click_released), app);
    gtk_widget_add_controller(app->window, GTK_EVENT_CONTROLLER(click_controller));
  }
  gtk_window_present(GTK_WINDOW(app->window));
  omni_macos_accessibility_schedule(app);
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
  gtk_accessible_update_state(
    GTK_ACCESSIBLE(button),
    GTK_ACCESSIBLE_STATE_CHECKED,
    gtk_check_button_get_active(button) ? GTK_ACCESSIBLE_TRISTATE_TRUE : GTK_ACCESSIBLE_TRISTATE_FALSE,
    -1
  );
  if (app && app->callback) {
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
  free(list->visible_indices);
  list->visible_indices = calloc((size_t)list->count, sizeof(int32_t));
  list->visible_count = 0;
  for (int32_t i = 0; i < list->count; i++) {
    if (sidebar_index_is_visible(list, i)) {
      list->visible_indices[list->visible_count++] = i;
    }
  }
  if (list->string_list) {
    guint existing = g_list_model_get_n_items(G_LIST_MODEL(list->string_list));
    while (existing > 0) {
      gtk_string_list_remove(list->string_list, 0);
      existing--;
    }
    for (int32_t i = 0; i < list->visible_count; i++) {
      int32_t original = list->visible_indices[i];
      gtk_string_list_append(list->string_list, list->labels[original] ? list->labels[original] : "");
    }
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
  if (!GTK_IS_BUTTON(button) || !GTK_IS_STRING_OBJECT(item)) return;
  GtkWidget *label = gtk_button_get_child(GTK_BUTTON(button));
  if (!GTK_IS_LABEL(label)) return;
  const char *text = gtk_string_object_get_string(GTK_STRING_OBJECT(item));
  guint position = gtk_list_item_get_position(list_item);
  GtkWidget *list_view = gtk_widget_get_ancestor(button, GTK_TYPE_LIST_VIEW);
  OmniStringListData *list = list_view ? (OmniStringListData *)g_object_get_data(G_OBJECT(list_view), "omni-string-list-data") : NULL;
  int32_t original = sidebar_original_index_for_visible_position(list, position);
  int32_t action_id = list && list->action_ids && original >= 0 && original < list->count ? list->action_ids[original] : 0;
  int32_t count = list ? list->count : 0;

  gtk_label_set_text(GTK_LABEL(label), text ? text : "");
  gtk_list_item_set_accessible_label(list_item, text ? text : "");
  gtk_list_item_set_accessible_description(list_item, action_id > 0 ? "Activates this list row" : "Static list row");
  gtk_list_item_set_activatable(list_item, action_id > 0);
  gtk_list_item_set_selectable(list_item, action_id > 0);
  gtk_list_item_set_focusable(list_item, action_id > 0);
  g_object_set_data(G_OBJECT(button), "omni-action-id", GINT_TO_POINTER(action_id));
  gtk_widget_set_focusable(button, action_id > 0);
  omni_accessible_set_disabled(button, action_id <= 0);
  omni_accessible_set_selected(button, gtk_list_item_get_selected(list_item));
  omni_accessible_list_position(button, (int32_t)position + 1, count);
  omni_accessible_description(button, action_id > 0 ? "Activates this list row" : "Static list row");
  omni_accessible_label(button, text);
}

static void on_string_list_activate(GtkListView *view, guint position, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)g_object_get_data(G_OBJECT(view), "omni-app");
  OmniStringListData *list = (OmniStringListData *)g_object_get_data(G_OBJECT(view), "omni-string-list-data");
  int32_t original = sidebar_original_index_for_visible_position(list, position);
  if (!app || !app->callback || !list || original < 0 || original >= list->count) return;
  int32_t action_id = list->action_ids ? list->action_ids[original] : 0;
  if (action_id > 0) {
    app->callback(action_id, app->context);
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
  if (app && app->callback && action_id > 0) {
    app->callback(action_id, app->context);
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
  GtkWidget *label = gtk_label_new("");
  gtk_widget_add_css_class(label, "omni-sidebar-label");
  gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
  gtk_label_set_wrap(GTK_LABEL(label), FALSE);
  gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_END);
  gtk_widget_set_hexpand(label, TRUE);
  gtk_widget_set_halign(label, GTK_ALIGN_FILL);
  gtk_button_set_child(GTK_BUTTON(button), label);
  gtk_box_append(GTK_BOX(box), button);

  gtk_list_item_set_child(list_item, box);
}

static void on_sidebar_list_bind(GtkSignalListItemFactory *factory, GtkListItem *list_item, gpointer data) {
  GtkWidget *box = gtk_list_item_get_child(list_item);
  gpointer item = gtk_list_item_get_item(list_item);
  if (!GTK_IS_BOX(box)) return;
  if (!GTK_IS_STRING_OBJECT(item)) return;
  GtkWidget *disclosure_button = gtk_widget_get_first_child(box);
  GtkWidget *button = disclosure_button ? gtk_widget_get_next_sibling(disclosure_button) : NULL;
  GtkWidget *disclosure = GTK_IS_BUTTON(disclosure_button) ? gtk_button_get_child(GTK_BUTTON(disclosure_button)) : NULL;
  GtkWidget *label = GTK_IS_BUTTON(button) ? gtk_button_get_child(GTK_BUTTON(button)) : NULL;
  if (!GTK_IS_BUTTON(disclosure_button) || !GTK_IS_BUTTON(button) || !GTK_IS_LABEL(disclosure) || !GTK_IS_LABEL(label)) return;

  const char *text = gtk_string_object_get_string(GTK_STRING_OBJECT(item));
  guint position = gtk_list_item_get_position(list_item);
  OmniStringListData *list = (OmniStringListData *)data;
  int32_t original = sidebar_original_index_for_visible_position(list, position);
  int32_t depth = list && list->depths && original >= 0 && original < list->count ? list->depths[original] : 0;
  int32_t action_id = list && list->action_ids && original >= 0 && original < list->count ? list->action_ids[original] : 0;
  int32_t count = list ? list->count : 0;
  gboolean has_children = sidebar_row_has_children(list, original);
  if (depth < 0) depth = 0;
  if (depth > 8) depth = 8;

  gtk_widget_set_margin_start(box, depth * 16);
  gtk_widget_set_visible(disclosure_button, has_children);
  gtk_label_set_text(GTK_LABEL(disclosure), has_children ? (list->collapsed && list->collapsed[original] ? "▸" : "▾") : "");
  gtk_label_set_text(GTK_LABEL(label), text ? text : "");
  gtk_list_item_set_accessible_label(list_item, text ? text : "");
  gtk_list_item_set_accessible_description(list_item, has_children ? "Collapsible sidebar item" : (action_id > 0 ? "Sidebar item" : "Static sidebar item"));
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
  omni_accessible_label(button, text);
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

static void on_new_tab_clicked(GtkButton *button, gpointer data) {
  (void)button;
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app) return;
  int32_t action_id = first_action_id_with_accessible_label(app->content, "New tab");
  if (action_id > 0 && app->callback) {
    app->callback(action_id, app->context);
    omni_flush_pending_ui(app);
  }
  if (app->tab_count < 1) app->tab_count = 1;
  app->tab_count += 1;
  app->active_tab = app->tab_count - 1;
  update_header_tab_strip(app);
  if (app->header_entry) {
    gtk_widget_grab_focus(app->header_entry);
    if (app->header_entry_action_id > 0) {
      gtk_editable_set_text(GTK_EDITABLE(app->header_entry), "");
      gtk_editable_set_position(GTK_EDITABLE(app->header_entry), 0);
    }
  }
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

static void on_plain_list_row_released(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data) {
  if (!omni_click_is_stationary(gesture, x, y)) return;
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
  if (app && app->callback && action_id > 0) {
    app->callback(action_id, app->context);
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

static const char *omni_symbolic_icon_name_for_label(const char *label) {
  if (!label || !label[0]) return NULL;
  if (strcmp(label, "⌂") == 0) return "user-home-symbolic";
  if (strcmp(label, "‹") == 0) return "go-previous-symbolic";
  if (strcmp(label, "›") == 0) return "go-next-symbolic";
  if (strcmp(label, "☰") == 0) return "open-menu-symbolic";
  if (strcmp(label, "↗") == 0) return "adw-external-link-symbolic";
  if (strcmp(label, "◆") == 0) return "bookmark-new-symbolic";
  if (strcmp(label, "+") == 0) return "adw-tab-new-symbolic";
  if (strcmp(label, "⌕") == 0 || strcmp(label, "🔍") == 0) return "system-search-symbolic";
  if (strcmp(label, "✓") == 0) return "adw-entry-apply-symbolic";
  return NULL;
}

static const char *omni_accessible_label_for_symbolic_label(const char *label) {
  if (!label || !label[0]) return NULL;
  if (strcmp(label, "⌂") == 0) return "Home";
  if (strcmp(label, "‹") == 0) return "Back";
  if (strcmp(label, "›") == 0) return "Forward";
  if (strcmp(label, "☰") == 0) return "Menu";
  if (strcmp(label, "↗") == 0) return "Open externally";
  if (strcmp(label, "◆") == 0) return "Bookmark";
  if (strcmp(label, "+") == 0) return "New tab";
  if (strcmp(label, "⌕") == 0 || strcmp(label, "🔍") == 0) return "Search";
  if (strcmp(label, "✓") == 0) return "Apply";
  return NULL;
}

static gboolean omni_button_set_symbolic_icon(GtkButton *button, const char *label) {
  const char *icon_name = omni_symbolic_icon_name_for_label(label);
  if (!button || !icon_name) return FALSE;
  gtk_button_set_icon_name(button, icon_name);
  GtkWidget *widget = GTK_WIDGET(button);
  gtk_widget_add_css_class(widget, "omni-icon-button");
  gtk_widget_set_size_request(widget, 38, 34);
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
  if (!app || !app->callback) return;

  double previous = 0.0;
  double *previous_ptr = (double *)g_object_get_data(G_OBJECT(range), "omni-scale-value");
  if (previous_ptr) previous = *previous_ptr;
  double next = gtk_range_get_value(range);
  gtk_accessible_update_property(GTK_ACCESSIBLE(range), GTK_ACCESSIBLE_PROPERTY_VALUE_NOW, next, -1);

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
  gtk_accessible_update_property(GTK_ACCESSIBLE(spin), GTK_ACCESSIBLE_PROPERTY_VALUE_NOW, next, -1);

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
  omni_accessible_value_text(GTK_WIDGET(button), gtk_button_get_label(button));
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
  if (app && action_id > 0) app->focused_action_id = action_id;
  omni_accessible_value_text(GTK_WIDGET(editable), gtk_editable_get_text(editable));
  omni_macos_accessibility_schedule(app);
  if (g_object_get_data(G_OBJECT(editable), "omni-modal-native-entry") != NULL) return;
  if (app && app->text_callback) {
    app->text_callback(action_id, gtk_editable_get_text(editable), app->context);
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

static GtkWidget *app_modal_native_text_widget(OmniAdwApp *app) {
  if (!app || !app->modal_dialog) return NULL;
  GtkWidget *entry = (GtkWidget *)g_object_get_data(G_OBJECT(app->modal_dialog), "omni-modal-entry");
  if (entry && (GTK_IS_ENTRY(entry) || GTK_IS_TEXT_VIEW(entry))) return entry;
  return NULL;
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

static gboolean on_key_pressed(GtkEventControllerKey *controller, guint keyval, guint keycode, GdkModifierType state, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app || !app->key_callback) return FALSE;

  if ((state & (GDK_META_MASK | GDK_CONTROL_MASK)) != 0 && keyval == GDK_KEY_comma) {
    present_settings_window(app);
    return TRUE;
  }

  if (keyval == GDK_KEY_Return || keyval == GDK_KEY_KP_Enter) {
    app->key_callback(0, 7, 0, app->context);
    return TRUE;
  }
  if (keyval == GDK_KEY_Escape) {
    app->key_callback(0, 8, 0, app->context);
    return TRUE;
  }

  GtkWidget *native_text = controller_native_text_widget(controller);
  if (!native_text) native_text = app_focused_native_text_widget(app);
  if (!native_text) native_text = app_modal_native_text_widget(app);
  if (native_text) {
    if (handle_entry_readline_key(app, native_text, keyval, state)) return TRUE;
    return FALSE;
  }

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
  app->key_callback(app->focused_action_id, kind, codepoint, app->context);
  return TRUE;
}

static void on_window_click_pressed(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data) {
  if (n_press != 1) return;
  omni_record_click_start(gesture, x, y);
}

static void on_window_click_released(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data) {
  if (!omni_click_is_stationary(gesture, x, y)) return;
  OmniAdwApp *app = (OmniAdwApp *)data;
  GtkWidget *window = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(gesture));
  GtkWidget *picked = window ? gtk_widget_pick(window, x, y, GTK_PICK_DEFAULT) : NULL;
  GtkWidget *action_widget = picked;
  while (action_widget) {
    int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(action_widget), "omni-action-id"));
    if (action_id > 0 && (GTK_IS_BUTTON(action_widget) || GTK_IS_CHECK_BUTTON(action_widget) || GTK_IS_MENU_BUTTON(action_widget))) {
      return;
    }
    if (action_id > 0 && GTK_IS_LIST_BOX_ROW(action_widget)) {
      if (app && app->callback) {
        app->callback(action_id, app->context);
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

static void wire_actions(GtkWidget *widget, OmniAdwApp *app) {
  if (!widget) return;
  if (GTK_IS_BUTTON(widget) || GTK_IS_CHECK_BUTTON(widget) || GTK_IS_ENTRY(widget) || GTK_IS_TEXT_VIEW(widget) || GTK_IS_DROP_DOWN(widget) || GTK_IS_MENU_BUTTON(widget) || GTK_IS_SCALE(widget) || GTK_IS_SPIN_BUTTON(widget) || GTK_IS_CALENDAR(widget) || GTK_IS_LIST_VIEW(widget) || GTK_IS_LIST_BOX(widget)) {
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
    if (GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-menu-expanded")) != 0 &&
        !g_object_get_data(G_OBJECT(widget), "omni-menu-popup-opened")) {
      gtk_menu_button_popup(GTK_MENU_BUTTON(widget));
      g_object_set_data(G_OBJECT(widget), "omni-menu-popup-opened", GINT_TO_POINTER(1));
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
static char omni_macos_accessibility_value_key;

static id omni_ns_string(const char *value);

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

static BOOL omni_macos_accessibility_perform_press(id self, SEL _cmd) {
  (void)_cmd;
  GtkWidget *widget = (GtkWidget *)objc_getAssociatedObject(self, &omni_macos_accessibility_widget_key);
  if (!widget) return NO;
  if (GTK_IS_ENTRY(widget) || GTK_IS_TEXT_VIEW(widget)) {
    gtk_widget_grab_focus(widget);
    return YES;
  }
  OmniAdwApp *app = omni_app_for_widget(widget);
  if (GTK_IS_BUTTON(widget)) {
    g_signal_emit_by_name(widget, "clicked");
    if (app) omni_flush_pending_ui(app);
    return YES;
  }
  if (GTK_IS_MENU_BUTTON(widget)) {
    gtk_menu_button_popup(GTK_MENU_BUTTON(widget));
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
  app->callback(actionID, app->context);
  omni_flush_pending_ui(app);
  return YES;
}

static void omni_macos_accessibility_set_value(id self, SEL _cmd, id value) {
  (void)_cmd;
  objc_setAssociatedObject(self, &omni_macos_accessibility_value_key, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  GtkWidget *widget = (GtkWidget *)objc_getAssociatedObject(self, &omni_macos_accessibility_widget_key);
  if (!widget || !value) return;
  const char *text = ((const char *(*)(id, SEL))objc_msgSend)(value, sel_registerName("UTF8String"));
  if (!text) text = "";
  if (GTK_IS_ENTRY(widget)) {
    gtk_editable_set_text(GTK_EDITABLE(widget), text);
    omni_accessible_value_text(widget, text);
    OmniAdwApp *app = omni_app_for_widget(widget);
    if (app) omni_macos_accessibility_schedule(app);
  } else if (GTK_IS_TEXT_VIEW(widget)) {
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(widget));
    gtk_text_buffer_set_text(buffer, text, -1);
    omni_accessible_value_text(widget, text);
    OmniAdwApp *app = omni_app_for_widget(widget);
    if (app) omni_macos_accessibility_schedule(app);
  }
}

static id omni_macos_accessibility_value(id self, SEL _cmd) {
  (void)_cmd;
  return objc_getAssociatedObject(self, &omni_macos_accessibility_value_key);
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
  if (GTK_IS_ENTRY(widget)) return "AXTextField";
  if (GTK_IS_TEXT_VIEW(widget)) return "AXTextArea";
  if (GTK_IS_CHECK_BUTTON(widget)) return "AXCheckBox";
  if (GTK_IS_BUTTON(widget) || GTK_IS_MENU_BUTTON(widget)) return "AXButton";
  if (GTK_IS_LIST_BOX_ROW(widget) && GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id")) > 0) return "AXButton";
  if (GTK_IS_LIST_BOX_ROW(widget)) return "AXRow";
  if (GTK_IS_LIST_VIEW(widget) || GTK_IS_LIST_BOX(widget)) return "AXList";
  if (GTK_IS_LABEL(widget)) return "AXStaticText";
  if (GTK_IS_SEPARATOR(widget)) return "AXSplitter";
  return "AXGroup";
}

static gboolean omni_macos_accessibility_is_action_widget(GtkWidget *widget) {
  if (!widget) return FALSE;
  if (GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id")) > 0) return TRUE;
  return GTK_IS_BUTTON(widget) || GTK_IS_MENU_BUTTON(widget) || GTK_IS_CHECK_BUTTON(widget);
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

static gboolean omni_macos_accessibility_should_export(GtkWidget *widget) {
  if (!widget || !gtk_widget_get_visible(widget) || !gtk_widget_get_mapped(widget)) return FALSE;
  if (GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id")) > 0) return TRUE;
  const char *label = (const char *)g_object_get_data(G_OBJECT(widget), "omni-accessible-label");
  if (label != NULL) {
    if (GTK_IS_LABEL(widget) && omni_macos_accessibility_has_exported_action_ancestor(widget)) return FALSE;
    if (!GTK_IS_ENTRY(widget) && !GTK_IS_TEXT_VIEW(widget) && !GTK_IS_BUTTON(widget) && !GTK_IS_MENU_BUTTON(widget) && !GTK_IS_CHECK_BUTTON(widget) && !GTK_IS_LIST_VIEW(widget) && !GTK_IS_LIST_BOX(widget) && !GTK_IS_LIST_BOX_ROW(widget) && strlen(label) > 160) return FALSE;
    return TRUE;
  }
  if (GTK_IS_ENTRY(widget) || GTK_IS_TEXT_VIEW(widget) || GTK_IS_BUTTON(widget) || GTK_IS_MENU_BUTTON(widget) || GTK_IS_CHECK_BUTTON(widget)) return TRUE;
  if (GTK_IS_LIST_VIEW(widget) || GTK_IS_LIST_BOX(widget) || GTK_IS_LIST_BOX_ROW(widget)) return TRUE;
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
  if (GTK_IS_ENTRY(widget)) return gtk_editable_get_text(GTK_EDITABLE(widget));
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
  if (!widget || !root || !elements || !count || *count >= 500) return;
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
          objc_setAssociatedObject(element, &omni_macos_accessibility_widget_key, (id)widget, OBJC_ASSOCIATION_ASSIGN);
          const char *description = (const char *)g_object_get_data(G_OBJECT(widget), "omni-accessible-description");
          const char *name = gtk_widget_get_name(widget);
          const char *value = omni_macos_widget_value(widget);
          int actionID = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "omni-action-id"));
          if (description && description[0]) omni_objc_send_void_id(element, "setAccessibilityHelp:", omni_ns_string(description));
          if (name && name[0]) omni_objc_send_void_id(element, "setAccessibilityIdentifier:", omni_ns_string(name));
          if (GTK_IS_ENTRY(widget) || GTK_IS_TEXT_VIEW(widget) || (value && value[0])) {
            objc_setAssociatedObject(element, &omni_macos_accessibility_value_key, omni_ns_string(value ? value : ""), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
          }
          omni_objc_send_void_bool(element, "setAccessibilityEnabled:", gtk_widget_get_sensitive(widget) && actionID >= 0);
          omni_objc_send_void_bool(element, "setAccessibilitySelected:", GTK_IS_LIST_BOX_ROW(widget) && gtk_list_box_row_is_selected(GTK_LIST_BOX_ROW(widget)));
          if (GTK_IS_BUTTON(widget) || GTK_IS_MENU_BUTTON(widget) || GTK_IS_CHECK_BUTTON(widget) || GTK_IS_LIST_BOX_ROW(widget)) {
            omni_objc_send_void_id(element, "setAccessibilityRoleDescription:", omni_ns_string(actionID > 0 ? "button" : "row"));
          }
          omni_ns_array_add(elements, element);
          *count += 1;
        }
      }
    }
  }

  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child) {
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
  if (app->modal_dialog && GTK_IS_WIDGET(app->modal_dialog)) {
    omni_macos_accessibility_add_widget(GTK_WIDGET(app->modal_dialog), GTK_WIDGET(app->modal_dialog), window, elements, windowFrame, contentFrame, &count);
  }
  omni_macos_accessibility_add_widget(app->window, app->window, window, elements, windowFrame, contentFrame, &count);

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

static void omni_macos_accessibility_schedule_after_scroll(OmniAdwApp *app) {
  if (!app) return;
  omni_macos_accessibility_cancel_pending(app);
  GSource *source = g_timeout_source_new(120);
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

static void omni_macos_accessibility_schedule_after_scroll(OmniAdwApp *app) {
  (void)app;
}
#endif

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
  app->sidebar_show_sidebar = TRUE;
  app->sidebar_collapsed_items = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
  app->tab_count = 1;
  app->active_tab = 0;
  app->application = adw_application_new(app_id ? app_id : "dev.omnikit.OmniUIAdwaita", G_APPLICATION_DEFAULT_FLAGS);
  install_application_actions(app);
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
  if (app->window) {
    gtk_show_uri(GTK_WINDOW(app->window), url, GDK_CURRENT_TIME);
  }
}

int32_t omni_adw_app_run(OmniAdwApp *app, int32_t argc, char **argv) {
  if (!app) return 1;
  return g_application_run(G_APPLICATION(app->application), argc, argv);
}

void omni_adw_app_free(OmniAdwApp *app) {
  if (!app) return;
  if (app->macos_accessibility_sync_source != 0) g_source_remove(app->macos_accessibility_sync_source);
  if (app->modal_dialog) adw_dialog_force_close(app->modal_dialog);
  if (app->settings_window) gtk_window_destroy(GTK_WINDOW(app->settings_window));
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
      gtk_widget_add_controller(app->window, app->key_controller);
    }
  }
  GtkWidget *focused = find_widget_for_action(app->content, focused_action_id);
  if (focused && gtk_widget_get_focusable(focused)) {
    gtk_widget_grab_focus(focused);
  }
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
    GtkWidget *entry = (GtkWidget *)g_object_get_data(G_OBJECT(dialog), "omni-modal-entry");
    int entry_action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(dialog), "omni-modal-entry-action-id"));
    if (entry_action_id > 0 && GTK_IS_ENTRY(entry) && app->text_callback) {
      app->text_callback(entry_action_id, gtk_editable_get_text(GTK_EDITABLE(entry)), app->context);
    }
    int index = atoi(response + 1);
    if (index >= 0 && index < (int)summary->action_ids->len) {
      int action_id = g_array_index(summary->action_ids, int, index);
      app->callback(action_id, app->context);
    }
  }
  if (app && app->modal_dialog == ADW_DIALOG(dialog)) {
    app->modal_dialog = NULL;
    app->modal_close_action_id = 0;
    app->modal_force_closing = FALSE;
  }
}

static gboolean modal_button_label_is_cancel(const char *label);

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

static gboolean modal_button_label_is_close(const char *label) {
  return label && g_ascii_strcasecmp(label, "Close") == 0;
}

static gboolean modal_button_label_is_cancel(const char *label) {
  return label && g_ascii_strcasecmp(label, "Cancel") == 0;
}

static gboolean modal_button_label_is_search(const char *label) {
  return label && g_ascii_strcasecmp(label, "Search") == 0;
}

static void on_sheet_closed(AdwDialog *dialog, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app) return;
  if (app->modal_dialog != dialog) return;
  int action_id = app->modal_close_action_id;
  gboolean force_closing = app->modal_force_closing;
  app->modal_dialog = NULL;
  app->modal_close_action_id = 0;
  app->modal_force_closing = FALSE;
  if (!force_closing && action_id > 0 && app->callback) {
    app->callback(action_id, app->context);
  }
}

static void on_sheet_close_attempt(AdwDialog *dialog, gpointer data) {
  OmniAdwApp *app = (OmniAdwApp *)data;
  if (!app || app->modal_close_action_id <= 0) return;
  adw_dialog_close(dialog);
}

static void present_sheet_dialog(OmniAdwApp *app, OmniAdwNode *modal, OmniModalSummary *summary, int close_action_id) {
  int effective_close_action_id = close_action_id > 0 ? close_action_id : modal_cancel_action_id(summary);
  const char *heading = summary && summary->labels->len > 0
    ? (const char *)g_ptr_array_index(summary->labels, 0)
    : "Sheet";
  AdwDialog *dialog = adw_alert_dialog_new(heading, NULL);
  AdwAlertDialog *alert = ADW_ALERT_DIALOG(dialog);
  adw_dialog_set_title(dialog, "Sheet");
  adw_dialog_set_can_close(dialog, effective_close_action_id > 0);
  adw_dialog_set_content_width(dialog, 560);
  adw_dialog_set_content_height(dialog, 360);
  adw_dialog_set_presentation_mode(dialog, ADW_DIALOG_FLOATING);
  adw_alert_dialog_set_prefer_wide_layout(alert, TRUE);
  omni_accessible_label(GTK_WIDGET(dialog), "Sheet");
  omni_accessible_description(GTK_WIDGET(dialog), "Modal sheet");
  gtk_accessible_update_property(GTK_ACCESSIBLE(dialog), GTK_ACCESSIBLE_PROPERTY_MODAL, TRUE, -1);
  app->modal_dialog = dialog;
  app->modal_close_action_id = effective_close_action_id;
  app->modal_force_closing = FALSE;
  wire_actions(modal->widget, app);

  GtkWidget *source_entry = find_first_entry_widget(modal->widget);
  GtkWidget *sheet_entry = NULL;
  GtkWidget *surface = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_add_css_class(surface, "omni-sheet-surface");
  gtk_widget_set_hexpand(surface, TRUE);
  gtk_widget_set_halign(surface, GTK_ALIGN_CENTER);
  gtk_widget_set_vexpand(surface, FALSE);
  gtk_widget_set_valign(surface, GTK_ALIGN_CENTER);
  if (source_entry) {
    GtkWidget *entry = gtk_entry_new();
    const char *placeholder = gtk_entry_get_placeholder_text(GTK_ENTRY(source_entry));
    const char *text = gtk_editable_get_text(GTK_EDITABLE(source_entry));
    int action_id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(source_entry), "omni-action-id"));
    gtk_widget_set_hexpand(entry, TRUE);
    gtk_widget_set_halign(entry, GTK_ALIGN_FILL);
    gtk_widget_set_focusable(entry, TRUE);
    gtk_widget_set_size_request(entry, 440, -1);
    gtk_entry_set_placeholder_text(GTK_ENTRY(entry), placeholder ? placeholder : "");
    gtk_editable_set_text(GTK_EDITABLE(entry), text ? text : "");
    omni_accessible_label(entry, placeholder && placeholder[0] ? placeholder : "Search");
    omni_accessible_placeholder(entry, placeholder);
    omni_accessible_value_text(entry, text);
    g_object_set_data(G_OBJECT(entry), "omni-action-id", GINT_TO_POINTER(action_id));
    g_object_set_data(G_OBJECT(entry), "omni-app", app);
    g_object_set_data(G_OBJECT(entry), "omni-modal-native-entry", GINT_TO_POINTER(1));
    g_signal_connect(entry, "changed", G_CALLBACK(on_entry_changed), NULL);
    wire_actions(entry, app);
    gtk_box_append(GTK_BOX(surface), entry);
    sheet_entry = entry;
    g_object_set_data(G_OBJECT(alert), "omni-modal-entry", entry);
    g_object_set_data(G_OBJECT(alert), "omni-modal-entry-action-id", GINT_TO_POINTER(action_id));
  } else {
    gtk_box_append(GTK_BOX(surface), modal->widget);
    modal->widget = NULL;
  }
  adw_alert_dialog_set_extra_child(alert, surface);
  g_object_set_data(G_OBJECT(dialog), "omni-sheet-content-widget", surface);

  char default_response[16] = "";
  char close_response[16] = "";
  if (summary) {
    for (guint i = 0; i < summary->button_labels->len; i++) {
      const char *label = (const char *)g_ptr_array_index(summary->button_labels, i);
      if (!label || !label[0] || modal_button_label_is_close(label)) continue;
      char response_id[16];
      snprintf(response_id, sizeof(response_id), "r%u", i);
      adw_alert_dialog_add_response(alert, response_id, label);
      if (modal_button_label_is_search(label)) {
        snprintf(default_response, sizeof(default_response), "%s", response_id);
      }
      if (modal_button_label_is_cancel(label)) {
        snprintf(close_response, sizeof(close_response), "%s", response_id);
      }
      if (!default_response[0]) {
        snprintf(default_response, sizeof(default_response), "%s", response_id);
      }
      if (!close_response[0]) {
        snprintf(close_response, sizeof(close_response), "%s", response_id);
      }
    }
    if (default_response[0]) {
      adw_alert_dialog_set_default_response(alert, default_response);
    }
    if (close_response[0]) {
      adw_alert_dialog_set_close_response(alert, close_response);
    }
    g_object_set_data_full(G_OBJECT(alert), "omni-modal-summary", summary, (GDestroyNotify)free_modal_summary);
    summary = NULL;
  }
  g_signal_connect(alert, "response", G_CALLBACK(on_alert_response), app);

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
      gtk_widget_grab_focus(sheet_entry);
    }
    omni_macos_accessibility_schedule(app);
  }
  free_modal_summary(summary);
}

void omni_adw_app_present_modal(OmniAdwApp *app, OmniAdwNode *modal, const char *title) {
  if (!app || !modal) return;
  if (app->modal_dialog) {
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
  if (app->window) {
    adw_dialog_present(base_dialog, app->window);
    omni_macos_accessibility_schedule(app);
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

  const char *value = text ? text : "";
  switch (kind) {
    case 0:
      if (!GTK_IS_LABEL(widget)) return 0;
      gtk_label_set_text(GTK_LABEL(widget), value);
      omni_accessible_label(widget, value);
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
      if (!GTK_IS_CHECK_BUTTON(widget)) return 0;
      gtk_check_button_set_label(GTK_CHECK_BUTTON(widget), value);
      gtk_check_button_set_active(GTK_CHECK_BUTTON(widget), active != 0);
      omni_accessible_label(widget, value);
      gtk_accessible_update_state(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_STATE_CHECKED, active ? GTK_ACCESSIBLE_TRISTATE_TRUE : GTK_ACCESSIBLE_TRISTATE_FALSE, -1);
      break;
    case 3:
      if (!GTK_IS_ENTRY(widget)) return 0;
      if (strcmp(gtk_editable_get_text(GTK_EDITABLE(widget)), value) != 0) {
        gtk_editable_set_text(GTK_EDITABLE(widget), value);
      }
      omni_accessible_value_text(widget, value);
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
            omni_accessible_value_text(widget, item);
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
  omni_macos_accessibility_schedule(app);
  return 1;
}

int32_t omni_adw_app_replace_node(OmniAdwApp *app, const char *semantic_id, OmniAdwNode *replacement, int32_t focused_action_id) {
  if (!app || !app->content || !semantic_id || !replacement || !replacement->widget) return 0;
  char *name = omni_sanitized_widget_name(semantic_id);
  GtkWidget *target = find_widget_for_name(app->content, name);
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

  app->active_split_view = NULL;
  wire_actions(app->content, app);
  sync_sidebar_toggle(app);

  GtkWidget *focused = find_widget_for_action(app->content, focused_action_id);
  if (focused && gtk_widget_get_focusable(focused)) {
    gtk_widget_grab_focus(focused);
  }
  omni_macos_accessibility_schedule(app);
  return 1;
}

OmniAdwNode *omni_adw_box_new(int32_t vertical, int32_t spacing) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_box_new(vertical ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL, spacing);
  gtk_widget_add_css_class(node->widget, "omni-stack");
  omni_widget_expand(node->widget, vertical != 0);
  omni_accessible_role_description(node->widget, vertical ? "vertical group" : "horizontal group");
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

OmniAdwNode *omni_adw_string_list_new(const char **labels, const int32_t *action_ids, int32_t count) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  GtkStringList *strings = gtk_string_list_new(NULL);
  OmniStringListData *data = calloc(1, sizeof(OmniStringListData));
  if (data && count > 0) {
    data->count = count;
    data->action_ids = calloc((size_t)count, sizeof(int32_t));
  }
  for (int32_t i = 0; i < count; i++) {
    const char *label = labels && labels[i] ? labels[i] : "";
    gtk_string_list_append(strings, label);
    if (data && data->action_ids) data->action_ids[i] = action_ids ? action_ids[i] : 0;
  }

  GtkSelectionModel *selection = GTK_SELECTION_MODEL(gtk_single_selection_new(G_LIST_MODEL(strings)));
  GtkListItemFactory *factory = gtk_signal_list_item_factory_new();
  g_signal_connect(factory, "setup", G_CALLBACK(on_string_list_setup), NULL);
  g_signal_connect(factory, "bind", G_CALLBACK(on_string_list_bind), NULL);

  node->widget = gtk_list_view_new(selection, factory);
  gtk_list_view_set_single_click_activate(GTK_LIST_VIEW(node->widget), TRUE);
  gtk_widget_add_css_class(node->widget, "boxed-list");
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  omni_accessible_label(node->widget, "Content list");
  omni_accessible_description(node->widget, "Virtualized list");
  omni_accessible_role_description(node->widget, "list");
  g_object_set_data_full(G_OBJECT(node->widget), "omni-string-list-data", data, free_string_list_data);
  g_signal_connect(node->widget, "activate", G_CALLBACK(on_string_list_activate), NULL);
  return node;
}

OmniAdwNode *omni_adw_plain_list_new(const char **labels, const int32_t *action_ids, int32_t count) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  node->widget = gtk_list_box_new();
  gtk_list_box_set_selection_mode(GTK_LIST_BOX(node->widget), GTK_SELECTION_NONE);
  gtk_list_box_set_activate_on_single_click(GTK_LIST_BOX(node->widget), TRUE);
  gtk_widget_add_css_class(node->widget, "omni-plain-list");
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
  omni_accessible_label(node->widget, "Content list");
  omni_accessible_role_description(node->widget, "list");
  g_signal_connect(node->widget, "row-activated", G_CALLBACK(on_plain_list_row_activated), NULL);
  install_row_click_controller(node->widget);

  for (int32_t i = 0; i < count; i++) {
    const char *text = labels && labels[i] ? labels[i] : "";
    int32_t action_id = action_ids ? action_ids[i] : 0;
    GtkWidget *row = gtk_list_box_row_new();
    GtkWidget *label = gtk_label_new(text);
    gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
    gtk_label_set_wrap(GTK_LABEL(label), FALSE);
    gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_NONE);
    gtk_widget_add_css_class(label, "omni-monospace-text");
    gtk_widget_set_hexpand(label, TRUE);
    gtk_widget_set_halign(label, GTK_ALIGN_FILL);
    if (action_id > 0) {
      GtkWidget *button = gtk_button_new();
      gtk_widget_add_css_class(button, "omni-list-row-button");
      gtk_widget_set_hexpand(button, TRUE);
      gtk_widget_set_halign(button, GTK_ALIGN_FILL);
      gtk_widget_set_focus_on_click(button, TRUE);
      gtk_button_set_child(GTK_BUTTON(button), label);
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

OmniAdwNode *omni_adw_sidebar_list_new(const char **labels, const int32_t *action_ids, const int32_t *depths, int32_t count) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  OmniStringListData *data = calloc(1, sizeof(OmniStringListData));
  if (data && count > 0) {
    data->count = count;
    data->labels = calloc((size_t)count, sizeof(char *));
    data->action_ids = calloc((size_t)count, sizeof(int32_t));
    data->depths = calloc((size_t)count, sizeof(int32_t));
    data->collapsed = calloc((size_t)count, sizeof(gboolean));
    for (int32_t i = 0; i < count; i++) {
      data->labels[i] = omni_strdup(labels && labels[i] ? labels[i] : "");
      if (data->action_ids) data->action_ids[i] = action_ids ? action_ids[i] : 0;
      if (data->depths) data->depths[i] = depths ? depths[i] : 0;
    }
  }
  if (count >= 128) {
    GtkStringList *strings = gtk_string_list_new(NULL);
    if (data) data->string_list = strings;
    sidebar_rebuild_visible_indices(data);

    GtkSelectionModel *selection = GTK_SELECTION_MODEL(gtk_single_selection_new(G_LIST_MODEL(strings)));
    GtkListItemFactory *factory = gtk_signal_list_item_factory_new();
    g_signal_connect(factory, "setup", G_CALLBACK(on_sidebar_list_setup), NULL);
    g_signal_connect(factory, "bind", G_CALLBACK(on_sidebar_list_bind), data);

    node->widget = gtk_list_view_new(selection, factory);
    gtk_list_view_set_single_click_activate(GTK_LIST_VIEW(node->widget), TRUE);
    gtk_widget_add_css_class(node->widget, "omni-sidebar-list");
    gtk_widget_set_hexpand(node->widget, TRUE);
    gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
    omni_accessible_label(node->widget, "Sidebar");
    omni_accessible_description(node->widget, "Virtualized sidebar outline");
    omni_accessible_role_description(node->widget, "sidebar list");
    g_object_set_data_full(G_OBJECT(node->widget), "omni-string-list-data", data, free_string_list_data);
    g_signal_connect(node->widget, "activate", G_CALLBACK(on_string_list_activate), NULL);
    return node;
  }

  node->widget = gtk_list_box_new();
  gtk_list_box_set_selection_mode(GTK_LIST_BOX(node->widget), GTK_SELECTION_SINGLE);
  gtk_list_box_set_activate_on_single_click(GTK_LIST_BOX(node->widget), TRUE);
  gtk_widget_add_css_class(node->widget, "omni-sidebar-list");
  gtk_widget_set_hexpand(node->widget, TRUE);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_FILL);
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
    GtkWidget *label = gtk_label_new(text);
    gtk_widget_add_css_class(label, "omni-sidebar-label");
    gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
    gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_END);
    gtk_widget_set_hexpand(label, TRUE);
    gtk_widget_set_halign(label, GTK_ALIGN_FILL);
    gtk_button_set_child(GTK_BUTTON(button), label);
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
    omni_accessible_label(label, text);
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
  adw_overlay_split_view_set_min_sidebar_width(ADW_OVERLAY_SPLIT_VIEW(node->widget), 220);
  adw_overlay_split_view_set_max_sidebar_width(ADW_OVERLAY_SPLIT_VIEW(node->widget), 320);
  adw_overlay_split_view_set_sidebar_width_fraction(ADW_OVERLAY_SPLIT_VIEW(node->widget), 0.28);
  omni_accessible_label(node->widget, "Navigation split view");
  omni_accessible_description(node->widget, "Sidebar and content");
  omni_accessible_role_description(node->widget, "navigation split view");
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
    gtk_text_view_set_monospace(GTK_TEXT_VIEW(node->widget), TRUE);
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(node->widget));
    gtk_text_buffer_set_text(buffer, value, -1);
    gtk_widget_add_css_class(node->widget, "omni-static-text");
    omni_accessible_read_only(node->widget, TRUE);
    omni_accessible_multi_line(node->widget, TRUE);
  } else {
    node->widget = gtk_label_new(value);
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

OmniAdwNode *omni_adw_button_new(const char *label, int32_t action_id) {
  OmniAdwNode *node = calloc(1, sizeof(OmniAdwNode));
  const char *value = label ? label : "Button";
  node->widget = gtk_button_new_with_label(value);
  omni_button_set_label_or_symbolic_icon(GTK_BUTTON(node->widget), value);
  gtk_widget_set_halign(node->widget, GTK_ALIGN_START);
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
  omni_accessible_multi_line(node->widget, TRUE);
  omni_accessible_value_text(node->widget, text);
  g_object_set_data(G_OBJECT(node->widget), "omni-action-id", GINT_TO_POINTER(action_id));
  g_signal_connect(buffer, "changed", G_CALLBACK(on_text_buffer_changed), node->widget);
  return node;
}

OmniAdwNode *omni_adw_dropdown_new(const char *title, const char *value, const char **labels, const int32_t *action_ids, int32_t count, int32_t expanded) {
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
    omni_accessible_description(item, "Menu option");
    omni_accessible_list_position(item, i + 1, count);
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
    g_object_set_data(G_OBJECT(node->widget), "omni-menu-expanded", GINT_TO_POINTER(1));
  }
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
  gtk_accessible_update_property(
    GTK_ACCESSIBLE(node->widget),
    GTK_ACCESSIBLE_PROPERTY_VALUE_MIN, lower,
    GTK_ACCESSIBLE_PROPERTY_VALUE_MAX, upper,
    GTK_ACCESSIBLE_PROPERTY_VALUE_NOW, value,
    -1
  );
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
  omni_accessible_set_disabled(node->widget, sensitive == 0);
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
    int action_id = first_widget_action_id(child->widget);
    if (action_id > 0) {
      g_object_set_data(G_OBJECT(row), "omni-action-id", GINT_TO_POINTER(action_id));
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
  } else if (GTK_IS_PANED(parent->widget)) {
    if (!gtk_paned_get_start_child(GTK_PANED(parent->widget))) {
      gtk_paned_set_start_child(GTK_PANED(parent->widget), child->widget);
    } else if (!gtk_paned_get_end_child(GTK_PANED(parent->widget))) {
      gtk_paned_set_end_child(GTK_PANED(parent->widget), child->widget);
    }
  } else if (ADW_IS_OVERLAY_SPLIT_VIEW(parent->widget)) {
    const gboolean sidebar = parent->split_child_count == 0;
    GtkWidget *child_widget = child->widget;
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
  }
  child->widget = NULL;
  omni_adw_node_free(child);
}

void omni_adw_node_free(OmniAdwNode *node) {
  if (!node) return;
  free(node);
}
