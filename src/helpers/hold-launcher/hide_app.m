// Hides another app (like Cmd-H) and waits until it is hidden, at most TIMEOUT seconds.
// The target app does the hiding itself, so this has to happen before it is stopped.
// Needs an NSApplication in this process (no Dock icon: activation policy prohibited).
#import <AppKit/AppKit.h>

int hide_app(pid_t pid, double timeout)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        if (!app) return 0;
        [app hide];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
        while (!app.hidden && [deadline timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        return app.hidden ? 1 : 0;
    }
}
