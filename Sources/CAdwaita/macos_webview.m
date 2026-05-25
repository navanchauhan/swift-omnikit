#if defined(__APPLE__)

#include "CAdwaita.h"

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <objc/message.h>

#include <adwaita.h>
#include <gdk/macos/gdkmacos.h>
#include <gtk/gtk.h>
#include <dispatch/dispatch.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

extern gboolean omni_adw_app_handle_macos_text_input(void *app, const char *text);

typedef struct {
  GtkWidget *widget;
  void *container_view;
  void *native_view;
  void *web_view;
  void *navigation_delegate;
  void *ui_delegate;
  void *url;
  void *html;
  void *base_url;
  void *identity;
  void *application_name;
  void *custom_user_agent;
  void *request_header_names;
  void *request_header_values;
  void *user_scripts;
  void *content_rules;
  void *message_handler_names;
  void *message_handlers;
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
  int32_t request_header_count;
  double page_zoom;
  int32_t allows_back_forward_navigation_gestures;
  int32_t javascript_can_open_windows;
  int32_t javascript_enabled;
  double minimum_font_size;
  int32_t is_inspectable;
  int32_t allows_inline_media_playback;
  int32_t media_playback_requires_user_gesture;
  gboolean uses_external_web_view;
  gboolean owns_native_view;
  gboolean owns_web_view;
  gboolean holds_widget_ref;
} OmniMacosWebView;

@interface OmniMacosWebViewContainer : NSView
@property(nonatomic, weak) NSView *embeddedView;
@property(nonatomic, weak) WKWebView *webView;
@property(nonatomic, assign) OmniMacosWebView *webViewData;
@end

@interface OmniMacosWebViewNavigationDelegate : NSObject <WKNavigationDelegate>
@property(nonatomic, assign) OmniMacosWebView *webViewData;
@end

@interface OmniMacosWebViewUIDelegate : NSObject <WKUIDelegate>
@property(nonatomic, assign) OmniMacosWebView *webViewData;
@end

@interface OmniMacosScriptMessageHandler : NSObject <WKScriptMessageHandler>
@property(nonatomic, assign) OmniMacosWebView *webViewData;
@property(nonatomic, copy) NSString *name;
@end

static OmniMacosWebView *omni_active_web_view = NULL;
static BOOL omni_web_views_occluded_by_modal = NO;
static NSMutableSet<NSValue *> *omni_registered_web_views(void) {
  static NSMutableSet<NSValue *> *registry = nil;
  if (!registry) registry = [NSMutableSet set];
  return registry;
}

static NSMutableDictionary<NSString *, NSValue *> *omni_registered_web_views_by_identity(void) {
  static NSMutableDictionary<NSString *, NSValue *> *registry = nil;
  if (!registry) registry = [NSMutableDictionary dictionary];
  return registry;
}

static NSMutableSet<NSValue *> *omni_registered_text_input_apps(void) {
  static NSMutableSet<NSValue *> *registry = nil;
  if (!registry) registry = [NSMutableSet set];
  return registry;
}

static void omni_macos_text_input_install_monitor_once(void) {
  static id monitor = nil;
  if (monitor) return;
  monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
    NSEventModifierFlags flags = event.modifierFlags;
    if ((flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) != 0) {
      return event;
    }
    NSString *characters = event.characters;
    if (!characters || characters.length == 0) return event;
    const char *utf8 = characters.UTF8String;
    if (!utf8 || !utf8[0]) return event;

    for (NSValue *value in [omni_registered_text_input_apps() copy]) {
      if (omni_adw_app_handle_macos_text_input(value.pointerValue, utf8)) {
        return nil;
      }
    }
    return event;
  }];
}

void omni_macos_text_input_install(void *app) {
  if (!app) return;
  [omni_registered_text_input_apps() addObject:[NSValue valueWithPointer:app]];
  omni_macos_text_input_install_monitor_once();
}

static void omni_macos_web_view_activate(OmniMacosWebView *data);
static void omni_macos_web_view_scroll_by(OmniMacosWebView *data, CGFloat dx, CGFloat dy);
static CGFloat omni_macos_web_view_page_delta(OmniMacosWebView *data);
static void omni_macos_web_view_sync(OmniMacosWebView *data);
static void omni_macos_web_view_run_stored_user_scripts(OmniMacosWebView *data, WKWebView *web_view);
static void omni_macos_web_view_dispatch_mouse_event(OmniMacosWebView *data, NSString *type, double x, double y, int32_t click_count);
static void omni_macos_web_view_install_mouse_monitor_once(void);
static OmniMacosWebView *omni_macos_web_view_under_pointer(void);
static OmniMacosWebView *omni_macos_single_visible_web_view(void);

static int32_t omni_macos_web_view_navigation_type(WKNavigationType type) {
  switch (type) {
    case WKNavigationTypeLinkActivated: return 0;
    case WKNavigationTypeFormSubmitted: return 1;
    case WKNavigationTypeBackForward: return 2;
    case WKNavigationTypeReload: return 3;
    case WKNavigationTypeFormResubmitted: return 4;
    case WKNavigationTypeOther:
    default:
      return -1;
  }
}

static BOOL omni_macos_web_view_point_for_event(OmniMacosWebView *data, NSEvent *event, NSPoint *out_point) {
  if (!data || !data->web_view || !event || !out_point) return NO;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  if (!web_view.window || web_view.isHidden || web_view.alphaValue <= 0.01) return NO;

  NSPoint window_point;
  if (event.window == web_view.window) {
    window_point = event.locationInWindow;
  } else {
    NSPoint screen_point;
    if (event.window) {
      screen_point = [event.window convertPointToScreen:event.locationInWindow];
    } else {
      screen_point = [NSEvent mouseLocation];
    }
    window_point = [web_view.window convertPointFromScreen:screen_point];
  }

  NSPoint local = [web_view convertPoint:window_point fromView:nil];
  if (!NSPointInRect(local, web_view.bounds)) return NO;
  if (!web_view.isFlipped) {
    local.y = web_view.bounds.size.height - local.y;
  }
  *out_point = local;
  return YES;
}

static OmniMacosWebView *omni_macos_web_view_for_event(NSEvent *event, NSPoint *out_point) {
  NSMutableSet<NSValue *> *registry = omni_registered_web_views();
  for (NSValue *value in [registry copy]) {
    OmniMacosWebView *data = (OmniMacosWebView *)value.pointerValue;
    NSPoint local = NSZeroPoint;
    if (omni_macos_web_view_point_for_event(data, event, &local)) {
      if (out_point) *out_point = local;
      return data;
    }
  }
  return NULL;
}

static void omni_macos_web_view_install_mouse_monitor_once(void) {
  static id monitor = nil;
  if (monitor) return;
  NSEventMask mask =
      NSEventMaskLeftMouseDown |
      NSEventMaskLeftMouseUp |
      NSEventMaskMouseMoved |
      NSEventMaskLeftMouseDragged;
  monitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask handler:^NSEvent *(NSEvent *event) {
    if (omni_web_views_occluded_by_modal) return event;
    NSPoint point = NSZeroPoint;
    OmniMacosWebView *data = omni_macos_web_view_for_event(event, &point);
    if (!data) return event;
    omni_macos_web_view_activate(data);
    switch (event.type) {
      case NSEventTypeLeftMouseDown:
        omni_macos_web_view_dispatch_mouse_event(data, @"mousedown", point.x, point.y, (int32_t)event.clickCount);
        break;
      case NSEventTypeLeftMouseUp:
        omni_macos_web_view_dispatch_mouse_event(data, @"mouseup", point.x, point.y, (int32_t)event.clickCount);
        break;
      case NSEventTypeMouseMoved:
      case NSEventTypeLeftMouseDragged:
        omni_macos_web_view_dispatch_mouse_event(data, @"mousemove", point.x, point.y, 0);
        break;
      default:
        break;
    }
    return event;
  }];
}

@implementation OmniMacosWebViewContainer
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event {
  (void)event;
  return YES;
}
- (void)mouseDown:(NSEvent *)event {
  omni_macos_web_view_activate(self.webViewData);
  if (self.embeddedView) {
    [self.window makeFirstResponder:self.embeddedView];
    [self.embeddedView mouseDown:event];
  } else {
    [super mouseDown:event];
  }
}
- (NSView *)hitTest:(NSPoint)point {
  if (self.hidden || self.alphaValue <= 0.01 || !NSPointInRect(point, self.bounds)) {
    return nil;
  }
  if (!self.embeddedView) return self;
  NSPoint child_point = [self.embeddedView convertPoint:point fromView:self];
  return [self.embeddedView hitTest:child_point] ?: self.embeddedView;
}
- (void)scrollWheel:(NSEvent *)event {
  omni_macos_web_view_activate(self.webViewData);
  if (self.embeddedView) {
    [self.window makeFirstResponder:self.embeddedView];
    [self.embeddedView scrollWheel:event];
  } else if (self.webViewData && self.webView) {
    CGFloat dx = event.scrollingDeltaX;
    CGFloat dy = event.scrollingDeltaY;
    if (!event.hasPreciseScrollingDeltas) {
      dx *= 14.0;
      dy *= 14.0;
    }
    omni_macos_web_view_scroll_by(self.webViewData, -dx, -dy);
  } else {
    [super scrollWheel:event];
  }
}
- (void)keyDown:(NSEvent *)event {
  if (self.embeddedView) {
    [self.embeddedView keyDown:event];
  } else {
    [super keyDown:event];
  }
}
@end

@implementation OmniMacosWebViewNavigationDelegate
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
  OmniMacosWebView *data = self.webViewData;
  if (!data || !data->policy_callback || !navigationAction) {
    decisionHandler(WKNavigationActionPolicyAllow);
    return;
  }
  NSURL *url = navigationAction.request.URL ?: webView.URL;
  const char *url_string = url.absoluteString.UTF8String ?: "";
  int32_t navigation_type = omni_macos_web_view_navigation_type(navigationAction.navigationType);
  int32_t is_new_window = navigationAction.targetFrame == nil ? 1 : 0;
  int32_t policy = data->policy_callback(data->callback_context, url_string, navigation_type, is_new_window);
  if (policy == 2) {
    if (@available(macOS 11.3, *)) {
      decisionHandler(WKNavigationActionPolicyDownload);
    } else {
      decisionHandler(WKNavigationActionPolicyCancel);
    }
    return;
  }
  decisionHandler(policy ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
  (void)webView;
  OmniMacosWebView *data = self.webViewData;
  if (!data || !data->response_policy_callback || !navigationResponse) {
    decisionHandler(WKNavigationResponsePolicyAllow);
    return;
  }
  NSURLResponse *response = navigationResponse.response;
  NSURL *url = response.URL;
  const char *url_string = url.absoluteString.UTF8String ?: "";
  const char *mime_type = response.MIMEType.UTF8String ?: "";
  const char *suggested_filename = response.suggestedFilename.UTF8String ?: "";
  int64_t expected = response.expectedContentLength;
  int32_t policy = data->response_policy_callback(
      data->callback_context,
      url_string,
      mime_type,
      navigationResponse.canShowMIMEType ? 1 : 0,
      expected,
      suggested_filename);
  if (policy == 2) {
    if (@available(macOS 11.3, *)) {
      decisionHandler(WKNavigationResponsePolicyDownload);
    } else {
      decisionHandler(WKNavigationResponsePolicyCancel);
    }
    return;
  }
  decisionHandler(policy ? WKNavigationResponsePolicyAllow : WKNavigationResponsePolicyCancel);
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
  (void)navigation;
  OmniMacosWebView *data = self.webViewData;
  if (!data || !data->navigation_callback) return;
  data->navigation_callback(data->callback_context, 0, webView.URL.absoluteString.UTF8String, NULL);
}
- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
  (void)navigation;
  OmniMacosWebView *data = self.webViewData;
  if (!data || !data->navigation_callback) return;
  data->navigation_callback(data->callback_context, 4, webView.URL.absoluteString.UTF8String, NULL);
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
  (void)navigation;
  OmniMacosWebView *data = self.webViewData;
  if (!data) return;
  omni_macos_web_view_run_stored_user_scripts(data, webView);
  if (data->navigation_callback) {
    data->navigation_callback(data->callback_context, 1, webView.URL.absoluteString.UTF8String, NULL);
  }
  if (data->title_callback) {
    data->title_callback(data->callback_context, webView.title.UTF8String);
  }
  if (data->progress_callback) {
    data->progress_callback(data->callback_context, webView.estimatedProgress);
  }
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
  (void)navigation;
  OmniMacosWebView *data = self.webViewData;
  if (!data || !data->navigation_callback) return;
  data->navigation_callback(data->callback_context, 2, webView.URL.absoluteString.UTF8String, error.localizedDescription.UTF8String);
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
  [self webView:webView didFailNavigation:navigation withError:error];
}
@end

@implementation OmniMacosWebViewUIDelegate
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
  (void)configuration;
  (void)windowFeatures;
  OmniMacosWebView *data = self.webViewData;
  NSURL *url = navigationAction.request.URL;
  if (!url) return nil;

  int32_t policy = 1;
  if (data && data->policy_callback) {
    policy = data->policy_callback(
        data->callback_context,
        url.absoluteString.UTF8String ?: "",
        omni_macos_web_view_navigation_type(navigationAction.navigationType),
        1);
  } else if (data && !data->javascript_can_open_windows) {
    policy = 0;
  }

  if (policy == 1) {
    [webView loadRequest:navigationAction.request];
  }
  return nil;
}

- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
  (void)webView;
  (void)frame;
  OmniMacosWebView *data = self.webViewData;
  if (data && data->script_dialog_callback) {
    int32_t handled = 0;
    int32_t confirmed = 0;
    char *prompt = data->script_dialog_callback(
        data->callback_context,
        0,
        message.UTF8String ?: "",
        "",
        &handled,
        &confirmed);
    if (prompt) free(prompt);
    if (!handled) {
      completionHandler();
      return;
    }
  }
  completionHandler();
}

- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL result))completionHandler {
  (void)webView;
  (void)frame;
  OmniMacosWebView *data = self.webViewData;
  int32_t handled = 0;
  int32_t confirmed = 0;
  if (data && data->script_dialog_callback) {
    char *prompt = data->script_dialog_callback(
        data->callback_context,
        1,
        message.UTF8String ?: "",
        "",
        &handled,
        &confirmed);
    if (prompt) free(prompt);
  }
  completionHandler(handled && confirmed);
}

- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)defaultText initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSString * _Nullable result))completionHandler {
  (void)webView;
  (void)frame;
  OmniMacosWebView *data = self.webViewData;
  int32_t handled = 0;
  int32_t confirmed = 0;
  NSString *result = nil;
  if (data && data->script_dialog_callback) {
    char *response = data->script_dialog_callback(
        data->callback_context,
        2,
        prompt.UTF8String ?: "",
        defaultText.UTF8String ?: "",
        &handled,
        &confirmed);
    if (response) {
      result = [[NSString alloc] initWithUTF8String:response];
      free(response);
    }
  }
  completionHandler(handled ? result : nil);
}
@end

@implementation OmniMacosScriptMessageHandler
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
  (void)userContentController;
  OmniMacosWebView *data = self.webViewData;
  if (!data || !data->message_callback) return;
  id body = message.body ?: [NSNull null];
  NSString *json = @"null";
  if ([NSJSONSerialization isValidJSONObject:body]) {
    NSData *encoded = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    if (encoded) json = [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding] ?: @"null";
  } else if ([body isKindOfClass:[NSString class]]) {
    NSData *encoded = [NSJSONSerialization dataWithJSONObject:@[body] options:0 error:nil];
    NSString *wrapped = encoded ? [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding] : nil;
    if (wrapped.length >= 2) json = [wrapped substringWithRange:NSMakeRange(1, wrapped.length - 2)];
  } else if ([body isKindOfClass:[NSNumber class]]) {
    json = [body description];
  }
  const char *name = (message.name ?: self.name ?: @"").UTF8String;
  data->message_callback(data->callback_context, name, json.UTF8String);
}
@end

static NSString *omni_macos_json_string_for_value(id value, NSError *error) {
  if (error) return nil;
  id normalized = value ?: [NSNull null];
  if ([normalized isKindOfClass:[NSString class]]) {
    NSData *encoded = [NSJSONSerialization dataWithJSONObject:@[normalized] options:0 error:nil];
    NSString *wrapped = encoded ? [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding] : nil;
    if (wrapped.length >= 2) return [wrapped substringWithRange:NSMakeRange(1, wrapped.length - 2)];
  }
  if ([normalized isKindOfClass:[NSNumber class]]) return [normalized description];
  if ([NSJSONSerialization isValidJSONObject:normalized]) {
    NSData *encoded = [NSJSONSerialization dataWithJSONObject:normalized options:0 error:nil];
    if (encoded) return [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding] ?: @"null";
  }
  return @"null";
}

static OmniMacosWebView *omni_macos_web_view_lookup(const char *identity) {
  if (!identity || !identity[0]) return NULL;
  NSString *key = [[NSString alloc] initWithUTF8String:identity];
  if (!key) return NULL;
  return (OmniMacosWebView *)omni_registered_web_views_by_identity()[key].pointerValue;
}

static BOOL omni_macos_webkit_trace_enabled(void) {
  const char *trace = getenv("OMNI_MACOS_WEBKIT_TRACE");
  return trace && trace[0] && strcmp(trace, "0") != 0;
}

static NSAppearance *omni_macos_web_view_effective_appearance(void) {
  NSAppearance *appearance = NSApp.effectiveAppearance ?: NSAppearance.currentDrawingAppearance;
  if (!appearance) appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
  return appearance;
}

static NSArray<WKUserScript *> *omni_macos_web_view_make_user_scripts(
  const char **script_sources,
  const int32_t *script_injection_times,
  const int32_t *script_main_frame_only,
  int32_t script_count
) {
  if (!script_sources || script_count <= 0) return @[];
  NSMutableArray<WKUserScript *> *scripts = [NSMutableArray arrayWithCapacity:(NSUInteger)script_count];
  for (int32_t i = 0; i < script_count; i++) {
    if (!script_sources[i] || !script_sources[i][0]) continue;
    NSString *source = [[NSString alloc] initWithUTF8String:script_sources[i]];
    if (!source) continue;
    WKUserScriptInjectionTime time = (script_injection_times && script_injection_times[i] == 0)
      ? WKUserScriptInjectionTimeAtDocumentStart
      : WKUserScriptInjectionTimeAtDocumentEnd;
    BOOL main_frame_only = script_main_frame_only && script_main_frame_only[i] ? YES : NO;
    WKUserScript *script = [[WKUserScript alloc] initWithSource:source injectionTime:time forMainFrameOnly:main_frame_only];
    [scripts addObject:script];
  }
  return scripts;
}

static void omni_macos_web_view_install_user_scripts(WKWebViewConfiguration *configuration, NSArray<WKUserScript *> *scripts) {
  if (!configuration || !scripts) return;
  WKUserContentController *controller = configuration.userContentController;
  if (!controller) {
    controller = [[WKUserContentController alloc] init];
    configuration.userContentController = controller;
  }
  [controller removeAllUserScripts];
  for (WKUserScript *script in scripts) {
    [controller addUserScript:script];
  }
}

static void omni_macos_web_view_run_stored_user_scripts(OmniMacosWebView *data, WKWebView *web_view) {
  if (!data || !web_view) return;
  NSArray<WKUserScript *> *scripts = (__bridge NSArray<WKUserScript *> *)data->user_scripts;
  for (WKUserScript *script in scripts) {
    if (script.source.length == 0) continue;
    [web_view evaluateJavaScript:script.source completionHandler:nil];
  }
}

static void omni_macos_web_view_register_message_handler(OmniMacosWebView *data, NSString *name) {
  if (!data || !data->web_view || name.length == 0) return;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  WKUserContentController *controller = web_view.configuration.userContentController;
  if (!controller) return;
  NSMutableDictionary<NSString *, OmniMacosScriptMessageHandler *> *handlers = (__bridge NSMutableDictionary *)data->message_handlers;
  if (!handlers) {
    handlers = [NSMutableDictionary dictionary];
    data->message_handlers = (__bridge_retained void *)handlers;
  }
  if (handlers[name]) {
    [controller removeScriptMessageHandlerForName:name];
  }
  OmniMacosScriptMessageHandler *handler = [[OmniMacosScriptMessageHandler alloc] init];
  handler.webViewData = data;
  handler.name = name;
  handlers[name] = handler;
  [controller addScriptMessageHandler:handler name:name];
}

static void omni_macos_web_view_install_message_handlers(
  WKWebViewConfiguration *configuration,
  OmniMacosWebView *data,
  const char **message_handler_names,
  int32_t message_handler_count
) {
  if (!configuration || !data || !message_handler_names || message_handler_count <= 0) return;
  NSMutableDictionary<NSString *, OmniMacosScriptMessageHandler *> *handlers = [NSMutableDictionary dictionary];
  for (int32_t i = 0; i < message_handler_count; i++) {
    if (!message_handler_names[i] || !message_handler_names[i][0]) continue;
    NSString *name = [[NSString alloc] initWithUTF8String:message_handler_names[i]];
    if (!name) continue;
    OmniMacosScriptMessageHandler *handler = [[OmniMacosScriptMessageHandler alloc] init];
    handler.webViewData = data;
    handler.name = name;
    handlers[name] = handler;
    [configuration.userContentController addScriptMessageHandler:handler name:name];
  }
  if (handlers.count > 0) data->message_handlers = (__bridge_retained void *)handlers;
}

static void omni_macos_web_view_load_current(OmniMacosWebView *data, const char **header_names, const char **header_values, int32_t header_count) {
  if (!data || !data->web_view) return;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  NSString *html = (__bridge NSString *)data->html;
  NSString *base = (__bridge NSString *)data->base_url;
  NSString *url = (__bridge NSString *)data->url;
  if (html) {
    NSURL *base_url = base ? [NSURL URLWithString:base] : nil;
    [web_view loadHTMLString:html baseURL:base_url];
    return;
  }
  NSURL *ns_url = [NSURL URLWithString:url ?: @"about:blank"];
  if (!ns_url) return;
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:ns_url];
  if (header_names && header_values && header_count > 0) {
    for (int32_t i = 0; i < header_count; i++) {
      if (!header_names[i] || !header_values[i]) continue;
      NSString *name = [[NSString alloc] initWithUTF8String:header_names[i]];
      NSString *value = [[NSString alloc] initWithUTF8String:header_values[i]];
      if (name && value) [request setValue:value forHTTPHeaderField:name];
    }
  } else {
    NSArray<NSString *> *names = (__bridge NSArray<NSString *> *)data->request_header_names;
    NSArray<NSString *> *values = (__bridge NSArray<NSString *> *)data->request_header_values;
    NSUInteger count = MIN(names.count, values.count);
    for (NSUInteger i = 0; i < count; i++) {
      NSString *name = names[i];
      NSString *value = values[i];
      if (name.length > 0 && value) [request setValue:value forHTTPHeaderField:name];
    }
  }
  [web_view loadRequest:request];
}

static NSArray<NSString *> *omni_macos_web_view_make_names(const char **names, int32_t count) {
  if (!names || count <= 0) return @[];
  NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
  for (int32_t i = 0; i < count; i++) {
    if (!names[i] || !names[i][0]) continue;
    NSString *name = [[NSString alloc] initWithUTF8String:names[i]];
    if (name) [result addObject:name];
  }
  return result;
}

static NSArray<NSDictionary<NSString *, NSString *> *> *omni_macos_web_view_make_content_rules(
  const char **identifiers,
  const char **sources,
  int32_t count
) {
  if (!identifiers || !sources || count <= 0) return @[];
  NSMutableArray<NSDictionary<NSString *, NSString *> *> *rules = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
  for (int32_t i = 0; i < count; i++) {
    if (!identifiers[i] || !identifiers[i][0] || !sources[i] || !sources[i][0]) continue;
    NSString *identifier = [[NSString alloc] initWithUTF8String:identifiers[i]];
    NSString *source = [[NSString alloc] initWithUTF8String:sources[i]];
    if (identifier && source) [rules addObject:@{ @"identifier": identifier, @"source": source }];
  }
  return rules;
}

static void omni_macos_web_view_release_retained(void **slot) {
  if (!slot || !*slot) return;
  id value = (__bridge_transfer id)*slot;
  (void)value;
  *slot = NULL;
}

static void omni_macos_web_view_replace_string(void **slot, const char *value) {
  omni_macos_web_view_release_retained(slot);
  if (value) *slot = (__bridge_retained void *)[[NSString alloc] initWithUTF8String:value];
}

static void omni_macos_web_view_replace_object(void **slot, id value) {
  omni_macos_web_view_release_retained(slot);
  if (value) *slot = (__bridge_retained void *)value;
}

static BOOL omni_macos_web_view_strings_equal(NSString *lhs, const char *rhs) {
  NSString *right = rhs ? [[NSString alloc] initWithUTF8String:rhs] : nil;
  if (!lhs && !right) return YES;
  return lhs && right && [lhs isEqualToString:right];
}

static void omni_macos_web_view_detach_for_reuse(GtkWidget *widget) {
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

static BOOL omni_macos_web_view_update_load(
  OmniMacosWebView *data,
  const char *url,
  const char *html,
  const char *base_url
) {
  NSString *old_url = (__bridge NSString *)data->url;
  NSString *old_html = (__bridge NSString *)data->html;
  NSString *old_base_url = (__bridge NSString *)data->base_url;
  const char *next_url = (url && url[0]) ? url : "about:blank";
  BOOL html_changed = (html != NULL) != (old_html != nil) || !omni_macos_web_view_strings_equal(old_html, html);
  BOOL url_changed = !omni_macos_web_view_strings_equal(old_url, next_url);
  BOOL base_changed = (base_url != NULL) != (old_base_url != nil) || !omni_macos_web_view_strings_equal(old_base_url, base_url);

  omni_macos_web_view_replace_string(&data->url, next_url);
  omni_macos_web_view_replace_string(&data->html, html);
  omni_macos_web_view_replace_string(&data->base_url, base_url);
  return html_changed || url_changed || base_changed;
}

static void omni_macos_web_view_update_common(
  OmniMacosWebView *data,
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
  NSArray<WKUserScript *> *user_scripts,
  NSArray<NSDictionary<NSString *, NSString *> *> *content_rules,
  NSArray<NSString *> *message_handler_names,
  omni_adw_web_message_callback message_callback,
  omni_adw_web_navigation_callback navigation_callback,
  omni_adw_web_policy_callback policy_callback,
  omni_adw_web_response_policy_callback response_policy_callback,
  omni_adw_web_download_destination_callback download_destination_callback,
  omni_adw_web_title_callback title_callback,
  omni_adw_web_progress_callback progress_callback,
  omni_adw_web_cookie_callback cookie_callback,
  omni_adw_web_script_dialog_callback script_dialog_callback,
  void *callback_context
) {
  omni_macos_web_view_replace_string(&data->application_name, application_name);
  omni_macos_web_view_replace_string(&data->custom_user_agent, custom_user_agent);
  omni_macos_web_view_replace_object(&data->request_header_names, omni_macos_web_view_make_names(request_header_names, request_header_count));
  omni_macos_web_view_replace_object(&data->request_header_values, omni_macos_web_view_make_names(request_header_values, request_header_count));
  data->request_header_count = request_header_count;
  omni_macos_web_view_replace_object(&data->user_scripts, user_scripts ?: @[]);
  omni_macos_web_view_replace_object(&data->content_rules, content_rules ?: @[]);
  omni_macos_web_view_replace_object(&data->message_handler_names, message_handler_names ?: @[]);
  data->message_callback = message_callback;
  data->navigation_callback = navigation_callback;
  data->policy_callback = policy_callback;
  data->response_policy_callback = response_policy_callback;
  data->download_destination_callback = download_destination_callback;
  data->title_callback = title_callback;
  data->progress_callback = progress_callback;
  data->cookie_callback = cookie_callback;
  data->script_dialog_callback = script_dialog_callback;
  data->callback_context = callback_context;
  data->page_zoom = page_zoom > 0 ? page_zoom : 1.0;
  data->allows_back_forward_navigation_gestures = allows_back_forward_navigation_gestures ? 1 : 0;
  data->javascript_can_open_windows = javascript_can_open_windows ? 1 : 0;
  data->javascript_enabled = javascript_enabled ? 1 : 0;
  data->minimum_font_size = minimum_font_size > 0 ? minimum_font_size : 0;
  data->is_inspectable = is_inspectable ? 1 : 0;
  data->allows_inline_media_playback = allows_inline_media_playback ? 1 : 0;
  data->media_playback_requires_user_gesture = media_playback_requires_user_gesture ? 1 : 0;
}

static void omni_macos_web_view_apply_settings(OmniMacosWebView *data) {
  if (!data || !data->web_view) return;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  WKWebViewConfiguration *configuration = web_view.configuration;
  NSString *application_name = (__bridge NSString *)data->application_name;
  NSString *custom_user_agent = (__bridge NSString *)data->custom_user_agent;
  configuration.applicationNameForUserAgent = application_name;
  web_view.customUserAgent = custom_user_agent;
  web_view.pageZoom = data->page_zoom > 0 ? data->page_zoom : 1.0;
  web_view.allowsBackForwardNavigationGestures = data->allows_back_forward_navigation_gestures ? YES : NO;
  configuration.preferences.javaScriptCanOpenWindowsAutomatically = data->javascript_can_open_windows ? YES : NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  configuration.preferences.javaScriptEnabled = data->javascript_enabled ? YES : NO;
#pragma clang diagnostic pop
  configuration.preferences.minimumFontSize = data->minimum_font_size > 0 ? data->minimum_font_size : 0;
  if ([configuration respondsToSelector:@selector(setAllowsInlineMediaPlayback:)]) {
    ((void (*)(id, SEL, BOOL))objc_msgSend)(configuration, @selector(setAllowsInlineMediaPlayback:), data->allows_inline_media_playback ? YES : NO);
  }
  if ([web_view respondsToSelector:@selector(setInspectable:)]) {
    ((void (*)(id, SEL, BOOL))objc_msgSend)(web_view, @selector(setInspectable:), data->is_inspectable ? YES : NO);
  }
}

static void omni_macos_web_view_sync_message_handlers(OmniMacosWebView *data) {
  if (!data || !data->web_view) return;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  WKUserContentController *controller = web_view.configuration.userContentController;
  if (!controller) return;

  NSMutableDictionary<NSString *, OmniMacosScriptMessageHandler *> *old_handlers = (__bridge NSMutableDictionary *)data->message_handlers;
  for (NSString *name in [old_handlers.allKeys copy]) {
    [controller removeScriptMessageHandlerForName:name];
  }

  NSMutableDictionary<NSString *, OmniMacosScriptMessageHandler *> *handlers = [NSMutableDictionary dictionary];
  NSArray<NSString *> *names = (__bridge NSArray<NSString *> *)data->message_handler_names;
  for (NSString *name in names) {
    if (name.length == 0) continue;
    OmniMacosScriptMessageHandler *handler = [[OmniMacosScriptMessageHandler alloc] init];
    handler.webViewData = data;
    handler.name = name;
    handlers[name] = handler;
    [controller addScriptMessageHandler:handler name:name];
  }
  omni_macos_web_view_replace_object(&data->message_handlers, handlers);
}

static void omni_macos_web_view_sync_content_rules(
  WKUserContentController *controller,
  NSArray<NSDictionary<NSString *, NSString *> *> *rules,
  void (^completion)(void)
) {
  if (!controller) {
    if (completion) completion();
    return;
  }
  [controller removeAllContentRuleLists];
  if (rules.count == 0) {
    if (completion) completion();
    return;
  }

  __block NSInteger remaining = (NSInteger)rules.count;
  void (^finish_one)(void) = ^{
    remaining -= 1;
    if (remaining == 0 && completion) completion();
  };

  for (NSDictionary<NSString *, NSString *> *rule in rules) {
    NSString *identifier = rule[@"identifier"];
    NSString *source = rule[@"source"];
    if (identifier.length == 0 || source.length == 0) {
      finish_one();
      continue;
    }
    [[WKContentRuleListStore defaultStore] compileContentRuleListForIdentifier:identifier encodedContentRuleList:source completionHandler:^(WKContentRuleList *ruleList, NSError *error) {
      (void)error;
      dispatch_async(dispatch_get_main_queue(), ^{
        if (ruleList) [controller addContentRuleList:ruleList];
        finish_one();
      });
    }];
  }
}

static void omni_macos_web_view_sync_existing_web_view(OmniMacosWebView *data, BOOL load_changed, BOOL content_rules_changed) {
  if (!data || !data->web_view) return;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  omni_macos_web_view_apply_settings(data);
  omni_macos_web_view_install_user_scripts(web_view.configuration, (__bridge NSArray<WKUserScript *> *)data->user_scripts);
  omni_macos_web_view_sync_message_handlers(data);
  NSArray<NSDictionary<NSString *, NSString *> *> *rules = (__bridge NSArray<NSDictionary<NSString *, NSString *> *> *)data->content_rules;
  omni_macos_web_view_sync_content_rules(web_view.configuration.userContentController, rules, ^{
    if (load_changed) {
      omni_macos_web_view_load_current(data, NULL, NULL, 0);
    } else if (content_rules_changed && web_view.URL) {
      [web_view reload];
    }
  });
}

static void omni_macos_web_view_activate(OmniMacosWebView *data) {
  if (!data) return;
  omni_active_web_view = data;
  GtkWidget *widget = data->widget;
  if (widget && gtk_widget_get_mapped(widget)) {
    gtk_widget_grab_focus(widget);
  }
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  if (web_view && web_view.window) {
    [web_view.window makeFirstResponder:web_view];
    return;
  }
  NSView *native_view = (__bridge NSView *)data->native_view;
  if (native_view && native_view.window) {
    [native_view.window makeFirstResponder:native_view];
  }
}

static void omni_macos_web_view_evaluate(OmniMacosWebView *data, NSString *script) {
  if (!data || !data->web_view || !script) return;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  [web_view evaluateJavaScript:script completionHandler:nil];
}

static void omni_macos_web_view_dispatch_mouse_event(OmniMacosWebView *data, NSString *type, double x, double y, int32_t click_count) {
  if (!data || !data->web_view || type.length == 0) return;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  if (web_view.isHidden || web_view.alphaValue <= 0.01) return;

  double clamped_x = fmax(0.0, fmin(x, web_view.bounds.size.width));
  double clamped_y = fmax(0.0, fmin(y, web_view.bounds.size.height));
  int32_t detail = click_count > 0 ? click_count : 1;
  NSString *script = [NSString stringWithFormat:
    @"(() => {"
      "const x=%0.3f,y=%0.3f,detail=%d,type='%@';"
      "const target=document.elementFromPoint(x,y);"
      "if(!target) return false;"
      "const common={bubbles:true,cancelable:true,composed:true,view:window,clientX:x,clientY:y,screenX:x,screenY:y,button:0,detail:detail};"
      "const fire=(name,buttons)=>target.dispatchEvent(new MouseEvent(name,Object.assign({},common,{buttons:buttons})));"
      "if(type==='mousedown'){"
        "fire('mouseover',0);fire('mouseenter',0);fire('mousemove',0);return fire('mousedown',1);"
      "}"
      "if(type==='mousemove'){"
        "fire('mouseover',0);fire('mouseenter',0);return fire('mousemove',0);"
      "}"
      "fire('mouseup',0);"
      "const ok=fire('click',0);"
      "if(detail>1) fire('dblclick',0);"
      "return ok;"
    "})()",
    clamped_x,
    clamped_y,
    detail,
    type
  ];
  omni_macos_web_view_evaluate(data, script);
}

static void omni_macos_web_view_scroll_by(OmniMacosWebView *data, CGFloat dx, CGFloat dy) {
  if (!data || !data->web_view) return;
  NSString *script = [NSString stringWithFormat:
    @"(function(){"
      "var dx=%0.3f,dy=%0.3f;"
      "var el=document.scrollingElement||document.documentElement||document.body;"
      "if(el){"
        "var beforeX=el.scrollLeft,beforeY=el.scrollTop;"
        "el.scrollLeft=beforeX+dx;el.scrollTop=beforeY+dy;"
        "if((dx&&el.scrollLeft===beforeX)||(dy&&el.scrollTop===beforeY)){window.scrollBy({left:dx,top:dy,behavior:'auto'});}"
      "}else{window.scrollBy({left:dx,top:dy,behavior:'auto'});}"
    "})();",
    dx,
    dy
  ];
  omni_macos_web_view_evaluate(data, script);
}

static CGFloat omni_macos_web_view_page_delta(OmniMacosWebView *data) {
  if (!data || !data->web_view) return 480.0;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  return fmax(160.0, web_view.bounds.size.height * 0.82);
}

static BOOL omni_macos_web_view_rect_nearly_equal(NSRect lhs, NSRect rhs) {
  const CGFloat epsilon = 0.5;
  return fabs(lhs.origin.x - rhs.origin.x) < epsilon &&
         fabs(lhs.origin.y - rhs.origin.y) < epsilon &&
         fabs(lhs.size.width - rhs.size.width) < epsilon &&
         fabs(lhs.size.height - rhs.size.height) < epsilon;
}

static BOOL omni_macos_web_view_appearance_matches(NSAppearance *lhs, NSAppearance *rhs) {
  if (lhs == rhs) return YES;
  NSString *left_name = lhs.name;
  NSString *right_name = rhs.name;
  if (left_name == right_name) return YES;
  return left_name && right_name && [left_name isEqualToString:right_name];
}

static gboolean omni_macos_web_view_intersect_bounds(graphene_rect_t *bounds, const graphene_rect_t *clip) {
  if (!bounds || !clip) return FALSE;
  double min_x = fmax(bounds->origin.x, clip->origin.x);
  double min_y = fmax(bounds->origin.y, clip->origin.y);
  double max_x = fmin(bounds->origin.x + bounds->size.width, clip->origin.x + clip->size.width);
  double max_y = fmin(bounds->origin.y + bounds->size.height, clip->origin.y + clip->size.height);
  bounds->origin.x = (float)min_x;
  bounds->origin.y = (float)min_y;
  bounds->size.width = (float)fmax(0.0, max_x - min_x);
  bounds->size.height = (float)fmax(0.0, max_y - min_y);
  return bounds->size.width > 0.5 && bounds->size.height > 0.5;
}

static gboolean omni_macos_web_view_visible_bounds(GtkWidget *widget, GtkWidget *root, graphene_rect_t *bounds) {
  if (!widget || !root || !bounds) return FALSE;
  if (!gtk_widget_compute_bounds(widget, root, bounds)) return FALSE;
  for (GtkWidget *ancestor = gtk_widget_get_parent(widget); ancestor && ancestor != root; ancestor = gtk_widget_get_parent(ancestor)) {
    if (g_object_get_data(G_OBJECT(ancestor), "omni-native-clip") == NULL) continue;
    graphene_rect_t clip;
    if (!gtk_widget_compute_bounds(ancestor, root, &clip)) continue;
    if (!omni_macos_web_view_intersect_bounds(bounds, &clip)) return FALSE;
  }
  return TRUE;
}

gboolean omni_macos_web_view_widget_scroll(GtkWidget *widget, double dx, double dy) {
  if (!widget) return FALSE;
  OmniMacosWebView *data = (OmniMacosWebView *)g_object_get_data(G_OBJECT(widget), "omni-macos-web-view");
  if (!data || !data->web_view) return FALSE;
  omni_macos_web_view_activate(data);
  omni_macos_web_view_scroll_by(data, dx, dy);
  return TRUE;
}

gboolean omni_macos_web_view_widget_scroll_page(GtkWidget *widget, int direction) {
  if (!widget) return FALSE;
  OmniMacosWebView *data = (OmniMacosWebView *)g_object_get_data(G_OBJECT(widget), "omni-macos-web-view");
  if (!data || !data->web_view) return FALSE;
  omni_macos_web_view_activate(data);
  omni_macos_web_view_scroll_by(data, 0, (direction >= 0 ? 1.0 : -1.0) * omni_macos_web_view_page_delta(data));
  return TRUE;
}

static OmniMacosWebView *omni_macos_web_view_under_pointer(void) {
  NSPoint screen_point = [NSEvent mouseLocation];
  NSMutableSet<NSValue *> *registry = omni_registered_web_views();
  for (NSValue *value in [registry copy]) {
    OmniMacosWebView *data = (OmniMacosWebView *)value.pointerValue;
    if (!data || !data->container_view) continue;
    NSView *container_view = (__bridge NSView *)data->container_view;
    if (container_view.hidden || container_view.alphaValue <= 0.01 || !container_view.window) continue;
    NSPoint window_point = [container_view.window convertPointFromScreen:screen_point];
    NSPoint view_point = [container_view convertPoint:window_point fromView:nil];
    if (NSPointInRect(view_point, container_view.bounds)) return data;
  }
  return NULL;
}

static gboolean omni_macos_web_view_is_visible(OmniMacosWebView *data) {
  if (!data || !data->container_view) return FALSE;
  NSView *container_view = (__bridge NSView *)data->container_view;
  return !container_view.hidden && container_view.alphaValue > 0.01 && container_view.window != nil;
}

static OmniMacosWebView *omni_macos_single_visible_web_view(void) {
  OmniMacosWebView *candidate = NULL;
  int count = 0;
  NSMutableSet<NSValue *> *registry = omni_registered_web_views();
  for (NSValue *value in [registry copy]) {
    OmniMacosWebView *data = (OmniMacosWebView *)value.pointerValue;
    if (!omni_macos_web_view_is_visible(data)) continue;
    candidate = data;
    count += 1;
    if (count > 1) return NULL;
  }
  return count == 1 ? candidate : NULL;
}

void omni_macos_web_view_set_modal_occlusion(gboolean occluded) {
  omni_web_views_occluded_by_modal = occluded ? YES : NO;
  NSMutableSet<NSValue *> *registry = omni_registered_web_views();
  for (NSValue *value in [registry copy]) {
    OmniMacosWebView *data = (OmniMacosWebView *)value.pointerValue;
    if (data) omni_macos_web_view_sync(data);
  }
}

gboolean omni_macos_web_view_handle_key(guint keyval, GdkModifierType state) {
  OmniMacosWebView *data = omni_macos_web_view_under_pointer();
  if (!data) data = omni_active_web_view;
  if (!data) data = omni_macos_single_visible_web_view();
  if (!data || !data->web_view) return FALSE;

  CGFloat page = omni_macos_web_view_page_delta(data);
  switch (keyval) {
    case GDK_KEY_Page_Down:
      omni_macos_web_view_scroll_by(data, 0, page);
      return TRUE;
    case GDK_KEY_Page_Up:
      omni_macos_web_view_scroll_by(data, 0, -page);
      return TRUE;
    case GDK_KEY_Down:
      omni_macos_web_view_scroll_by(data, 0, 56.0);
      return TRUE;
    case GDK_KEY_Up:
      omni_macos_web_view_scroll_by(data, 0, -56.0);
      return TRUE;
    case GDK_KEY_space:
      omni_macos_web_view_scroll_by(data, 0, (state & GDK_SHIFT_MASK) ? -page : page);
      return TRUE;
    case GDK_KEY_Home:
      omni_macos_web_view_evaluate(data, @"window.scrollTo({left:0, top:0, behavior:'auto'});");
      return TRUE;
    case GDK_KEY_End:
      omni_macos_web_view_evaluate(data, @"window.scrollTo({left:0, top:document.scrollingElement ? document.scrollingElement.scrollHeight : document.body.scrollHeight, behavior:'auto'});");
      return TRUE;
    default:
      return FALSE;
  }
}

static gboolean omni_macos_web_view_gtk_scroll(GtkEventControllerScroll *controller, double dx, double dy, gpointer user_data) {
  (void)controller;
  OmniMacosWebView *data = (OmniMacosWebView *)user_data;
  omni_macos_web_view_activate(data);
  omni_macos_web_view_scroll_by(data, dx * 96.0, dy * 96.0);
  return TRUE;
}

static void omni_macos_web_view_gtk_pressed(GtkGestureClick *gesture, int n_press, double x, double y, gpointer user_data) {
  guint button = gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(gesture));
  if (button != GDK_BUTTON_PRIMARY) return;
  (void)n_press;
  OmniMacosWebView *data = (OmniMacosWebView *)user_data;
  omni_macos_web_view_activate(data);
  omni_macos_web_view_dispatch_mouse_event(data, @"mousedown", x, y, n_press);
}

static void omni_macos_web_view_gtk_released(GtkGestureClick *gesture, int n_press, double x, double y, gpointer user_data) {
  guint button = gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(gesture));
  if (button != GDK_BUTTON_PRIMARY) return;
  OmniMacosWebView *data = (OmniMacosWebView *)user_data;
  omni_macos_web_view_activate(data);
  omni_macos_web_view_dispatch_mouse_event(data, @"mouseup", x, y, n_press);
}

static double omni_macos_web_view_effective_opacity(GtkWidget *widget) {
  double opacity = 1.0;
  for (GtkWidget *current = widget; current; current = gtk_widget_get_parent(current)) {
    if (!gtk_widget_get_visible(current) || !gtk_widget_get_child_visible(current)) return 0.0;
    opacity *= gtk_widget_get_opacity(current);
    if (opacity <= 0.01) return 0.0;
  }
  return opacity;
}

static void omni_macos_web_view_sync(OmniMacosWebView *data) {
  if (!data || !data->widget) return;
  if (!gtk_widget_get_mapped(data->widget)) {
    if (data->container_view) [(__bridge NSView *)data->container_view setHidden:YES];
    return;
  }

  GtkRoot *root = gtk_widget_get_root(data->widget);
  if (!root || !GTK_IS_WIDGET(root)) return;

  GtkNative *native = gtk_widget_get_native(data->widget);
  GdkSurface *surface = native ? gtk_native_get_surface(native) : NULL;
  if (!surface || !GDK_IS_MACOS_SURFACE(surface)) return;

  NSWindow *window = (__bridge NSWindow *)gdk_macos_surface_get_native_window(GDK_MACOS_SURFACE(surface));
  if (!window.acceptsMouseMovedEvents) window.acceptsMouseMovedEvents = YES;
  NSView *content_view = window.contentView;
  if (!content_view) return;

  graphene_rect_t raw_bounds;
  if (!gtk_widget_compute_bounds(data->widget, GTK_WIDGET(root), &raw_bounds)) return;
  graphene_rect_t visible_bounds = raw_bounds;
  gboolean has_visible_bounds = omni_macos_web_view_visible_bounds(data->widget, GTK_WIDGET(root), &visible_bounds);

  CGFloat raw_width = fmax(1.0, raw_bounds.size.width);
  CGFloat raw_height = fmax(1.0, raw_bounds.size.height);
  CGFloat raw_y = content_view.isFlipped ? raw_bounds.origin.y : content_view.bounds.size.height - raw_bounds.origin.y - raw_height;
  NSRect raw_frame = NSMakeRect(raw_bounds.origin.x, raw_y, raw_width, raw_height);

  CGFloat width = fmax(1.0, visible_bounds.size.width);
  CGFloat height = fmax(1.0, visible_bounds.size.height);
  CGFloat y = content_view.isFlipped ? visible_bounds.origin.y : content_view.bounds.size.height - visible_bounds.origin.y - height;
  NSRect frame = NSMakeRect(visible_bounds.origin.x, y, width, height);
  double opacity = omni_macos_web_view_effective_opacity(data->widget);

  NSView *container_view = (__bridge NSView *)data->container_view;
  NSView *native_view = (__bridge NSView *)data->native_view;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  NSString *url = (__bridge NSString *)data->url;

  if (!container_view) {
    container_view = [[OmniMacosWebViewContainer alloc] initWithFrame:frame];
    container_view.wantsLayer = YES;
    container_view.layer.masksToBounds = YES;
    container_view.autoresizingMask = NSViewNotSizable;
    data->container_view = (__bridge_retained void *)container_view;
  }

  if (!native_view) {
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    NSString *application_name = (__bridge NSString *)data->application_name;
    configuration.applicationNameForUserAgent = application_name ?: @"Version/18.3 Safari/605.1.15";
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = data->javascript_can_open_windows ? YES : NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    configuration.preferences.javaScriptEnabled = data->javascript_enabled ? YES : NO;
#pragma clang diagnostic pop
    configuration.preferences.minimumFontSize = data->minimum_font_size > 0 ? data->minimum_font_size : 0;
    if ([configuration respondsToSelector:@selector(setAllowsInlineMediaPlayback:)]) {
      ((void (*)(id, SEL, BOOL))objc_msgSend)(configuration, @selector(setAllowsInlineMediaPlayback:), data->allows_inline_media_playback ? YES : NO);
    }
    omni_macos_web_view_install_user_scripts(configuration, (__bridge NSArray<WKUserScript *> *)data->user_scripts);
    if (omni_macos_webkit_trace_enabled()) {
      NSString *identity = (__bridge NSString *)data->identity;
      NSArray *scripts = (__bridge NSArray *)data->user_scripts;
      fprintf(stderr, "OMNI_MACOS_WEBKIT_CREATE identity=%s scripts=%lu url=%s html=%d\n",
              identity.UTF8String ?: "",
              (unsigned long)scripts.count,
              url.UTF8String ?: "",
              data->html ? 1 : 0);
    }

    web_view = [[WKWebView alloc] initWithFrame:container_view.bounds configuration:configuration];
    native_view = web_view;
    web_view.allowsBackForwardNavigationGestures = data->allows_back_forward_navigation_gestures ? YES : NO;
    web_view.allowsMagnification = YES;
    web_view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    web_view.wantsLayer = YES;
    web_view.layer.masksToBounds = YES;
    NSAppearance *appearance = omni_macos_web_view_effective_appearance();
    web_view.appearance = appearance;
    [appearance performAsCurrentDrawingAppearance:^{
      web_view.underPageBackgroundColor = NSColor.windowBackgroundColor;
    }];
    OmniMacosWebViewNavigationDelegate *delegate = [[OmniMacosWebViewNavigationDelegate alloc] init];
    delegate.webViewData = data;
    web_view.navigationDelegate = delegate;
    data->navigation_delegate = (__bridge_retained void *)delegate;
    OmniMacosWebViewUIDelegate *ui_delegate = [[OmniMacosWebViewUIDelegate alloc] init];
    ui_delegate.webViewData = data;
    web_view.UIDelegate = ui_delegate;
    data->ui_delegate = (__bridge_retained void *)ui_delegate;

    data->native_view = (__bridge void *)native_view;
    data->web_view = (__bridge_retained void *)web_view;
    data->owns_native_view = FALSE;
    data->owns_web_view = TRUE;
    omni_macos_web_view_apply_settings(data);
    omni_macos_web_view_sync_message_handlers(data);
    NSArray<NSDictionary<NSString *, NSString *> *> *rules = (__bridge NSArray<NSDictionary<NSString *, NSString *> *> *)data->content_rules;
    omni_macos_web_view_sync_content_rules(web_view.configuration.userContentController, rules, ^{
      omni_macos_web_view_load_current(data, NULL, NULL, 0);
    });
  } else if (!web_view && [native_view isKindOfClass:[WKWebView class]]) {
    web_view = (WKWebView *)native_view;
    data->web_view = (__bridge void *)web_view;
    omni_macos_web_view_apply_settings(data);
    omni_macos_web_view_install_user_scripts(web_view.configuration, (__bridge NSArray<WKUserScript *> *)data->user_scripts);
    omni_macos_web_view_sync_message_handlers(data);
  }
  if ([container_view isKindOfClass:[OmniMacosWebViewContainer class]]) {
    ((OmniMacosWebViewContainer *)container_view).embeddedView = native_view;
    ((OmniMacosWebViewContainer *)container_view).webView = web_view;
    ((OmniMacosWebViewContainer *)container_view).webViewData = data;
  }

  if (container_view.superview != content_view) {
    [container_view removeFromSuperview];
    [content_view addSubview:container_view positioned:NSWindowAbove relativeTo:nil];
  }

  if (native_view.superview != container_view) {
    [native_view removeFromSuperview];
    [container_view addSubview:native_view];
  }

  if (!omni_macos_web_view_rect_nearly_equal(container_view.frame, frame)) {
    container_view.frame = frame;
  }
  NSRect native_frame = NSMakeRect(
    raw_frame.origin.x - frame.origin.x,
    raw_frame.origin.y - frame.origin.y,
    raw_frame.size.width,
    raw_frame.size.height
  );
  if (!omni_macos_web_view_rect_nearly_equal(native_view.frame, native_frame)) {
    native_view.frame = native_frame;
  }
  if (native_view.autoresizingMask != (NSViewWidthSizable | NSViewHeightSizable)) {
    native_view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  }
  if (web_view) {
    NSAppearance *appearance = omni_macos_web_view_effective_appearance();
    if (!omni_macos_web_view_appearance_matches(web_view.appearance, appearance)) {
      web_view.appearance = appearance;
      [appearance performAsCurrentDrawingAppearance:^{
        web_view.underPageBackgroundColor = NSColor.windowBackgroundColor;
      }];
    }
  }
  BOOL hidden = !has_visible_bounds || omni_web_views_occluded_by_modal || opacity <= 0.01 || width <= 1.0 || height <= 1.0;
  if (fabs(container_view.alphaValue - opacity) > 0.001) container_view.alphaValue = opacity;
  if (container_view.hidden != hidden) container_view.hidden = hidden;
}

static gboolean omni_macos_web_view_tick(GtkWidget *widget, GdkFrameClock *clock, gpointer user_data) {
  (void)widget;
  (void)clock;
  omni_macos_web_view_sync((OmniMacosWebView *)user_data);
  return G_SOURCE_CONTINUE;
}

static void omni_macos_web_view_mapped(GtkWidget *widget, gpointer user_data) {
  (void)widget;
  omni_macos_web_view_sync((OmniMacosWebView *)user_data);
}

static void omni_macos_web_view_unmapped(GtkWidget *widget, gpointer user_data) {
  (void)widget;
  OmniMacosWebView *data = (OmniMacosWebView *)user_data;
  if (data && data->container_view) [(__bridge NSView *)data->container_view setHidden:YES];
}

static void omni_macos_web_view_destroy(gpointer user_data) {
  OmniMacosWebView *data = (OmniMacosWebView *)user_data;
  if (!data) return;
  if (data->web_view && data->owns_web_view) {
    WKWebView *web_view = (__bridge_transfer WKWebView *)data->web_view;
    [web_view stopLoading];
    web_view.navigationDelegate = nil;
    web_view.UIDelegate = nil;
    NSMutableDictionary<NSString *, OmniMacosScriptMessageHandler *> *handlers = (__bridge NSMutableDictionary *)data->message_handlers;
    for (NSString *name in [handlers.allKeys copy]) {
      [web_view.configuration.userContentController removeScriptMessageHandlerForName:name];
    }
    [web_view.configuration.userContentController removeAllContentRuleLists];
    [web_view removeFromSuperview];
  } else if (data->native_view) {
    NSView *native_view = (__bridge NSView *)data->native_view;
    [native_view removeFromSuperview];
  }
  if (data->native_view && data->owns_native_view) {
    NSView *native_view = (__bridge_transfer NSView *)data->native_view;
    (void)native_view;
  }
  if (data->navigation_delegate) {
    OmniMacosWebViewNavigationDelegate *delegate = (__bridge_transfer OmniMacosWebViewNavigationDelegate *)data->navigation_delegate;
    (void)delegate;
  }
  if (data->ui_delegate) {
    OmniMacosWebViewUIDelegate *delegate = (__bridge_transfer OmniMacosWebViewUIDelegate *)data->ui_delegate;
    (void)delegate;
  }
  if (data->container_view) {
    NSView *container_view = (__bridge_transfer NSView *)data->container_view;
    [container_view removeFromSuperview];
  }
  [omni_registered_web_views() removeObject:[NSValue valueWithPointer:data]];
  if (omni_active_web_view == data) omni_active_web_view = NULL;
  if (data->url) {
    NSString *url = (__bridge_transfer NSString *)data->url;
    (void)url;
  }
  if (data->application_name) {
    NSString *application_name = (__bridge_transfer NSString *)data->application_name;
    (void)application_name;
  }
  if (data->custom_user_agent) {
    NSString *custom_user_agent = (__bridge_transfer NSString *)data->custom_user_agent;
    (void)custom_user_agent;
  }
  if (data->request_header_names) {
    NSArray *names = (__bridge_transfer NSArray *)data->request_header_names;
    (void)names;
  }
  if (data->request_header_values) {
    NSArray *values = (__bridge_transfer NSArray *)data->request_header_values;
    (void)values;
  }
  if (data->user_scripts) {
    NSArray *user_scripts = (__bridge_transfer NSArray *)data->user_scripts;
    (void)user_scripts;
  }
  if (data->content_rules) {
    NSArray *content_rules = (__bridge_transfer NSArray *)data->content_rules;
    (void)content_rules;
  }
  if (data->message_handler_names) {
    NSArray *names = (__bridge_transfer NSArray *)data->message_handler_names;
    (void)names;
  }
  if (data->message_handlers) {
    NSDictionary *handlers = (__bridge_transfer NSDictionary *)data->message_handlers;
    (void)handlers;
  }
  if (data->html) {
    NSString *html = (__bridge_transfer NSString *)data->html;
    (void)html;
  }
  if (data->base_url) {
    NSString *base_url = (__bridge_transfer NSString *)data->base_url;
    (void)base_url;
  }
  if (data->identity) {
    NSString *identity = (__bridge_transfer NSString *)data->identity;
    [omni_registered_web_views_by_identity() removeObjectForKey:identity];
  }
  free(data);
}

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
  void *callback_context
) {
  if ((!url || !url[0]) && (!html || !html[0])) return NULL;
  NSArray<WKUserScript *> *new_user_scripts = omni_macos_web_view_make_user_scripts(
    script_sources,
    script_injection_times,
    script_main_frame_only,
    script_count
  );
  NSArray<NSDictionary<NSString *, NSString *> *> *new_content_rules = omni_macos_web_view_make_content_rules(
    content_rule_identifiers,
    content_rule_sources,
    content_rule_count
  );
  NSArray<NSString *> *new_handler_names = omni_macos_web_view_make_names(message_handler_names, message_handler_count);

  OmniMacosWebView *existing = omni_macos_web_view_lookup(identity);
  if (existing) {
    NSArray<NSDictionary<NSString *, NSString *> *> *old_content_rules = (__bridge NSArray<NSDictionary<NSString *, NSString *> *> *)existing->content_rules;
    BOOL content_rules_changed = ![old_content_rules isEqualToArray:new_content_rules];
    BOOL load_changed = omni_macos_web_view_update_load(existing, url, html, base_url);
    omni_macos_web_view_update_common(
      existing,
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
      new_user_scripts,
      new_content_rules,
      new_handler_names,
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
    omni_macos_web_view_detach_for_reuse(existing->widget);
    if (existing->widget) {
      gtk_accessible_update_property(
        GTK_ACCESSIBLE(existing->widget),
        GTK_ACCESSIBLE_PROPERTY_LABEL, accessibility_label && accessibility_label[0] ? accessibility_label : url,
        GTK_ACCESSIBLE_PROPERTY_DESCRIPTION, accessibility_description && accessibility_description[0] ? accessibility_description : "Web content",
        -1
      );
      g_object_set_data_full(G_OBJECT(existing->widget), "omni-accessible-label", g_strdup(accessibility_label && accessibility_label[0] ? accessibility_label : url), g_free);
      g_object_set_data_full(G_OBJECT(existing->widget), "omni-accessible-description", g_strdup(accessibility_description && accessibility_description[0] ? accessibility_description : "Web content"), g_free);
    }
    omni_macos_web_view_sync_existing_web_view(existing, load_changed, content_rules_changed);
    omni_macos_web_view_sync(existing);
    if (existing->widget) gtk_widget_queue_draw(existing->widget);
    return existing->widget;
  }

  GtkWidget *placeholder = gtk_drawing_area_new();
  gtk_widget_set_hexpand(placeholder, TRUE);
  gtk_widget_set_vexpand(placeholder, TRUE);
  gtk_widget_set_halign(placeholder, GTK_ALIGN_FILL);
  gtk_widget_set_valign(placeholder, GTK_ALIGN_FILL);
  gtk_widget_set_focusable(placeholder, TRUE);
  gtk_widget_add_css_class(placeholder, "omni-web-view");

  OmniMacosWebView *data = calloc(1, sizeof(OmniMacosWebView));
  if (!data) return placeholder;
  data->widget = placeholder;
  if (identity && identity[0]) data->identity = (__bridge_retained void *)[[NSString alloc] initWithUTF8String:identity];
  (void)omni_macos_web_view_update_load(data, url, html, base_url);
  omni_macos_web_view_update_common(
    data,
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
    new_user_scripts,
    new_content_rules,
    new_handler_names,
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
  if (omni_macos_webkit_trace_enabled()) {
    fprintf(stderr, "OMNI_MACOS_WEBKIT_NEW identity=%s script_count=%d handlers=%d rules=%d native=%p url=%s\n",
            identity ? identity : "",
            script_count,
            message_handler_count,
            content_rule_count,
            native_view,
            url ? url : "");
  }
  if (native_view) {
    NSView *external_view = (__bridge NSView *)native_view;
    data->native_view = (__bridge_retained void *)external_view;
    data->owns_native_view = TRUE;
    if ([external_view isKindOfClass:[WKWebView class]]) {
      data->web_view = (__bridge void *)external_view;
      data->owns_web_view = FALSE;
      data->uses_external_web_view = TRUE;
    }
  }
  if (data->web_view && !data->uses_external_web_view) {
    WKWebView *existing_web_view = (__bridge WKWebView *)data->web_view;
    omni_macos_web_view_install_user_scripts(existing_web_view.configuration, (__bridge NSArray<WKUserScript *> *)data->user_scripts);
    omni_macos_web_view_sync_message_handlers(data);
  }

  gtk_accessible_update_property(
    GTK_ACCESSIBLE(placeholder),
    GTK_ACCESSIBLE_PROPERTY_LABEL, accessibility_label && accessibility_label[0] ? accessibility_label : url,
    GTK_ACCESSIBLE_PROPERTY_DESCRIPTION, accessibility_description && accessibility_description[0] ? accessibility_description : "Web content",
    -1
  );
  g_object_set_data_full(G_OBJECT(placeholder), "omni-accessible-label", g_strdup(accessibility_label && accessibility_label[0] ? accessibility_label : url), g_free);
  g_object_set_data_full(G_OBJECT(placeholder), "omni-accessible-description", g_strdup(accessibility_description && accessibility_description[0] ? accessibility_description : "Web content"), g_free);

  g_object_set_data_full(G_OBJECT(placeholder), "omni-macos-web-view", data, omni_macos_web_view_destroy);
  g_object_ref(placeholder);
  data->holds_widget_ref = TRUE;
  [omni_registered_web_views() addObject:[NSValue valueWithPointer:data]];
  omni_macos_web_view_install_mouse_monitor_once();
  if (data->identity) {
    NSString *identity_key = (__bridge NSString *)data->identity;
    omni_registered_web_views_by_identity()[identity_key] = [NSValue valueWithPointer:data];
  }
  if (data->web_view) {
    if (!data->uses_external_web_view) {
      omni_macos_web_view_load_current(data, request_header_names, request_header_values, request_header_count);
    }
  }
  GtkEventController *scroll_controller = gtk_event_controller_scroll_new(
    GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES | GTK_EVENT_CONTROLLER_SCROLL_KINETIC
  );
  g_signal_connect(scroll_controller, "scroll", G_CALLBACK(omni_macos_web_view_gtk_scroll), data);
  gtk_widget_add_controller(placeholder, scroll_controller);

  GtkGesture *click_controller = gtk_gesture_click_new();
  g_signal_connect(click_controller, "pressed", G_CALLBACK(omni_macos_web_view_gtk_pressed), data);
  g_signal_connect(click_controller, "released", G_CALLBACK(omni_macos_web_view_gtk_released), data);
  gtk_widget_add_controller(placeholder, GTK_EVENT_CONTROLLER(click_controller));
  gtk_widget_add_tick_callback(placeholder, omni_macos_web_view_tick, data, NULL);
  g_signal_connect(placeholder, "map", G_CALLBACK(omni_macos_web_view_mapped), data);
  g_signal_connect(placeholder, "unmap", G_CALLBACK(omni_macos_web_view_unmapped), data);

  return placeholder;
}

GtkWidget *omni_macos_web_view_new(const char *url, void *native_view) {
  return omni_macos_web_view_new_ex(
      NULL, url, NULL, NULL, NULL, NULL, 0, NULL, NULL, 1.0, 1, 1, 1, 0.0, 0, 1, 0,
      native_view, NULL, NULL, NULL, 0, NULL, NULL, 0, NULL, 0, url, "Web content",
      NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
}

int32_t omni_macos_web_view_evaluate_javascript(const char *identity, const char *script, omni_adw_web_evaluate_callback callback, void *callback_context) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view || !script) return 0;
  if (omni_macos_webkit_trace_enabled()) {
    fprintf(stderr, "OMNI_MACOS_WEBKIT_EVAL identity=%s len=%lu prefix=%.80s\n", identity ? identity : "", (unsigned long)strlen(script), script);
  }
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  NSString *source = [[NSString alloc] initWithUTF8String:script];
  if (!source) return 0;
  [web_view evaluateJavaScript:source completionHandler:^(id result, NSError *error) {
    if (!callback) return;
    NSString *json = omni_macos_json_string_for_value(result, error);
    callback(callback_context, json ? json.UTF8String : NULL, error ? error.localizedDescription.UTF8String : NULL);
  }];
  return 1;
}

int32_t omni_macos_web_view_load_uri(const char *identity, const char *url) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view || !url) return 0;
  omni_macos_web_view_replace_string(&data->url, url);
  omni_macos_web_view_replace_string(&data->html, NULL);
  omni_macos_web_view_replace_string(&data->base_url, NULL);
  omni_macos_web_view_replace_object(&data->request_header_names, @[]);
  omni_macos_web_view_replace_object(&data->request_header_values, @[]);
  data->request_header_count = 0;
  omni_macos_web_view_load_current(data, NULL, NULL, 0);
  return 1;
}

int32_t omni_macos_web_view_load_request(const char *identity, const char *url, const char **header_names, const char **header_values, int32_t header_count) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view || !url) return 0;
  omni_macos_web_view_replace_string(&data->url, url);
  omni_macos_web_view_replace_string(&data->html, NULL);
  omni_macos_web_view_replace_string(&data->base_url, NULL);
  omni_macos_web_view_replace_object(&data->request_header_names, omni_macos_web_view_make_names(header_names, header_count));
  omni_macos_web_view_replace_object(&data->request_header_values, omni_macos_web_view_make_names(header_values, header_count));
  data->request_header_count = header_count;
  omni_macos_web_view_load_current(data, NULL, NULL, 0);
  return 1;
}

int32_t omni_macos_web_view_load_html(const char *identity, const char *html, const char *base_url) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view || !html) return 0;
  omni_macos_web_view_replace_string(&data->html, html);
  omni_macos_web_view_replace_string(&data->base_url, base_url);
  omni_macos_web_view_replace_string(&data->url, (base_url && base_url[0]) ? base_url : "about:blank");
  omni_macos_web_view_load_current(data, NULL, NULL, 0);
  return 1;
}

int32_t omni_macos_web_view_go_back(const char *identity) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view) return 0;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  if (!web_view.canGoBack) return 0;
  [web_view goBack];
  return 1;
}

int32_t omni_macos_web_view_go_forward(const char *identity) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view) return 0;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  if (!web_view.canGoForward) return 0;
  [web_view goForward];
  return 1;
}

int32_t omni_macos_web_view_reload(const char *identity) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view) return 0;
  [(__bridge WKWebView *)data->web_view reload];
  return 1;
}

int32_t omni_macos_web_view_stop_loading(const char *identity) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view) return 0;
  [(__bridge WKWebView *)data->web_view stopLoading];
  return 1;
}

int32_t omni_macos_web_view_can_go_back(const char *identity) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  return data && data->web_view && ((__bridge WKWebView *)data->web_view).canGoBack ? 1 : 0;
}

int32_t omni_macos_web_view_can_go_forward(const char *identity) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  return data && data->web_view && ((__bridge WKWebView *)data->web_view).canGoForward ? 1 : 0;
}

int32_t omni_macos_web_view_unregister(const char *identity) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data) return 0;
  if (data->web_view) {
    WKWebView *web_view = (__bridge WKWebView *)data->web_view;
    [web_view stopLoading];
  }
  data->message_callback = NULL;
  data->navigation_callback = NULL;
  data->policy_callback = NULL;
  data->response_policy_callback = NULL;
  data->download_destination_callback = NULL;
  data->title_callback = NULL;
  data->progress_callback = NULL;
  data->cookie_callback = NULL;
  data->script_dialog_callback = NULL;
  if (data->identity) {
    NSString *identity_key = (__bridge NSString *)data->identity;
    [omni_registered_web_views_by_identity() removeObjectForKey:identity_key];
  }
  if (data->widget && data->holds_widget_ref) {
    data->holds_widget_ref = FALSE;
    g_object_unref(data->widget);
  }
  return 1;
}

int32_t omni_macos_web_view_focus(const char *identity) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data) return 0;
  omni_macos_web_view_activate(data);
  return 1;
}

int32_t omni_macos_web_view_scroll_by_identity(const char *identity, double dx, double dy) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view) return 0;
  omni_macos_web_view_activate(data);
  omni_macos_web_view_scroll_by(data, dx, dy);
  return 1;
}

int32_t omni_macos_web_view_scroll_page_identity(const char *identity, int32_t direction) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view) return 0;
  omni_macos_web_view_activate(data);
  omni_macos_web_view_scroll_by(data, 0, (direction >= 0 ? 1.0 : -1.0) * omni_macos_web_view_page_delta(data));
  return 1;
}

int32_t omni_macos_web_view_set_zoom(const char *identity, double page_zoom) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view) return 0;
  data->page_zoom = page_zoom > 0 ? page_zoom : 1.0;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  web_view.pageZoom = data->page_zoom;
  return 1;
}

int32_t omni_macos_web_view_set_allows_back_forward_navigation_gestures(const char *identity, int32_t enabled) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view) return 0;
  data->allows_back_forward_navigation_gestures = enabled ? 1 : 0;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  web_view.allowsBackForwardNavigationGestures = enabled ? YES : NO;
  return 1;
}

int32_t omni_macos_web_view_set_javascript_can_open_windows(const char *identity, int32_t enabled) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view) return 0;
  data->javascript_can_open_windows = enabled ? 1 : 0;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  web_view.configuration.preferences.javaScriptCanOpenWindowsAutomatically = enabled ? YES : NO;
  return 1;
}

int32_t omni_macos_web_view_set_javascript_enabled(const char *identity, int32_t enabled) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view) return 0;
  data->javascript_enabled = enabled ? 1 : 0;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  web_view.configuration.preferences.javaScriptEnabled = enabled ? YES : NO;
#pragma clang diagnostic pop
  return 1;
}

int32_t omni_macos_web_view_set_minimum_font_size(const char *identity, double size) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view) return 0;
  data->minimum_font_size = size > 0 ? size : 0;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  web_view.configuration.preferences.minimumFontSize = size > 0 ? size : 0;
  return 1;
}

int32_t omni_macos_web_view_set_inspectable(const char *identity, int32_t enabled) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view) return 0;
  data->is_inspectable = enabled ? 1 : 0;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  if ([web_view respondsToSelector:@selector(setInspectable:)]) {
    ((void (*)(id, SEL, BOOL))objc_msgSend)(web_view, @selector(setInspectable:), enabled ? YES : NO);
  }
  return 1;
}

int32_t omni_macos_web_view_set_user_agent(const char *identity, const char *application_name, const char *custom_user_agent) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view) return 0;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  NSString *app_name = application_name && application_name[0] ? [[NSString alloc] initWithUTF8String:application_name] : nil;
  NSString *custom = custom_user_agent && custom_user_agent[0] ? [[NSString alloc] initWithUTF8String:custom_user_agent] : nil;
  omni_macos_web_view_replace_object(&data->application_name, app_name);
  omni_macos_web_view_replace_object(&data->custom_user_agent, custom);
  web_view.configuration.applicationNameForUserAgent = app_name;
  web_view.customUserAgent = custom;
  return 1;
}

int32_t omni_macos_web_view_add_user_script(const char *identity, const char *source, int32_t injection_time, int32_t main_frame_only) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view || !source) return 0;
  const char *sources[1] = { source };
  int32_t times[1] = { injection_time };
  int32_t frames[1] = { main_frame_only };
  NSArray<WKUserScript *> *scripts = omni_macos_web_view_make_user_scripts(sources, times, frames, 1);
  WKUserScript *script = scripts.firstObject;
  if (!script) return 0;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  [web_view.configuration.userContentController addUserScript:script];
  NSArray<WKUserScript *> *existing = (__bridge NSArray<WKUserScript *> *)data->user_scripts;
  omni_macos_web_view_replace_object(&data->user_scripts, [existing arrayByAddingObject:script]);
  return 1;
}

int32_t omni_macos_web_view_remove_all_user_scripts(const char *identity) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view) return 0;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  [web_view.configuration.userContentController removeAllUserScripts];
  omni_macos_web_view_replace_object(&data->user_scripts, @[]);
  return 1;
}

int32_t omni_macos_web_view_register_message_handler_named(const char *identity, const char *name) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view || !name || !name[0]) return 0;
  NSString *ns_name = [[NSString alloc] initWithUTF8String:name];
  omni_macos_web_view_register_message_handler(data, ns_name);
  NSArray<NSString *> *names = (__bridge NSArray<NSString *> *)data->message_handler_names;
  if (![names containsObject:ns_name]) {
    omni_macos_web_view_replace_object(&data->message_handler_names, [names arrayByAddingObject:ns_name]);
  }
  return 1;
}

int32_t omni_macos_web_view_unregister_message_handler_named(const char *identity, const char *name) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view || !name || !name[0]) return 0;
  NSString *ns_name = [[NSString alloc] initWithUTF8String:name];
  if (!ns_name) return 0;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  [web_view.configuration.userContentController removeScriptMessageHandlerForName:ns_name];
  NSMutableDictionary *handlers = (__bridge NSMutableDictionary *)data->message_handlers;
  [handlers removeObjectForKey:ns_name];
  NSArray<NSString *> *names = (__bridge NSArray<NSString *> *)data->message_handler_names;
  NSMutableArray<NSString *> *remaining = [names mutableCopy];
  [remaining removeObject:ns_name];
  omni_macos_web_view_replace_object(&data->message_handler_names, remaining);
  return 1;
}

int32_t omni_macos_web_view_add_content_rule(const char *identity, const char *identifier, const char *source) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view || !identifier || !source) return 0;
  NSString *ns_identifier = [[NSString alloc] initWithUTF8String:identifier];
  NSString *ns_source = [[NSString alloc] initWithUTF8String:source];
  if (!ns_identifier || !ns_source) return 0;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  NSDictionary<NSString *, NSString *> *entry = @{ @"identifier": ns_identifier, @"source": ns_source };
  NSArray<NSDictionary<NSString *, NSString *> *> *existing = (__bridge NSArray<NSDictionary<NSString *, NSString *> *> *)data->content_rules;
  NSMutableArray<NSDictionary<NSString *, NSString *> *> *rules = [existing mutableCopy] ?: [NSMutableArray array];
  NSIndexSet *matches = [rules indexesOfObjectsPassingTest:^BOOL(NSDictionary<NSString *, NSString *> *obj, NSUInteger idx, BOOL *stop) {
    (void)idx;
    BOOL match = [obj[@"identifier"] isEqualToString:ns_identifier];
    if (match) *stop = YES;
    return match;
  }];
  if (matches.count > 0) [rules removeObjectsAtIndexes:matches];
  [rules addObject:entry];
  omni_macos_web_view_replace_object(&data->content_rules, rules);
  [[WKContentRuleListStore defaultStore] compileContentRuleListForIdentifier:ns_identifier encodedContentRuleList:ns_source completionHandler:^(WKContentRuleList *ruleList, NSError *error) {
    (void)error;
    if (ruleList) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [web_view.configuration.userContentController addContentRuleList:ruleList];
        if (web_view.URL) [web_view reload];
      });
    }
  }];
  return 1;
}

int32_t omni_macos_web_view_remove_all_content_rules(const char *identity) {
  OmniMacosWebView *data = omni_macos_web_view_lookup(identity);
  if (!data || !data->web_view) return 0;
  WKWebView *web_view = (__bridge WKWebView *)data->web_view;
  [web_view.configuration.userContentController removeAllContentRuleLists];
  omni_macos_web_view_replace_object(&data->content_rules, @[]);
  return 1;
}

#endif
