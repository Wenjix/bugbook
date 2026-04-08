#import "BBChromiumBridge.h"

#import <dispatch/dispatch.h>
#import <math.h>

#include <atomic>
#include <limits.h>

#include "include/capi/cef_app_capi.h"
#include "include/cef_api_hash.h"
#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_devtools_message_observer_capi.h"
#include "include/capi/cef_download_handler_capi.h"
#include "include/capi/cef_download_item_capi.h"
#include "include/capi/cef_find_handler_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_life_span_handler_capi.h"
#include "include/capi/cef_load_handler_capi.h"
#include "include/capi/cef_request_context_capi.h"
#include "include/capi/cef_values_capi.h"
#include "include/cef_application_mac.h"
#include "include/cef_version.h"
#include "include/internal/cef_string.h"
#include "include/internal/cef_types.h"

@implementation BBChromiumPageState
@end

@class BBChromiumPage;

@interface BBPendingJavaScriptEvaluation : NSObject
@property(nonatomic, copy) void (^completion)(NSString *_Nullable result, NSError *_Nullable error);
@end

@implementation BBPendingJavaScriptEvaluation
@end

@interface BBChromiumHostContainerView : NSView
@property(nonatomic, weak) BBChromiumPage *page;
@end

@interface BBChromiumApplication : NSApplication <CefAppProtocol> {
@private
    BOOL handlingSendEvent_;
}
@end

@interface BBChromiumMessagePumpEventHandler : NSObject
- (void)scheduleWork:(NSNumber *)delayMS;
- (void)timerTimeout:(NSTimer *)timer;
@end

@implementation BBChromiumApplication

- (BOOL)isHandlingSendEvent {
    return handlingSendEvent_;
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
    handlingSendEvent_ = handlingSendEvent;
}

- (void)sendEvent:(NSEvent *)event {
    CefScopedSendingEvent sendingEventScoper;
    [super sendEvent:event];
}

@end

static NSTimer *BBChromiumMessagePumpTimer;
static NSThread *BBChromiumMessagePumpOwnerThread;
static BBChromiumMessagePumpEventHandler *BBChromiumMessagePumpEventHandlerShared;
static void BBChromiumHandleScheduledMessagePumpWork(int64_t delay_ms);
static void BBChromiumPerformMessagePumpWork(void);
static void BBChromiumInvalidateMessagePumpTimer(void);

@implementation BBChromiumMessagePumpEventHandler

- (void)scheduleWork:(NSNumber *)delayMS {
    BBChromiumHandleScheduledMessagePumpWork(delayMS.longLongValue);
}

- (void)timerTimeout:(NSTimer *)timer {
    if (timer != BBChromiumMessagePumpTimer) {
        return;
    }

    BBChromiumInvalidateMessagePumpTimer();
    BBChromiumPerformMessagePumpWork();
}

@end

static cef_request_context_t *BBChromiumSharedRequestContext = nullptr;
static BOOL BBChromiumDidInitialize = NO;
static BOOL BBChromiumMessagePumpActive = NO;
static BOOL BBChromiumMessagePumpReentrancyDetected = NO;
static struct BBChromiumAppWrapper *BBChromiumApp = nullptr;
static struct BBChromiumBrowserProcessHandlerWrapper *BBChromiumBrowserProcessHandler = nullptr;

static constexpr double BBChromiumZoomBase = 1.2;
static constexpr int64_t BBChromiumMessagePumpPlaceholderDelay = INT_MAX;
static constexpr int64_t BBChromiumMessagePumpMaxDelayMS = 1000 / 30;

static void BBChromiumEnsureMessagePumpHandler(void);
static void BBChromiumInvalidateMessagePumpTimer(void);
static void BBChromiumScheduleMessagePumpWork(int64_t delay_ms);
static void BBChromiumPerformMessagePumpWork(void);
static void BBChromiumEnsureApplicationHandlers(void);

static NSURL *BBChromiumFirstDirectoryURL(NSSearchPathDirectory searchPathDirectory) {
    NSURL *directoryURL = [[[NSFileManager defaultManager] URLsForDirectory:searchPathDirectory inDomains:NSUserDomainMask] firstObject];
    return directoryURL ?: NSFileManager.defaultManager.temporaryDirectory;
}

static void BBChromiumCreateDirectoryIfNeeded(NSString *path) {
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
}

static NSString *BBChromiumStringFromCef(const cef_string_t *string) {
    if (!string || !string->str || string->length == 0) {
        return @"";
    }
    return [[NSString alloc] initWithCharacters:(const unichar *)string->str length:string->length];
}

static NSString *BBChromiumStringFromUserFree(cef_string_userfree_t string) {
    if (!string) {
        return @"";
    }
    NSString *value = BBChromiumStringFromCef(string);
    cef_string_userfree_free(string);
    return value;
}

static cef_string_t BBChromiumCefString(NSString *string) {
    cef_string_t value = {};
    if (string.length > 0) {
        cef_string_from_utf8(string.UTF8String, [string lengthOfBytesUsingEncoding:NSUTF8StringEncoding], &value);
    }
    return value;
}

static void BBChromiumReleaseRefCounted(cef_base_ref_counted_t *base) {
    if (base && base->release) {
        base->release(base);
    }
}

static NSError *BBChromiumError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:@"ChromiumBridge"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description ?: @"Chromium bridge error."}];
}

static NSString *BBChromiumDownloadsDirectory(void) {
    return BBChromiumFirstDirectoryURL(NSDownloadsDirectory).path;
}

static NSString *BBChromiumApplicationSupportPath(void) {
    NSURL *directory = BBChromiumFirstDirectoryURL(NSApplicationSupportDirectory);
    return [[directory URLByAppendingPathComponent:@"Bugbook/Chromium" isDirectory:YES] path];
}

static NSString *BBChromiumRootCachePath(void) {
    return [BBChromiumApplicationSupportPath() stringByAppendingPathComponent:@"Profiles"];
}

static NSString *BBChromiumCachePath(void) {
    return [BBChromiumRootCachePath() stringByAppendingPathComponent:@"Default"];
}

static NSArray<NSString *> *BBChromiumAdditionalArguments(void) {
    static NSArray<NSString *> *arguments = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // On recent macOS builds, --disable-gpu still leaves Chromium's display
        // compositor in a GPU process, which is what reaches the fatal fallback.
        // Force the GL stack onto SwiftShader instead of relying on GPU disable
        // fallback modes.
        arguments = @[
            @"--use-gl=angle",
            @"--use-angle=swiftshader",
            @"--enable-unsafe-swiftshader",
        ];
    });
    return arguments;
}

static cef_main_args_t BBChromiumMainArgsWithStorage(NSMutableArray<NSData *> *storage) {
    NSMutableArray<NSString *> *arguments = [NSProcessInfo.processInfo.arguments mutableCopy];
    for (NSString *argument in BBChromiumAdditionalArguments()) {
        if (![arguments containsObject:argument]) {
            [arguments addObject:argument];
        }
    }
    cef_main_args_t mainArgs = {};
    mainArgs.argc = (int)arguments.count;

    char **argv = (char **)calloc(arguments.count, sizeof(char *));
    for (NSUInteger index = 0; index < arguments.count; index += 1) {
        NSData *data = [arguments[index] dataUsingEncoding:NSUTF8StringEncoding];
        [storage addObject:data];
        argv[index] = strdup((const char *)data.bytes);
    }
    mainArgs.argv = argv;
    return mainArgs;
}

static void BBChromiumFreeMainArgs(cef_main_args_t mainArgs) {
    if (!mainArgs.argv) {
        return;
    }
    for (int index = 0; index < mainArgs.argc; index += 1) {
        free(mainArgs.argv[index]);
    }
    free(mainArgs.argv);
}

static double BBChromiumZoomLevelFromPageZoom(double pageZoom) {
    double normalizedZoom = pageZoom > 0.01 ? pageZoom : 1.0;
    return log(normalizedZoom) / log(BBChromiumZoomBase);
}

static double BBChromiumPageZoomFromLevel(double zoomLevel) {
    return pow(BBChromiumZoomBase, zoomLevel);
}

template <typename Wrapper>
static void CEF_CALLBACK BBChromiumAddRef(cef_base_ref_counted_t *base) {
    auto *wrapper = reinterpret_cast<Wrapper *>(base);
    wrapper->refCount.fetch_add(1, std::memory_order_relaxed);
}

template <typename Wrapper>
static int CEF_CALLBACK BBChromiumRelease(cef_base_ref_counted_t *base) {
    auto *wrapper = reinterpret_cast<Wrapper *>(base);
    if (wrapper->refCount.fetch_sub(1, std::memory_order_acq_rel) == 1) {
        delete wrapper;
        return 1;
    }
    return 0;
}

template <typename Wrapper>
static int CEF_CALLBACK BBChromiumHasOneRef(cef_base_ref_counted_t *base) {
    auto *wrapper = reinterpret_cast<Wrapper *>(base);
    return wrapper->refCount.load(std::memory_order_acquire) == 1;
}

template <typename Wrapper>
static int CEF_CALLBACK BBChromiumHasAtLeastOneRef(cef_base_ref_counted_t *base) {
    auto *wrapper = reinterpret_cast<Wrapper *>(base);
    return wrapper->refCount.load(std::memory_order_acquire) >= 1;
}

template <typename Wrapper, typename API>
static void BBChromiumInitializeBase(API *api) {
    api->base.size = sizeof(API);
    api->base.add_ref = BBChromiumAddRef<Wrapper>;
    api->base.release = BBChromiumRelease<Wrapper>;
    api->base.has_one_ref = BBChromiumHasOneRef<Wrapper>;
    api->base.has_at_least_one_ref = BBChromiumHasAtLeastOneRef<Wrapper>;
}

struct BBChromiumClientWrapper {
    cef_client_t client;
    std::atomic<int> refCount{1};
    __unsafe_unretained BBChromiumPage *page = nil;
};

struct BBChromiumBrowserProcessHandlerWrapper {
    cef_browser_process_handler_t handler;
    std::atomic<int> refCount{1};
};

struct BBChromiumAppWrapper {
    cef_app_t app;
    std::atomic<int> refCount{1};
    BBChromiumBrowserProcessHandlerWrapper *browserProcessHandler = nullptr;
};

struct BBChromiumDisplayHandlerWrapper {
    cef_display_handler_t handler;
    std::atomic<int> refCount{1};
    __unsafe_unretained BBChromiumPage *page = nil;
};

struct BBChromiumLoadHandlerWrapper {
    cef_load_handler_t handler;
    std::atomic<int> refCount{1};
    __unsafe_unretained BBChromiumPage *page = nil;
};

struct BBChromiumLifeSpanHandlerWrapper {
    cef_life_span_handler_t handler;
    std::atomic<int> refCount{1};
    __unsafe_unretained BBChromiumPage *page = nil;
};

struct BBChromiumDownloadHandlerWrapper {
    cef_download_handler_t handler;
    std::atomic<int> refCount{1};
    __unsafe_unretained BBChromiumPage *page = nil;
};

struct BBChromiumFindHandlerWrapper {
    cef_find_handler_t handler;
    std::atomic<int> refCount{1};
    __unsafe_unretained BBChromiumPage *page = nil;
};

struct BBChromiumDevToolsObserverWrapper {
    cef_dev_tools_message_observer_t observer;
    std::atomic<int> refCount{1};
    __unsafe_unretained BBChromiumPage *page = nil;
};

template <typename API>
static API *BBChromiumRetainAPI(API *api) {
    if (api && api->base.add_ref) {
        api->base.add_ref(&api->base);
    }
    return api;
}

static void BBChromiumEnsureMessagePumpHandler(void) {
    if (BBChromiumMessagePumpEventHandlerShared) {
        return;
    }

    BBChromiumMessagePumpOwnerThread = NSThread.currentThread;
    BBChromiumMessagePumpEventHandlerShared = [BBChromiumMessagePumpEventHandler new];
}

static void BBChromiumHandleScheduledMessagePumpWork(int64_t delay_ms) {
    if (delay_ms == BBChromiumMessagePumpPlaceholderDelay && BBChromiumMessagePumpTimer) {
        return;
    }

    BBChromiumInvalidateMessagePumpTimer();

    if (delay_ms <= 0) {
        BBChromiumPerformMessagePumpWork();
        return;
    }

    if (delay_ms > BBChromiumMessagePumpMaxDelayMS) {
        delay_ms = BBChromiumMessagePumpMaxDelayMS;
    }

    NSTimer *timer = [NSTimer timerWithTimeInterval:(NSTimeInterval)delay_ms / 1000.0
                                             target:BBChromiumMessagePumpEventHandlerShared
                                           selector:@selector(timerTimeout:)
                                           userInfo:nil
                                            repeats:NO];
    BBChromiumMessagePumpTimer = timer;

    NSRunLoop *runLoop = NSRunLoop.currentRunLoop;
    [runLoop addTimer:timer forMode:NSRunLoopCommonModes];
    [runLoop addTimer:timer forMode:NSEventTrackingRunLoopMode];
}

static void BBChromiumScheduleMessagePumpWork(int64_t delay_ms) {
    if (!BBChromiumMessagePumpEventHandlerShared || !BBChromiumMessagePumpOwnerThread) {
        return;
    }

    NSNumber *delayNumber = [NSNumber numberWithLongLong:delay_ms];
    [BBChromiumMessagePumpEventHandlerShared performSelector:@selector(scheduleWork:)
                                                    onThread:BBChromiumMessagePumpOwnerThread
                                                  withObject:delayNumber
                                               waitUntilDone:NO];
}

static void BBChromiumPerformMessagePumpWork(void) {
    if (!BBChromiumDidInitialize) {
        return;
    }

    if (BBChromiumMessagePumpActive) {
        BBChromiumMessagePumpReentrancyDetected = YES;
        return;
    }

    BBChromiumMessagePumpReentrancyDetected = NO;
    BBChromiumMessagePumpActive = YES;
    cef_do_message_loop_work();
    BBChromiumMessagePumpActive = NO;

    if (BBChromiumMessagePumpReentrancyDetected) {
        BBChromiumScheduleMessagePumpWork(0);
    } else if (!BBChromiumMessagePumpTimer) {
        BBChromiumScheduleMessagePumpWork(BBChromiumMessagePumpPlaceholderDelay);
    }
}

static void BBChromiumInvalidateMessagePumpTimer(void) {
    if (!BBChromiumMessagePumpTimer) {
        return;
    }

    [BBChromiumMessagePumpTimer invalidate];
    BBChromiumMessagePumpTimer = nil;
}

@interface BBChromiumRuntime ()
+ (cef_request_context_t *)sharedRequestContext;
@end

@interface BBChromiumPage ()
@property(nonatomic, strong) BBChromiumHostContainerView *hostContainerView;
@property(nonatomic, strong) NSView *browserView;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BBPendingJavaScriptEvaluation *> *pendingJavaScriptEvaluations;
@property(nonatomic, copy, nullable) NSString *pendingURLString;
@property(nonatomic, copy, nullable) NSString *currentURLString;
@property(nonatomic, copy, nullable) NSString *currentTitle;
@property(nonatomic, copy, nullable) NSString *lastFindQuery;
@property(nonatomic, assign) BOOL isLoading;
@property(nonatomic, assign) double estimatedProgress;
@property(nonatomic, assign) BOOL canGoBack;
@property(nonatomic, assign) BOOL canGoForward;
@property(nonatomic, assign) double pageZoom;
@property(nonatomic, assign) BOOL browserCreationAttempted;
@property(nonatomic, assign) BOOL disposed;
@property(nonatomic, assign) int nextDevToolsMessageID;
@property(nonatomic, assign) cef_browser_t *browser;
@property(nonatomic, assign) cef_browser_host_t *browserHost;
@property(nonatomic, assign) cef_registration_t *devToolsRegistration;
@property(nonatomic, assign) BBChromiumClientWrapper *clientWrapper;
@property(nonatomic, assign) BBChromiumDisplayHandlerWrapper *displayHandlerWrapper;
@property(nonatomic, assign) BBChromiumLoadHandlerWrapper *loadHandlerWrapper;
@property(nonatomic, assign) BBChromiumLifeSpanHandlerWrapper *lifeSpanHandlerWrapper;
@property(nonatomic, assign) BBChromiumDownloadHandlerWrapper *downloadHandlerWrapper;
@property(nonatomic, assign) BBChromiumFindHandlerWrapper *findHandlerWrapper;
@property(nonatomic, assign) BBChromiumDevToolsObserverWrapper *devToolsObserverWrapper;
- (void)ensureBrowserCreatedIfPossible;
- (void)handleAddressChange:(NSString *)urlString browser:(cef_browser_t *)browser;
- (void)handleTitleChange:(NSString *)title browser:(cef_browser_t *)browser;
- (void)handleStatusMessage:(NSString *)status;
- (void)handleProgressChange:(double)progress browser:(cef_browser_t *)browser;
- (void)handleLoadingStateChange:(BOOL)isLoading
                       canGoBack:(BOOL)canGoBack
                    canGoForward:(BOOL)canGoForward
                         browser:(cef_browser_t *)browser;
- (void)handleLoadFinishedForBrowser:(cef_browser_t *)browser;
- (void)handlePopupURL:(NSString *)urlString;
- (void)handleDownloadStatus:(NSString *)status;
- (void)handleAfterCreatedBrowser:(cef_browser_t *)browser;
- (void)handleBrowserBeforeClose;
- (void)notifyNavigationFinishedIfReady;
- (void)handleDevToolsMethodResultForMessageID:(int)messageID success:(BOOL)success data:(NSData *)data;
- (void)failPendingJavaScriptEvaluationsWithError:(NSError *)error;
@end

@implementation BBChromiumRuntime

+ (void)startIfNeeded {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        (void)cef_api_hash(CEF_API_VERSION, 0);
        BBChromiumEnsureMessagePumpHandler();
        NSMutableArray<NSData *> *storage = [NSMutableArray array];
        cef_main_args_t mainArgs = BBChromiumMainArgsWithStorage(storage);
        BBChromiumEnsureApplicationHandlers();

        NSString *cachePath = BBChromiumCachePath();
        NSString *rootCachePath = BBChromiumRootCachePath();
        BBChromiumCreateDirectoryIfNeeded(cachePath);
        BBChromiumCreateDirectoryIfNeeded(rootCachePath);

        NSBundle *mainBundle = NSBundle.mainBundle;
        NSString *frameworkPath = [mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"Chromium Embedded Framework.framework"];
        NSString *resourcesPath = [frameworkPath stringByAppendingPathComponent:@"Resources"];
        NSString *localesPath = resourcesPath;

        cef_settings_t settings = {};
        settings.size = sizeof(settings);
        settings.no_sandbox = 1;
        settings.persist_session_cookies = 1;
        settings.external_message_pump = 1;
        settings.log_severity = LOGSEVERITY_DISABLE;
        settings.framework_dir_path = BBChromiumCefString(frameworkPath);
        settings.main_bundle_path = BBChromiumCefString(mainBundle.bundlePath);
        settings.resources_dir_path = BBChromiumCefString(resourcesPath);
        settings.locales_dir_path = BBChromiumCefString(localesPath);
        settings.cache_path = BBChromiumCefString(cachePath);
        settings.root_cache_path = BBChromiumCefString(rootCachePath);

        BBChromiumDidInitialize = cef_initialize(&mainArgs, &settings, &BBChromiumApp->app, nullptr);
        if (BBChromiumDidInitialize) {
            BBChromiumScheduleMessagePumpWork(0);
            [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationWillTerminateNotification
                                                              object:nil
                                                               queue:nil
                                                          usingBlock:^(__unused NSNotification *notification) {
                BBChromiumInvalidateMessagePumpTimer();
                if (BBChromiumSharedRequestContext) {
                    BBChromiumReleaseRefCounted(&BBChromiumSharedRequestContext->base.base);
                    BBChromiumSharedRequestContext = nullptr;
                }
                if (BBChromiumDidInitialize) {
                    cef_shutdown();
                    BBChromiumDidInitialize = NO;
                }
                if (BBChromiumApp) {
                    BBChromiumReleaseRefCounted(&BBChromiumApp->app.base);
                    BBChromiumApp = nullptr;
                }
                if (BBChromiumBrowserProcessHandler) {
                    BBChromiumReleaseRefCounted(&BBChromiumBrowserProcessHandler->handler.base);
                    BBChromiumBrowserProcessHandler = nullptr;
                }
                BBChromiumMessagePumpEventHandlerShared = nil;
                BBChromiumMessagePumpOwnerThread = nil;
            }];
        } else {
            NSLog(@"[ChromiumBridge] Failed to initialize CEF runtime.");
            if (BBChromiumApp) {
                BBChromiumReleaseRefCounted(&BBChromiumApp->app.base);
                BBChromiumApp = nullptr;
            }
            if (BBChromiumBrowserProcessHandler) {
                BBChromiumReleaseRefCounted(&BBChromiumBrowserProcessHandler->handler.base);
                BBChromiumBrowserProcessHandler = nullptr;
            }
            BBChromiumMessagePumpEventHandlerShared = nil;
            BBChromiumMessagePumpOwnerThread = nil;
        }
        BBChromiumFreeMainArgs(mainArgs);
    });
}

+ (NSString *)runtimeDescription {
    return [NSString stringWithFormat:@"CEF %s", CEF_VERSION];
}

+ (cef_request_context_t *)sharedRequestContext {
    [self startIfNeeded];
    if (!BBChromiumDidInitialize || BBChromiumSharedRequestContext) {
        return BBChromiumSharedRequestContext;
    }

    cef_request_context_settings_t contextSettings = {};
    contextSettings.size = sizeof(contextSettings);
    contextSettings.persist_session_cookies = 1;

    cef_string_t cachePath = BBChromiumCefString(BBChromiumCachePath());
    contextSettings.cache_path = cachePath;
    BBChromiumSharedRequestContext = cef_request_context_create_context(&contextSettings, nullptr);
    cef_string_clear(&cachePath);

    return BBChromiumSharedRequestContext;
}

@end

@implementation BBChromiumHostContainerView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) {
        return nil;
    }
    self.wantsLayer = YES;
    self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
    return self;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self.page ensureBrowserCreatedIfPossible];
}

- (void)layout {
    [super layout];
    self.page.browserView.frame = self.bounds;
}

@end

static BBChromiumClientWrapper *BBChromiumClientFrom(cef_client_t *client) {
    return reinterpret_cast<BBChromiumClientWrapper *>(client);
}

static BBChromiumAppWrapper *BBChromiumAppFrom(cef_app_t *app) {
    return reinterpret_cast<BBChromiumAppWrapper *>(app);
}

static BBChromiumBrowserProcessHandlerWrapper *BBChromiumBrowserProcessHandlerFrom(cef_browser_process_handler_t *handler) {
    return reinterpret_cast<BBChromiumBrowserProcessHandlerWrapper *>(handler);
}

static BBChromiumDisplayHandlerWrapper *BBChromiumDisplayHandlerFrom(cef_display_handler_t *handler) {
    return reinterpret_cast<BBChromiumDisplayHandlerWrapper *>(handler);
}

static BBChromiumLoadHandlerWrapper *BBChromiumLoadHandlerFrom(cef_load_handler_t *handler) {
    return reinterpret_cast<BBChromiumLoadHandlerWrapper *>(handler);
}

static BBChromiumLifeSpanHandlerWrapper *BBChromiumLifeSpanHandlerFrom(cef_life_span_handler_t *handler) {
    return reinterpret_cast<BBChromiumLifeSpanHandlerWrapper *>(handler);
}

static BBChromiumDownloadHandlerWrapper *BBChromiumDownloadHandlerFrom(cef_download_handler_t *handler) {
    return reinterpret_cast<BBChromiumDownloadHandlerWrapper *>(handler);
}

static BBChromiumFindHandlerWrapper *BBChromiumFindHandlerFrom(cef_find_handler_t *handler) {
    return reinterpret_cast<BBChromiumFindHandlerWrapper *>(handler);
}

static BBChromiumDevToolsObserverWrapper *BBChromiumDevToolsObserverFrom(cef_dev_tools_message_observer_t *observer) {
    return reinterpret_cast<BBChromiumDevToolsObserverWrapper *>(observer);
}

static void CEF_CALLBACK BBChromiumOnScheduleMessagePumpWork(cef_browser_process_handler_t *handler,
                                                             int64_t delay_ms) {
    __unused BBChromiumBrowserProcessHandlerWrapper *wrapper = BBChromiumBrowserProcessHandlerFrom(handler);
    BBChromiumScheduleMessagePumpWork(delay_ms);
}

static cef_browser_process_handler_t *CEF_CALLBACK BBChromiumGetBrowserProcessHandler(cef_app_t *app) {
    BBChromiumAppWrapper *wrapper = BBChromiumAppFrom(app);
    return wrapper->browserProcessHandler
        ? BBChromiumRetainAPI(&wrapper->browserProcessHandler->handler)
        : nullptr;
}

static void BBChromiumEnsureApplicationHandlers(void) {
    if (BBChromiumApp && BBChromiumBrowserProcessHandler) {
        return;
    }

    BBChromiumBrowserProcessHandler = new BBChromiumBrowserProcessHandlerWrapper();
    BBChromiumInitializeBase<BBChromiumBrowserProcessHandlerWrapper>(&BBChromiumBrowserProcessHandler->handler);
    BBChromiumBrowserProcessHandler->handler.on_schedule_message_pump_work = BBChromiumOnScheduleMessagePumpWork;

    BBChromiumApp = new BBChromiumAppWrapper();
    BBChromiumInitializeBase<BBChromiumAppWrapper>(&BBChromiumApp->app);
    BBChromiumApp->app.get_browser_process_handler = BBChromiumGetBrowserProcessHandler;
    BBChromiumApp->browserProcessHandler = BBChromiumBrowserProcessHandler;
}

static cef_display_handler_t *CEF_CALLBACK BBChromiumGetDisplayHandler(cef_client_t *client) {
    BBChromiumClientWrapper *wrapper = BBChromiumClientFrom(client);
    return wrapper->page && wrapper->page.displayHandlerWrapper
        ? BBChromiumRetainAPI(&wrapper->page.displayHandlerWrapper->handler)
        : nullptr;
}

static cef_load_handler_t *CEF_CALLBACK BBChromiumGetLoadHandler(cef_client_t *client) {
    BBChromiumClientWrapper *wrapper = BBChromiumClientFrom(client);
    return wrapper->page && wrapper->page.loadHandlerWrapper
        ? BBChromiumRetainAPI(&wrapper->page.loadHandlerWrapper->handler)
        : nullptr;
}

static cef_life_span_handler_t *CEF_CALLBACK BBChromiumGetLifeSpanHandler(cef_client_t *client) {
    BBChromiumClientWrapper *wrapper = BBChromiumClientFrom(client);
    return wrapper->page && wrapper->page.lifeSpanHandlerWrapper
        ? BBChromiumRetainAPI(&wrapper->page.lifeSpanHandlerWrapper->handler)
        : nullptr;
}

static cef_download_handler_t *CEF_CALLBACK BBChromiumGetDownloadHandler(cef_client_t *client) {
    BBChromiumClientWrapper *wrapper = BBChromiumClientFrom(client);
    return wrapper->page && wrapper->page.downloadHandlerWrapper
        ? BBChromiumRetainAPI(&wrapper->page.downloadHandlerWrapper->handler)
        : nullptr;
}

static cef_find_handler_t *CEF_CALLBACK BBChromiumGetFindHandler(cef_client_t *client) {
    BBChromiumClientWrapper *wrapper = BBChromiumClientFrom(client);
    return wrapper->page && wrapper->page.findHandlerWrapper
        ? BBChromiumRetainAPI(&wrapper->page.findHandlerWrapper->handler)
        : nullptr;
}

static void CEF_CALLBACK BBChromiumOnAddressChange(cef_display_handler_t *handler,
                                                   cef_browser_t *browser,
                                                   cef_frame_t *frame,
                                                   const cef_string_t *url) {
    BBChromiumPage *page = BBChromiumDisplayHandlerFrom(handler)->page;
    if (!page || !frame || !frame->is_main(frame)) {
        return;
    }
    [page handleAddressChange:BBChromiumStringFromCef(url) browser:browser];
}

static void CEF_CALLBACK BBChromiumOnTitleChange(cef_display_handler_t *handler,
                                                 cef_browser_t *browser,
                                                 const cef_string_t *title) {
    BBChromiumPage *page = BBChromiumDisplayHandlerFrom(handler)->page;
    [page handleTitleChange:BBChromiumStringFromCef(title) browser:browser];
}

static void CEF_CALLBACK BBChromiumOnStatusMessage(cef_display_handler_t *handler,
                                                   __unused cef_browser_t *browser,
                                                   const cef_string_t *value) {
    BBChromiumPage *page = BBChromiumDisplayHandlerFrom(handler)->page;
    [page handleStatusMessage:BBChromiumStringFromCef(value)];
}

static void CEF_CALLBACK BBChromiumOnLoadingProgressChange(cef_display_handler_t *handler,
                                                           cef_browser_t *browser,
                                                           double progress) {
    BBChromiumPage *page = BBChromiumDisplayHandlerFrom(handler)->page;
    [page handleProgressChange:progress browser:browser];
}

static void CEF_CALLBACK BBChromiumOnLoadingStateChange(cef_load_handler_t *handler,
                                                        cef_browser_t *browser,
                                                        int isLoading,
                                                        int canGoBack,
                                                        int canGoForward) {
    BBChromiumPage *page = BBChromiumLoadHandlerFrom(handler)->page;
    [page handleLoadingStateChange:isLoading != 0
                         canGoBack:canGoBack != 0
                      canGoForward:canGoForward != 0
                           browser:browser];
}

static void CEF_CALLBACK BBChromiumOnLoadEnd(cef_load_handler_t *handler,
                                             cef_browser_t *browser,
                                             cef_frame_t *frame,
                                             __unused int httpStatusCode) {
    BBChromiumPage *page = BBChromiumLoadHandlerFrom(handler)->page;
    if (!page || !frame || !frame->is_main(frame)) {
        return;
    }
    [page handleLoadFinishedForBrowser:browser];
}

static void CEF_CALLBACK BBChromiumOnLoadError(cef_load_handler_t *handler,
                                               __unused cef_browser_t *browser,
                                               cef_frame_t *frame,
                                               __unused cef_errorcode_t errorCode,
                                               const cef_string_t *errorText,
                                               const cef_string_t *failedUrl) {
    BBChromiumPage *page = BBChromiumLoadHandlerFrom(handler)->page;
    if (!page || !frame || !frame->is_main(frame)) {
        return;
    }
    NSString *message = BBChromiumStringFromCef(errorText);
    NSString *failedURL = BBChromiumStringFromCef(failedUrl);
    [page handleDownloadStatus:[NSString stringWithFormat:@"%@ (%@)", message, failedURL]];
}

static int CEF_CALLBACK BBChromiumOnBeforePopup(cef_life_span_handler_t *handler,
                                                __unused cef_browser_t *browser,
                                                __unused cef_frame_t *frame,
                                                __unused int popup_id,
                                                const cef_string_t *target_url,
                                                __unused const cef_string_t *target_frame_name,
                                                __unused cef_window_open_disposition_t target_disposition,
                                                __unused int user_gesture,
                                                __unused const cef_popup_features_t *popupFeatures,
                                                __unused cef_window_info_t *windowInfo,
                                                __unused cef_client_t **client,
                                                __unused cef_browser_settings_t *settings,
                                                __unused cef_dictionary_value_t **extra_info,
                                                __unused int *no_javascript_access) {
    BBChromiumPage *page = BBChromiumLifeSpanHandlerFrom(handler)->page;
    [page handlePopupURL:BBChromiumStringFromCef(target_url)];
    return 1;
}

static void CEF_CALLBACK BBChromiumOnAfterCreated(cef_life_span_handler_t *handler,
                                                  cef_browser_t *browser) {
    BBChromiumPage *page = BBChromiumLifeSpanHandlerFrom(handler)->page;
    [page handleAfterCreatedBrowser:browser];
}

static void CEF_CALLBACK BBChromiumOnBeforeClose(cef_life_span_handler_t *handler,
                                                 __unused cef_browser_t *browser) {
    BBChromiumPage *page = BBChromiumLifeSpanHandlerFrom(handler)->page;
    [page handleBrowserBeforeClose];
}

static int CEF_CALLBACK BBChromiumCanDownload(cef_download_handler_t *handler,
                                              __unused cef_browser_t *browser,
                                              __unused const cef_string_t *url,
                                              __unused const cef_string_t *request_method) {
    return BBChromiumDownloadHandlerFrom(handler)->page != nil;
}

static int CEF_CALLBACK BBChromiumOnBeforeDownload(cef_download_handler_t *handler,
                                                   __unused cef_browser_t *browser,
                                                   __unused cef_download_item_t *download_item,
                                                   const cef_string_t *suggested_name,
                                                   cef_before_download_callback_t *callback) {
    BBChromiumPage *page = BBChromiumDownloadHandlerFrom(handler)->page;
    if (!page || !callback) {
        return 0;
    }

    NSString *suggestedName = BBChromiumStringFromCef(suggested_name);
    if (suggestedName.length == 0) {
        suggestedName = @"download";
    }
    NSString *destination = [BBChromiumDownloadsDirectory() stringByAppendingPathComponent:suggestedName];
    cef_string_t downloadPath = BBChromiumCefString(destination);
    callback->cont(callback, &downloadPath, 0);
    cef_string_clear(&downloadPath);
    [page handleDownloadStatus:[NSString stringWithFormat:@"Downloading %@…", suggestedName]];
    return 1;
}

static void CEF_CALLBACK BBChromiumOnDownloadUpdated(cef_download_handler_t *handler,
                                                     __unused cef_browser_t *browser,
                                                     cef_download_item_t *download_item,
                                                     __unused cef_download_item_callback_t *callback) {
    BBChromiumPage *page = BBChromiumDownloadHandlerFrom(handler)->page;
    if (!page || !download_item || !download_item->is_valid(download_item)) {
        return;
    }

    if (download_item->is_complete(download_item)) {
        [page handleDownloadStatus:@"Download finished"];
        return;
    }
    if (download_item->is_canceled(download_item) || download_item->is_interrupted(download_item)) {
        [page handleDownloadStatus:@"Download failed"];
        return;
    }

    NSString *fileName = BBChromiumStringFromUserFree(download_item->get_suggested_file_name(download_item));
    int percentComplete = download_item->get_percent_complete(download_item);
    if (fileName.length == 0) {
        fileName = @"download";
    }
    if (percentComplete >= 0) {
        [page handleDownloadStatus:[NSString stringWithFormat:@"Downloading %@ (%d%%)…", fileName, percentComplete]];
    }
}

static void CEF_CALLBACK BBChromiumOnFindResult(cef_find_handler_t *handler,
                                                __unused cef_browser_t *browser,
                                                __unused int identifier,
                                                int count,
                                                __unused const cef_rect_t *selectionRect,
                                                int activeMatchOrdinal,
                                                int finalUpdate) {
    BBChromiumPage *page = BBChromiumFindHandlerFrom(handler)->page;
    if (!page || !finalUpdate) {
        return;
    }
    if (count > 0) {
        [page handleDownloadStatus:[NSString stringWithFormat:@"Found %@ of %@", @(activeMatchOrdinal), @(count)]];
    }
}

static void CEF_CALLBACK BBChromiumOnDevToolsMethodResult(cef_dev_tools_message_observer_t *observer,
                                                          __unused cef_browser_t *browser,
                                                          int message_id,
                                                          int success,
                                                          const void *result,
                                                          size_t result_size) {
    BBChromiumPage *page = BBChromiumDevToolsObserverFrom(observer)->page;
    if (!page) {
        return;
    }
    NSData *data = result && result_size > 0 ? [NSData dataWithBytes:result length:result_size] : nil;
    [page handleDevToolsMethodResultForMessageID:message_id success:success != 0 data:data];
}

static void CEF_CALLBACK BBChromiumOnDevToolsAgentDetached(cef_dev_tools_message_observer_t *observer,
                                                           __unused cef_browser_t *browser) {
    BBChromiumPage *page = BBChromiumDevToolsObserverFrom(observer)->page;
    [page failPendingJavaScriptEvaluationsWithError:BBChromiumError(5, @"Chromium DevTools agent detached.")];
}

@implementation BBChromiumPage

- (instancetype)initWithInitialURLString:(nullable NSString *)initialURLString {
    self = [super init];
    if (!self) {
        return nil;
    }

    _pendingJavaScriptEvaluations = [NSMutableDictionary dictionary];
    _pendingURLString = initialURLString.length > 0 ? [initialURLString copy] : nil;
    _pageZoom = 1.0;
    _nextDevToolsMessageID = 1;

    _hostContainerView = [[BBChromiumHostContainerView alloc] initWithFrame:NSZeroRect];
    _hostContainerView.page = self;
    _browserView = [[NSView alloc] initWithFrame:NSZeroRect];
    _browserView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_hostContainerView addSubview:_browserView];

    [self setupCEFCallbacks];
    [self notifyStateChanged];
    return self;
}

- (void)dealloc {
    [self dispose];
}

- (NSView *)hostView {
    return self.hostContainerView;
}

- (BBChromiumPageState *)state {
    BBChromiumPageState *state = [[BBChromiumPageState alloc] init];
    state.title = self.currentTitle;
    state.urlString = self.currentURLString;
    state.loading = self.isLoading;
    state.estimatedProgress = self.estimatedProgress;
    state.canGoBack = self.canGoBack;
    state.canGoForward = self.canGoForward;
    state.pageZoom = self.pageZoom > 0 ? self.pageZoom : 1.0;
    return state;
}

- (void)loadURLString:(NSString *)urlString {
    if (urlString.length == 0) {
        return;
    }
    self.pendingURLString = urlString;
    [self ensureBrowserCreatedIfPossible];
    if (!self.browser) {
        self.currentURLString = urlString;
        [self notifyStateChanged];
        return;
    }

    cef_frame_t *frame = self.browser->get_main_frame(self.browser);
    if (!frame) {
        return;
    }
    cef_string_t url = BBChromiumCefString(urlString);
    frame->load_url(frame, &url);
    cef_string_clear(&url);
    BBChromiumReleaseRefCounted(&frame->base);
}

- (void)goBack {
    if (self.browser && self.browser->can_go_back(self.browser)) {
        self.browser->go_back(self.browser);
    }
}

- (void)goForward {
    if (self.browser && self.browser->can_go_forward(self.browser)) {
        self.browser->go_forward(self.browser);
    }
}

- (void)reload {
    if (self.browser) {
        self.browser->reload(self.browser);
    }
}

- (void)stopLoading {
    if (self.browser) {
        self.browser->stop_load(self.browser);
    }
}

- (void)setPageZoom:(double)pageZoom {
    _pageZoom = pageZoom > 0.01 ? pageZoom : 1.0;
    if (self.browserHost) {
        self.browserHost->set_zoom_level(self.browserHost, BBChromiumZoomLevelFromPageZoom(_pageZoom));
    }
    [self syncStateFromBrowser];
    [self notifyStateChanged];
}

- (void)printPage {
    if (self.browserHost) {
        self.browserHost->print(self.browserHost);
    }
}

- (void)findText:(NSString *)query forward:(BOOL)forward {
    if (!self.browserHost) {
        return;
    }
    if (query.length == 0) {
        self.lastFindQuery = nil;
        self.browserHost->stop_finding(self.browserHost, 0);
        return;
    }

    BOOL findNext = [self.lastFindQuery isEqualToString:query];
    self.lastFindQuery = query;
    cef_string_t searchText = BBChromiumCefString(query);
    self.browserHost->find(self.browserHost, &searchText, forward ? 1 : 0, 0, findNext ? 1 : 0);
    cef_string_clear(&searchText);
}

- (void)evaluateJavaScript:(NSString *)script completion:(void (^)(NSString *_Nullable result, NSError *_Nullable error))completion {
    [self ensureBrowserCreatedIfPossible];
    if (!self.browserHost) {
        completion(nil, BBChromiumError(1, @"Chromium page is not ready."));
        return;
    }

    BBPendingJavaScriptEvaluation *pendingEvaluation = [[BBPendingJavaScriptEvaluation alloc] init];
    pendingEvaluation.completion = completion;

    cef_dictionary_value_t *params = cef_dictionary_value_create();
    cef_string_t expressionKey = BBChromiumCefString(@"expression");
    cef_string_t returnByValueKey = BBChromiumCefString(@"returnByValue");
    cef_string_t awaitPromiseKey = BBChromiumCefString(@"awaitPromise");
    cef_string_t method = BBChromiumCefString(@"Runtime.evaluate");
    cef_string_t expression = BBChromiumCefString(script);

    params->set_string(params, &expressionKey, &expression);
    params->set_bool(params, &returnByValueKey, 1);
    params->set_bool(params, &awaitPromiseKey, 1);

    int messageID = self.browserHost->execute_dev_tools_method(self.browserHost, self.nextDevToolsMessageID, &method, params);
    if (messageID == 0) {
        completion(nil, BBChromiumError(2, @"Failed to submit JavaScript evaluation to Chromium."));
    } else {
        self.nextDevToolsMessageID = messageID + 1;
        self.pendingJavaScriptEvaluations[@(messageID)] = pendingEvaluation;
    }

    cef_string_clear(&expressionKey);
    cef_string_clear(&returnByValueKey);
    cef_string_clear(&awaitPromiseKey);
    cef_string_clear(&method);
    cef_string_clear(&expression);
    BBChromiumReleaseRefCounted(&params->base);
}

- (void)dispose {
    if (self.disposed) {
        return;
    }
    self.disposed = YES;
    self.delegate = nil;
    self.hostContainerView.page = nil;

    [self failPendingJavaScriptEvaluationsWithError:BBChromiumError(6, @"Chromium page was disposed.")];

    if (self.browserHost) {
        self.browserHost->close_browser(self.browserHost, 1);
    }

    if (self.devToolsRegistration) {
        BBChromiumReleaseRefCounted(&self.devToolsRegistration->base);
        self.devToolsRegistration = nullptr;
    }
    if (self.browserHost) {
        BBChromiumReleaseRefCounted(&self.browserHost->base);
        self.browserHost = nullptr;
    }
    if (self.browser) {
        BBChromiumReleaseRefCounted(&self.browser->base);
        self.browser = nullptr;
    }

    if (self.clientWrapper) {
        self.clientWrapper->page = nil;
        BBChromiumReleaseRefCounted(&self.clientWrapper->client.base);
        self.clientWrapper = nullptr;
    }
    if (self.displayHandlerWrapper) {
        self.displayHandlerWrapper->page = nil;
        BBChromiumReleaseRefCounted(&self.displayHandlerWrapper->handler.base);
        self.displayHandlerWrapper = nullptr;
    }
    if (self.loadHandlerWrapper) {
        self.loadHandlerWrapper->page = nil;
        BBChromiumReleaseRefCounted(&self.loadHandlerWrapper->handler.base);
        self.loadHandlerWrapper = nullptr;
    }
    if (self.lifeSpanHandlerWrapper) {
        self.lifeSpanHandlerWrapper->page = nil;
        BBChromiumReleaseRefCounted(&self.lifeSpanHandlerWrapper->handler.base);
        self.lifeSpanHandlerWrapper = nullptr;
    }
    if (self.downloadHandlerWrapper) {
        self.downloadHandlerWrapper->page = nil;
        BBChromiumReleaseRefCounted(&self.downloadHandlerWrapper->handler.base);
        self.downloadHandlerWrapper = nullptr;
    }
    if (self.findHandlerWrapper) {
        self.findHandlerWrapper->page = nil;
        BBChromiumReleaseRefCounted(&self.findHandlerWrapper->handler.base);
        self.findHandlerWrapper = nullptr;
    }
    if (self.devToolsObserverWrapper) {
        self.devToolsObserverWrapper->page = nil;
        BBChromiumReleaseRefCounted(&self.devToolsObserverWrapper->observer.base);
        self.devToolsObserverWrapper = nullptr;
    }
}

- (void)setupCEFCallbacks {
    self.clientWrapper = new BBChromiumClientWrapper();
    self.clientWrapper->page = self;
    BBChromiumInitializeBase<BBChromiumClientWrapper>(&self.clientWrapper->client);
    self.clientWrapper->client.get_display_handler = BBChromiumGetDisplayHandler;
    self.clientWrapper->client.get_download_handler = BBChromiumGetDownloadHandler;
    self.clientWrapper->client.get_find_handler = BBChromiumGetFindHandler;
    self.clientWrapper->client.get_life_span_handler = BBChromiumGetLifeSpanHandler;
    self.clientWrapper->client.get_load_handler = BBChromiumGetLoadHandler;

    self.displayHandlerWrapper = new BBChromiumDisplayHandlerWrapper();
    self.displayHandlerWrapper->page = self;
    BBChromiumInitializeBase<BBChromiumDisplayHandlerWrapper>(&self.displayHandlerWrapper->handler);
    self.displayHandlerWrapper->handler.on_address_change = BBChromiumOnAddressChange;
    self.displayHandlerWrapper->handler.on_title_change = BBChromiumOnTitleChange;
    self.displayHandlerWrapper->handler.on_status_message = BBChromiumOnStatusMessage;
    self.displayHandlerWrapper->handler.on_loading_progress_change = BBChromiumOnLoadingProgressChange;

    self.loadHandlerWrapper = new BBChromiumLoadHandlerWrapper();
    self.loadHandlerWrapper->page = self;
    BBChromiumInitializeBase<BBChromiumLoadHandlerWrapper>(&self.loadHandlerWrapper->handler);
    self.loadHandlerWrapper->handler.on_loading_state_change = BBChromiumOnLoadingStateChange;
    self.loadHandlerWrapper->handler.on_load_end = BBChromiumOnLoadEnd;
    self.loadHandlerWrapper->handler.on_load_error = BBChromiumOnLoadError;

    self.lifeSpanHandlerWrapper = new BBChromiumLifeSpanHandlerWrapper();
    self.lifeSpanHandlerWrapper->page = self;
    BBChromiumInitializeBase<BBChromiumLifeSpanHandlerWrapper>(&self.lifeSpanHandlerWrapper->handler);
    self.lifeSpanHandlerWrapper->handler.on_before_popup = BBChromiumOnBeforePopup;
    self.lifeSpanHandlerWrapper->handler.on_after_created = BBChromiumOnAfterCreated;
    self.lifeSpanHandlerWrapper->handler.on_before_close = BBChromiumOnBeforeClose;

    self.downloadHandlerWrapper = new BBChromiumDownloadHandlerWrapper();
    self.downloadHandlerWrapper->page = self;
    BBChromiumInitializeBase<BBChromiumDownloadHandlerWrapper>(&self.downloadHandlerWrapper->handler);
    self.downloadHandlerWrapper->handler.can_download = BBChromiumCanDownload;
    self.downloadHandlerWrapper->handler.on_before_download = BBChromiumOnBeforeDownload;
    self.downloadHandlerWrapper->handler.on_download_updated = BBChromiumOnDownloadUpdated;

    self.findHandlerWrapper = new BBChromiumFindHandlerWrapper();
    self.findHandlerWrapper->page = self;
    BBChromiumInitializeBase<BBChromiumFindHandlerWrapper>(&self.findHandlerWrapper->handler);
    self.findHandlerWrapper->handler.on_find_result = BBChromiumOnFindResult;

    self.devToolsObserverWrapper = new BBChromiumDevToolsObserverWrapper();
    self.devToolsObserverWrapper->page = self;
    BBChromiumInitializeBase<BBChromiumDevToolsObserverWrapper>(&self.devToolsObserverWrapper->observer);
    self.devToolsObserverWrapper->observer.on_dev_tools_method_result = BBChromiumOnDevToolsMethodResult;
    self.devToolsObserverWrapper->observer.on_dev_tools_agent_detached = BBChromiumOnDevToolsAgentDetached;
}

- (void)ensureBrowserCreatedIfPossible {
    if (self.disposed || self.browser || self.browserCreationAttempted) {
        return;
    }
    if (!self.hostContainerView.window) {
        return;
    }

    self.browserCreationAttempted = YES;
    [BBChromiumRuntime startIfNeeded];

    cef_window_info_t windowInfo = {};
    windowInfo.size = sizeof(windowInfo);
    windowInfo.parent_view = CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(self.hostContainerView);
    windowInfo.view = CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(self.browserView);
    windowInfo.bounds = cef_rect_t{0, 0, (int)NSWidth(self.browserView.bounds), (int)NSHeight(self.browserView.bounds)};
    windowInfo.runtime_style = CEF_RUNTIME_STYLE_ALLOY;

    cef_browser_settings_t browserSettings = {};
    browserSettings.size = sizeof(browserSettings);
    browserSettings.background_color = CefColorSetARGB(255, 255, 255, 255);

    NSString *initialURL = self.pendingURLString.length > 0 ? self.pendingURLString : @"about:blank";
    cef_string_t url = BBChromiumCefString(initialURL);
    cef_browser_t *browser = cef_browser_host_create_browser_sync(
        &windowInfo,
        &self.clientWrapper->client,
        &url,
        &browserSettings,
        nullptr,
        [BBChromiumRuntime sharedRequestContext]
    );
    cef_string_clear(&url);

    if (!browser) {
        self.browserCreationAttempted = NO;
        NSLog(@"[ChromiumBridge] Failed to create browser for %@", initialURL);
        return;
    }

    self.browser = browser;
    self.browserHost = browser->get_host(browser);
    if (self.browserHost) {
        self.devToolsRegistration = self.browserHost->add_dev_tools_message_observer(
            self.browserHost,
            &self.devToolsObserverWrapper->observer
        );
    }

    self.pendingURLString = nil;
    [self syncStateFromBrowser];
    if (self.browserHost) {
        self.browserHost->set_zoom_level(self.browserHost, BBChromiumZoomLevelFromPageZoom(self.pageZoom));
    }
    [self notifyStateChanged];
}

- (void)syncStateFromBrowser {
    if (!self.browser || !self.browser->is_valid(self.browser)) {
        return;
    }

    self.isLoading = self.browser->is_loading(self.browser) != 0;
    self.canGoBack = self.browser->can_go_back(self.browser) != 0;
    self.canGoForward = self.browser->can_go_forward(self.browser) != 0;

    if (self.browserHost) {
        _pageZoom = BBChromiumPageZoomFromLevel(self.browserHost->get_zoom_level(self.browserHost));
    }
}

- (void)notifyStateChanged {
    id<BBChromiumPageDelegate> delegate = self.delegate;
    if (!delegate) {
        return;
    }
    [delegate chromiumPageDidUpdateState:self.state];
}

- (void)handleAfterCreatedBrowser:(cef_browser_t *)browser {
    if (!self.browser) {
        self.browser = browser;
        if (self.browser && self.browser->base.add_ref) {
            self.browser->base.add_ref(&self.browser->base);
        }
    }
    if (!self.browserHost && browser) {
        self.browserHost = browser->get_host(browser);
    }
    [self syncStateFromBrowser];
    [self notifyStateChanged];
}

- (void)handleBrowserBeforeClose {
    self.browserCreationAttempted = NO;
    if (self.devToolsRegistration) {
        BBChromiumReleaseRefCounted(&self.devToolsRegistration->base);
        self.devToolsRegistration = nullptr;
    }
    if (self.browserHost) {
        BBChromiumReleaseRefCounted(&self.browserHost->base);
        self.browserHost = nullptr;
    }
    if (self.browser) {
        BBChromiumReleaseRefCounted(&self.browser->base);
        self.browser = nullptr;
    }
}

- (void)handleAddressChange:(NSString *)urlString browser:(cef_browser_t *)browser {
    self.currentURLString = urlString.length > 0 ? urlString : nil;
    [self syncStateFromBrowser];
    [self notifyStateChanged];
    if (browser) {
        [self notifyNavigationFinishedIfReady];
    }
}

- (void)handleTitleChange:(NSString *)title browser:(cef_browser_t *)browser {
    self.currentTitle = title.length > 0 ? title : self.currentTitle;
    [self syncStateFromBrowser];
    [self notifyStateChanged];
    if (browser) {
        [self notifyNavigationFinishedIfReady];
    }
}

- (void)handleStatusMessage:(NSString *)status {
    NSString *trimmed = [status stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *hoverURL = ([trimmed containsString:@"://"] || [trimmed hasPrefix:@"mailto:"]) ? trimmed : nil;
    [self.delegate chromiumPageDidChangeHoverURL:hoverURL];
}

- (void)handleProgressChange:(double)progress browser:(cef_browser_t *)browser {
    self.estimatedProgress = progress;
    [self syncStateFromBrowser];
    [self notifyStateChanged];
    if (!self.isLoading && browser) {
        [self notifyNavigationFinishedIfReady];
    }
}

- (void)handleLoadingStateChange:(BOOL)isLoading
                       canGoBack:(BOOL)canGoBack
                    canGoForward:(BOOL)canGoForward
                         browser:(cef_browser_t *)browser {
    self.isLoading = isLoading;
    self.canGoBack = canGoBack;
    self.canGoForward = canGoForward;
    [self syncStateFromBrowser];
    [self notifyStateChanged];
    if (!isLoading && browser) {
        [self notifyNavigationFinishedIfReady];
    }
}

- (void)handleLoadFinishedForBrowser:(cef_browser_t *)browser {
    [self syncStateFromBrowser];
    [self notifyStateChanged];

    if (self.currentTitle.length == 0 && self.currentURLString.length > 0) {
        NSURL *url = [NSURL URLWithString:self.currentURLString];
        self.currentTitle = url.host ?: self.currentURLString;
    }
    if (browser) {
        [self notifyNavigationFinishedIfReady];
    }
}

- (void)handlePopupURL:(NSString *)urlString {
    if (urlString.length > 0) {
        [self.delegate chromiumPageDidRequestNewTab:urlString];
    }
}

- (void)handleDownloadStatus:(NSString *)status {
    if (status.length > 0) {
        [self.delegate chromiumPageDidUpdateDownloadStatus:status];
    }
}

- (void)notifyNavigationFinishedIfReady {
    if (self.currentTitle.length == 0 || self.currentURLString.length == 0) {
        return;
    }
    [self.delegate chromiumPageDidFinishNavigationWithTitle:self.currentTitle urlString:self.currentURLString];
}

- (void)handleDevToolsMethodResultForMessageID:(int)messageID success:(BOOL)success data:(NSData *)data {
    BBPendingJavaScriptEvaluation *pendingEvaluation = self.pendingJavaScriptEvaluations[@(messageID)];
    if (!pendingEvaluation) {
        return;
    }
    [self.pendingJavaScriptEvaluations removeObjectForKey:@(messageID)];

    if (!success) {
        NSString *message = @"JavaScript evaluation failed.";
        if (data.length > 0) {
            NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([payload isKindOfClass:NSDictionary.class]) {
                message = payload[@"message"] ?: message;
            }
        }
        pendingEvaluation.completion(nil, BBChromiumError(3, message));
        return;
    }

    if (data.length == 0) {
        pendingEvaluation.completion(nil, BBChromiumError(4, @"JavaScript evaluation returned no result."));
        return;
    }

    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![payload isKindOfClass:NSDictionary.class]) {
        pendingEvaluation.completion(nil, BBChromiumError(4, @"Failed to decode JavaScript result."));
        return;
    }

    NSDictionary *exceptionDetails = payload[@"exceptionDetails"];
    if ([exceptionDetails isKindOfClass:NSDictionary.class]) {
        NSString *message = exceptionDetails[@"text"] ?: @"JavaScript evaluation threw an exception.";
        pendingEvaluation.completion(nil, BBChromiumError(4, message));
        return;
    }

    NSDictionary *result = payload[@"result"];
    id value = [result isKindOfClass:NSDictionary.class] ? result[@"value"] : nil;
    if ([value isKindOfClass:NSString.class]) {
        pendingEvaluation.completion(value, nil);
        return;
    }
    if (value && [NSJSONSerialization isValidJSONObject:value]) {
        NSData *serialized = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
        NSString *stringValue = [[NSString alloc] initWithData:serialized encoding:NSUTF8StringEncoding];
        pendingEvaluation.completion(stringValue, nil);
        return;
    }
    if (value) {
        pendingEvaluation.completion([value description], nil);
        return;
    }

    pendingEvaluation.completion(nil, BBChromiumError(4, @"JavaScript evaluation did not return a value."));
}

- (void)failPendingJavaScriptEvaluationsWithError:(NSError *)error {
    NSDictionary<NSNumber *, BBPendingJavaScriptEvaluation *> *pending = [self.pendingJavaScriptEvaluations copy];
    [self.pendingJavaScriptEvaluations removeAllObjects];
    [pending enumerateKeysAndObjectsUsingBlock:^(__unused NSNumber *key, BBPendingJavaScriptEvaluation *evaluation, __unused BOOL *stop) {
        evaluation.completion(nil, error);
    }];
}

@end
