module trayicon;

import core.sys.windows.windows;

const UINT WM_TRAYICON = WM_USER + 10;

class TrayIcon {
    NOTIFYICONDATA nid;
    const MAX_TIPLEN = NOTIFYICONDATA.szTip.sizeof - 1;

    bool visible = false;
    size_t tipLen;

    this(HWND hwndParent, UINT id, HICON hicon, wchar[] tooltip)	{
        nid.cbSize = NOTIFYICONDATA.sizeof;
        nid.hWnd = hwndParent;
        nid.uID = id;
        nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
        nid.uCallbackMessage = WM_TRAYICON;
        nid.hIcon = hicon;
        // handle keyboard and mouse events differently beginning with Windows 2000.
        nid.uVersion = NOTIFYICON_VERSION;

        this.setTip(tooltip);
    }
    
    ~this() {
        hide();
    }

    // in case WM_TRAYICON conflicts, use this
    void message(UINT newMessage) {
        nid.uCallbackMessage = newMessage;
        if (visible) {
            Shell_NotifyIcon(NIM_MODIFY, &nid);
        }
    }

    UINT id() {
        return nid.uID;
    }
    
    void show() {
        hide();
        Shell_NotifyIcon(NIM_ADD, &nid);
        Shell_NotifyIcon(NIM_SETVERSION, &nid);
        visible = true;
    }

    void hide() {
        if (visible) {
            Shell_NotifyIcon(NIM_DELETE, &nid);
            visible = false;
        }
    }

    wchar[] tip() {
        return nid.szTip[0 .. tipLen];
    }

    void setTip(wchar[] newTip) {
        tipLen = (newTip.length > MAX_TIPLEN) ? MAX_TIPLEN : newTip.length;
        nid.szTip[0 .. tipLen] = newTip[0 .. tipLen];
        nid.szTip[tipLen] = 0;
        if (visible) {
            Shell_NotifyIcon(NIM_MODIFY, &nid);
        }
    }

    HICON icon() {
        return nid.hIcon;
    }   

    void setIcon(HICON hnewIcon) {
        nid.hIcon = hnewIcon;
        if(visible) {
            Shell_NotifyIcon(NIM_MODIFY, &nid);
        }
    }

    void showContextMenu(HWND hwndParent, HMENU menu) {
        POINT curPoint;
        GetCursorPos(&curPoint);

        SetForegroundWindow(hwndParent);
        // Alignment for contextmenu left/bottom, which seems the most practical and common use
        TrackPopupMenuEx(menu, TPM_LEFTBUTTON | TPM_RIGHTBUTTON | TPM_LEFTALIGN | TPM_BOTTOMALIGN, curPoint.x, curPoint.y, hwndParent, NULL);
    }
}
