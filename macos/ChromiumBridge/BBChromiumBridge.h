#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class BBChromiumPageState;

@protocol BBChromiumPageDelegate <NSObject>
- (void)chromiumPageDidUpdateState:(BBChromiumPageState *)state;
- (void)chromiumPageDidChangeHoverURL:(nullable NSString *)urlString;
- (void)chromiumPageDidFinishNavigationWithTitle:(NSString *)title urlString:(NSString *)urlString;
- (void)chromiumPageDidRequestNewTab:(NSString *)urlString;
- (void)chromiumPageDidUpdateDownloadStatus:(NSString *)status;
@end

@interface BBChromiumPageState : NSObject
@property(nonatomic, copy, nullable) NSString *title;
@property(nonatomic, copy, nullable) NSString *urlString;
@property(nonatomic, assign, getter=isLoading) BOOL loading;
@property(nonatomic, assign) double estimatedProgress;
@property(nonatomic, assign) BOOL canGoBack;
@property(nonatomic, assign) BOOL canGoForward;
@property(nonatomic, assign) double pageZoom;
@end

@interface BBChromiumRuntime : NSObject
+ (void)startIfNeeded;
+ (NSString *)runtimeDescription;
+ (void)clearCookies;
@end

@interface BBChromiumPage : NSObject
@property(nonatomic, weak, nullable) id<BBChromiumPageDelegate> delegate;
@property(nonatomic, readonly) NSView *hostView;
@property(nonatomic, readonly) BBChromiumPageState *state;

- (instancetype)initWithInitialURLString:(nullable NSString *)initialURLString NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)loadURLString:(NSString *)urlString;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)stopLoading;
- (void)setPageZoom:(double)pageZoom;
- (void)printPage;
- (void)findText:(NSString *)query forward:(BOOL)forward;
- (void)evaluateJavaScript:(NSString *)script completion:(void (^)(NSString *_Nullable result, NSError *_Nullable error))completion;
- (void)dispose;
@end

NS_ASSUME_NONNULL_END
