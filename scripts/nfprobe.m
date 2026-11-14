/* AppKit probe for native fullscreen (#116): what a borderless window that covers a screen does
   in a fullscreen Space. No Wine and no game: one NSWindow whose CAMetalLayer draws a frame
   counter. Public API only. scripts/nfprobe.sh builds it and runs every mode:
     clang -fobjc-arc -O2 -framework AppKit -framework Metal -framework QuartzCore \
       -o nfprobe scripts/nfprobe.m

   nfprobe <run> [--no-toggle] [--wait <s>]
     control  a titled, resizable window enters a Space and leaves it
     a        a borderless window covering the main screen, with FullScreenPrimary
     b        the same, made Titled|Resizable in windowWillEnterFullScreen and borderless again
              after windowDidExitFullScreen (what SDL2 does)
     a-opts, b-opts
              a and b with window:willUseFullScreenPresentationOptions: returning
              FullScreen|HideDock|HideMenuBar
     display  the borderless window (as a) on a second screen; once in its Space it waits up to
              --wait seconds (default 60) for that screen to go away and reports the window
     --no-toggle  never calls toggleFullScreen: (the failing control)

   In the Space it hands activation to a helper app (this program as "nfprobe helper", whose window
   waits on the desktop), which hands it back 1.5 s later, and reports the first nextDrawable after
   that; then it leaves the Space. Every run ends with the window out of its Space (or the
   process gone, which takes the Space with it) and the process exiting by itself: each wait has
   a timeout, and a watchdog ends a run that takes longer than its limit.

   stdout: one fact per line, "<ms since start> <fact>", and last
     verdict run=<run> result=<entered|refused|failed|no verdict> exit=<exited|failed|->
   refused: AppKit said no (windowDidFailToEnterFullScreen before windowWillEnterFullScreen, or an
   exception from toggleFullScreen:). failed: no notification within the timeout, or a transition
   that began and didn't end. no verdict: the control itself can't enter and leave, so this Mac
   can't judge, or display mode without a second screen.
   Exit status: 0 entered and exited, 10 refused, 11 failed (also an exit that failed), 12 no
   verdict, 64 usage. */
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <stdatomic.h>
#include <sys/sysctl.h>
#include <unistd.h>

static double t0;
static double now(void) { return CACurrentMediaTime(); }

static void say(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void say(NSString *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    printf("%9.1f %s\n", (now() - t0) * 1000.0, s.UTF8String);
}

static void after(double s, dispatch_block_t b)
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s * NSEC_PER_SEC)), dispatch_get_main_queue(), b);
}

/* ---- the run's settings and state ---- */

static NSString *run;
static BOOL titled, variantB, presentationOpts, displayMode, noToggle;
static double waitGone = 60;
static NSWindow *win;
static NSScreen *target;
static CGDirectDisplayID targetID;
static NSRect cover;
static NSMutableArray<NSString *> *events; /* event names, main thread only */
static NSString *enterResult = @"failed", *exitResult = @"-";

static atomic_bool rendering;
static atomic_ullong frames;
static atomic_bool waitFirstDrawable;
static _Atomic double reactivatedAt;
static dispatch_semaphore_t renderDone;
static BOOL returning;
static NSTask *helper; /* the other app of the round trip */
static NSRunningApplication *helperApp;

static CGDirectDisplayID screenID(NSScreen *s)
{
    return [s.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
}

static NSString *rect(NSRect r)
{
    return [NSString stringWithFormat:@"%.0f,%.0f %.0fx%.0f", r.origin.x, r.origin.y, r.size.width, r.size.height];
}

static NSString *styleNames(NSWindowStyleMask m)
{
    NSMutableArray *a = [NSMutableArray array];
    if (m & NSWindowStyleMaskTitled) [a addObject:@"titled"];
    if (m & NSWindowStyleMaskClosable) [a addObject:@"closable"];
    if (m & NSWindowStyleMaskMiniaturizable) [a addObject:@"miniaturizable"];
    if (m & NSWindowStyleMaskResizable) [a addObject:@"resizable"];
    if (m & NSWindowStyleMaskFullSizeContentView) [a addObject:@"fullSizeContent"];
    if (m & NSWindowStyleMaskFullScreen) [a addObject:@"fullscreen"];
    return [NSString stringWithFormat:@"0x%lx(%@)", (unsigned long)m, a.count ? [a componentsJoinedByString:@"|"] : @"borderless"];
}

static NSString *screenFacts(NSScreen *s)
{
    NSEdgeInsets i = s.safeAreaInsets;
    return [NSString stringWithFormat:@"screen=%u frame=%@ visible=%@ safeArea=top%.0f,left%.0f,bottom%.0f,right%.0f scale=%.0f%@",
            screenID(s), rect(s.frame), rect(s.visibleFrame), i.top, i.left, i.bottom, i.right,
            s.backingScaleFactor, s == NSScreen.screens.firstObject ? @" main" : @""];
}

static void facts(NSString *when)
{
    say(@"%@ window frame=%@ content=%@ style=%@ collection=0x%lx", when, rect(win.frame),
        rect([win contentRectForFrameRect:win.frame]), styleNames(win.styleMask), (unsigned long)win.collectionBehavior);
    say(@"%@ window visible=%d key=%d onActiveSpace=%d occlusionVisible=%d appActive=%d frames=%llu", when, win.visible,
        win.keyWindow, win.onActiveSpace, (win.occlusionState & NSWindowOcclusionStateVisible) != 0, NSApp.active,
        (unsigned long long)atomic_load(&frames));
    say(@"%@ %@", when, win.screen ? screenFacts(win.screen) : @"screen=none");
    say(@"%@ presentation system=0x%lx app=0x%lx", when, (unsigned long)NSApp.currentSystemPresentationOptions,
        (unsigned long)NSApp.presentationOptions);
}

static void note(NSString *name, NSString *detail)
{
    [events addObject:name];
    say(@"event %@%@%@", name, detail.length ? @" " : @"", detail ?: @"");
}

/* Calls done with the first of names that arrives after events[mark], or nil after timeout. */
static void waitEvent(NSArray<NSString *> *names, NSUInteger mark, double until, void (^done)(NSString *))
{
    for (NSUInteger i = mark; i < events.count; i++)
        if ([names containsObject:events[i]]) {
            done(events[i]);
            return;
        }
    if (now() >= until) {
        done(nil);
        return;
    }
    after(0.02, ^{ waitEvent(names, mark, until, done); });
}

/* ---- the end of a run ---- */

/* Prints the run's one verdict line and returns the exit status for its caller to exit with. Only
   the first call prints; a later one (the watchdog while end() finishes, or the reverse) returns -1,
   and its caller doesn't exit. The runner's own time limit covers a process that never gets there. */
static atomic_flag verdictOnce = ATOMIC_FLAG_INIT;

static int finishWith(NSString *enterR, NSString *exitR)
{
    if (atomic_flag_test_and_set(&verdictOnce)) return -1;
    NSString *result = enterR;
    if ([run isEqualToString:@"control"] && !([enterR isEqualToString:@"entered"] && [exitR isEqualToString:@"exited"]))
        result = @"no verdict";
    int code = [result isEqualToString:@"no verdict"] ? 12 : [result isEqualToString:@"refused"] ? 10
        : [result isEqualToString:@"entered"] && [exitR isEqualToString:@"exited"] ? 0 : 11;
    printf("verdict run=%s result=%s exit=%s\n", run.UTF8String, result.UTF8String, exitR.UTF8String);
    fflush(stdout);
    return code;
}

static int finish(void)
{
    return finishWith(enterResult, exitResult);
}

/* Exits with the verdict's status, or waits for the watchdog that is printing its own. */
static void exitWith(int code)
{
    while (code < 0) pause();
    exit(code);
}

static void end(void)
{
    atomic_store(&rendering, false);
    dispatch_semaphore_wait(renderDone, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
    if (helper.running) [helper terminate];
    [win orderOut:nil];
    [win close];
    exitWith(finish());
}

/* ---- the frame counter ---- */

static NSString *const shaderSource = @
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct V { float4 p [[position]]; };\n"
    "vertex V vs(uint i [[vertex_id]]) {\n"
    "  float2 u = float2(float((i << 1) & 2), float(i & 2)); V o; o.p = float4(u * 2.0 - 1.0, 0, 1); return o; }\n"
    "constant ushort SEG[10] = {0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F};\n"
    "bool box(float2 c, float x0, float y0, float x1, float y1) {\n"
    "  return c.x >= x0 && c.x <= x1 && c.y >= y0 && c.y <= y1; }\n"
    "fragment float4 fs(V in [[stage_in]], constant uint2 &u [[buffer(0)]]) {\n"
    "  float h = max(float(u.y), 1.0);\n"
    "  float4 bg = float4(0.08, 0.10, 0.16, 1);\n"
    "  float2 g = (in.p.xy - 0.05 * h) / (0.2 * h);\n" /* a digit is 0.2 of the height */
    "  if (g.x < 0 || g.y < 0 || g.y > 1 || g.x >= 4.8) return bg;\n"
    "  int k = int(g.x / 0.6);\n"
    "  uint n = u.x; for (int j = 7; j > k; j--) n /= 10;\n"
    "  ushort s = SEG[n % 10];\n"
    "  float2 c = float2(g.x - k * 0.6, g.y);\n"
    "  bool on = ((s & 1) && box(c, 0.08, 0.00, 0.42, 0.08)) || ((s & 2) && box(c, 0.42, 0.04, 0.50, 0.50))\n"
    "    || ((s & 4) && box(c, 0.42, 0.50, 0.50, 0.96)) || ((s & 8) && box(c, 0.08, 0.92, 0.42, 1.00))\n"
    "    || ((s & 16) && box(c, 0.00, 0.50, 0.08, 0.96)) || ((s & 32) && box(c, 0.00, 0.04, 0.08, 0.50))\n"
    "    || ((s & 64) && box(c, 0.08, 0.46, 0.42, 0.54));\n"
    "  return on ? float4(1, 0.85, 0.3, 1) : bg; }\n";

@interface MetalView : NSView
@end

@implementation MetalView
- (CALayer *)makeBackingLayer
{
    return [CAMetalLayer layer];
}
- (void)sizeDrawable
{
    CAMetalLayer *l = (CAMetalLayer *)self.layer;
    CGFloat scale = self.window ? self.window.backingScaleFactor : 1;
    l.contentsScale = scale;
    l.drawableSize = CGSizeMake(self.bounds.size.width * scale, self.bounds.size.height * scale);
}
- (void)setFrameSize:(NSSize)size
{
    [super setFrameSize:size];
    [self sizeDrawable];
}
- (void)viewDidChangeBackingProperties
{
    [super viewDidChangeBackingProperties];
    [self sizeDrawable];
}
@end

static void render(CAMetalLayer *layer)
{
    id<MTLDevice> dev = layer.device;
    id<MTLCommandQueue> q = [dev newCommandQueue];
    NSError *err = nil;
    id<MTLLibrary> lib = [dev newLibraryWithSource:shaderSource options:nil error:&err];
    id<MTLRenderPipelineState> pipe = nil;
    if (lib) {
        MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
        d.vertexFunction = [lib newFunctionWithName:@"vs"];
        d.fragmentFunction = [lib newFunctionWithName:@"fs"];
        d.colorAttachments[0].pixelFormat = layer.pixelFormat;
        pipe = [dev newRenderPipelineStateWithDescriptor:d error:&err];
    }
    if (!pipe) say(@"render: no counter shader (%@), clearing only", err.localizedDescription);
    while (atomic_load(&rendering)) @autoreleasepool {
        double a = now();
        id<CAMetalDrawable> drawable = [layer nextDrawable];
        double b = now();
        if ((b - a) * 1000 >= 50) say(@"nextDrawable blocked %.0f ms%@", (b - a) * 1000, drawable ? @"" : @", returned nil");
        if (!drawable) {
            usleep(5000);
            continue;
        }
        if (atomic_load(&waitFirstDrawable) && b >= atomic_load(&reactivatedAt)) {
            atomic_store(&waitFirstDrawable, false);
            say(@"first nextDrawable after re-activation: returned %.0f ms after didBecomeActive, the call took %.0f ms",
                (b - atomic_load(&reactivatedAt)) * 1000, (b - a) * 1000);
        }
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = drawable.texture;
        rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0.08, 0.10, 0.16, 1);
        id<MTLCommandBuffer> cb = [q commandBuffer];
        id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
        if (pipe) {
            uint32_t u[2] = {(uint32_t)(atomic_load(&frames) % 100000000), (uint32_t)drawable.texture.height};
            [enc setRenderPipelineState:pipe];
            [enc setFragmentBytes:u length:sizeof(u) atIndex:0];
            [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        }
        [enc endEncoding];
        [cb presentDrawable:drawable];
        [cb commit];
        atomic_fetch_add(&frames, 1);
    }
    dispatch_semaphore_signal(renderDone);
}

/* ---- the window and its delegate ---- */

@interface ProbeWindow : NSWindow
@end

@implementation ProbeWindow
/* A borderless window can't become key by default; Wine's windows can. */
- (BOOL)canBecomeKeyWindow
{
    return YES;
}
- (BOOL)canBecomeMainWindow
{
    return YES;
}
@end

@interface Probe : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end

@interface ProbeApp : NSApplication
@end

@implementation ProbeApp
- (void)reportException:(NSException *)e
{
    say(@"exception %@: %@", e.name, e.reason);
    [super reportException:e];
}
@end

static void leave(void);
static void inSpace(void);

static void enter(void)
{
    facts(@"before");
    NSUInteger mark0 = events.count;
    if (noToggle) {
        say(@"toggleFullScreen: not called (--no-toggle)");
    } else {
        @try {
            say(@"toggleFullScreen:");
            [win toggleFullScreen:nil];
        } @catch (NSException *e) {
            say(@"exception from toggleFullScreen: %@: %@", e.name, e.reason);
            enterResult = @"refused";
            end();
        }
    }
    waitEvent(@[ @"windowWillEnterFullScreen", @"windowDidFailToEnterFullScreen" ], mark0, now() + 5, ^(NSString *hit) {
        if (!hit) {
            say(@"no notification within 5 s of toggleFullScreen:");
            enterResult = @"failed";
            end();
        } else if ([hit isEqualToString:@"windowDidFailToEnterFullScreen"]) {
            enterResult = @"refused";
            end();
        } else {
            NSUInteger mark = [events indexOfObject:hit inRange:NSMakeRange(mark0, events.count - mark0)] + 1;
            waitEvent(@[ @"windowDidEnterFullScreen", @"windowDidFailToEnterFullScreen" ], mark, now() + 10, ^(NSString *h) {
                if ([h isEqualToString:@"windowDidEnterFullScreen"]) {
                    enterResult = @"entered";
                    after(1.0, ^{ inSpace(); });
                } else {
                    say(@"%@", h ? @"the transition began and failed" : @"no windowDidEnterFullScreen within 10 s");
                    enterResult = @"failed";
                    leave();
                }
            });
        }
    });
}

/* The other app is the probe itself in helper mode: started before the window enters its Space, so
   its window sits on the desktop. Activation goes over by yielding both ways, since macOS 27 doesn't
   let the probe take it back on its own (Finder doesn't yield, and [NSApp activate] was refused). */
static void waitHelper(double until, void (^then)(void))
{
    NSRunningApplication *h = [NSRunningApplication runningApplicationWithProcessIdentifier:helper.processIdentifier];
    if (h.finishedLaunching) {
        helperApp = h;
        then();
    } else if (!helper.running || now() >= until) {
        say(@"the helper app didn't start within 5 s; no round trip");
        then();
    } else {
        after(0.05, ^{ waitHelper(until, then); });
    }
}

static void startHelper(void (^then)(void))
{
    NSError *err = nil;
    helper = [NSTask launchedTaskWithExecutableURL:NSBundle.mainBundle.executableURL
                                         arguments:@[ @"helper", @(getpid()).stringValue, [NSString stringWithFormat:@"%.9f", t0] ]
                                             error:&err
                                terminationHandler:nil];
    if (!helper) {
        say(@"no helper app (%@); no round trip", err.localizedDescription);
        then();
        return;
    }
    waitHelper(now() + 5, then);
}

static void roundTrip(void (^then)(void))
{
    if (!helperApp || helperApp.terminated) {
        say(@"round trip skipped: no helper app");
        then();
        return;
    }
    unsigned long long before = atomic_load(&frames);
    say(@"activating the helper app");
    NSUInteger mark = events.count;
    [NSApp yieldActivationToApplication:helperApp];
    [helperApp activateWithOptions:0];
    waitEvent(@[ @"applicationDidResignActive" ], mark, now() + 3, ^(NSString *hit) {
        if (!hit) say(@"the probe stayed active");
        returning = YES; /* the helper gives activation back 1.5 s after it got it */
        NSUInteger m = events.count;
        after(1.0, ^{
            say(@"away: %llu frames presented since the helper app was asked", atomic_load(&frames) - before);
            facts(@"away");
        });
        waitEvent(@[ @"applicationDidBecomeActive" ], m, now() + 5, ^(NSString *h) {
            returning = NO;
            if (!h) say(@"the probe wasn't activated again within 5 s");
            after(1.5, ^{
                if (atomic_load(&waitFirstDrawable)) {
                    atomic_store(&waitFirstDrawable, false);
                    say(@"no nextDrawable within 1.5 s of re-activation");
                }
                facts(@"back");
                then();
            });
        });
    });
}

static void pollGone(double until, void (^then)(void))
{
    for (NSScreen *s in NSScreen.screens)
        if (screenID(s) == targetID) {
            if (now() < until) {
                after(0.1, ^{ pollGone(until, then); });
            } else {
                say(@"display %u still there after %.0f s", targetID, waitGone);
                then();
            }
            return;
        }
    say(@"display %u is gone", targetID);
    after(3.0, ^{
        facts(@"after-removal");
        for (NSScreen *s in NSScreen.screens) say(@"after-removal %@", screenFacts(s));
        then();
    });
}

static void displayGone(void (^then)(void))
{
    say(@"waiting up to %.0f s for display %u to go away", waitGone, targetID);
    pollGone(now() + waitGone, then);
}

static void inSpace(void)
{
    facts(@"in");
    for (NSScreen *s in NSScreen.screens) say(@"in %@", screenFacts(s));
    if (displayMode)
        displayGone(^{ leave(); });
    else
        roundTrip(^{ leave(); });
}

static void leaveOnce(BOOL retry)
{
    if (!(win.styleMask & NSWindowStyleMaskFullScreen)) {
        say(@"the window isn't in a Space any more");
        exitResult = @"exited";
        after(0.5, ^{
            facts(@"after");
            end();
        });
        return;
    }
    NSUInteger mark = events.count;
    say(@"toggleFullScreen: (leave)");
    @try {
        [win toggleFullScreen:nil];
    } @catch (NSException *e) {
        say(@"exception from toggleFullScreen: %@: %@", e.name, e.reason);
    }
    waitEvent(@[ @"windowDidExitFullScreen", @"windowDidFailToExitFullScreen" ], mark, now() + 10, ^(NSString *hit) {
        if ([hit isEqualToString:@"windowDidExitFullScreen"]) {
            exitResult = @"exited";
            after(0.5, ^{
                facts(@"after");
                end();
            });
        } else if (retry) {
            say(@"%@; one more try in 1 s", hit ? @"the exit failed" : @"no windowDidExitFullScreen within 10 s");
            after(1.0, ^{ leaveOnce(NO); });
        } else {
            say(@"the window is still in its Space; the process exits, which removes it");
            exitResult = @"failed";
            facts(@"after");
            end();
        }
    });
}

static void leave(void)
{
    leaveOnce(YES);
}

@implementation Probe

- (BOOL)respondsToSelector:(SEL)sel
{
    if (sel == @selector(window:willUseFullScreenPresentationOptions:)) return presentationOpts;
    return [super respondsToSelector:sel];
}

- (void)applicationDidFinishLaunching:(NSNotification *)n
{
    NSArray<NSScreen *> *screens = NSScreen.screens;
    say(@"separateSpaces=%d screens=%lu", NSScreen.screensHaveSeparateSpaces, (unsigned long)screens.count);
    for (NSScreen *s in screens) say(@"start %@", screenFacts(s));
    if (!screens.count) {
        say(@"no screen: this session has no window server display");
        enterResult = @"no verdict";
        exitWith(finish());
    }
    if (displayMode && screens.count < 2) {
        say(@"no second display attached");
        enterResult = @"no verdict";
        exitWith(finish());
    }
    target = displayMode ? screens.lastObject : screens.firstObject;
    targetID = screenID(target);
    cover = target.frame;
    NSRect r = cover;
    NSWindowStyleMask style = NSWindowStyleMaskBorderless;
    if (titled) {
        r = NSMakeRect(NSMidX(cover) - 480, NSMidY(cover) - 300, 960, 600);
        style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    }
    win = [[ProbeWindow alloc] initWithContentRect:r styleMask:style backing:NSBackingStoreBuffered defer:NO];
    win.releasedWhenClosed = NO;
    win.title = [@"nfprobe " stringByAppendingString:run];
    win.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
    win.delegate = self;
    MetalView *v = [[MetalView alloc] initWithFrame:NSMakeRect(0, 0, r.size.width, r.size.height)];
    v.wantsLayer = YES;
    CAMetalLayer *layer = (CAMetalLayer *)v.layer;
    layer.device = MTLCreateSystemDefaultDevice();
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.opaque = YES;
    win.contentView = v;
    [win setFrame:[win frameRectForContentRect:r] display:NO];
    [v sizeDrawable];
    [win makeKeyAndOrderFront:nil];
    [NSApp activate];
    say(@"window on screen %u, metal device %@", targetID, layer.device.name);
    atomic_store(&rendering, true);
    [NSThread detachNewThreadWithBlock:^{ render(layer); }];

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserverForName:NSApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification *x) {
        if (returning) {
            atomic_store(&reactivatedAt, now());
            atomic_store(&waitFirstDrawable, true);
        }
        note(@"applicationDidBecomeActive", nil);
    }];
    [nc addObserverForName:NSApplicationDidResignActiveNotification object:nil queue:nil usingBlock:^(NSNotification *x) {
        note(@"applicationDidResignActive", nil);
    }];
    [nc addObserverForName:NSApplicationDidChangeScreenParametersNotification object:nil queue:nil usingBlock:^(NSNotification *x) {
        note(@"applicationDidChangeScreenParameters", [NSString stringWithFormat:@"screens=%lu", (unsigned long)NSScreen.screens.count]);
    }];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification object:nil
        queue:nil usingBlock:^(NSNotification *x) {
            note(@"activeSpaceDidChange", [NSString stringWithFormat:@"onActiveSpace=%d", win.onActiveSpace]);
        }];
    if (displayMode)
        after(1.0, ^{ enter(); });
    else
        startHelper(^{ after(1.0, ^{ enter(); }); });
}

- (void)windowWillEnterFullScreen:(NSNotification *)n
{
    note(@"windowWillEnterFullScreen", [NSString stringWithFormat:@"style=%@", styleNames(win.styleMask)]);
    if (variantB) {
        win.styleMask = (win.styleMask & NSWindowStyleMaskFullScreen) | NSWindowStyleMaskTitled | NSWindowStyleMaskResizable;
        say(@"variant b: style now %@", styleNames(win.styleMask));
    }
}
- (void)windowDidEnterFullScreen:(NSNotification *)n
{
    note(@"windowDidEnterFullScreen", [NSString stringWithFormat:@"frame=%@ style=%@", rect(win.frame), styleNames(win.styleMask)]);
}
- (void)windowDidFailToEnterFullScreen:(NSWindow *)w
{
    note(@"windowDidFailToEnterFullScreen", nil);
}
- (void)windowWillExitFullScreen:(NSNotification *)n
{
    note(@"windowWillExitFullScreen", nil);
}
- (void)windowDidExitFullScreen:(NSNotification *)n
{
    note(@"windowDidExitFullScreen", [NSString stringWithFormat:@"frame=%@ style=%@", rect(win.frame), styleNames(win.styleMask)]);
    if (variantB) {
        win.styleMask = NSWindowStyleMaskBorderless;
        [win setFrame:cover display:YES];
        say(@"variant b: style back to %@, frame %@", styleNames(win.styleMask), rect(win.frame));
    }
}
- (void)windowDidFailToExitFullScreen:(NSWindow *)w
{
    note(@"windowDidFailToExitFullScreen", nil);
}
- (NSSize)window:(NSWindow *)w willUseFullScreenContentSize:(NSSize)proposed
{
    note(@"willUseFullScreenContentSize", [NSString stringWithFormat:@"%.0fx%.0f", proposed.width, proposed.height]);
    return proposed;
}
- (NSApplicationPresentationOptions)window:(NSWindow *)w willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)proposed
{
    NSApplicationPresentationOptions o = NSApplicationPresentationFullScreen | NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar;
    note(@"willUseFullScreenPresentationOptions", [NSString stringWithFormat:@"proposed=0x%lx returned=0x%lx", (unsigned long)proposed, (unsigned long)o]);
    return o;
}
- (void)windowWillStartLiveResize:(NSNotification *)n
{
    note(@"windowWillStartLiveResize", nil);
}
- (void)windowDidEndLiveResize:(NSNotification *)n
{
    note(@"windowDidEndLiveResize", nil);
}
- (void)windowDidResize:(NSNotification *)n
{
    note(@"windowDidResize", rect(win.frame));
}
- (void)windowDidMove:(NSNotification *)n
{
    note(@"windowDidMove", rect(win.frame));
}
- (void)windowDidChangeScreen:(NSNotification *)n
{
    note(@"windowDidChangeScreen", [NSString stringWithFormat:@"screen=%u", win.screen ? screenID(win.screen) : 0]);
}
- (void)windowDidChangeOcclusionState:(NSNotification *)n
{
    note(@"windowDidChangeOcclusionState", [NSString stringWithFormat:@"visible=%d", (win.occlusionState & NSWindowOcclusionStateVisible) != 0]);
}
@end

/* ---- helper mode: the other app of the round trip ---- */

static pid_t probePid;

@interface Helper : NSObject <NSApplicationDelegate>
@end

@implementation Helper {
    NSWindow *w;
}
- (void)applicationDidFinishLaunching:(NSNotification *)n
{
    NSRect f = NSScreen.screens.firstObject.frame;
    w = [[NSWindow alloc] initWithContentRect:NSMakeRect(NSMidX(f) - 200, NSMidY(f) - 120, 400, 240)
                                    styleMask:NSWindowStyleMaskTitled
                                      backing:NSBackingStoreBuffered
                                        defer:NO];
    w.releasedWhenClosed = NO;
    w.title = @"nfprobe helper";
    [w orderBack:nil]; /* on the desktop, behind the probe's window */
    /* never outlive the probe */
    [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
        if (getppid() != probePid) exit(0);
    }];
}
- (void)applicationDidBecomeActive:(NSNotification *)n
{
    say(@"helper: active");
    [w makeKeyAndOrderFront:nil];
    after(1.5, ^{
        NSRunningApplication *p = [NSRunningApplication runningApplicationWithProcessIdentifier:probePid];
        say(@"helper: yielding activation to the probe");
        [NSApp yieldActivationToApplication:p];
        [p activateWithOptions:0];
        after(1.0, ^{ exit(0); });
    });
}
@end

static void usage(void)
{
    fprintf(stderr, "usage: nfprobe control|a|b|a-opts|b-opts|display [--no-toggle] [--wait <s>]\n");
    exit(64);
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        t0 = now();
        setvbuf(stdout, NULL, _IOLBF, 0);
        if (argc < 2) usage();
        if (!strcmp(argv[1], "helper") && argc == 4) { /* started by the probe: helper <probe pid> <its t0> */
            probePid = atoi(argv[2]);
            t0 = atof(argv[3]);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ _exit(0); });
            [NSApplication sharedApplication];
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
            Helper *h = [Helper new];
            NSApp.delegate = h;
            [NSApp run];
            return 0;
        }
        run = @(argv[1]);
        NSDictionary *runs = @{@"control" : @"t", @"a" : @"", @"b" : @"B", @"a-opts" : @"o", @"b-opts" : @"Bo", @"display" : @"d"};
        NSString *f = runs[run];
        if (!f) usage();
        titled = [f containsString:@"t"];
        variantB = [f containsString:@"B"];
        presentationOpts = [f containsString:@"o"];
        displayMode = [f containsString:@"d"];
        for (int i = 2; i < argc; i++) {
            if (!strcmp(argv[i], "--no-toggle"))
                noToggle = YES;
            else if (!strcmp(argv[i], "--wait") && i + 1 < argc && atof(argv[i + 1]) > 0)
                waitGone = atof(argv[++i]);
            else
                usage();
        }
        events = [NSMutableArray array];
        renderDone = dispatch_semaphore_create(0);

        char model[64] = "", chip[128] = "";
        size_t len = sizeof(model);
        sysctlbyname("hw.model", model, &len, NULL, 0);
        len = sizeof(chip);
        sysctlbyname("machdep.cpu.brand_string", chip, &len, NULL, 0);
        say(@"run=%@ macOS %@ %s %s", run, NSProcessInfo.processInfo.operatingSystemVersionString, model, chip);

        /* The watchdog: a run that hasn't finished in time ends here, whatever the main thread does.
           Exiting takes the window, and its Space, with the process. */
        double limit = 60 + (displayMode ? waitGone : 0);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(limit * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                           say(@"watchdog: the run took longer than %.0f s", limit);
                           BOOL in = [enterResult isEqualToString:@"entered"];
                           int code = finishWith(in ? @"entered" : @"failed", in ? @"failed" : @"-");
                           if (code >= 0) _exit(code);
                       });

        [ProbeApp sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        Probe *p = [Probe new];
        NSApp.delegate = p;
        [NSApp run];
    }
    return 0;
}
