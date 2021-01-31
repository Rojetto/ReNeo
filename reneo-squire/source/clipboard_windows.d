module clipboard_windows;

version(Windows) {
	import std.stdio;
	import core.stdc.string;
	import core.stdc.wchar_;
	import core.sys.windows.windows;
	import std.string;
	import std.conv;
	import std.utf;

	extern(Windows) {
		bool OpenClipboard(void*);
		void* GetClipboardData(uint);
		void* SetClipboardData(uint, void*);
		bool EmptyClipboard();
		bool CloseClipboard();
		void* GlobalAlloc(uint, size_t);
		void* GlobalLock(void*);
		bool GlobalUnlock(void*);
		bool SetConsoleCP(uint);
		bool SetConsoleOutputCP(uint);
	}

	/**
		Read a string from the clipboard.
	*/
	public wstring readClipboard() {
		if (OpenClipboard(null)) {
			scope(exit) {
				CloseClipboard();
			}
			auto cstr = cast(wchar*)GetClipboardData(13);
			if(cstr) {
				return to!wstring(cstr[0..wcslen(cstr)]);
			} else {
				return ""w;
			}
		} else {
			return ""w;
		}
	}

	/**
		Write a string to the clipboard.
	*/
	public void writeClipboard(wstring text) {
		if (OpenClipboard(null)) {
			scope(exit) {
				CloseClipboard();
			}
			
			auto data = toUTF16z(text);
			void* handle = GlobalAlloc(0, (to!wstring(text).length + 1) * 2); // each wchar needs two bytes!
			void* ptr = GlobalLock(handle);
			
			memcpy(ptr, data, (to!wstring(text).length + 1) * 2); // each wchar needs two bytes!
			GlobalUnlock(handle);
			SetClipboardData(13, handle);
		}
	}

	/**
		Clears the clipboard.
	*/
	public void clearClipboard() {
		EmptyClipboard();
	}

	/**
		Prepare the console in order to read and write UTF8 strings.
	*/
	public void prepareConsole() {
		SetConsoleCP(65001);
		SetConsoleOutputCP(65001);
	}
}