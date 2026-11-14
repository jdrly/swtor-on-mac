/* nfwinprobe.c: the window probe for native fullscreen (#119), run as swtor.exe under the engine
   with the app's Mac driver. It does what the game and d9mt do to the game's window and logs every
   window message it gets, so two runs (NativeFullscreen off and on, or the engine's own driver)
   can be compared line by line:

     1. a popup covering the primary monitor (exclusive fullscreen, d9mt's EnterFullscreenMode)
     2. windowed: the style first, then the rect, a few ms apart (d9mt's LeaveFullscreenMode)
     3. fullscreen again: the style, then the monitor's rect
     4. hidden, 5. shown, 6. closed

   Built like the keyboard probe:  x86_64-w64-mingw32-gcc -O2 -o swtor.exe nfwinprobe.c -lgdi32
   nfwinprobe [<seconds before step 2, default 8>] [<seconds per step, default 4>] [second]
   "second": the popup covers a monitor other than the primary one (the test that takes that
   display away while the window holds its Space; the steps then use that monitor too).

   stdout, one line each: "step <n> <what>", "msg <name> <wparam> <lparam>" for every message the
   window procedure gets (times left out, so runs compare), "rect <n> (l,t)-(r,b)" with the
   window's rect at the end of each step. Messages with no name print in hex. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define WINDOWED_LEFT   100
#define WINDOWED_TOP    100
#define WINDOWED_WIDTH  1280
#define WINDOWED_HEIGHT 720

static HWND win;
static RECT monitor;
static int step;

static const struct { UINT msg; const char *name; } names[] = {
#define N(m) { m, #m }
    N(WM_CREATE), N(WM_DESTROY), N(WM_MOVE), N(WM_SIZE), N(WM_ACTIVATE), N(WM_SETFOCUS),
    N(WM_KILLFOCUS), N(WM_ENABLE), N(WM_SETTEXT), N(WM_GETTEXT), N(WM_GETTEXTLENGTH), N(WM_PAINT),
    N(WM_CLOSE), N(WM_QUIT), N(WM_ERASEBKGND), N(WM_SHOWWINDOW), N(WM_ACTIVATEAPP), N(WM_CANCELMODE),
    N(WM_SETCURSOR), N(WM_MOUSEACTIVATE), N(WM_GETMINMAXINFO), N(WM_WINDOWPOSCHANGING),
    N(WM_WINDOWPOSCHANGED), N(WM_GETICON), N(WM_NCCREATE), N(WM_NCDESTROY), N(WM_NCCALCSIZE),
    N(WM_NCHITTEST), N(WM_NCPAINT), N(WM_NCACTIVATE), N(WM_GETDLGCODE), N(WM_SYNCPAINT),
    N(WM_NCMOUSEMOVE), N(WM_KEYDOWN), N(WM_KEYUP), N(WM_CHAR), N(WM_SYSKEYDOWN), N(WM_SYSKEYUP),
    N(WM_SYSCOMMAND), N(WM_TIMER), N(WM_MOUSEMOVE), N(WM_LBUTTONDOWN), N(WM_LBUTTONUP),
    N(WM_RBUTTONDOWN), N(WM_RBUTTONUP), N(WM_CAPTURECHANGED), N(WM_MOVING), N(WM_SIZING),
    N(WM_ENTERSIZEMOVE), N(WM_EXITSIZEMOVE), N(WM_IME_SETCONTEXT), N(WM_IME_NOTIFY),
    N(WM_STYLECHANGING), N(WM_STYLECHANGED), N(WM_DISPLAYCHANGE), N(WM_SETICON),
    N(WM_DWMNCRENDERINGCHANGED), N(WM_GETOBJECT), N(WM_SETTINGCHANGE), N(WM_DEVICECHANGE),
#undef N
};

static BOOL CALLBACK pick_second(HMONITOR m, HDC dc, LPRECT r, LPARAM l)
{
    MONITORINFO mi = { sizeof(mi) };
    GetMonitorInfoA(m, &mi);
    if (!(mi.dwFlags & MONITORINFOF_PRIMARY)) { *(RECT *)l = mi.rcMonitor; return FALSE; }
    return TRUE;
}

static void say(const char *fmt, ...)
{
    va_list a;
    va_start(a, fmt);
    vprintf(fmt, a);
    va_end(a);
    printf("\n");
    fflush(stdout);
}

static void log_message(UINT m, WPARAM w, LPARAM l)
{
    unsigned int i;

    if (m == WM_TIMER) return; /* the probe's own clock */
    for (i = 0; i < sizeof(names) / sizeof(names[0]); i++)
        if (names[i].msg == m) break;
    /* lparam of the position messages points at a structure: its address isn't comparable */
    if (m == WM_WINDOWPOSCHANGING || m == WM_WINDOWPOSCHANGED)
    {
        const WINDOWPOS *p = (const WINDOWPOS *)l;
        say("msg %s (%d,%d) %dx%d flags 0x%x", names[i].name, p->x, p->y, p->cx, p->cy, p->flags);
    }
    else if (m == WM_GETMINMAXINFO || m == WM_NCCALCSIZE || m == WM_NCCREATE || m == WM_CREATE ||
             m == WM_STYLECHANGING || m == WM_STYLECHANGED || m == WM_GETTEXT || m == WM_SETTEXT ||
             m == WM_GETICON || m == WM_SETTINGCHANGE)
        say("msg %s %lx", i < sizeof(names) / sizeof(names[0]) ? names[i].name : "?", (unsigned long)w);
    else if (i < sizeof(names) / sizeof(names[0]))
        say("msg %s %lx %lx", names[i].name, (unsigned long)w, (unsigned long)l);
    else
        say("msg 0x%04x %lx %lx", m, (unsigned long)w, (unsigned long)l);
}

static void log_rect(void)
{
    RECT r;
    GetWindowRect(win, &r);
    say("rect %d (%ld,%ld)-(%ld,%ld)", step, r.left, r.top, r.right, r.bottom);
}

static void next_step(void)
{
    log_rect();
    step++;
    switch (step)
    {
    case 2:
        say("step 2 windowed: style, then rect");
        SetWindowLongPtrA(win, GWL_STYLE, WS_OVERLAPPEDWINDOW | WS_VISIBLE);
        Sleep(5);
        SetWindowPos(win, NULL, WINDOWED_LEFT, WINDOWED_TOP, WINDOWED_WIDTH, WINDOWED_HEIGHT,
                     SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
        break;
    case 3:
        say("step 3 fullscreen: style, then the monitor's rect");
        SetWindowLongPtrA(win, GWL_STYLE, WS_POPUP | WS_VISIBLE);
        Sleep(5);
        SetWindowPos(win, HWND_TOP, monitor.left, monitor.top, monitor.right - monitor.left,
                     monitor.bottom - monitor.top, SWP_NOACTIVATE | SWP_FRAMECHANGED);
        break;
    case 4:
        say("step 4 hide");
        ShowWindow(win, SW_HIDE);
        break;
    case 5:
        say("step 5 show");
        ShowWindow(win, SW_SHOW);
        break;
    default:
        say("step 6 close");
        DestroyWindow(win);
        break;
    }
}

static LRESULT CALLBACK proc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    log_message(m, w, l);
    switch (m)
    {
    case WM_TIMER:
        next_step();
        return 0;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcA(h, m, w, l);
}

int main(int argc, char **argv)
{
    UINT first = argc > 1 ? atoi(argv[1]) * 1000 : 8000, each = argc > 2 ? atoi(argv[2]) * 1000 : 4000;
    MONITORINFO mi = { sizeof(mi) };
    WNDCLASSA wc = { 0 };
    MSG msg;

    GetMonitorInfoA(MonitorFromPoint((POINT){ 0, 0 }, MONITOR_DEFAULTTOPRIMARY), &mi);
    monitor = mi.rcMonitor;
    if (argc > 3 && !strcmp(argv[3], "second"))
    {
        RECT primary = monitor;
        EnumDisplayMonitors(NULL, NULL, pick_second, (LPARAM)&monitor);
        if (EqualRect(&primary, &monitor)) say("no second monitor");
    }
    wc.lpfnWndProc = proc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "nfwinprobe";
    wc.hbrBackground = (HBRUSH)GetStockObject(DKGRAY_BRUSH);
    RegisterClassA(&wc);
    step = 1;
    say("step 1 fullscreen popup on the%s monitor (%ld,%ld)-(%ld,%ld)", argc > 3 ? " second" : "", monitor.left, monitor.top, monitor.right, monitor.bottom);
    win = CreateWindowExA(0, "nfwinprobe", "nfwinprobe", WS_POPUP | WS_VISIBLE, monitor.left, monitor.top,
                          monitor.right - monitor.left, monitor.bottom - monitor.top, NULL, NULL, wc.hInstance, NULL);
    SetTimer(win, 1, first, NULL);
    while (GetMessageA(&msg, NULL, 0, 0) > 0)
    {
        if (msg.message == WM_TIMER && msg.hwnd == win && step == 1)
            SetTimer(win, 1, each, NULL);
        DispatchMessageA(&msg);
    }
    say("end");
    return 0;
}
