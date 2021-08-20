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


enum OSKTheme {
    Grey,
    NeoBlue
}


struct OSKKeyInfo {
    float x;
    float y;
    float width;
    Scancode scan;
}

auto KEY_POSITIONS = [
    // First row
    OSKKeyInfo(0, 0, 1, Scancode(0x29, false)),
    OSKKeyInfo(1, 0, 1, Scancode(0x02, false)),
    OSKKeyInfo(2, 0, 1, Scancode(0x03, false)),
    OSKKeyInfo(3, 0, 1, Scancode(0x04, false)),
    OSKKeyInfo(4, 0, 1, Scancode(0x05, false)),
    OSKKeyInfo(5, 0, 1, Scancode(0x06, false)),
    OSKKeyInfo(6, 0, 1, Scancode(0x07, false)),
    OSKKeyInfo(7, 0, 1, Scancode(0x08, false)),
    OSKKeyInfo(8, 0, 1, Scancode(0x09, false)),
    OSKKeyInfo(9, 0, 1, Scancode(0x0A, false)),
    OSKKeyInfo(10, 0, 1, Scancode(0x0B, false)),
    OSKKeyInfo(11, 0, 1, Scancode(0x0C, false)),
    OSKKeyInfo(12, 0, 1, Scancode(0x0D, false)),
    OSKKeyInfo(13, 0, 2, Scancode(0x0E, false)), // Backspace
    // Second row
    OSKKeyInfo(0, 1, 1.5, Scancode(0x0F, false)), // Tab
    OSKKeyInfo(1.5, 1, 1, Scancode(0x10, false)),
    OSKKeyInfo(2.5, 1, 1, Scancode(0x11, false)),
    OSKKeyInfo(3.5, 1, 1, Scancode(0x12, false)),
    OSKKeyInfo(4.5, 1, 1, Scancode(0x13, false)),
    OSKKeyInfo(5.5, 1, 1, Scancode(0x14, false)),
    OSKKeyInfo(6.5, 1, 1, Scancode(0x15, false)),
    OSKKeyInfo(7.5, 1, 1, Scancode(0x16, false)),
    OSKKeyInfo(8.5, 1, 1, Scancode(0x17, false)),
    OSKKeyInfo(9.5, 1, 1, Scancode(0x18, false)),
    OSKKeyInfo(10.5, 1, 1, Scancode(0x19, false)),
    OSKKeyInfo(11.5, 1, 1, Scancode(0x1A, false)),
    OSKKeyInfo(12.5, 1, 1, Scancode(0x1B, false)),
    // Third row
    OSKKeyInfo(0, 2, 1.75, Scancode(0x3A, false)), // Capslock
    OSKKeyInfo(1.75, 2, 1, Scancode(0x1E, false)),
    OSKKeyInfo(2.75, 2, 1, Scancode(0x1F, false)),
    OSKKeyInfo(3.75, 2, 1, Scancode(0x20, false)),
    OSKKeyInfo(4.75, 2, 1, Scancode(0x21, false)),
    OSKKeyInfo(5.75, 2, 1, Scancode(0x22, false)),
    OSKKeyInfo(6.75, 2, 1, Scancode(0x23, false)),
    OSKKeyInfo(7.75, 2, 1, Scancode(0x24, false)),
    OSKKeyInfo(8.75, 2, 1, Scancode(0x25, false)),
    OSKKeyInfo(9.75, 2, 1, Scancode(0x26, false)),
    OSKKeyInfo(10.75, 2, 1, Scancode(0x27, false)),
    OSKKeyInfo(11.75, 2, 1, Scancode(0x28, false)),
    OSKKeyInfo(12.75, 2, 1, Scancode(0x2B, false)),
    // Fourth row
    OSKKeyInfo(0, 3, 1.25, Scancode(0x2A, false)), // Shift
    OSKKeyInfo(1.25, 3, 1, Scancode(0x56, false)),
    OSKKeyInfo(2.25, 3, 1, Scancode(0x2C, false)),
    OSKKeyInfo(3.25, 3, 1, Scancode(0x2D, false)),
    OSKKeyInfo(4.25, 3, 1, Scancode(0x2E, false)),
    OSKKeyInfo(5.25, 3, 1, Scancode(0x2F, false)),
    OSKKeyInfo(6.25, 3, 1, Scancode(0x30, false)),
    OSKKeyInfo(7.25, 3, 1, Scancode(0x31, false)),
    OSKKeyInfo(8.25, 3, 1, Scancode(0x32, false)),
    OSKKeyInfo(9.25, 3, 1, Scancode(0x33, false)),
    OSKKeyInfo(10.25, 3, 1, Scancode(0x34, false)),
    OSKKeyInfo(11.25, 3, 1, Scancode(0x35, false)),
    OSKKeyInfo(12.25, 3, 2.75, Scancode(0x36, true)), // Shift
    // Fifth row
    OSKKeyInfo(3.75, 4, 6.25, Scancode(0x39, false)), // Space
    OSKKeyInfo(10, 4, 1.25, Scancode(0x38, true)), // AltGr
];

auto KEY_POSITIONS_NUMPAD = [
    // First row
    OSKKeyInfo(16, 0, 1, Scancode(0x45, true)),
    OSKKeyInfo(17, 0, 1, Scancode(0x35, true)),
    OSKKeyInfo(18, 0, 1, Scancode(0x37, false)),
    OSKKeyInfo(19, 0, 1, Scancode(0x4A, false)),
    // Second row
    OSKKeyInfo(16, 1, 1, Scancode(0x47, false)),
    OSKKeyInfo(17, 1, 1, Scancode(0x48, false)),
    OSKKeyInfo(18, 1, 1, Scancode(0x49, false)),
    // Third row
    OSKKeyInfo(16, 2, 1, Scancode(0x4B, false)),
    OSKKeyInfo(17, 2, 1, Scancode(0x4C, false)),
    OSKKeyInfo(18, 2, 1, Scancode(0x4D, false)),
    // Fourth row
    OSKKeyInfo(16, 3, 1, Scancode(0x4F, false)),
    OSKKeyInfo(17, 3, 1, Scancode(0x50, false)),
    OSKKeyInfo(18, 3, 1, Scancode(0x51, false)),
    // Fifth row
    OSKKeyInfo(16, 4, 2, Scancode(0x52, false)),
    OSKKeyInfo(18, 4, 1, Scancode(0x53, false)),
];

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

    // Load fonts
    WIN_FONTS ~= CreateFont(0, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, ANSI_CHARSET, OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH, "Segoe UI".toUTF16z);
    WIN_FONTS ~= CreateFont(0, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, ANSI_CHARSET, OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH, "Segoe UI Symbol".toUTF16z);
    
    foreach (HFONT win_font; WIN_FONTS) {
        CAIRO_FONTS ~= cairo_win32_font_face_create_for_hfont(win_font);
    }
}

cairo_font_face_t* get_font_face_for_char(HDC hdc, string c) {
    for (int i = 0; i < WIN_FONTS.length - 1; i++) {
        SelectObject(hdc, WIN_FONTS[i]);
        WORD glyph_index;
        GetGlyphIndices(hdc, c.toUTF16z, 1, &glyph_index, GGI_MARK_NONEXISTING_GLYPHS);
        if (glyph_index != 0xffff) {
            return CAIRO_FONTS[i];
        }
    }

    // Fallback, return last font
    return CAIRO_FONTS[CAIRO_FONTS.length - 1];
}

void draw_osk(HWND hwnd, NeoLayout *layout, uint layer, bool capslock) {
    RECT win_rect;
    GetWindowRect(hwnd, &win_rect);
    const uint win_width = win_rect.right - win_rect.left;
    const uint win_height = win_rect.bottom - win_rect.top;

    // window is unsuitable for drawing
    if (win_width == 0 || win_height == 0) {
        return;
    }
    
    HDC hdcScreen = GetDC(NULL);

    // Offscreen hdc for painting
    HDC hdcMem = CreateCompatibleDC(hdcScreen);
    HBITMAP hbmMem = CreateCompatibleBitmap(hdcScreen, win_width, win_height);
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
    float keyboard_width_px, keyboard_height_px;
    const float KEYBOARD_WIDTH = configOskNumpad ? KEYBOARD_WIDTH_WITH_NUMPAD : KEYBOARD_WIDTH_NO_NUMPAD;
    // should we letterbox left and right or on top and bottom?
    if (win_width / win_height > KEYBOARD_WIDTH / KEYBOARD_HEIGHT) {
        // letterbox left and right
        keyboard_height_px = win_height;
        keyboard_width_px = keyboard_height_px * KEYBOARD_WIDTH / KEYBOARD_HEIGHT;
    } else {
        // letterbox top and bottom
        keyboard_width_px = win_width;
        keyboard_height_px = keyboard_width_px * KEYBOARD_HEIGHT / KEYBOARD_WIDTH;
    }
    cairo_translate(cr, (win_width - keyboard_width_px) / 2, (win_height - keyboard_height_px) / 2);
    cairo_scale(cr, keyboard_width_px / KEYBOARD_WIDTH, keyboard_height_px / KEYBOARD_HEIGHT);

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

    void show_key_label_centered(Scancode scan, float key_x, float key_width, float baseline) {
        if (layout != null) {
            string label;
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

                label = layout.map[scan].layers[layerConsideringCapslock-1].label;
            } else if (scan == Scancode(0x0E, false)) {
                label = "\u232b"; // Backspace
            } else if (scan == Scancode(0x1C, true) || scan == Scancode(0x1C, false)) {
                label = "\u21a9"; // Return or Numpad Return
            } else if (scan in layout.modifiers) {
                uint mod = layout.modifiers[scan] & 0xFFFE; // convert left and right variant to left variant
                switch (mod) {
                    case Modifier.LSHIFT: label = "\u21e7"; break;
                    case Modifier.LCTRL: label = "Ctrl"; break;
                    case Modifier.LALT: label = "Alt"; break;
                    case Modifier.MOD3: label = "M3"; break;
                    case Modifier.MOD4: label = "M4"; break;
                    case Modifier.MOD5: label = "M5"; break;
                    case Modifier.MOD6: label = "M6"; break;
                    case Modifier.MOD7: label = "M7"; break;
                    case Modifier.MOD8: label = "M8"; break;
                    case Modifier.MOD9: label = "M9"; break;
                    default: break;
                }
            }

            cairo_set_source_rgba(cr, 0.95, 0.95, 0.95, 1.0);
            cairo_set_font_face(cr, get_font_face_for_char(hdcMem, label));
            auto labelz = label.toStringz;
            cairo_text_extents_t extents;
            cairo_text_extents(cr, labelz, &extents);
            cairo_move_to(cr, key_x + (key_width - extents.width) / 2, baseline);
            cairo_show_text(cr, labelz);
        }
    }

    // Draw “regular” keys, i.e. keys with height 1
    foreach (key; configOskNumpad ? KEY_POSITIONS ~ KEY_POSITIONS_NUMPAD : KEY_POSITIONS) {    
        round_rectangle(cr, key.x + PADDING, key.y + PADDING, key.width - 2*PADDING, 1 - 2*PADDING, CORNER_RADIUS);
        cairo_set_source(cr, KEY_COLOR);
        cairo_fill(cr);

        show_key_label_centered(key.scan, key.x, key.width, key.y + BASE_LINE);
    }

    // Draw special keys with height ≠ 1
    if (configOskNumpad) {
        // Numpad Add
        round_rectangle(cr, 19 + PADDING, 1 + PADDING, 1 - 2*PADDING, 2 - 2*PADDING, CORNER_RADIUS);
        cairo_set_source(cr, KEY_COLOR);
        cairo_fill(cr);
        show_key_label_centered(Scancode(0x4E, false), 19, 1, 1.5 + BASE_LINE);
        // Numpad Return
        round_rectangle(cr, 19 + PADDING, 3 + PADDING, 1 - 2*PADDING, 2 - 2*PADDING, CORNER_RADIUS);
        cairo_set_source(cr, KEY_COLOR);
        cairo_fill(cr);
        show_key_label_centered(Scancode(0x1C, true), 19, 1, 3.5 + BASE_LINE);
    }
    // Return
    return_key(cr, 13.5 + PADDING, 1 + PADDING, 1.5 - 2*PADDING, 1.25 - 2*PADDING, 1 - 2*PADDING, 1, CORNER_RADIUS);
    cairo_set_source(cr, KEY_COLOR);
    cairo_fill(cr);
    show_key_label_centered(Scancode(0x1C, false), 13.75, 1.25, 1.5 + BASE_LINE);

    // Cairo cleanup    
    cairo_destroy(cr);
    cairo_surface_destroy(surface);

    // Show on screen
    BLENDFUNCTION blend = { 0 };
    blend.BlendOp = AC_SRC_OVER;
    blend.SourceConstantAlpha = 255;
    blend.AlphaFormat = AC_SRC_ALPHA;

    POINT ptZero = POINT(0, 0);
    POINT win_pos = POINT(win_rect.left, win_rect.top);
    SIZE win_dims = SIZE(win_width, win_height);

    UpdateLayeredWindow(hwnd, hdcScreen, &win_pos, &win_dims, hdcMem, &ptZero, RGB(0, 0, 0), &blend, ULW_ALPHA);

    // Reset offscreen hdc to default bitmap
    SelectObject(hdcMem, hOld);

    // Cleanup
    DeleteObject(hbmMem);
    DeleteDC(hdcMem);
    ReleaseDC(NULL, hdcScreen);
}

void round_rectangle(cairo_t *cr, float x, float y, float w, float h, float r) {
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

void return_key(cairo_t *cr, float x, float y, float w_u, float w_l, float h_u, float h_l, float r) {
    const float QR = M_PI / 2;

    cairo_save(cr);

    cairo_translate(cr, x, y);

    cairo_new_sub_path(cr);
    cairo_arc(cr, w_u - r, h_u + h_l - r, r, 0*QR, 1*QR);
    cairo_arc(cr, w_u - w_l + r, h_u + h_l - r, r, 1*QR, 2*QR);
    cairo_arc_negative(cr, w_u - w_l - r, h_u + r, r, 0*QR, -1*QR);
    cairo_arc(cr, r, h_u - r, r, 1*QR, 2*QR);
    cairo_arc(cr, r, r, r, 2*QR, 3*QR);
    cairo_arc(cr, w_u - r, r, r, 3*QR, 4*QR);
    cairo_close_path(cr);

    cairo_restore(cr);
}

LRESULT oskWndProc(HWND hwnd, uint msg, WPARAM wParam, LPARAM lParam) {
    RECT win_rect;
    GetWindowRect(hwnd, &win_rect);

    uint calculateHeightWithAspectRatio(uint width) {
        return width * OSK_HEIGHT_96DPI / (configOskNumpad ? OSK_WIDTH_WITH_NUMPAD_96DPI : OSK_WIDTH_NO_NUMPAD_96DPI);
    }

    switch (msg) {
        case WM_NCHITTEST:
        // Manually implement left and right resize handles, all other points drag the window
        short x = cast(short) (lParam & 0xFFFF);
        short y = cast(short) ((lParam >> 16) & 0xFFFF);

        const GRAB_WIDTH = 20;
        
        if (x < win_rect.left + GRAB_WIDTH) {
            return HTLEFT;
        } else if (x > win_rect.right - GRAB_WIDTH) {
            return HTRIGHT;
        } else {
            return HTCAPTION;
        }

        case WM_WINDOWPOSCHANGING:
        // Preserve aspect ratio when resizing
        WINDOWPOS *new_window_pos = cast(WINDOWPOS*) lParam;
        new_window_pos.cy = calculateHeightWithAspectRatio(new_window_pos.cx);
        break;

        case WM_GETMINMAXINFO:
        // // Preserve a minimal OSK width
        uint osk_min_width = (OSK_MIN_WIDTH_96DPI * dpi) / 96;
        MINMAXINFO *minmaxinfo = cast(MINMAXINFO*) lParam;
        minmaxinfo.ptMinTrackSize = POINT(osk_min_width, calculateHeightWithAspectRatio(osk_min_width));
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
        debug_writeln("Running with PerMonitorV2 DPI scaling");
    } else {
        HDC screen = GetDC(NULL);  // Get system DPI on older versions of windows
        dpi = GetDeviceCaps(screen, LOGPIXELSX);
        ReleaseDC(NULL, screen);
        debug_writeln("Running with system DPI scaling");
    }

    uint win_width = ((configOskNumpad ? OSK_WIDTH_WITH_NUMPAD_96DPI : OSK_WIDTH_NO_NUMPAD_96DPI) * dpi) / 96;
    uint win_height = (OSK_HEIGHT_96DPI * dpi) / 96;
    uint win_bottom_offset = (OSK_BOTTOM_OFFSET_96DPI * dpi) / 96;
    SetWindowPos(hwnd, cast(HWND) 0,
        workArea.left + (workArea.right - workArea.left - win_width) / 2,
        workArea.bottom - win_height - win_bottom_offset,
        win_width, win_height, SWP_NOZORDER);
}