#if defined(__APPLE__)

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

#include <gdk/macos/gdkmacos.h>
#include <gtk/gtk.h>
#include <math.h>
#include <stdlib.h>

extern gboolean omni_adw_app_handle_macos_text_input(void *app, const char *text);

typedef struct {
  GtkWidget *widget;
  void *container_view;
  void *native_view;
  void *web_view;
  void *navigation_delegate;
  void *url;
  gboolean owns_native_view;
  gboolean owns_web_view;
} OmniMacosWebView;

@interface OmniMacosWebViewContainer : NSView
@property(nonatomic, weak) NSView *embeddedView;
@property(nonatomic, weak) WKWebView *webView;
@property(nonatomic, assign) OmniMacosWebView *webViewData;
@end

@interface OmniMacosWebViewNavigationDelegate : NSObject <WKNavigationDelegate>
@property(nonatomic, assign) OmniMacosWebView *webViewData;
@end

static OmniMacosWebView *omni_active_web_view = NULL;
static BOOL omni_web_views_occluded_by_modal = NO;
static NSMutableSet<NSValue *> *omni_registered_web_views(void) {
  static NSMutableSet<NSValue *> *registry = nil;
  if (!registry) registry = [NSMutableSet set];
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
static OmniMacosWebView *omni_macos_web_view_under_pointer(void);
static OmniMacosWebView *omni_macos_single_visible_web_view(void);

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
  if (self.webViewData && self.webView) {
    CGFloat dx = event.scrollingDeltaX;
    CGFloat dy = event.scrollingDeltaY;
    if (!event.hasPreciseScrollingDeltas) {
      dx *= 14.0;
      dy *= 14.0;
    }
    omni_macos_web_view_scroll_by(self.webViewData, -dx, -dy);
  } else if (self.embeddedView) {
    [self.embeddedView scrollWheel:event];
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
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
  (void)webView;
  (void)navigation;
}
@end

static NSAppearance *omni_macos_web_view_effective_appearance(void) {
  NSAppearance *appearance = NSApp.effectiveAppearance ?: NSAppearance.currentDrawingAppearance;
  if (!appearance) appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
  return appearance;
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
  (void)gesture;
  (void)n_press;
  (void)x;
  (void)y;
  omni_macos_web_view_activate((OmniMacosWebView *)user_data);
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
  NSView *content_view = window.contentView;
  if (!content_view) return;

  graphene_rect_t bounds;
  if (!gtk_widget_compute_bounds(data->widget, GTK_WIDGET(root), &bounds)) return;

  CGFloat width = fmax(1.0, bounds.size.width);
  CGFloat height = fmax(1.0, bounds.size.height);
  CGFloat y = content_view.isFlipped ? bounds.origin.y : content_view.bounds.size.height - bounds.origin.y - height;
  NSRect frame = NSMakeRect(bounds.origin.x, y, width, height);
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
    configuration.applicationNameForUserAgent = @"Version/18.3 Safari/605.1.15";

    web_view = [[WKWebView alloc] initWithFrame:container_view.bounds configuration:configuration];
    native_view = web_view;
    web_view.allowsBackForwardNavigationGestures = YES;
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

    NSURL *ns_url = [NSURL URLWithString:url];
    if (ns_url) {
      [web_view loadRequest:[NSURLRequest requestWithURL:ns_url]];
    }
    data->native_view = (__bridge void *)native_view;
    data->web_view = (__bridge_retained void *)web_view;
    data->owns_native_view = FALSE;
    data->owns_web_view = TRUE;
  } else if (!web_view && [native_view isKindOfClass:[WKWebView class]]) {
    web_view = (WKWebView *)native_view;
    data->web_view = (__bridge void *)web_view;
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

  container_view.frame = frame;
  native_view.frame = container_view.bounds;
  native_view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  if (web_view) {
    NSAppearance *appearance = omni_macos_web_view_effective_appearance();
    web_view.appearance = appearance;
    [appearance performAsCurrentDrawingAppearance:^{
      web_view.underPageBackgroundColor = NSColor.windowBackgroundColor;
    }];
  }
  container_view.alphaValue = opacity;
  container_view.hidden = omni_web_views_occluded_by_modal || opacity <= 0.01 || width <= 1.0 || height <= 1.0;
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
  free(data);
}

GtkWidget *omni_macos_web_view_new(const char *url, void *native_view) {
  if (!url || !url[0]) return NULL;

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
  data->url = (__bridge_retained void *)[[NSString alloc] initWithUTF8String:url];
  if (native_view) {
    NSView *external_view = (__bridge NSView *)native_view;
    data->native_view = (__bridge_retained void *)external_view;
    data->owns_native_view = TRUE;
    if ([external_view isKindOfClass:[WKWebView class]]) {
      data->web_view = (__bridge void *)external_view;
      data->owns_web_view = FALSE;
    }
  }

  gtk_accessible_update_property(
    GTK_ACCESSIBLE(placeholder),
    GTK_ACCESSIBLE_PROPERTY_LABEL, url,
    GTK_ACCESSIBLE_PROPERTY_DESCRIPTION, "Web content",
    -1
  );
  g_object_set_data_full(G_OBJECT(placeholder), "omni-accessible-label", g_strdup(url), g_free);
  g_object_set_data_full(G_OBJECT(placeholder), "omni-accessible-description", g_strdup("Web content"), g_free);

  g_object_set_data_full(G_OBJECT(placeholder), "omni-macos-web-view", data, omni_macos_web_view_destroy);
  [omni_registered_web_views() addObject:[NSValue valueWithPointer:data]];
  GtkEventController *scroll_controller = gtk_event_controller_scroll_new(
    GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES | GTK_EVENT_CONTROLLER_SCROLL_KINETIC
  );
  g_signal_connect(scroll_controller, "scroll", G_CALLBACK(omni_macos_web_view_gtk_scroll), data);
  gtk_widget_add_controller(placeholder, scroll_controller);

  GtkGesture *click_controller = gtk_gesture_click_new();
  g_signal_connect(click_controller, "pressed", G_CALLBACK(omni_macos_web_view_gtk_pressed), data);
  gtk_widget_add_controller(placeholder, GTK_EVENT_CONTROLLER(click_controller));
  gtk_widget_add_tick_callback(placeholder, omni_macos_web_view_tick, data, NULL);
  g_signal_connect(placeholder, "map", G_CALLBACK(omni_macos_web_view_mapped), data);
  g_signal_connect(placeholder, "unmap", G_CALLBACK(omni_macos_web_view_unmapped), data);

  return placeholder;
}

#endif
