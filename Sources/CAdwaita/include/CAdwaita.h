#pragma once

#include <stdint.h>

typedef void (*omni_adw_action_callback)(int32_t action_id, void *context);
typedef void (*omni_adw_text_callback)(int32_t action_id, const char *text, void *context);
typedef void (*omni_adw_key_callback)(int32_t action_id, int32_t key_kind, uint32_t codepoint, void *context);
typedef void (*omni_adw_focus_callback)(int32_t action_id, void *context);

typedef struct OmniAdwApp OmniAdwApp;
typedef struct OmniAdwNode OmniAdwNode;

OmniAdwApp *omni_adw_app_new(const char *app_id, const char *title, omni_adw_action_callback callback, omni_adw_text_callback text_callback, omni_adw_key_callback key_callback, omni_adw_focus_callback focus_callback, void *context);
int32_t omni_adw_app_run(OmniAdwApp *app, int32_t argc, char **argv);
void omni_adw_app_free(OmniAdwApp *app);
void omni_adw_app_set_default_size(OmniAdwApp *app, int32_t width, int32_t height);
void omni_adw_app_set_header_entry(OmniAdwApp *app, const char *placeholder, const char *text, int32_t action_id);
void omni_adw_app_set_settings(OmniAdwApp *app, OmniAdwNode *settings);
void omni_adw_app_set_commands(OmniAdwApp *app, OmniAdwNode *commands);
void omni_adw_app_set_root(OmniAdwApp *app, OmniAdwNode *root);
void omni_adw_app_set_root_focused(OmniAdwApp *app, OmniAdwNode *root, int32_t focused_action_id);
void omni_adw_app_present_modal(OmniAdwApp *app, OmniAdwNode *modal, const char *title);
void omni_adw_app_dismiss_modal(OmniAdwApp *app);
void omni_adw_app_share_url(OmniAdwApp *app, const char *url);
int32_t omni_adw_app_update_node(OmniAdwApp *app, const char *semantic_id, int32_t kind, const char *text, int32_t active);
int32_t omni_adw_app_replace_node(OmniAdwApp *app, const char *semantic_id, OmniAdwNode *replacement, int32_t focused_action_id);

OmniAdwNode *omni_adw_box_new(int32_t vertical, int32_t spacing);
OmniAdwNode *omni_adw_list_new(void);
OmniAdwNode *omni_adw_string_list_new(const char **labels, const int32_t *action_ids, int32_t count);
OmniAdwNode *omni_adw_plain_list_new(const char **labels, const int32_t *action_ids, int32_t count);
OmniAdwNode *omni_adw_sidebar_list_new(const char **labels, const int32_t *action_ids, const int32_t *depths, int32_t count);
OmniAdwNode *omni_adw_form_new(void);
OmniAdwNode *omni_adw_split_new(void);
OmniAdwNode *omni_adw_text_new(const char *text);
OmniAdwNode *omni_adw_button_new(const char *label, int32_t action_id);
OmniAdwNode *omni_adw_toggle_new(const char *label, int32_t active, int32_t action_id);
OmniAdwNode *omni_adw_entry_new(const char *placeholder, const char *text, int32_t action_id);
OmniAdwNode *omni_adw_secure_entry_new(const char *placeholder, const char *text, int32_t action_id);
OmniAdwNode *omni_adw_text_view_new(const char *text, int32_t action_id);
OmniAdwNode *omni_adw_dropdown_new(const char *title, const char *value, const char **labels, const int32_t *action_ids, int32_t count, int32_t expanded);
OmniAdwNode *omni_adw_progress_new(const char *label, double fraction);
OmniAdwNode *omni_adw_scale_new(const char *label, double value, double lower, double upper, double step, int32_t decrement_action_id, int32_t increment_action_id);
OmniAdwNode *omni_adw_spin_new(const char *label, double value, int32_t decrement_action_id, int32_t increment_action_id);
OmniAdwNode *omni_adw_date_new(const char *label, const char *value, double timestamp, int32_t set_action_id, int32_t decrement_action_id, int32_t increment_action_id);
OmniAdwNode *omni_adw_scroll_new(int32_t vertical, double offset);
OmniAdwNode *omni_adw_separator_new(void);
OmniAdwNode *omni_adw_drawing_new(const char *label);
OmniAdwNode *omni_adw_frame_new(const char *css_classes, int32_t spacing);
void omni_adw_node_apply_layout(OmniAdwNode *node, int32_t width, int32_t height, int32_t min_width, int32_t min_height, int32_t margin_top, int32_t margin_start, int32_t margin_bottom, int32_t margin_end, double opacity);
void omni_adw_node_set_sensitive(OmniAdwNode *node, int32_t sensitive);
void omni_adw_node_set_metadata(OmniAdwNode *node, const char *semantic_id, const char *label);
void omni_adw_node_append(OmniAdwNode *parent, OmniAdwNode *child);
void omni_adw_node_free(OmniAdwNode *node);
