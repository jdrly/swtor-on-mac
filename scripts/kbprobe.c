/* Keyboard probe for scripts/test-sandbox.sh: how Wine's Mac driver maps the keys of the
   current keyboard layout (set WINEMAC_TEST_KEYBOARD_LAYOUT=<input source ID> to pick one
   with SWTOR on Mac's winemac.so). For every character key, by scan code: the virtual key,
   the scan code back, GetKeyNameText, ToUnicodeEx without and with Shift (a dead key is
   composed with E) and MapVirtualKey's VK_TO_CHAR; then the number row in summary lines
   ("numrow-<what>: ..."), and VkKeyScan for a few characters. Prints UTF-8.
     x86_64-w64-mingw32-gcc -O2 -o swtor.exe scripts/kbprobe.c */
#include <windows.h>
#include <stdio.h>

static HKL hkl;

static void put(const WCHAR *w, int n)
{
    char buf[64];
    int len = WideCharToMultiByte(CP_UTF8, 0, w, n, buf, sizeof(buf) - 1, NULL, NULL);
    buf[len > 0 ? len : 0] = 0;
    fputs(buf, stdout);
}

static UINT vk_of(UINT sc) { return MapVirtualKeyExW(sc, MAPVK_VSC_TO_VK, hkl); }

static void name(UINT sc)
{
    WCHAR w[32];
    int n = GetKeyNameTextW(sc << 16, w, ARRAYSIZE(w));
    if (n > 0) put(w, n); else fputs("?", stdout);
}

static void type(UINT sc, BOOL shift)
{
    BYTE ks[256] = {0}, plain[256] = {0};
    WCHAR b[8], c[8];
    int n, m;
    if (shift) ks[VK_SHIFT] = ks[VK_LSHIFT] = 0x80;
    n = ToUnicodeEx(vk_of(sc), sc, ks, b, 8, 0, hkl);
    if (n < 0)
    {
        put(b, 1);
        fputs("(dead)+e=", stdout);
        m = ToUnicodeEx('E', MapVirtualKeyExW('E', MAPVK_VK_TO_VSC, hkl), plain, c, 8, 0, hkl);
        if (m > 0) put(c, m); else fputs("?", stdout);
    }
    else if (n == 0) fputs("-", stdout);
    else put(b, n);
}

int main(void)
{
    static const UINT rows[] = {
        0x29, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0,
        0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0,
        0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2B, 0,
        0x56, 0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0,
    };
    static const WCHAR probes[] = { '1', '+', 0x011b /* e caron */, 'z', 'y', 0x00e9 /* e acute */, 0 };
    UINT sc;
    int i;

    hkl = GetKeyboardLayout(0);
    printf("scan  vk    ->scan  name\tplain\tshift\tvk_to_char\n");
    for (i = 0; i < ARRAYSIZE(rows); i++)
    {
        UINT vk, ch;
        if (!(sc = rows[i])) { printf("\n"); continue; }
        vk = vk_of(sc);
        printf("0x%02x  0x%02x  0x%02x   ", sc, vk, MapVirtualKeyExW(vk, MAPVK_VK_TO_VSC, hkl));
        name(sc); printf("\t");
        type(sc, FALSE); printf("\t");
        type(sc, TRUE); printf("\t");
        ch = MapVirtualKeyExW(vk, MAPVK_VK_TO_CHAR, hkl);
        if (ch & 0xffff) { WCHAR w = ch & 0xffff; put(&w, 1); if (ch & 0x80000000) fputs("(dead)", stdout); }
        printf("\n");
    }
    printf("numrow-vk:");
    for (sc = 0x02; sc <= 0x0B; sc++) printf(" %c", vk_of(sc) >= '0' && vk_of(sc) <= 'Z' ? vk_of(sc) : '?');
    printf("\nnumrow-name:");
    for (sc = 0x02; sc <= 0x0B; sc++) { printf(" "); name(sc); }
    printf("\nnumrow-plain:");
    for (sc = 0x02; sc <= 0x0B; sc++) { printf(" "); type(sc, FALSE); }
    printf("\nnumrow-shift:");
    for (sc = 0x02; sc <= 0x0B; sc++) { printf(" "); type(sc, TRUE); }
    printf("\nkey-0x15: vk %c name ", vk_of(0x15));
    name(0x15);
    printf(" plain ");
    type(0x15, FALSE);
    printf("\nVkKeyScan:");
    for (i = 0; probes[i]; i++)
    {
        printf(" "); put(&probes[i], 1); printf("=0x%04x", (unsigned short)VkKeyScanExW(probes[i], hkl));
    }
    printf("\n");
    return 0;
}
