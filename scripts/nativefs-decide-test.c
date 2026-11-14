/* nativefs-decide-test.c: the native fullscreen decision of the app's Mac driver (nativefs.h,
   from patches/winemac-native-fullscreen.patch), tested without AppKit.
   scripts/test-nativefs-decide.sh builds it with clang and runs it, and builds it again against
   two broken stubs (-DSTUB_NEVER_ENTER, -DSTUB_IGNORE_DECLINED), which must fail.
   Prints one line per failed check and exits 1 if any failed. */
#include <stdio.h>
#include "nativefs.h"

#if defined(STUB_NEVER_ENTER)
static struct nfs_decision step(struct nfs_state *s, const struct nfs_facts *f, double now)
{
    struct nfs_decision d = nfs_step(s, f, now);
    if (d.action == NFS_ENTER) d.action = NFS_NOTHING;
    return d;
}
#elif defined(STUB_IGNORE_DECLINED)
static struct nfs_decision step(struct nfs_state *s, const struct nfs_facts *f, double now)
{
    s->declined = 0;
    return nfs_step(s, f, now);
}
#else
#define step nfs_step
#endif

static int failures, checks;

#define CHECK(cond, what) do { checks++; if (!(cond)) { failures++; printf("FAIL line %d: %s\n", __LINE__, what); } } while (0)

/* The game's fullscreen window on screen 1, the app active, nothing in a Space. */
static struct nfs_facts game(void)
{
    struct nfs_facts f;
    memset(&f, 0, sizeof(f));
    f.option = f.top_level = f.ordered_in = f.borderless = 1;
    f.screen = 1;
    f.separate_spaces = 1;
    f.screens = 1;
    f.app_active = f.on_active_space = 1;
    return f;
}

static struct nfs_facts in_space(struct nfs_facts f)
{
    f.in_space = 1;
    f.space_screen = 1;
    f.request_is_content = 1;
    return f;
}

static enum nfs_action act(struct nfs_state *s, struct nfs_facts f, double now)
{
    return step(s, &f, now).action;
}

/* Settled in the Space: entered at 0.3 and in it since 1.0. */
static void settle_in_space(struct nfs_state *s, struct nfs_facts f)
{
    memset(s, 0, sizeof(*s));
    act(s, f, 0);
    act(s, f, 0.3);
    act(s, in_space(f), 1.0);
}

int main(void)
{
    struct nfs_state s;
    struct nfs_facts f, g;
    struct nfs_decision d;

    /* the option off: nothing, whatever the window is */
    memset(&s, 0, sizeof(s));
    f = game(); f.option = 0;
    CHECK(act(&s, f, 0) == NFS_NOTHING && act(&s, f, 10) == NFS_NOTHING, "option off: nothing");

    /* qualifying: stable for 300 ms, then enter */
    memset(&s, 0, sizeof(s));
    f = game();
    d = step(&s, &f, 5.0);
    CHECK(d.action == NFS_WAIT && d.at > 5.29 && d.at < 5.31, "qualifying: wait 300 ms first");
    CHECK(act(&s, f, 5.2) == NFS_WAIT, "qualifying: still waiting at 200 ms");
    CHECK(act(&s, f, 5.3) == NFS_ENTER, "qualifying for 300 ms: enter");

    /* Q1-Q8, one at a time: none enters */
    {
        static const char *names[] = { "parent", "hidden", "minimized", "disabled", "no foreground",
                                       "maximized", "titled", "covers no screen", "captured",
                                       "shared Spaces, 2 screens" };
        int i;
        for (i = 0; i < 10; i++)
        {
            memset(&s, 0, sizeof(s));
            f = game();
            switch (i)
            {
            case 0: f.top_level = 0; break;
            case 1: f.ordered_in = 0; break;
            case 2: f.minimized = 1; break;
            case 3: f.disabled = 1; break;
            case 4: f.no_foreground = 1; break;
            case 5: f.maximized = 1; break;
            case 6: f.borderless = 0; break;
            case 7: f.screen = 0; break;
            case 8: f.displays_captured = 1; break;
            case 9: f.separate_spaces = 0; f.screens = 2; break;
            }
            act(&s, f, 0);
            CHECK(act(&s, f, 5) != NFS_ENTER, names[i]);
        }
    }
    memset(&s, 0, sizeof(s));
    f = game(); f.displays_captured = 1;
    d = step(&s, &f, 0);
    CHECK(d.action == NFS_NOTHING && d.skipped && !strcmp(d.skipped, "displays captured"), "captured: skipped, named");
    memset(&s, 0, sizeof(s));
    f = game(); f.separate_spaces = 0; f.screens = 2;
    d = step(&s, &f, 0);
    CHECK(d.skipped && !strcmp(d.skipped, "displays share one Space"), "shared Spaces: skipped, named");
    memset(&s, 0, sizeof(s));
    f = game(); f.separate_spaces = 0; f.screens = 1;
    act(&s, f, 0);
    CHECK(act(&s, f, 0.3) == NFS_ENTER, "shared Spaces, one screen: enters");

    /* only the active app enters, and only with the window on the active Space */
    memset(&s, 0, sizeof(s));
    f = game(); f.app_active = 0;
    act(&s, f, 0);
    CHECK(act(&s, f, 5) == NFS_NOTHING, "inactive app: nothing");
    f.app_active = 1;
    CHECK(act(&s, f, 6) == NFS_WAIT, "activated: wait 300 ms from the activation");
    CHECK(act(&s, f, 6.3) == NFS_ENTER, "activated: then enter");
    memset(&s, 0, sizeof(s));
    f = game(); f.on_active_space = 0;
    act(&s, f, 0);
    CHECK(act(&s, f, 5) == NFS_NOTHING, "window on another Space: nothing");

    /* in a transition, or in a Space the player entered by hand: nothing */
    memset(&s, 0, sizeof(s));
    f = game(); f.in_transition = 1;
    act(&s, f, 0);
    CHECK(act(&s, f, 5) == NFS_NOTHING, "in a transition: nothing");
    memset(&s, 0, sizeof(s));
    f = game(); f.borderless = 0; f.in_other_space = 1;
    act(&s, f, 0);
    CHECK(act(&s, f, 5) == NFS_NOTHING, "the player's own Space: nothing");

    /* in the Space and still qualifying: stay */
    f = game();
    settle_in_space(&s, f);
    CHECK(act(&s, in_space(f), 9) == NFS_NOTHING, "in the Space, qualifying: stay");

    /* d9mt's leave: the style first, the frame a few ms later; exit 150 ms after the last */
    f = game();
    settle_in_space(&s, f);
    g = in_space(f); g.borderless = 0;
    CHECK(act(&s, g, 10.0) == NFS_WAIT, "style request: wait");
    g.screen = 0; g.request_is_content = 0;
    d = step(&s, &g, 10.005);
    CHECK(d.action == NFS_WAIT && d.at > 10.154 && d.at < 10.156, "frame request 5 ms later: the clock restarts");
    d = step(&s, &g, 10.16);
    CHECK(d.action == NFS_EXIT && d.reason == NFS_REASON_WINDOWED, "stable 150 ms: exit, reason windowed");

    /* hidden in the Space */
    f = game();
    settle_in_space(&s, f);
    g = in_space(f); g.ordered_in = 0;
    act(&s, g, 10);
    d = step(&s, &g, 10.15);
    CHECK(d.action == NFS_EXIT && d.reason == NFS_REASON_HIDDEN, "hidden: exit, reason hidden");

    /* the request equals the Space's content (a notch): stay */
    f = game();
    settle_in_space(&s, f);
    g = in_space(f); g.screen = 0; g.request_is_content = 1;
    act(&s, g, 10);
    CHECK(act(&s, g, 11) == NFS_NOTHING, "request = the Space's content: stay");

    /* a request on another screen: leave, then enter there */
    f = game();
    settle_in_space(&s, f);
    g = in_space(f); g.screen = 2; g.request_is_content = 0;
    act(&s, g, 10);
    d = step(&s, &g, 10.15);
    CHECK(d.action == NFS_EXIT && d.reason == NFS_REASON_OTHER_SCREEN, "other screen: exit, reason other-screen");
    g = game(); g.screen = 2;
    act(&s, g, 11);
    CHECK(act(&s, g, 11.3) == NFS_ENTER, "other screen: then enter there");

    /* the fight guard: more than 3 corrections in 2 s */
    f = game();
    settle_in_space(&s, f);
    CHECK(!nfs_correction(&s, 10.0) && !nfs_correction(&s, 10.5) && !nfs_correction(&s, 11.0), "3 corrections: no fight");
    CHECK(nfs_correction(&s, 11.5), "a 4th within 2 s: fight");
    g = in_space(f);
    d = step(&s, &g, 11.5);
    CHECK(d.action == NFS_EXIT && d.reason == NFS_REASON_FIGHT, "fight: exit at once, reason fight");
    g = game();
    act(&s, g, 12);
    CHECK(act(&s, g, 20) == NFS_NOTHING, "after a fight: stay out");
    g.borderless = 0;
    act(&s, g, 21);
    g.borderless = 1;
    act(&s, g, 22);
    CHECK(act(&s, g, 22.3) == NFS_ENTER, "after a fight and a mode switch: enter again");
    f = game();
    settle_in_space(&s, f);
    CHECK(!nfs_correction(&s, 10.0) && !nfs_correction(&s, 11.0) && !nfs_correction(&s, 12.1) &&
          !nfs_correction(&s, 13.2) && !nfs_correction(&s, 14.3), "corrections spread out: no fight");

    /* failed entries: back off 2 s, 3 tries at most, until the game leaves fullscreen */
    memset(&s, 0, sizeof(s));
    f = game();
    act(&s, f, 0);
    CHECK(act(&s, f, 0.3) == NFS_ENTER, "first try");
    CHECK(nfs_enter_failed(&s, 0.9) == 1, "first failure counted");
    d = step(&s, &f, 1.0);
    CHECK(d.action == NFS_WAIT && d.at > 2.89 && d.at < 2.91, "failed: back off 2 s");
    CHECK(act(&s, f, 2.9) == NFS_ENTER, "second try after 2 s");
    nfs_enter_failed(&s, 3.5);
    CHECK(act(&s, f, 5.5) == NFS_ENTER, "third try");
    CHECK(nfs_enter_failed(&s, 6.0) == 3, "third failure counted");
    CHECK(act(&s, f, 9) == NFS_NOTHING && act(&s, f, 60) == NFS_NOTHING, "after 3 failures: no more tries");
    g = f; g.borderless = 0;
    act(&s, g, 61);
    act(&s, f, 62);
    CHECK(act(&s, f, 62.3) == NFS_ENTER, "the next mode switch: tries again");

    /* the player's exit wins: stay out until the game leaves fullscreen or the player enters */
    f = game();
    settle_in_space(&s, f);
    nfs_declined(&s);
    f.in_transition = 1;
    act(&s, f, 10);
    f.in_transition = 0;
    act(&s, f, 10.6);
    CHECK(act(&s, f, 11) == NFS_NOTHING && act(&s, f, 30) == NFS_NOTHING, "declined: stays out");
    g = f; g.borderless = 0;
    act(&s, g, 31);
    act(&s, f, 32);
    CHECK(act(&s, f, 32.3) == NFS_ENTER, "declined, then a mode switch: enter again");
    f = game();
    settle_in_space(&s, f);
    nfs_declined(&s);
    act(&s, f, 10.6);
    nfs_taken_over(&s);
    act(&s, f, 11);
    CHECK(act(&s, f, 11.3) == NFS_ENTER, "declined, then the player enters by hand: the driver's again");

    /* a display change: nothing for 1 s, then decide on what is true */
    memset(&s, 0, sizeof(s));
    f = game();
    act(&s, f, 0);
    nfs_displays_changed(&s, 0.1);
    d = step(&s, &f, 0.4);
    CHECK(d.action == NFS_WAIT && d.at > 1.09 && d.at < 1.11, "display change: wait for the settle");
    CHECK(act(&s, f, 1.1) == NFS_ENTER, "after the settle: enter");
    f = game();
    settle_in_space(&s, f);
    g = in_space(f); g.screen = 2; g.request_is_content = 0;
    nfs_displays_changed(&s, 10);
    CHECK(act(&s, g, 10.5) == NFS_WAIT, "display change in the Space: wait");
    CHECK(step(&s, &g, 11.0).reason == NFS_REASON_OTHER_SCREEN, "after the settle: leave for the other screen");

    /* the display holding the Space went away and the game didn't re-snap: leave, reason
       display-change (the window keeps the request's size on the screen AppKit moved it to) */
    f = game();
    settle_in_space(&s, f);
    g = in_space(f); g.screen = 0; g.request_is_content = 0; g.request_off_screens = 1; g.space_screen = 2;
    nfs_displays_changed(&s, 10);
    CHECK(act(&s, g, 10.5) == NFS_WAIT, "display gone: wait for the settle");
    d = step(&s, &g, 11.0);
    CHECK(d.action == NFS_EXIT && d.reason == NFS_REASON_DISPLAY_CHANGE, "display gone: exit, reason display-change");

    /* a failed exit: one retry after 1 s, then stuck */
    f = game();
    settle_in_space(&s, f);
    g = in_space(f); g.borderless = 0; g.screen = 0; g.request_is_content = 0;
    act(&s, g, 10);
    CHECK(act(&s, g, 10.15) == NFS_EXIT, "leaving");
    CHECK(nfs_exit_failed(&s, 10.8) == 1, "exit failed: retry");
    d = step(&s, &g, 11.0);
    CHECK(d.action == NFS_WAIT && d.at > 11.79 && d.at < 11.81, "exit failed: wait 1 s");
    d = step(&s, &g, 11.8);
    CHECK(d.action == NFS_EXIT && d.retry, "then retry once");
    CHECK(nfs_exit_failed(&s, 12.4) == 2, "failed again: stuck");
    CHECK(act(&s, g, 13) == NFS_NOTHING && act(&s, g, 30) == NFS_NOTHING, "stuck: nothing more");
    f = game();
    settle_in_space(&s, f);
    g = in_space(f); g.borderless = 0; g.screen = 0; g.request_is_content = 0;
    act(&s, g, 10);
    nfs_exit_failed(&s, 10.8);
    CHECK(act(&s, in_space(f), 11.0) == NFS_NOTHING, "exit failed, but the game is fullscreen again: stay");
    CHECK(s.exit_failures == 0, "... and the failure is forgotten");

    printf("%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
