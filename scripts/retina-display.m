/* retina-display: a Retina (2x) main display for CI, whose macOS runners have one 1x display.
 *
 *   retina-display <width> <height>     (points; pixels are twice that)
 *
 * Creates a virtual display with CoreGraphics' private CGVirtualDisplay classes (as DeskPad and
 * BetterDisplay use them), makes it the main display for as long as this process runs (an
 * app-only configuration: nothing is saved), prints "ready <w>x<h> scale 2" and waits until it
 * gets SIGTERM or SIGINT. The display goes away with the process, killed or not.
 * Only for CI (scripts/ui-snapshot.sh updateflow): it rearranges the displays. */
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

@protocol RDDescriptor <NSObject>
@property (retain) dispatch_queue_t queue;
@property (retain) NSString *name;
@property unsigned int maxPixelsWide;
@property unsigned int maxPixelsHigh;
@property CGSize sizeInMillimeters;
@property unsigned int productID;
@property unsigned int vendorID;
@property unsigned int serialNum;
@end
@protocol RDMode <NSObject>
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)rate;
@end
@protocol RDSettings <NSObject>
@property unsigned int hiDPI;
@property (retain) NSArray *modes;
@end
@protocol RDDisplay <NSObject>
- (instancetype)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@property (readonly) unsigned int displayID;
@end

static volatile sig_atomic_t stop;
static void on_signal(int sig) { (void)sig; stop = 1; }

int main(int argc, char **argv) {
  @autoreleasepool {
    if (getenv("CI") == NULL || argc != 3) {
      fprintf(stderr, "usage: retina-display <width> <height>   (CI only)\n");
      return 2;
    }
    const unsigned int w = (unsigned int)atoi(argv[1]), h = (unsigned int)atoi(argv[2]);
    if (w < 320 || w > 4096 || h < 240 || h > 4096) { fprintf(stderr, "retina-display: bad size\n"); return 2; }
    setvbuf(stdout, NULL, _IOLBF, 0);

    Class descClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");
    if (!descClass || !modeClass || !settingsClass || !displayClass) { printf("no CGVirtualDisplay\n"); return 1; }

    id<RDDescriptor> desc = [[descClass alloc] init];
    desc.queue = dispatch_get_main_queue();
    desc.name = @"CI Retina display";
    desc.maxPixelsWide = w * 2u;
    desc.maxPixelsHigh = h * 2u;
    desc.sizeInMillimeters = CGSizeMake(w * 0.2, h * 0.2);
    desc.vendorID = 0xf00d;
    desc.productID = 1;
    desc.serialNum = (unsigned int)getpid();
    id<RDDisplay> display = [[displayClass alloc] initWithDescriptor:desc];
    id<RDSettings> settings = [[settingsClass alloc] init];
    settings.hiDPI = 1;
    settings.modes = @[ [[modeClass alloc] initWithWidth:w height:h refreshRate:60.0] ];
    if (!display || ![display applySettings:settings]) { printf("no virtual display\n"); return 1; }
    const CGDirectDisplayID did = display.displayID;

    BOOL up = NO;
    for (int i = 0; i < 100 && !up; i++) {
      CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
      CGRect b = CGDisplayBounds(did);
      up = b.size.width == w && b.size.height == h;
    }
    if (!up) { printf("the virtual display did not come up\n"); return 1; }

    // the main display is the one at (0, 0): put this one there, the runner's to its right
    const CGDirectDisplayID old = CGMainDisplayID();
    CGDisplayConfigRef cfg = NULL;
    if (CGBeginDisplayConfiguration(&cfg) != kCGErrorSuccess) { printf("no display configuration\n"); return 1; }
    CGConfigureDisplayOrigin(cfg, did, 0, 0);
    if (old != did) CGConfigureDisplayOrigin(cfg, old, (int32_t)w, 0);
    if (CGCompleteDisplayConfiguration(cfg, kCGConfigureForAppOnly) != kCGErrorSuccess) {
      printf("could not make it the main display\n");
      return 1;
    }
    for (int i = 0; i < 100 && CGMainDisplayID() != did; i++) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    if (CGMainDisplayID() != did) { printf("not the main display\n"); return 1; }

    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(did);
    printf("ready %zux%zu scale %zu\n", CGDisplayModeGetWidth(mode), CGDisplayModeGetHeight(mode),
           CGDisplayModeGetPixelWidth(mode) / CGDisplayModeGetWidth(mode));
    CGDisplayModeRelease(mode);

    signal(SIGTERM, on_signal);
    signal(SIGINT, on_signal);
    while (!stop) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);
  }
  return 0;
}
