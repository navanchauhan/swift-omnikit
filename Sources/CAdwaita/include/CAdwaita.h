#pragma once

#include <stdint.h>

typedef void (*omni_adw_action_callback)(int32_t action_id, void *context);
typedef void (*omni_adw_text_callback)(int32_t action_id, const char *text, void *context);
typedef void (*omni_adw_key_callback)(int32_t action_id, int32_t key_kind, uint32_t codepoint, void *context);
typedef void (*omni_adw_focus_callback)(int32_t action_id, void *context);
typedef void (*omni_adw_tick_callback)(void *context);
typedef void (*omni_adw_web_message_callback)(void *context, const char *name, const char *json_body);
typedef void (*omni_adw_web_navigation_callback)(void *context, int32_t event, const char *url, const char *error);
typedef int32_t (*omni_adw_web_policy_callback)(void *context, const char *url, int32_t navigation_type, int32_t is_new_window);
typedef void (*omni_adw_web_evaluate_callback)(void *context, const char *json_body, const char *error);
typedef void (*omni_adw_web_title_callback)(void *context, const char *title);
typedef void (*omni_adw_web_progress_callback)(void *context, double progress);
typedef void (*omni_adw_web_cookie_callback)(
    void *context,
    const char **cookie_names,
    const char **cookie_values,
    const char **cookie_domains,
    const char **cookie_paths,
    const double *cookie_expires_at,
    const int32_t *cookie_secure,
    const int32_t *cookie_http_only,
    int32_t cookie_count);
typedef char *(*omni_adw_web_script_dialog_callback)(
    void *context,
    int32_t dialog_type,
    const char *message,
    const char *default_text,
    int32_t *handled,
    int32_t *confirmed);

typedef struct OmniAdwApp OmniAdwApp;
typedef struct OmniAdwNode OmniAdwNode;

OmniAdwApp *omni_adw_app_new(const char *app_id, const char *title, omni_adw_action_callback callback, omni_adw_text_callback text_callback, omni_adw_key_callback key_callback, omni_adw_focus_callback focus_callback, void *context);
int32_t omni_adw_app_run(OmniAdwApp *app, int32_t argc, char **argv);
void omni_adw_app_free(OmniAdwApp *app);
uint32_t omni_adw_app_add_tick_callback(OmniAdwApp *app, int32_t interval_ms, omni_adw_tick_callback callback, void *context);
void omni_adw_app_remove_tick_callback(uint32_t source_id);
void omni_adw_app_set_default_size(OmniAdwApp *app, int32_t width, int32_t height);
void omni_adw_set_color_scheme(const char *scheme);
void omni_adw_app_set_header_title(OmniAdwApp *app, const char *title);
void omni_adw_app_set_header_entry(OmniAdwApp *app, const char *placeholder, const char *text, int32_t action_id);
void omni_adw_app_set_header_actions(OmniAdwApp *app, const char **labels, const int32_t *action_ids, const int32_t *placements, const int32_t *styles, int32_t count);
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
void omni_adw_box_set_homogeneous(OmniAdwNode *node, int32_t homogeneous);
OmniAdwNode *omni_adw_overlay_new(void);
OmniAdwNode *omni_adw_list_new(void);
OmniAdwNode *omni_adw_string_list_new(const char **labels, const int32_t *action_ids, int32_t count);
OmniAdwNode *omni_adw_plain_list_new(const char **labels, const int32_t *action_ids, int32_t count);
OmniAdwNode *omni_adw_sidebar_list_new(const char **labels, const int32_t *action_ids, const int32_t *depths, int32_t count);
OmniAdwNode *omni_adw_form_new(void);
OmniAdwNode *omni_adw_split_new(void);
OmniAdwNode *omni_adw_text_new(const char *text);
OmniAdwNode *omni_adw_image_new(const uint8_t *data, int32_t length, const char *alternative_text);
OmniAdwNode *omni_adw_web_view_new(const char *url, const char *fallback_text, void *native_view);
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
    omni_adw_web_title_callback title_callback,
    omni_adw_web_progress_callback progress_callback,
    omni_adw_web_cookie_callback cookie_callback,
    omni_adw_web_script_dialog_callback script_dialog_callback,
    void *callback_context);
int32_t omni_adw_web_view_load_uri(const char *identity, const char *url);
int32_t omni_adw_web_view_load_request(const char *identity, const char *url, const char **header_names, const char **header_values, int32_t header_count);
int32_t omni_adw_web_view_load_html(const char *identity, const char *html, const char *base_url);
int32_t omni_adw_web_view_evaluate_javascript(const char *identity, const char *script, omni_adw_web_evaluate_callback callback, void *callback_context);
int32_t omni_adw_web_view_go_back(const char *identity);
int32_t omni_adw_web_view_go_forward(const char *identity);
int32_t omni_adw_web_view_reload(const char *identity);
int32_t omni_adw_web_view_stop_loading(const char *identity);
int32_t omni_adw_web_view_can_go_back(const char *identity);
int32_t omni_adw_web_view_can_go_forward(const char *identity);
int32_t omni_adw_web_view_set_zoom(const char *identity, double page_zoom);
int32_t omni_adw_web_view_set_allows_back_forward_navigation_gestures(const char *identity, int32_t enabled);
int32_t omni_adw_web_view_set_javascript_can_open_windows(const char *identity, int32_t enabled);
int32_t omni_adw_web_view_set_javascript_enabled(const char *identity, int32_t enabled);
int32_t omni_adw_web_view_set_minimum_font_size(const char *identity, double size);
int32_t omni_adw_web_view_set_inspectable(const char *identity, int32_t enabled);
int32_t omni_adw_web_view_set_user_agent(const char *identity, const char *application_name, const char *custom_user_agent);
int32_t omni_adw_web_view_add_user_script(const char *identity, const char *source, int32_t injection_time, int32_t main_frame_only);
int32_t omni_adw_web_view_remove_all_user_scripts(const char *identity);
int32_t omni_adw_web_view_register_message_handler(const char *identity, const char *name);
int32_t omni_adw_web_view_unregister_message_handler(const char *identity, const char *name);
int32_t omni_adw_web_view_add_content_rule(const char *identity, const char *identifier, const char *source);
int32_t omni_adw_web_view_remove_all_content_rules(const char *identity);
int32_t omni_adw_web_view_focus(const char *identity);
int32_t omni_adw_web_view_scroll_by(const char *identity, double dx, double dy);
int32_t omni_adw_web_view_scroll_page(const char *identity, int32_t direction);
int32_t omni_adw_web_cookie_store_set(
    const char *name,
    const char *value,
    const char *domain,
    const char *path,
    double expires_at,
    int32_t secure,
    int32_t http_only);
int32_t omni_adw_web_cookie_store_delete(
    const char *name,
    const char *value,
    const char *domain,
    const char *path,
    double expires_at,
    int32_t secure,
    int32_t http_only);
OmniAdwNode *omni_adw_button_new(const char *label, int32_t action_id);
OmniAdwNode *omni_adw_click_container_new(const char *label, int32_t action_id);
OmniAdwNode *omni_adw_inline_button_new(const char *label, int32_t action_id, const char *css_classes);
OmniAdwNode *omni_adw_toggle_new(const char *label, int32_t active, int32_t action_id);
OmniAdwNode *omni_adw_entry_new(const char *placeholder, const char *text, int32_t action_id);
OmniAdwNode *omni_adw_secure_entry_new(const char *placeholder, const char *text, int32_t action_id);
OmniAdwNode *omni_adw_text_view_new(const char *text, int32_t action_id);
OmniAdwNode *omni_adw_dropdown_new(const char *title, const char *value, const char **labels, const int32_t *action_ids, int32_t count, int32_t expanded);
OmniAdwNode *omni_adw_segmented_new(const char *title, const char **labels, const int32_t *action_ids, int32_t selected_index, int32_t count);
OmniAdwNode *omni_adw_progress_new(const char *label, double fraction);
OmniAdwNode *omni_adw_scale_new(const char *label, double value, double lower, double upper, double step, int32_t decrement_action_id, int32_t increment_action_id);
OmniAdwNode *omni_adw_spin_new(const char *label, double value, int32_t decrement_action_id, int32_t increment_action_id);
OmniAdwNode *omni_adw_date_new(const char *label, const char *value, double timestamp, int32_t set_action_id, int32_t decrement_action_id, int32_t increment_action_id);
OmniAdwNode *omni_adw_scroll_new(int32_t vertical, double offset);
OmniAdwNode *omni_adw_separator_new(void);
OmniAdwNode *omni_adw_drawing_new(const char *label, const char *fill_color);
OmniAdwNode *omni_adw_frame_new(const char *css_classes, int32_t spacing);
void omni_adw_node_apply_layout(OmniAdwNode *node, int32_t width, int32_t height, int32_t min_width, int32_t min_height, int32_t margin_top, int32_t margin_start, int32_t margin_bottom, int32_t margin_end, double opacity);
void omni_adw_node_set_visible(OmniAdwNode *node, int32_t visible);
void omni_adw_node_set_sensitive(OmniAdwNode *node, int32_t sensitive);
void omni_adw_node_set_metadata(OmniAdwNode *node, const char *semantic_id, const char *label);
void omni_adw_node_add_css_class(OmniAdwNode *node, const char *css_class);
void omni_adw_node_append(OmniAdwNode *parent, OmniAdwNode *child);
void omni_adw_node_set_expand(OmniAdwNode *node, int32_t horizontal, int32_t vertical);
void omni_adw_node_free(OmniAdwNode *node);
