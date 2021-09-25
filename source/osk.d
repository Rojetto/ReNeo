module osk;

import core.sys.windows.windows;

import std.string;
import std.path;
import std.utf;
import std.json;
import std.conv;

import mapping;
import reneo;
import app : updateOSK, toggleOSK;
import localization : controlKeyName;

import cairo;
import cairo_win32;

const WM_DPICHANGED = 0x02E0;
const WM_DRAWOSK = WM_APP + 1;

const UINT OSK_WIDTH_WITH_NUMPAD_96DPI = 1000;
const UINT OSK_WIDTH_NO_NUMPAD_96DPI = 750;
const UINT OSK_HEIGHT_96DPI = 250;
const UINT OSK_BOTTOM_OFFSET_96DPI = 5;
const UINT OSK_MIN_WIDTH_96DPI = 250;

uint dpi = 96;

bool configOskNumpad;
OSKTheme configOskTheme;
OSKLayout configOskLayout;
bool configOskNumberRow;


enum OSKTheme {
    Grey,
    NeoBlue
}

enum OSKLayout {
    ISO,
    ANSI
}

const float KEYBOARD_WIDTH_WITH_NUMPAD = 20;
const float KEYBOARD_WIDTH_NO_NUMPAD = 15;
const float KEYBOARD_HEIGHT = 5;

const float M_PI = 3.14159265358979323846;

HFONT[] WIN_FONTS;
cairo_font_face_t*[] CAIRO_FONTS;


void initOsk(JSONValue oskJson) {
    // Read config
    configOskNumpad = oskJson["numpad"].boolean;
    configOskTheme = oskJson["theme"].str.to!OSKTheme;
    configOskLayout = oskJson["layout"].str.toUpper.to!OSKLayout;
    configOskNumberRow = oskJson["numberRow"].boolean;

    // Load fonts
    WIN_FONTS ~= CreateFont(0, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, ANSI_CHARSET, OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH, "Segoe UI".toUTF16z);
    WIN_FONTS ~= CreateFont(0, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, ANSI_CHARSET, OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH, "Segoe UI Symbol".toUTF16z);
    
    foreach (HFONT winFont; WIN_FONTS) {
        CAIRO_FONTS ~= cairo_win32_font_face_create_for_hfont(winFont);
    }
}

cairo_font_face_t* getFontFaceForChar(HDC hdc, string c) {
    for (int i = 0; i < WIN_FONTS.length - 1; i++) {
        SelectObject(hdc, WIN_FONTS[i]);
        WORD glyphIndex;
        GetGlyphIndices(hdc, c.toUTF16z, 1, &glyphIndex, GGI_MARK_NONEXISTING_GLYPHS);
        if (glyphIndex != 0xffff) {
            return CAIRO_FONTS[i];
        }
    }

    // Fallback, return last font
    return CAIRO_FONTS[CAIRO_FONTS.length - 1];
}

void drawOsk(HWND hwnd, NeoLayout *layout, uint layer, bool capslock) {
    RECT winRect;
    GetWindowRect(hwnd, &winRect);
    const uint winWidth = winRect.right - winRect.left;
    const uint winHeight = winRect.bottom - winRect.top;

    // window is unsuitable for drawing
    if (winWidth == 0 || winHeight == 0) {
        return;
    }
    
    HDC hdcScreen = GetDC(NULL);

    // Offscreen hdc for painting
    HDC hdcMem = CreateCompatibleDC(hdcScreen);
    HBITMAP hbmMem = CreateCompatibleBitmap(hdcScreen, winWidth, winHeight);
    auto hOld = SelectObject(hdcMem, hbmMem);

    // Draw using offscreen hdc
    auto surface = cairo_win32_surface_create(hdcMem);
    auto cr = cairo_create(surface);

    // There seems to be a Cairo bug where the first draw calls alpha value can't be exactly 0 or 1
    // If it is, alpha behaves strangely on later drawcalls, i.e. opaque regions disappear or are blended weirdly.
    // https://gitlab.freedesktop.org/cairo/cairo/-/issues/494
    // Workaround: draw a very faint 1px by 1px rectangle in the upper left corner
    // All following draw calls should then work correctly.
    cairo_rectangle(cr, 0, 0, 1, 1);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.01);
    cairo_fill(cr);

    // Move coordinate system to keyboard coords
    // normal keys are 1 unit wide and high, (0, 0) is upper left,
    // with whole keyboard proportionally centered in window
    float keyboardWidthPx, keyboardHeightPx;
    const float KEYBOARD_WIDTH = configOskNumpad ? KEYBOARD_WIDTH_WITH_NUMPAD : KEYBOARD_WIDTH_NO_NUMPAD;
    // should we letterbox left and right or on top and bottom?
    if (winWidth / winHeight > KEYBOARD_WIDTH / KEYBOARD_HEIGHT) {
        // letterbox left and right
        keyboardHeightPx = winHeight;
        keyboardWidthPx = keyboardHeightPx * KEYBOARD_WIDTH / KEYBOARD_HEIGHT;
    } else {
        // letterbox top and bottom
        keyboardWidthPx = winWidth;
        keyboardHeightPx = keyboardWidthPx * KEYBOARD_HEIGHT / KEYBOARD_WIDTH;
    }
    cairo_translate(cr, (winWidth - keyboardWidthPx) / 2, (winHeight - keyboardHeightPx) / 2);
    cairo_scale(cr, keyboardWidthPx / KEYBOARD_WIDTH, keyboardHeightPx / KEYBOARD_HEIGHT);

    // Draw keys
    const float PADDING = 0.05;
    const float CORNER_RADIUS = 0.1;

    const float FONT_SIZE = 0.45;
    const float BASE_LINE = 0.7;

    cairo_pattern_t *KEY_COLOR;
    switch (configOskTheme) {
        case OSKTheme.Grey:
        KEY_COLOR = cairo_pattern_create_rgba(0.4, 0.4, 0.4, 0.9);
        break;
        case OSKTheme.NeoBlue:
        KEY_COLOR = cairo_pattern_create_rgba(0.024, 0.533, 0.612, 0.95);
        break;
        default: break;
    }

    cairo_set_font_size(cr, FONT_SIZE);

    string getKeyLabel(Scancode scan) {
        // Returns "UNMAPPED" for unmapped keys, those don't get drawn

        if (layout != null) {
            if (scan in layout.map) {    
                auto entry = layout.map[scan];
                uint layerConsideringCapslock = layer;

                if (capslock && entry.capslockable) {
                    if (layer == 2) {
                        layerConsideringCapslock = 1;
                    } else if (layer == 1) {
                        layerConsideringCapslock = 2;
                    }
                }

                return layout.map[scan].layers[layerConsideringCapslock-1].label;
            } else if (scan in layout.modifiers) {
                uint mod = layout.modifiers[scan] & 0xFFFE; // convert left and right variant to left variant
                switch (mod) {
                    case Modifier.LSHIFT: return "\u21e7";
                    case Modifier.LCTRL: return controlKeyName();
                    case Modifier.LALT: return "Alt";
                    case Modifier.MOD3: return "M3";
                    case Modifier.MOD4: return "M4";
                    case Modifier.MOD5: return "M5";
                    case Modifier.MOD6: return "M6";
                    case Modifier.MOD7: return "M7";
                    case Modifier.MOD8: return "M8";
                    case Modifier.MOD9: return "M9";
                    default: break;
                }
            } else if (scan == Scancode(0x0E, false)) {
                return "\u232b"; // Backspace
            } else if (scan == Scancode(0x1C, true) || scan == Scancode(0x1C, false)) {
                return "\u21a9"; // Return or Numpad Return
            }
        }

        return "UNMAPPED";
    }

    void showKeyLabelCentered(string label, float keyX, float keyWidth, float baseline) {
        cairo_set_source_rgba(cr, 0.95, 0.95, 0.95, 1.0);
        cairo_set_font_face(cr, getFontFaceForChar(hdcMem, label));
        auto labelz = label.toStringz;
        cairo_text_extents_t extents;
        cairo_text_extents(cr, labelz, &extents);
        cairo_move_to(cr, keyX + (keyWidth - extents.width) / 2, baseline);
        cairo_show_text(cr, labelz);
    }

    void drawKey(float x, float y, float width, float height, Scancode scan) {
        string label = getKeyLabel(scan);

        if (label == "UNMAPPED")
            return;

        roundRectangle(cr, x + PADDING, y + PADDING, width - 2*PADDING, height - 2*PADDING, CORNER_RADIUS);
        cairo_set_source(cr, KEY_COLOR);
        cairo_fill(cr);

        showKeyLabelCentered(label, x, width, y + (height - 1) / 2 + BASE_LINE);
    }

    // Draw “regular” keys, i.e. keys with height 1
    // First row
    if (configOskNumberRow) {
        drawKey(0, 0, 1, 1, Scancode(0x29, false));
        drawKey(1, 0, 1, 1, Scancode(0x02, false));
        drawKey(2, 0, 1, 1, Scancode(0x03, false));
        drawKey(3, 0, 1, 1, Scancode(0x04, false));
        drawKey(4, 0, 1, 1, Scancode(0x05, false));
        drawKey(5, 0, 1, 1, Scancode(0x06, false));
        drawKey(6, 0, 1, 1, Scancode(0x07, false));
        drawKey(7, 0, 1, 1, Scancode(0x08, false));
        drawKey(8, 0, 1, 1, Scancode(0x09, false));
        drawKey(9, 0, 1, 1, Scancode(0x0A, false));
        drawKey(10, 0, 1, 1, Scancode(0x0B, false));
        drawKey(11, 0, 1, 1, Scancode(0x0C, false));
        drawKey(12, 0, 1, 1, Scancode(0x0D, false));
        drawKey(13, 0, 2, 1, Scancode(0x0E, false)); // Backspace
    }
    // Second row
    drawKey(0, 1, 1.5, 1, Scancode(0x0F, false)); // Tab
    drawKey(1.5, 1, 1, 1, Scancode(0x10, false));
    drawKey(2.5, 1, 1, 1, Scancode(0x11, false));
    drawKey(3.5, 1, 1, 1, Scancode(0x12, false));
    drawKey(4.5, 1, 1, 1, Scancode(0x13, false));
    drawKey(5.5, 1, 1, 1, Scancode(0x14, false));
    drawKey(6.5, 1, 1, 1, Scancode(0x15, false));
    drawKey(7.5, 1, 1, 1, Scancode(0x16, false));
    drawKey(8.5, 1, 1, 1, Scancode(0x17, false));
    drawKey(9.5, 1, 1, 1, Scancode(0x18, false));
    drawKey(10.5, 1, 1, 1, Scancode(0x19, false));
    drawKey(11.5, 1, 1, 1, Scancode(0x1A, false));
    drawKey(12.5, 1, 1, 1, Scancode(0x1B, false));
    if (configOskLayout == OSKLayout.ISO) {
        // OEM key on third row
        drawKey(12.75, 2, 1, 1, Scancode(0x2B, false));

        // Big return key
        string label = getKeyLabel(Scancode(0x1C, false));
        if (label != "UNMAPPED") {
            returnKey(cr, 13.5 + PADDING, 1 + PADDING, 1.5 - 2*PADDING, 1.25 - 2*PADDING, 1 - 2*PADDING, 1, CORNER_RADIUS);
            cairo_set_source(cr, KEY_COLOR);
            cairo_fill(cr);
            showKeyLabelCentered(label, 13.75, 1.25, 1.5 + BASE_LINE);
        }
    } else if (configOskLayout == OSKLayout.ANSI) {
        // OEM key
        drawKey(13.5, 1, 1.5, 1, Scancode(0x2B, false));

        // Third row return key
        drawKey(12.75, 2, 2.25, 1, Scancode(0x1C, false));
    }
    // Third row
    drawKey(0, 2, 1.75, 1, Scancode(0x3A, false)); // Capslock
    drawKey(1.75, 2, 1, 1, Scancode(0x1E, false));
    drawKey(2.75, 2, 1, 1, Scancode(0x1F, false));
    drawKey(3.75, 2, 1, 1, Scancode(0x20, false));
    drawKey(4.75, 2, 1, 1, Scancode(0x21, false));
    drawKey(5.75, 2, 1, 1, Scancode(0x22, false));
    drawKey(6.75, 2, 1, 1, Scancode(0x23, false));
    drawKey(7.75, 2, 1, 1, Scancode(0x24, false));
    drawKey(8.75, 2, 1, 1, Scancode(0x25, false));
    drawKey(9.75, 2, 1, 1, Scancode(0x26, false));
    drawKey(10.75, 2, 1, 1, Scancode(0x27, false));
    drawKey(11.75, 2, 1, 1, Scancode(0x28, false));
    // Fourth row
    if (configOskLayout == OSKLayout.ISO) {
        drawKey(0, 3, 1.25, 1, Scancode(0x2A, false)); // Shift
        drawKey(1.25, 3, 1, 1, Scancode(0x56, false)); // OEM key
    } else if (configOskLayout == OSKLayout.ANSI) {
        drawKey(0, 3, 2.25, 1, Scancode(0x2A, false)); // Shift
    }
    drawKey(2.25, 3, 1, 1, Scancode(0x2C, false));
    drawKey(3.25, 3, 1, 1, Scancode(0x2D, false));
    drawKey(4.25, 3, 1, 1, Scancode(0x2E, false));
    drawKey(5.25, 3, 1, 1, Scancode(0x2F, false));
    drawKey(6.25, 3, 1, 1, Scancode(0x30, false));
    drawKey(7.25, 3, 1, 1, Scancode(0x31, false));
    drawKey(8.25, 3, 1, 1, Scancode(0x32, false));
    drawKey(9.25, 3, 1, 1, Scancode(0x33, false));
    drawKey(10.25, 3, 1, 1, Scancode(0x34, false));
    drawKey(11.25, 3, 1, 1, Scancode(0x35, false));
    drawKey(12.25, 3, 2.75, 1, Scancode(0x36, true)); // Shift
    // Fifth row
    drawKey(0, 4, 1.25, 1, Scancode(0x1D, false)); // Ctrl
    drawKey(1.25, 4, 1.25, 1, Scancode(0x5B, true)); // Win
    drawKey(2.5, 4, 1.25, 1, Scancode(0x38, false)); // Alt
    drawKey(3.75, 4, 6.25, 1, Scancode(0x39, false)); // Space
    drawKey(10, 4, 1.25, 1, Scancode(0x38, true)); // AltGr
    drawKey(11.25, 4, 1.25, 1, Scancode(0x5C, true)); // Win
    drawKey(13.75, 4, 1.25, 1, Scancode(0x1D, true)); // Ctrl
    
    if (configOskNumpad) {
        // First row
        drawKey(16, 0, 1, 1, Scancode(0x45, true));
        drawKey(17, 0, 1, 1, Scancode(0x35, true));
        drawKey(18, 0, 1, 1, Scancode(0x37, false));
        drawKey(19, 0, 1, 1, Scancode(0x4A, false));
        // Second row
        drawKey(16, 1, 1, 1, Scancode(0x47, false));
        drawKey(17, 1, 1, 1, Scancode(0x48, false));
        drawKey(18, 1, 1, 1, Scancode(0x49, false));
        // Third row
        drawKey(16, 2, 1, 1, Scancode(0x4B, false));
        drawKey(17, 2, 1, 1, Scancode(0x4C, false));
        drawKey(18, 2, 1, 1, Scancode(0x4D, false));
        // Fourth row
        drawKey(16, 3, 1, 1, Scancode(0x4F, false));
        drawKey(17, 3, 1, 1, Scancode(0x50, false));
        drawKey(18, 3, 1, 1, Scancode(0x51, false));
        // Fifth row
        drawKey(16, 4, 2, 1, Scancode(0x52, false));
        drawKey(18, 4, 1, 1, Scancode(0x53, false));

        // Numpad Add
        drawKey(19, 1, 1, 2, Scancode(0x4E, false));
        // Numpad Return
        drawKey(19, 3, 1, 2, Scancode(0x1C, true));
    }

    // Cairo cleanup    
    cairo_destroy(cr);
    cairo_surface_destroy(surface);

    // Show on screen
    BLENDFUNCTION blend = { 0 };
    blend.BlendOp = AC_SRC_OVER;
    blend.SourceConstantAlpha = 255;
    blend.AlphaFormat = AC_SRC_ALPHA;

    POINT ptZero = POINT(0, 0);
    POINT winPos = POINT(winRect.left, winRect.top);
    SIZE winDims = SIZE(winWidth, winHeight);

    UpdateLayeredWindow(hwnd, hdcScreen, &winPos, &winDims, hdcMem, &ptZero, RGB(0, 0, 0), &blend, ULW_ALPHA);

    // Reset offscreen hdc to default bitmap
    SelectObject(hdcMem, hOld);

    // Cleanup
    DeleteObject(hbmMem);
    DeleteDC(hdcMem);
    ReleaseDC(NULL, hdcScreen);
}

void roundRectangle(cairo_t *cr, float x, float y, float w, float h, float r) {
    const float QR = M_PI / 2;

    cairo_save(cr);

    cairo_translate(cr, x, y);

    cairo_new_sub_path(cr);
    cairo_arc(cr, w - r, h - r, r, 0*QR, 1*QR);
    cairo_arc(cr, r, h - r, r, 1*QR, 2*QR);
    cairo_arc(cr, r, r, r, 2*QR, 3*QR);
    cairo_arc(cr, w - r, r, r, 3*QR, 4*QR);
    cairo_close_path(cr);

    cairo_restore(cr);
}

void returnKey(cairo_t *cr, float x, float y, float wU, float wL, float hU, float hL, float r) {
    const float QR = M_PI / 2;

    cairo_save(cr);

    cairo_translate(cr, x, y);

    cairo_new_sub_path(cr);
    cairo_arc(cr, wU - r, hU + hL - r, r, 0*QR, 1*QR);
    cairo_arc(cr, wU - wL + r, hU + hL - r, r, 1*QR, 2*QR);
    cairo_arc_negative(cr, wU - wL - r, hU + r, r, 0*QR, -1*QR);
    cairo_arc(cr, r, hU - r, r, 1*QR, 2*QR);
    cairo_arc(cr, r, r, r, 2*QR, 3*QR);
    cairo_arc(cr, wU - r, r, r, 3*QR, 4*QR);
    cairo_close_path(cr);

    cairo_restore(cr);
}

LRESULT oskWndProc(HWND hwnd, uint msg, WPARAM wParam, LPARAM lParam) {
    RECT winRect;
    GetWindowRect(hwnd, &winRect);

    uint calculateHeightWithAspectRatio(uint width) {
        return width * OSK_HEIGHT_96DPI / (configOskNumpad ? OSK_WIDTH_WITH_NUMPAD_96DPI : OSK_WIDTH_NO_NUMPAD_96DPI);
    }

    switch (msg) {
        case WM_NCHITTEST:
        // Manually implement left and right resize handles, all other points drag the window
        short x = cast(short) (lParam & 0xFFFF);
        short y = cast(short) ((lParam >> 16) & 0xFFFF);

        const GRAB_WIDTH = 20;
        
        if (x < winRect.left + GRAB_WIDTH) {
            return HTLEFT;
        } else if (x > winRect.right - GRAB_WIDTH) {
            return HTRIGHT;
        } else {
            return HTCAPTION;
        }

        case WM_WINDOWPOSCHANGING:
        // Preserve aspect ratio when resizing
        WINDOWPOS *newWindowPos = cast(WINDOWPOS*) lParam;
        newWindowPos.cy = calculateHeightWithAspectRatio(newWindowPos.cx);
        break;

        case WM_GETMINMAXINFO:
        // // Preserve a minimal OSK width
        uint oskMinWidth = (OSK_MIN_WIDTH_96DPI * dpi) / 96;
        MINMAXINFO *minmaxinfo = cast(MINMAXINFO*) lParam;
        minmaxinfo.ptMinTrackSize = POINT(oskMinWidth, calculateHeightWithAspectRatio(oskMinWidth));
        break;

        case WM_SIZE:
        updateOSK();
        break;

        case WM_DRAWOSK:
        updateOSK();
        break;

        case WM_DPICHANGED:
        dpi = LOWORD(wParam);  // Update cached DPI
        // Accept new window size suggestion
        RECT* suggestedRect = cast(RECT*) lParam;
        SetWindowPos(hwnd, cast(HWND) 0, suggestedRect.left, suggestedRect.top,
            suggestedRect.right - suggestedRect.left, suggestedRect.bottom - suggestedRect.top,
            SWP_NOZORDER);
        break;

        default: break;
    }

    return DefWindowProc(hwnd, msg, wParam, lParam);
}

void centerOskOnScreen(HWND hwnd) {
    auto wndMonitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO monitorInfo;
    GetMonitorInfo(wndMonitor, &monitorInfo);
    RECT workArea = monitorInfo.rcWork;

    HMODULE user32Lib = GetModuleHandle("User32.dll".toUTF16z);
    auto ptrGetDpiForWindow = cast(UINT function(HWND)) GetProcAddress(user32Lib, "GetDpiForWindow".toStringz);
    if (ptrGetDpiForWindow) {
        dpi = ptrGetDpiForWindow(hwnd);  // Only available for Win 10 1607 and up
        debugWriteln("Running with PerMonitorV2 DPI scaling");
    } else {
        HDC screen = GetDC(NULL);  // Get system DPI on older versions of windows
        dpi = GetDeviceCaps(screen, LOGPIXELSX);
        ReleaseDC(NULL, screen);
        debugWriteln("Running with system DPI scaling");
    }

    uint winWidth = ((configOskNumpad ? OSK_WIDTH_WITH_NUMPAD_96DPI : OSK_WIDTH_NO_NUMPAD_96DPI) * dpi) / 96;
    uint winHeight = (OSK_HEIGHT_96DPI * dpi) / 96;
    uint winBottomOffset = (OSK_BOTTOM_OFFSET_96DPI * dpi) / 96;
    SetWindowPos(hwnd, cast(HWND) 0,
        workArea.left + (workArea.right - workArea.left - winWidth) / 2,
        workArea.bottom - winHeight - winBottomOffset,
        winWidth, winHeight, SWP_NOZORDER);
}