// FastRevers for Windows: fixes text typed in the wrong RU/EN keyboard layout.
// One native .exe: no installer, no runtime, settings are kept next to the exe. The same exe also runs
// from the Microsoft Store package (MSIX): then settings live in the package's data folder.
//   Space                  - a word typed in the wrong layout is fixed automatically
//   Pause or double Shift  - fix the last word (again - revert); with no fresh word, fix the selected text
//   Shift+Pause            - fix the selected text
#include <windows.h>
#include <appmodel.h>
#include <commctrl.h>
#include <roapi.h>
#include <shellapi.h>
#include <shlobj.h>
#include <windows.applicationmodel.h>
#include <wrl/client.h>
#include <wrl/wrappers/corewrappers.h>

#include <algorithm>
#include <deque>
#include <string>
#include <vector>

#include "ls_core.h"
#include "resource.h"

namespace {

constexpr ULONG_PTR kMagic = 0x4C53;   // marks our own SendInput events so the hook skips them
constexpr DWORD kTapMaxHold = 400;     // ms: a longer Shift press is not a tap
constexpr DWORD kDoubleTapGap = 400;   // ms between the two taps of a double Shift
constexpr WORD kLangEn = LANG_ENGLISH, kLangRu = LANG_RUSSIAN;
const wchar_t kWndClass[] = L"LS_LiteSwitcher";        // the same in every version since 2.0: one copy of any
const wchar_t kMutex[] = L"Local\\LS_LiteSwitcher";     // of them runs, and an older one is found and closed
const wchar_t kRunKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
const wchar_t kApprovedKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run";
const wchar_t kRunName[] = L"FastRevers";
const wchar_t kStartupTaskId[] = L"FastReversStartup";  // windows.startupTask in windows/msix/AppxManifest.xml

// Earlier names of the program, newest first: 2.1.x was LiteSwitcher, 2.0.x was LS. Their settings and
// autostart are taken over once; when both are there, the newer one wins.
struct OldName {
    const wchar_t *exe, *ini, *dir, *run;
};
const OldName kOldNames[] = {
    {L"LiteSwitcher.exe", L"LiteSwitcher.ini", L"LiteSwitcher", L"LiteSwitcher"},
    {L"LS.exe", L"LS.ini", L"LS", L"LS"},
};
const char kTerminals[] =
    "windowsterminal cmd powershell pwsh conhost openconsole putty kitty mintty alacritty wezterm-gui mobaxterm tabby hyper";

enum : UINT { WM_TRAY = WM_APP + 1, WM_LS_RUN, WM_LS_HELLO };
enum : UINT { IDM_AUTO = 100, IDM_SHIFT, IDM_STARTUP, IDM_EXCEPTIONS, IDM_RELOAD, IDM_EXIT, IDM_DONATE, IDM_PRIVACY };
constexpr UINT_PTR kTimerExceptions = 1;

struct Key {
    WORD vk, sc;
    bool shift, caps;
};

// Work decided inside the keyboard hook and carried out right after it returns.
struct Action {
    bool selection;      // fix the selected text instead of retyping
    int erase;           // characters to delete
    std::wstring text;   // text to type instead
    WORD tail;           // key to send afterwards (the Space that triggered the fix), 0 for none
    HWND target;         // window whose layout is switched
    HKL hkl;             // layout to switch to
    std::wstring learn;  // word to add to the exceptions (an auto-fix was undone)
};

HINSTANCE g_inst;
HWND g_wnd;
HHOOK g_kbd, g_mouse;
UINT g_taskbarCreated;
bool g_ru;        // Russian UI
bool g_packaged;  // runs from the Microsoft Store package (MSIX)
bool g_closedOld, g_adoptedFiles, g_adoptedStartup;  // what was taken over from an older version at this start
const wchar_t *g_oldExe;                             // and the file name of that version
std::wstring g_exe, g_dir, g_ini, g_exc;
bool g_optAuto = true, g_optShift = true;
FILETIME g_excTime{};
NOTIFYICONDATAW g_nid{};

std::vector<Key> g_buf;          // keys of the current word
HKL g_bufHkl = 0;                // layout the word is being typed in
HKL g_bufLayout = 0;             // layout the word is shown in after our own fix
std::wstring g_lastAuto;         // the word as it was before the last auto-fix (learning on undo)
HWND g_lastFg = 0;
bool g_fgExcluded = false;
bool g_caps = false, g_capsDown = false;
bool g_shiftDown[2]{};
bool g_shiftClean = false;
DWORD g_shiftDownAt = 0, g_lastTap = 0;
std::deque<Action> g_actions;
bool g_selBusy = false;

const wchar_t *T(const wchar_t *ru, const wchar_t *en) { return g_ru ? ru : en; }

bool DetectRussianUi()
{
    return PRIMARYLANGID(GetUserDefaultUILanguage()) == LANG_RUSSIAN ||
           PRIMARYLANGID(LANGIDFROMLCID(GetUserDefaultLCID())) == LANG_RUSSIAN;
}

// ------------------------------------------------------------------ files and settings
std::string Utf8(const std::wstring &w)
{
    if (w.empty()) return {};
    int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), nullptr, 0, nullptr, nullptr);
    std::string s(n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), s.data(), n, nullptr, nullptr);
    return s;
}

bool ReadAll(const std::wstring &path, std::string &out)
{
    HANDLE h = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                           OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return false;
    LARGE_INTEGER size{};
    bool ok = GetFileSizeEx(h, &size) && size.QuadPart < (16 << 20);
    if (ok) {
        out.resize((size_t)size.QuadPart);
        DWORD got = 0;
        ok = out.empty() || (ReadFile(h, out.data(), (DWORD)out.size(), &got, nullptr) && got == out.size());
    }
    CloseHandle(h);
    return ok;
}

bool Append(const std::wstring &path, const std::string &data)
{
    HANDLE h = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ, nullptr, OPEN_ALWAYS,
                           FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return false;
    DWORD put = 0;
    bool ok = WriteFile(h, data.data(), (DWORD)data.size(), &put, nullptr) && put == data.size();
    CloseHandle(h);
    return ok;
}

FILETIME FileTime(const std::wstring &path)
{
    WIN32_FILE_ATTRIBUTE_DATA d{};
    if (GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &d)) return d.ftLastWriteTime;
    return {};
}

bool Exists(const std::wstring &path) { return GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES; }

// Settings of an older name (LiteSwitcher.ini, LS.ini, %APPDATA%\LiteSwitcher...) are taken over once, by
// renaming them.
bool AdoptOld(const std::wstring &oldPath, const std::wstring &newPath, const wchar_t *oldExe)
{
    if (Exists(newPath) || !Exists(oldPath) || !MoveFileW(oldPath.c_str(), newPath.c_str())) return false;
    g_adoptedFiles = true;
    if (!g_oldExe) g_oldExe = oldExe;
    return true;
}

void AdoptOldIni(const std::wstring &dir)
{
    for (const OldName &o : kOldNames) AdoptOld(dir + L"\\" + o.ini, dir + L"\\FastRevers.ini", o.exe);
}

bool IsPackaged()
{
    UINT32 n = 0;
    return GetCurrentPackageFullName(&n, nullptr) == ERROR_INSUFFICIENT_BUFFER;
}

// The package's own data folder, %LOCALAPPDATA%\Packages\<family>\LocalState. It is a real folder, so
// Notepad (outside the package) opens exceptions.txt there; plain AppData writes of a packaged app would
// be redirected into a private copy that Notepad does not see.
std::wstring PackageDataDir()
{
    UINT32 n = 0;
    if (GetCurrentPackageFamilyName(&n, nullptr) != ERROR_INSUFFICIENT_BUFFER || !n) return {};
    std::wstring family(n, L'\0');
    if (GetCurrentPackageFamilyName(&n, family.data()) != ERROR_SUCCESS) return {};
    family.resize(wcslen(family.c_str()));
    std::wstring dir;
    PWSTR local = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local)))
        dir = std::wstring(local) + L"\\Packages\\" + family + L"\\LocalState";
    CoTaskMemFree(local);
    return dir;
}

void InitPaths()
{
    wchar_t buf[MAX_PATH * 4];
    DWORD n = GetModuleFileNameW(nullptr, buf, ARRAYSIZE(buf));
    g_exe.assign(buf, n);
    g_dir = g_exe.substr(0, g_exe.find_last_of(L"\\/"));
    g_packaged = IsPackaged();
    std::wstring packageDir = g_packaged ? PackageDataDir() : std::wstring();
    if (!packageDir.empty()) {  // Microsoft Store: the program folder is read-only
        g_dir = packageDir;
        CreateDirectoryW(g_dir.c_str(), nullptr);
        g_ini = g_dir + L"\\FastRevers.ini";
        g_exc = g_dir + L"\\exceptions.txt";
        return;
    }
    // Portable: settings live next to FastRevers.exe. If that folder is read-only, fall back to
    // %APPDATA%\FastRevers.
    AdoptOldIni(g_dir);
    HANDLE h = CreateFileW((g_dir + L"\\FastRevers.ini").c_str(), FILE_APPEND_DATA,
                           FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_ALWAYS,
                           FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h != INVALID_HANDLE_VALUE) {
        CloseHandle(h);
    } else {
        PWSTR app = nullptr;
        if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &app))) {
            std::wstring base(app);
            for (const OldName &o : kOldNames) AdoptOld(base + L"\\" + o.dir, base + L"\\FastRevers", o.exe);
            g_dir = base + L"\\FastRevers";
            CreateDirectoryW(g_dir.c_str(), nullptr);
            AdoptOldIni(g_dir);
        }
        CoTaskMemFree(app);
    }
    g_ini = g_dir + L"\\FastRevers.ini";
    g_exc = g_dir + L"\\exceptions.txt";
}

bool ReadOption(const wchar_t *name, int def)
{
    return GetPrivateProfileIntW(L"Options", name, def, g_ini.c_str()) != 0;
}

void WriteOption(const wchar_t *name, bool value)
{
    WritePrivateProfileStringW(L"Options", name, value ? L"1" : L"0", g_ini.c_str());
}

// ------------------------------------------------------------------ exceptions
void LoadExceptions()
{
    ls_exc_reset();
    std::string t = kTerminals;
    for (size_t i = 0; i < t.size();) {
        size_t j = t.find(' ', i);
        if (j == std::string::npos) j = t.size();
        ls_app_add_utf8(t.substr(i, j - i).c_str());
        i = j + 1;
    }
    std::string data;
    if (ReadAll(g_exc, data)) ls_exc_load(data.data(), data.size());
    g_excTime = FileTime(g_exc);
    g_lastFg = nullptr;  // check the active program against the new list
}

void EnsureExceptionsFile()
{
    if (Exists(g_exc)) return;
    Append(g_exc, Utf8(T(L"# Исключения FastRevers. Одно слово в строке — оно не будет автоисправляться.\r\n"
                         L"# Строка вида @имя_программы (без .exe) отключает автопереключение в этой программе.\r\n",
                         L"# FastRevers exceptions. One word per line: it will not be auto-fixed.\r\n"
                         L"# A line like @program_name (without .exe) turns auto-switching off in that program.\r\n")));
}

void AddException(const std::wstring &word)
{
    const ls_char *w = (const ls_char *)word.data();
    if (word.empty() || ls_exc_has_word(w, (int)word.size())) return;
    ls_exc_add_word(w, (int)word.size());
    EnsureExceptionsFile();
    std::string data, line = Utf8(word) + "\r\n";
    if (ReadAll(g_exc, data) && !data.empty() && data.back() != '\n') line = "\r\n" + line;
    Append(g_exc, line);
    g_excTime = FileTime(g_exc);
}

// ------------------------------------------------------------------ layouts
WORD Lang(HKL h) { return PRIMARYLANGID(LOWORD((UINT_PTR)h)); }

int LayoutList(HKL *list, int cap) { return GetKeyboardLayoutList(cap, list); }

// The English and Russian layouts; the active one is preferred when there are several of a language.
void FindLayouts(HKL cur, HKL *en, HKL *ru)
{
    HKL list[64];
    int n = LayoutList(list, 64);
    *en = *ru = nullptr;
    for (int i = 0; i < n; i++) {
        if (Lang(list[i]) == kLangEn && !*en) *en = list[i];
        if (Lang(list[i]) == kLangRu && !*ru) *ru = list[i];
    }
    if (cur && Lang(cur) == kLangEn) *en = cur;
    if (cur && Lang(cur) == kLangRu) *ru = cur;
}

HKL NextLayout(HKL cur)
{
    HKL en, ru;
    FindLayouts(cur, &en, &ru);
    if (en && ru) return Lang(cur) == kLangRu ? en : ru;
    HKL list[64];
    int n = LayoutList(list, 64);
    if (n < 2) return cur;
    for (int i = 0; i < n; i++)
        if (list[i] == cur) return list[(i + 1) % n];
    return list[0];
}

// Layout of the window that has keyboard focus; target receives the focus window.
HKL FocusLayout(HWND *target)
{
    HWND fg = GetForegroundWindow(), w = fg;
    if (target) *target = fg;
    if (!fg) return nullptr;
    DWORD tid = GetWindowThreadProcessId(fg, nullptr);
    GUITHREADINFO gti{sizeof(gti)};
    if (GetGUIThreadInfo(tid, &gti) && gti.hwndFocus) {
        w = gti.hwndFocus;
        tid = GetWindowThreadProcessId(w, nullptr);
    }
    if (target) *target = w;
    return GetKeyboardLayout(tid);
}

void SwitchLayout(HWND target, HKL hkl)
{
    if (target && hkl) PostMessageW(target, WM_INPUTLANGCHANGEREQUEST, 0, (LPARAM)hkl);
}

// Text the keys give in a layout. Keys are matched by scan code, so it also works with Dvorak and the like.
std::wstring Render(const std::vector<Key> &keys, HKL hkl)
{
    BYTE state[256]{};
    wchar_t out[8];
    std::wstring s;
    for (const Key &k : keys) {
        if (k.vk == VK_SPACE) {
            s += L' ';
            continue;
        }
        state[VK_SHIFT] = k.shift ? 0x80 : 0;
        state[VK_CAPITAL] = k.caps ? 1 : 0;
        UINT vk = k.sc ? MapVirtualKeyExW(k.sc, MAPVK_VSC_TO_VK, hkl) : 0;
        if (!vk) vk = k.vk;
        int n = ToUnicodeEx(vk, k.sc, state, out, 8, 4 /* keep the keyboard state */, hkl);
        if (n > 0) s.append(out, n);
    }
    return s;
}

// The two layouts key by key, for converting selected text.
void BuildMap(HKL en, HKL ru, std::wstring &enChars, std::wstring &ruChars)
{
    static const WORD scans[] = {0x29, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D,
                                 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x2B,
                                 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28,
                                 0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x56};
    BYTE state[256]{};
    enChars.clear();
    ruChars.clear();
    for (int shift = 0; shift < 2; shift++) {
        state[VK_SHIFT] = shift ? 0x80 : 0;
        for (WORD sc : scans) {
            UINT ve = MapVirtualKeyExW(sc, MAPVK_VSC_TO_VK, en), vr = MapVirtualKeyExW(sc, MAPVK_VSC_TO_VK, ru);
            wchar_t a[8], b[8];
            if (!ve || !vr) continue;
            if (ToUnicodeEx(ve, sc, state, a, 8, 4, en) == 1 && ToUnicodeEx(vr, sc, state, b, 8, 4, ru) == 1 &&
                a[0] != b[0]) {
                enChars += a[0];
                ruChars += b[0];
            }
        }
    }
}

std::wstring MapText(std::wstring s, HKL en, HKL ru, bool toRu)
{
    std::wstring e, r;
    BuildMap(en, ru, e, r);
    const std::wstring &from = toRu ? e : r, &to = toRu ? r : e;
    ls_map_text((ls_char *)s.data(), (int)s.size(), (const ls_char *)from.data(), (const ls_char *)to.data(),
                (int)from.size());
    return s;
}

// ------------------------------------------------------------------ the active program
bool IsExcludedProgram(HWND fg)
{
    if (!fg) return false;
    DWORD pid = 0;
    GetWindowThreadProcessId(fg, &pid);
    HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!h) return false;
    wchar_t path[MAX_PATH * 2];
    DWORD n = ARRAYSIZE(path);
    BOOL ok = QueryFullProcessImageNameW(h, 0, path, &n);
    CloseHandle(h);
    if (!ok) return false;
    std::wstring name(path, n);
    name.erase(0, name.find_last_of(L'\\') + 1);
    if (name.size() > 4 && _wcsicmp(name.c_str() + name.size() - 4, L".exe") == 0) name.resize(name.size() - 4);
    return ls_app_excluded((const ls_char *)name.data(), (int)name.size());
}

// Classic password boxes (Win32 and WinForms edits); other programs are not detectable cheaply.
bool IsPasswordBox(HWND w)
{
    wchar_t cls[64];
    if (!w || !GetClassNameW(w, cls, ARRAYSIZE(cls))) return false;
    CharUpperW(cls);
    if (wcscmp(cls, L"EDIT") != 0 && !wcsstr(cls, L".EDIT.")) return false;
    return (GetWindowLongPtrW(w, GWL_STYLE) & ES_PASSWORD) != 0;
}

// ------------------------------------------------------------------ synthetic input
void AddKey(std::vector<INPUT> &in, WORD vk, WORD sc, DWORD flags)
{
    INPUT i{};
    i.type = INPUT_KEYBOARD;
    i.ki.wVk = vk;
    i.ki.wScan = sc;
    i.ki.dwFlags = flags;
    i.ki.dwExtraInfo = kMagic;
    in.push_back(i);
}

void SendText(int erase, const std::wstring &text, WORD tail)
{
    std::vector<INPUT> in;
    for (int i = 0; i < erase; i++) {
        AddKey(in, VK_BACK, 0x0E, 0);
        AddKey(in, VK_BACK, 0x0E, KEYEVENTF_KEYUP);
    }
    for (wchar_t c : text) {
        AddKey(in, 0, c, KEYEVENTF_UNICODE);
        AddKey(in, 0, c, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP);
    }
    if (tail) {
        WORD sc = (WORD)MapVirtualKeyW(tail, MAPVK_VK_TO_VSC);
        AddKey(in, tail, sc, 0);
        AddKey(in, tail, sc, KEYEVENTF_KEYUP);
    }
    if (!in.empty()) SendInput((UINT)in.size(), in.data(), sizeof(INPUT));
}

void SendCtrl(WORD vk)
{
    std::vector<INPUT> in;
    WORD ctrl = (WORD)MapVirtualKeyW(VK_CONTROL, MAPVK_VK_TO_VSC), sc = (WORD)MapVirtualKeyW(vk, MAPVK_VK_TO_VSC);
    // A Shift still held (Shift+Pause) would turn Ctrl+C into Ctrl+Shift+C.
    if (GetAsyncKeyState(VK_LSHIFT) & 0x8000) AddKey(in, VK_LSHIFT, 0x2A, KEYEVENTF_KEYUP);
    if (GetAsyncKeyState(VK_RSHIFT) & 0x8000) AddKey(in, VK_RSHIFT, 0x36, KEYEVENTF_KEYUP);
    AddKey(in, VK_CONTROL, ctrl, 0);
    AddKey(in, vk, sc, 0);
    AddKey(in, vk, sc, KEYEVENTF_KEYUP);
    AddKey(in, VK_CONTROL, ctrl, KEYEVENTF_KEYUP);
    SendInput((UINT)in.size(), in.data(), sizeof(INPUT));
}

// Keeps the message loop (and with it the hooks) running while waiting.
template <class Done> void Pump(DWORD ms, Done done)
{
    DWORD start = GetTickCount();
    for (;;) {
        MSG m;
        while (PeekMessageW(&m, nullptr, 0, 0, PM_REMOVE)) {
            if (m.message == WM_QUIT) {
                PostQuitMessage((int)m.wParam);
                return;
            }
            TranslateMessage(&m);
            DispatchMessageW(&m);
        }
        if (done()) return;
        DWORD spent = GetTickCount() - start;
        if (spent >= ms) return;
        MsgWaitForMultipleObjects(0, nullptr, FALSE, std::min<DWORD>(ms - spent, 10), QS_ALLINPUT);
    }
}

// ------------------------------------------------------------------ clipboard (selected text)
struct ClipItem {
    UINT format;
    HGLOBAL data;
};

bool OpenClip()
{
    for (int i = 0; i < 20; i++) {
        if (OpenClipboard(g_wnd)) return true;
        Sleep(10);
    }
    return false;
}

// Keeps what we put on the clipboard out of the Win+V history and the cloud clipboard.
void MarkPrivate()
{
    static const UINT formats[] = {RegisterClipboardFormatW(L"ExcludeClipboardContentFromMonitorProcessing"),
                                   RegisterClipboardFormatW(L"CanIncludeInClipboardHistory"),
                                   RegisterClipboardFormatW(L"CanUploadToCloudClipboard")};
    for (UINT f : formats) {
        HGLOBAL g = GlobalAlloc(GMEM_MOVEABLE, sizeof(DWORD));
        if (!g) continue;
        *(DWORD *)GlobalLock(g) = 0;
        GlobalUnlock(g);
        if (!SetClipboardData(f, g)) GlobalFree(g);
    }
}

std::vector<ClipItem> SaveClipboard()
{
    std::vector<ClipItem> items;
    if (!OpenClip()) return items;
    for (UINT f = EnumClipboardFormats(0); f; f = EnumClipboardFormats(f)) {
        if (f == CF_BITMAP || f == CF_METAFILEPICT || f == CF_PALETTE || f == CF_ENHMETAFILE || f == CF_OWNERDISPLAY ||
            f == CF_DSPBITMAP || f == CF_DSPMETAFILEPICT || f == CF_DSPENHMETAFILE ||
            (f >= CF_PRIVATEFIRST && f <= CF_PRIVATELAST) || (f >= CF_GDIOBJFIRST && f <= CF_GDIOBJLAST))
            continue;  // not plain memory; bitmaps are rebuilt by Windows from CF_DIB
        HANDLE h = GetClipboardData(f);
        SIZE_T n = h ? GlobalSize(h) : 0;
        if (!n || n > (SIZE_T(64) << 20)) continue;
        void *src = GlobalLock(h);
        if (!src) continue;
        HGLOBAL copy = GlobalAlloc(GMEM_MOVEABLE, n);
        if (copy) {
            memcpy(GlobalLock(copy), src, n);
            GlobalUnlock(copy);
            items.push_back({f, copy});
        }
        GlobalUnlock(h);
    }
    CloseClipboard();
    return items;
}

void RestoreClipboard(std::vector<ClipItem> &items)
{
    if (!OpenClip()) {
        for (auto &i : items) GlobalFree(i.data);
        return;
    }
    EmptyClipboard();
    for (auto &i : items)
        if (!SetClipboardData(i.format, i.data)) GlobalFree(i.data);
    if (!items.empty()) MarkPrivate();
    CloseClipboard();
    items.clear();
}

std::wstring ClipText()
{
    std::wstring s;
    if (!OpenClip()) return s;
    if (HANDLE h = GetClipboardData(CF_UNICODETEXT))
        if (const wchar_t *p = (const wchar_t *)GlobalLock(h)) {
            s.assign(p, wcsnlen(p, GlobalSize(h) / sizeof(wchar_t)));
            GlobalUnlock(h);
        }
    CloseClipboard();
    return s;
}

void SetClipText(const std::wstring &s)
{
    if (!OpenClip()) return;
    EmptyClipboard();
    if (HGLOBAL g = GlobalAlloc(GMEM_MOVEABLE, (s.size() + 1) * sizeof(wchar_t))) {
        wchar_t *p = (wchar_t *)GlobalLock(g);
        memcpy(p, s.c_str(), (s.size() + 1) * sizeof(wchar_t));
        GlobalUnlock(g);
        if (!SetClipboardData(CF_UNICODETEXT, g)) GlobalFree(g);
    }
    MarkPrivate();
    CloseClipboard();
}

void ConvertSelection()
{
    if (g_selBusy) return;
    g_selBusy = true;
    HWND target;
    FocusLayout(&target);
    HKL en, ru;
    FindLayouts(nullptr, &en, &ru);
    if (en && ru) {
        std::vector<ClipItem> saved = SaveClipboard();
        if (OpenClip()) {
            EmptyClipboard();
            CloseClipboard();
        }
        DWORD seq = GetClipboardSequenceNumber();
        SendCtrl('C');
        std::wstring text;
        Pump(500, [&] {
            if (GetClipboardSequenceNumber() == seq) return false;
            text = ClipText();
            return !text.empty();
        });
        if (!text.empty()) {
            bool toRu = ls_latin_wins((const ls_char *)text.data(), (int)text.size()) != 0;
            SetClipText(MapText(text, en, ru, toRu));
            SendCtrl('V');
            SwitchLayout(target, toRu ? ru : en);
            Pump(300, [] { return false; });  // let the program paste before the clipboard is restored
        }
        RestoreClipboard(saved);
    }
    g_selBusy = false;
}

void RunActions()
{
    while (!g_actions.empty()) {
        Action a = std::move(g_actions.front());
        g_actions.pop_front();
        if (a.selection) {
            ConvertSelection();
            continue;
        }
        SendText(a.erase, a.text, a.tail);
        SwitchLayout(a.target, a.hkl);
        if (!a.learn.empty()) AddException(a.learn);
    }
}

void Queue(Action a)
{
    g_actions.push_back(std::move(a));
    PostMessageW(g_wnd, WM_LS_RUN, 0, 0);
}

// ------------------------------------------------------------------ typing tracker (runs inside the hook)
bool Held(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }

bool EndsWithSpace() { return !g_buf.empty() && g_buf.back().vk == VK_SPACE; }

bool IsCharVk(DWORD vk)
{
    return (vk >= 0x30 && vk <= 0x39) || (vk >= 0x41 && vk <= 0x5A) || (vk >= 0xBA && vk <= 0xC0) ||
           (vk >= 0xDB && vk <= 0xDF) || vk == 0xE2;
}

void ClearBuf()
{
    g_buf.clear();
    g_bufHkl = g_bufLayout = nullptr;
    g_lastAuto.clear();
}

void PushKey(WORD vk, WORD sc, bool shift) { g_buf.push_back({vk, sc, shift, g_caps}); }

std::wstring Lower(std::wstring s)
{
    ls_lower_str((ls_char *)s.data(), (int)s.size());
    return s;
}

// Pause / double Shift: retype the last word in the next layout, or fix the selection.
void ManualConvert()
{
    bool any = std::any_of(g_buf.begin(), g_buf.end(), [](const Key &k) { return k.vk != VK_SPACE; });
    if (!any) {
        Queue({true});
        return;
    }
    HWND target;
    HKL cur = FocusLayout(&target);
    if (g_bufLayout) cur = g_bufLayout;
    HKL next = NextLayout(cur);
    if (!next || next == cur) return;
    std::wstring old = Render(g_buf, cur);
    Queue({false, (int)old.size(), Render(g_buf, next), 0, target, next, g_lastAuto});
    g_lastAuto.clear();  // undoing an auto-fix teaches FastRevers the word (see Action::learn)
    g_bufLayout = next;
}

// Space after a word: true when the word gets fixed (the Space is then swallowed and sent again after the fix).
bool TryAuto()
{
    if (g_fgExcluded) return false;
    HWND target;
    HKL cur = FocusLayout(&target);
    if (g_bufLayout) cur = g_bufLayout;
    if (IsPasswordBox(target)) return false;
    HKL en, ru;
    FindLayouts(cur, &en, &ru);
    if (!en || !ru) return false;
    bool curIsEn;
    if (Lang(cur) == kLangEn)
        curIsEn = true;
    else if (Lang(cur) == kLangRu)
        curIsEn = false;
    else
        return false;
    HKL alt = curIsEn ? ru : en;
    std::wstring curText = Render(g_buf, cur), altText = Render(g_buf, alt);
    const std::wstring &e = curIsEn ? curText : altText, &r = curIsEn ? altText : curText;
    if (!ls_should_switch((const ls_char *)e.data(), (int)e.size(), (const ls_char *)r.data(), (int)r.size(), curIsEn))
        return false;
    Queue({false, (int)curText.size(), altText, VK_SPACE, target, alt, L""});
    PushKey(VK_SPACE, 0x39, false);
    g_bufLayout = alt;
    g_lastAuto = Lower(curText);
    return true;
}

// true = swallow the key
bool OnKey(DWORD vk, DWORD sc, bool down)
{
    if (vk == VK_CAPITAL) {
        if (down && !g_capsDown) g_caps = !g_caps;
        g_capsDown = down;
    }
    if (vk == VK_LSHIFT || vk == VK_RSHIFT || vk == VK_SHIFT) {
        int side = vk == VK_RSHIFT ? 1 : 0;
        DWORD now = GetTickCount();
        if (down) {
            if (!g_shiftDown[side]) {  // not auto-repeat
                g_shiftDown[side] = true;
                g_shiftClean = !g_shiftDown[1 - side] && !Held(VK_CONTROL) && !Held(VK_MENU) && !Held(VK_LWIN) &&
                               !Held(VK_RWIN);
                g_shiftDownAt = now;
            }
        } else {
            g_shiftDown[side] = false;
            bool tap = g_shiftClean && now - g_shiftDownAt <= kTapMaxHold;
            g_shiftClean = false;
            if (tap && g_optShift) {
                if (g_lastTap && now - g_lastTap <= kDoubleTapGap) {
                    g_lastTap = 0;
                    ManualConvert();
                } else {
                    g_lastTap = now;
                }
            } else {
                g_lastTap = 0;
            }
        }
        return false;
    }
    if (!down) return false;
    g_shiftClean = false;  // something was pressed together with Shift: not a tap
    g_lastTap = 0;
    switch (vk) {
    case VK_CAPITAL:
    case VK_CONTROL: case VK_LCONTROL: case VK_RCONTROL:
    case VK_MENU: case VK_LMENU: case VK_RMENU:
    case VK_LWIN: case VK_RWIN:
        return false;
    case VK_PAUSE:
        if (Held(VK_CONTROL) || Held(VK_MENU) || Held(VK_LWIN) || Held(VK_RWIN)) return false;  // Win+Pause etc.
        if (Held(VK_SHIFT))
            Queue({true});
        else
            ManualConvert();
        return true;
    }
    HWND fg = GetForegroundWindow();
    if (fg != g_lastFg) {
        g_lastFg = fg;
        g_fgExcluded = IsExcludedProgram(fg);
        ClearBuf();
    }
    if (Held(VK_CONTROL) || Held(VK_MENU) || Held(VK_LWIN) || Held(VK_RWIN)) {
        ClearBuf();
        return false;
    }
    if (vk == VK_BACK) {
        if (!g_buf.empty()) g_buf.pop_back();
        g_lastAuto.clear();
        return false;
    }
    if (vk == VK_SPACE) {
        if (g_buf.empty()) return false;
        if (!EndsWithSpace() && g_optAuto && TryAuto()) return true;
        PushKey(VK_SPACE, 0x39, false);
        return false;
    }
    if (IsCharVk(vk)) {
        HKL cur = FocusLayout(nullptr);
        HKL expected = g_bufLayout ? g_bufLayout : g_bufHkl;
        if (EndsWithSpace() || g_buf.size() >= 100 || (expected && cur != expected))
            ClearBuf();  // a new word, or the layout was switched in the middle of one
        g_lastAuto.clear();
        g_bufLayout = nullptr;
        g_bufHkl = cur;
        PushKey((WORD)vk, (WORD)sc, Held(VK_SHIFT));
        return false;
    }
    ClearBuf();  // arrows, Tab, Enter, Delete...: the caret moved or the word ended
    return false;
}

LRESULT CALLBACK KeyboardProc(int code, WPARAM wp, LPARAM lp)
{
    if (code == HC_ACTION) {
        const KBDLLHOOKSTRUCT *k = (const KBDLLHOOKSTRUCT *)lp;
        if (k->dwExtraInfo != kMagic && OnKey(k->vkCode, k->scanCode, wp == WM_KEYDOWN || wp == WM_SYSKEYDOWN))
            return 1;
    }
    return CallNextHookEx(nullptr, code, wp, lp);
}

LRESULT CALLBACK MouseProc(int code, WPARAM wp, LPARAM lp)
{
    if (code == HC_ACTION &&
        (wp == WM_LBUTTONDOWN || wp == WM_RBUTTONDOWN || wp == WM_MBUTTONDOWN || wp == WM_XBUTTONDOWN)) {
        ClearBuf();  // the caret may have moved
        g_lastTap = 0;
        g_shiftClean = false;
    }
    return CallNextHookEx(nullptr, code, wp, lp);
}

// ------------------------------------------------------------------ start with Windows
std::wstring Quoted(const std::wstring &s) { return L"\"" + s + L"\""; }

void Balloon(const wchar_t *title, const wchar_t *text);

// The Store package cannot use the Run key (its registry writes stay inside the package): it starts with
// Windows through its startup task. The WinRT calls run on a helper thread in the multithreaded apartment,
// so the UI thread needs no COM; each call takes a few milliseconds.
namespace startup_task {
namespace AM = ABI::Windows::ApplicationModel;
namespace WF = ABI::Windows::Foundation;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Wrappers::HStringReference;

enum class Op { Query, Enable, Disable };
struct Job {
    Op op;
    int state;  // AM::StartupTaskState after the call, -1 when the task could not be reached
};

bool Wait(IUnknown *operation)
{
    ComPtr<WF::IAsyncInfo> info;
    if (FAILED(operation->QueryInterface(IID_PPV_ARGS(&info)))) return false;
    WF::AsyncStatus s = WF::AsyncStatus::Started;
    for (int i = 0; i < 1000 && SUCCEEDED(info->get_Status(&s)) && s == WF::AsyncStatus::Started; i++) Sleep(10);
    return s == WF::AsyncStatus::Completed;
}

DWORD WINAPI Thread(void *param)
{
    Job &job = *static_cast<Job *>(param);
    if (FAILED(RoInitialize(RO_INIT_MULTITHREADED))) return 0;
    {
        ComPtr<AM::IStartupTaskStatics> statics;
        ComPtr<WF::IAsyncOperation<AM::StartupTask *>> get;
        ComPtr<AM::IStartupTask> task;
        AM::StartupTaskState state;
        if (SUCCEEDED(RoGetActivationFactory(HStringReference(RuntimeClass_Windows_ApplicationModel_StartupTask).Get(),
                                             IID_PPV_ARGS(&statics))) &&
            SUCCEEDED(statics->GetAsync(HStringReference(kStartupTaskId).Get(), &get)) && Wait(get.Get()) &&
            SUCCEEDED(get->GetResults(&task))) {
            if (job.op == Op::Enable) {
                ComPtr<WF::IAsyncOperation<AM::StartupTaskState>> request;
                if (SUCCEEDED(task->RequestEnableAsync(&request)) && Wait(request.Get()) &&
                    SUCCEEDED(request->GetResults(&state)))
                    job.state = state;
            } else {
                if (job.op == Op::Disable) task->Disable();
                if (SUCCEEDED(task->get_State(&state))) job.state = state;
            }
        }
    }
    RoUninitialize();
    return 0;
}

int Call(Op op)
{
    Job job{op, -1};
    if (HANDLE t = CreateThread(nullptr, 0, Thread, &job, 0, nullptr)) {
        WaitForSingleObject(t, INFINITE);  // Wait() gives up after 10 s
        CloseHandle(t);
    }
    return job.state;
}

bool IsOn(int state) { return state == AM::StartupTaskState_Enabled || state == AM::StartupTaskState_EnabledByPolicy; }
}  // namespace startup_task

bool StartupEnabled()
{
    if (g_packaged) return startup_task::IsOn(startup_task::Call(startup_task::Op::Query));
    wchar_t value[MAX_PATH * 4];
    DWORD size = sizeof(value);
    if (RegGetValueW(HKEY_CURRENT_USER, kRunKey, kRunName, RRF_RT_REG_SZ, nullptr, value, &size) != ERROR_SUCCESS)
        return false;
    if (_wcsicmp(value, Quoted(g_exe).c_str()) != 0) return false;
    BYTE approved[12];
    size = sizeof(approved);
    if (RegGetValueW(HKEY_CURRENT_USER, kApprovedKey, kRunName, RRF_RT_REG_BINARY, nullptr, approved, &size) ==
            ERROR_SUCCESS &&
        size >= 1 && (approved[0] & 1))
        return false;  // turned off in Settings > Apps > Startup
    return true;
}

void SetStartup(bool on)
{
    if (g_packaged) {
        using namespace startup_task;
        if (!on) {
            Call(Op::Disable);
        } else if (!IsOn(Call(Op::Enable))) {  // switched off by the user in Windows settings: only they can undo it
            Balloon(T(L"Автозапуск выключен в Windows", L"Startup is turned off in Windows"),
                    T(L"Включите FastRevers в «Параметры» → «Приложения» → «Автозагрузка».",
                      L"Turn FastRevers on in Settings > Apps > Startup."));
        }
        return;
    }
    if (on) {
        std::wstring v = Quoted(g_exe);
        RegSetKeyValueW(HKEY_CURRENT_USER, kRunKey, kRunName, REG_SZ, v.c_str(), (DWORD)((v.size() + 1) * 2));
        RegDeleteKeyValueW(HKEY_CURRENT_USER, kApprovedKey, kRunName);
    } else {
        RegDeleteKeyValueW(HKEY_CURRENT_USER, kRunKey, kRunName);
    }
}

// Older versions started with Windows under their own names ("LiteSwitcher", "LS"): move that entry over to
// FastRevers.exe once. The newest one decides: if it was switched off in Settings > Apps > Startup, autostart
// stays off; a "turned off" mark the user set for FastRevers there is left as it is too.
void AdoptOldStartup()
{
    bool decided = false;
    for (const OldName &o : kOldNames) {
        wchar_t value[MAX_PATH * 4];
        DWORD size = sizeof(value);
        if (RegGetValueW(HKEY_CURRENT_USER, kRunKey, o.run, RRF_RT_REG_SZ, nullptr, value, &size) != ERROR_SUCCESS)
            continue;
        std::wstring exe = std::wstring(L"\\") + o.exe;
        CharLowerW(value);
        CharLowerW(exe.data());
        if (!wcsstr(value, exe.c_str())) continue;  // some other program with that name
        BYTE approved[12];
        size = sizeof(approved);
        bool off = RegGetValueW(HKEY_CURRENT_USER, kApprovedKey, o.run, RRF_RT_REG_BINARY, nullptr, approved,
                                &size) == ERROR_SUCCESS &&
                   size >= 1 && (approved[0] & 1);
        RegDeleteKeyValueW(HKEY_CURRENT_USER, kRunKey, o.run);
        RegDeleteKeyValueW(HKEY_CURRENT_USER, kApprovedKey, o.run);
        if (!g_oldExe) g_oldExe = o.exe;
        if (!decided && !off) {
            std::wstring v = Quoted(g_exe);
            RegSetKeyValueW(HKEY_CURRENT_USER, kRunKey, kRunName, REG_SZ, v.c_str(), (DWORD)((v.size() + 1) * 2));
            g_adoptedStartup = true;
        }
        decided = true;
    }
}

// A running older version (LiteSwitcher.exe or LS.exe) is closed so that FastRevers.exe takes over without a
// restart. Returns false when the running copy is FastRevers itself.
bool RetireOldName()
{
    HWND w = FindWindowW(kWndClass, nullptr);
    DWORD pid = 0;
    if (!w || !GetWindowThreadProcessId(w, &pid)) return false;
    HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, pid);
    if (!p) return false;
    wchar_t path[MAX_PATH * 4];
    DWORD n = ARRAYSIZE(path);
    const wchar_t *oldExe = nullptr;
    if (QueryFullProcessImageNameW(p, 0, path, &n)) {
        const wchar_t *name = wcsrchr(path, L'\\');
        name = name ? name + 1 : path;
        for (const OldName &o : kOldNames)
            if (_wcsicmp(name, o.exe) == 0) oldExe = o.exe;
    }
    bool closed = false;
    if (oldExe) {
        PostMessageW(w, WM_CLOSE, 0, 0);  // older versions quit on WM_CLOSE: tray icon and hooks are removed
        closed = WaitForSingleObject(p, 5000) == WAIT_OBJECT_0;
    }
    CloseHandle(p);
    if (closed) {
        g_closedOld = true;
        g_oldExe = oldExe;
    }
    return closed;
}

// The AutoHotkey version (LS.ahk) would fix every word twice. FastRevers does not close it or change its
// autostart: it only tells the user what to do.
BOOL CALLBACK FindScriptVersion(HWND w, LPARAM found)
{
    wchar_t cls[32], title[1024];
    if (GetClassNameW(w, cls, ARRAYSIZE(cls)) && wcscmp(cls, L"AutoHotkey") == 0 &&
        GetWindowTextW(w, title, ARRAYSIZE(title))) {
        CharLowerW(title);
        if (wcsstr(title, L"\\ls.ahk")) {
            *reinterpret_cast<bool *>(found) = true;
            return FALSE;
        }
    }
    return TRUE;
}

void WarnScriptVersion()
{
    bool running = false, shortcut = false;
    EnumWindows(FindScriptVersion, reinterpret_cast<LPARAM>(&running));
    PWSTR dir = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Startup, 0, nullptr, &dir))) {
        std::string data;
        const char wide[] = "L\0S\0.\0a\0h\0k\0";
        shortcut = ReadAll(std::wstring(dir) + L"\\LS.lnk", data) &&
                   (data.find("LS.ahk") != std::string::npos || data.find(std::string(wide, 12)) != std::string::npos);
    }
    CoTaskMemFree(dir);
    if (!running && !shortcut) return;
    std::wstring text;
    if (running)
        text = T(L"Запущена старая версия LS.ahk. Закройте её (значок AutoHotkey у часов → Exit), иначе слова будут "
                 L"исправляться дважды.",
                 L"An old LS.ahk is running. Close it (AutoHotkey icon near the clock → Exit), otherwise words will be "
                 L"fixed twice.");
    if (shortcut) {
        if (!text.empty()) text += L"\n\n";
        text += T(L"В автозагрузке остался ярлык LS.lnk старой версии. Удалите его из папки shell:startup "
                  L"(Win+R → shell:startup), иначе она запустится снова. Чтобы с Windows запускался FastRevers, "
                  L"включите в его меню «Запускать вместе с Windows».",
                  L"The old version's LS.lnk shortcut is still in the Startup folder. Delete it from shell:startup "
                  L"(Win+R → shell:startup), or the old version will start again. To start FastRevers with "
                  L"Windows, tick “Start with Windows” in its menu.");
    }
    MessageBoxW(nullptr, text.c_str(), L"FastRevers", MB_ICONWARNING | MB_SETFOREGROUND);
}

// ------------------------------------------------------------------ tray
void TrayAdd()
{
    g_nid.cbSize = sizeof(g_nid);
    g_nid.hWnd = g_wnd;
    g_nid.uID = 1;
    g_nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
    g_nid.uCallbackMessage = WM_TRAY;
    if (!g_nid.hIcon) LoadIconMetric(g_inst, MAKEINTRESOURCEW(IDI_LS), LIM_SMALL, &g_nid.hIcon);
    wcscpy_s(g_nid.szTip, L"FastRevers");
    Shell_NotifyIconW(NIM_ADD, &g_nid);
    g_nid.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &g_nid);
}

void Balloon(const wchar_t *title, const wchar_t *text)
{
    static HICON big;
    if (!big) LoadIconMetric(g_inst, MAKEINTRESOURCEW(IDI_LS), LIM_LARGE, &big);
    NOTIFYICONDATAW n = g_nid;
    n.uFlags = NIF_INFO;
    wcsncpy_s(n.szInfoTitle, title, _TRUNCATE);  // wcscpy_s would end the program on a too long text
    wcsncpy_s(n.szInfo, text, _TRUNCATE);
    n.dwInfoFlags = NIIF_USER | NIIF_LARGE_ICON;
    n.hBalloonIcon = big;
    Shell_NotifyIconW(NIM_MODIFY, &n);
}

// Context menus follow the dark theme (uxtheme exports these by ordinal since Windows 10 1809).
void UpdateMenuTheme(bool first)
{
    static HMODULE ux = LoadLibraryExW(L"uxtheme.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    using SetMode = int(WINAPI *)(int);
    using Void = void(WINAPI *)();
    using RtlGetVersionFn = LONG(WINAPI *)(OSVERSIONINFOW *);
    OSVERSIONINFOW v{sizeof(v)};
    auto rtl = (RtlGetVersionFn)GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion");
    if (!ux || !rtl || rtl(&v) != 0 || v.dwBuildNumber < 17763) return;
    if (first) {
        if (auto setMode = (SetMode)GetProcAddress(ux, MAKEINTRESOURCEA(135))) setMode(1);  // allow dark
    } else if (auto refresh = (Void)GetProcAddress(ux, MAKEINTRESOURCEA(104))) {
        refresh();
    }
    if (auto flush = (Void)GetProcAddress(ux, MAKEINTRESOURCEA(136))) flush();
}

void OnCommand(UINT id)
{
    switch (id) {
    case IDM_AUTO:
        g_optAuto = !g_optAuto;
        WriteOption(L"Auto", g_optAuto);
        break;
    case IDM_SHIFT:
        g_optShift = !g_optShift;
        WriteOption(L"DoubleShift", g_optShift);
        break;
    case IDM_STARTUP:
        SetStartup(!StartupEnabled());
        break;
    case IDM_EXCEPTIONS:
        EnsureExceptionsFile();
        ShellExecuteW(nullptr, L"open", L"notepad.exe", Quoted(g_exc).c_str(), nullptr, SW_SHOWNORMAL);
        break;
    case IDM_RELOAD:
        LoadExceptions();
        break;
    case IDM_DONATE:
        ShellExecuteW(nullptr, L"open", TEXT(LS_DONATE_URL), nullptr, nullptr, SW_SHOWNORMAL);
        break;
    case IDM_PRIVACY:
        ShellExecuteW(nullptr, L"open", TEXT(LS_PRIVACY_URL), nullptr, nullptr, SW_SHOWNORMAL);
        break;
    case IDM_EXIT:
        DestroyWindow(g_wnd);
        break;
    }
}

void ShowMenu()
{
    HMENU m = CreatePopupMenu();
    auto add = [&](UINT id, const wchar_t *text, bool checked) {
        AppendMenuW(m, MF_STRING | (checked ? MF_CHECKED : 0), id, text);
    };
    add(IDM_AUTO, T(L"Автопереключение", L"Auto-switching"), g_optAuto);
    add(IDM_SHIFT, T(L"Двойной Shift — исправить", L"Double Shift to fix"), g_optShift);
    add(IDM_STARTUP, T(L"Запускать вместе с Windows", L"Start with Windows"), StartupEnabled());
    add(IDM_EXCEPTIONS, T(L"Исключения…", L"Exceptions…"), false);
    add(IDM_RELOAD, T(L"Перечитать исключения", L"Reload exceptions"), false);
    AppendMenuW(m, MF_SEPARATOR, 0, nullptr);
    add(IDM_PRIVACY, T(L"Конфиденциальность…", L"Privacy…"), false);
    add(IDM_DONATE, T(L"Поддержать проект (lava.top)…", L"Support the project (lava.top)…"), false);
    add(IDM_EXIT, T(L"Выход", L"Exit"), false);
    POINT pt;
    GetCursorPos(&pt);
    SetForegroundWindow(g_wnd);
    UINT align = GetSystemMetrics(SM_MENUDROPALIGNMENT) ? TPM_RIGHTALIGN : TPM_LEFTALIGN;
    UINT cmd = (UINT)TrackPopupMenuEx(m, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN | align,
                                      pt.x, pt.y, g_wnd, nullptr);
    PostMessageW(g_wnd, WM_NULL, 0, 0);
    DestroyMenu(m);
    OnCommand(cmd);
}

LRESULT CALLBACK WndProc(HWND h, UINT msg, WPARAM wp, LPARAM lp)
{
    if (g_taskbarCreated && msg == g_taskbarCreated) {  // Explorer restarted
        TrayAdd();
        return 0;
    }
    switch (msg) {
    case WM_TRAY:
        switch (LOWORD(lp)) {
        case WM_CONTEXTMENU:
        case NIN_SELECT:
        case NIN_KEYSELECT:
            ShowMenu();
        }
        return 0;
    case WM_LS_RUN:
        RunActions();
        return 0;
#ifdef LS_TEST_COMMANDS  // local test builds only: a test script picks menu items with WM_COMMAND
    case WM_COMMAND:
        OnCommand(LOWORD(wp));
        return 0;
#endif
    case WM_LS_HELLO:
        Balloon(T(L"FastRevers уже запущен", L"FastRevers is already running"),
                T(L"Значок FastRevers — в области уведомлений, у часов.",
                  L"The FastRevers icon is in the notification area."));
        return 0;
    case WM_TIMER:
        if (wp == kTimerExceptions) {
            FILETIME t = FileTime(g_exc);
            if (CompareFileTime(&t, &g_excTime) != 0) LoadExceptions();
        }
        return 0;
    case WM_SETTINGCHANGE:
        if (lp && wcscmp((const wchar_t *)lp, L"ImmersiveColorSet") == 0) UpdateMenuTheme(false);
        break;
    case WM_DESTROY:
        KillTimer(h, kTimerExceptions);
        Shell_NotifyIconW(NIM_DELETE, &g_nid);
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

// ------------------------------------------------------------------ self-test: FastRevers.exe --selftest report.txt
std::vector<Key> KeysFor(const std::wstring &text, HKL hkl)
{
    std::vector<Key> keys;
    for (wchar_t c : text) {
        if (c == L' ') {
            keys.push_back({VK_SPACE, 0x39, false, false});
            continue;
        }
        SHORT r = VkKeyScanExW(c, hkl);
        if (r == -1) continue;
        WORD vk = LOBYTE(r);
        keys.push_back({vk, (WORD)MapVirtualKeyExW(vk, MAPVK_VK_TO_VSC, hkl), (HIBYTE(r) & 1) != 0, false});
    }
    return keys;
}

int SelfTest(const wchar_t *path)
{
    static char report[32768];
    int fails = ls_selftest(report, (int)sizeof report);
    std::string out = "== detector ==\n";
    out += report;
    out += "== layouts (" + std::string(sizeof(void *) == 8 ? "64" : "32") + "-bit) ==\n";
    HKL en, ru, loaded = nullptr;
    FindLayouts(nullptr, &en, &ru);
    if (!en) en = LoadKeyboardLayoutW(L"00000409", KLF_NOTELLSHELL);
    if (!ru) ru = loaded = LoadKeyboardLayoutW(L"00000419", KLF_NOTELLSHELL);
    if (!en || !ru) {
        out += "FAIL no English or Russian layout\n";
        fails++;
    } else {
        struct Case {
            const wchar_t *typed;
            bool inEn;
            const wchar_t *expect;
            int fix;  // expected auto-fix decision, -1 = not checked
        };
        const Case cases[] = {
            {L"ghbdtn", true, L"привет", 1},          {L"Ghbdtn? vbh!", true, L"Привет, мир!", -1},
            {L"cgfcb,j", true, L"спасибо", 1},        {L"[jhjij", true, L"хорошо", 1},
            {L"hello", true, L"руддщ", 0},            {L"руддщ", false, L"hello", 1},
            {L"Руддщб цщкдв", false, L"Hello, world", -1}, {L"привет", false, L"ghbdtn", 0},
        };
        for (const Case &c : cases) {
            std::vector<Key> keys = KeysFor(c.typed, c.inEn ? en : ru);
            std::wstring same = Render(keys, c.inEn ? en : ru), other = Render(keys, c.inEn ? ru : en);
            std::wstring mapped = MapText(c.typed, en, ru, c.inEn);
            bool ok = same == c.typed && other == c.expect && mapped == c.expect;
            int fix = -1;
            if (c.fix >= 0) {
                const std::wstring &e = c.inEn ? same : other, &r = c.inEn ? other : same;
                fix = ls_should_switch((const ls_char *)e.data(), (int)e.size(), (const ls_char *)r.data(),
                                       (int)r.size(), c.inEn);
                ok = ok && fix == c.fix;
            }
            if (!ok) fails++;
            out += (ok ? "ok   " : "FAIL ") + Utf8(c.typed) + " -> keys " + Utf8(other) + ", text " + Utf8(mapped) +
                   (fix < 0 ? "" : fix ? ", switch" : ", keep") + "\n";
        }
    }
    if (loaded) UnloadKeyboardLayout(loaded);
    out += std::to_string(fails) + " failed\n";
    HANDLE h = CreateFileW(path, GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h != INVALID_HANDLE_VALUE) {
        DWORD put;
        WriteFile(h, out.data(), (DWORD)out.size(), &put, nullptr);
        CloseHandle(h);
    }
    return fails;
}

}  // namespace

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE, PWSTR, int)
{
    g_inst = inst;
    g_ru = DetectRussianUi();
    int argc = 0;
    LPWSTR *argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (argv && argc >= 3 && wcscmp(argv[1], L"--selftest") == 0) return SelfTest(argv[2]);

    HANDLE mutex = CreateMutexW(nullptr, FALSE, kMutex);  // same name as in LS 2.0.x: one copy of either
    if (GetLastError() == ERROR_ALREADY_EXISTS && !RetireOldName()) {
        if (HWND w = FindWindowW(kWndClass, nullptr)) PostMessageW(w, WM_LS_HELLO, 0, 0);
        return 0;
    }

    // An input hook must answer fast even when the PC is busy: no efficiency mode, a bit higher priority.
    PROCESS_POWER_THROTTLING_STATE pt{PROCESS_POWER_THROTTLING_CURRENT_VERSION,
                                      PROCESS_POWER_THROTTLING_EXECUTION_SPEED, 0};
    SetProcessInformation(GetCurrentProcess(), ProcessPowerThrottling, &pt, sizeof(pt));
    SetPriorityClass(GetCurrentProcess(), ABOVE_NORMAL_PRIORITY_CLASS);

    InitPaths();
    g_optAuto = ReadOption(L"Auto", 1);
    g_optShift = ReadOption(L"DoubleShift", 1);
    LoadExceptions();
    g_caps = (GetKeyState(VK_CAPITAL) & 1) != 0;
    UpdateMenuTheme(true);

    WNDCLASSEXW wc{sizeof(wc)};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = inst;
    wc.hIcon = LoadIconW(inst, MAKEINTRESOURCEW(IDI_LS));
    wc.lpszClassName = kWndClass;
    RegisterClassExW(&wc);
    g_wnd = CreateWindowExW(0, kWndClass, L"FastRevers", WS_OVERLAPPED, 0, 0, 0, 0, nullptr, nullptr, inst, nullptr);
    g_taskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");
    ChangeWindowMessageFilterEx(g_wnd, g_taskbarCreated, MSGFLT_ALLOW, nullptr);
    ChangeWindowMessageFilterEx(g_wnd, WM_LS_HELLO, MSGFLT_ALLOW, nullptr);
    TrayAdd();
    if (!g_packaged) {  // older portable versions have nothing to hand over to the Store package
        WarnScriptVersion();
        AdoptOldStartup();
    }

    g_kbd = SetWindowsHookExW(WH_KEYBOARD_LL, KeyboardProc, inst, 0);
    g_mouse = SetWindowsHookExW(WH_MOUSE_LL, MouseProc, inst, 0);
    if (!g_kbd) {
        MessageBoxW(nullptr, T(L"Не удалось перехватывать клавиатуру.", L"Could not hook the keyboard."),
                    L"FastRevers", MB_ICONERROR);
        return 1;
    }
    SetTimer(g_wnd, kTimerExceptions, 2000, nullptr);

    HKL en, ru;
    FindLayouts(nullptr, &en, &ru);
    if (!en || !ru) {
        Balloon(T(L"FastRevers: нужны две раскладки", L"FastRevers needs two layouts"),
                T(L"Добавьте в Windows раскладки «Русская» и «Английская (США)».",
                  L"Add the Russian and English (US) keyboard layouts in Windows settings."));
    } else if (g_closedOld || g_adoptedFiles || g_adoptedStartup) {
        std::wstring old = g_oldExe ? g_oldExe : L"LiteSwitcher.exe";
        std::wstring text = T(L"Раньше программа называлась ", L"The program used to be called ");
        text += old.substr(0, old.size() - 4) + L". ";
        if (g_adoptedFiles) text += T(L"Настройки и исключения перенесены. ", L"Settings and exceptions were moved over. ");
        if (g_adoptedStartup) text += T(L"Автозапуск перенесён. ", L"Start with Windows was moved over. ");
        text += T(L"Старый файл ", L"You can delete the old file ") + old + T(L" можно удалить.", L".");
        Balloon(T(L"Теперь это FastRevers", L"This is FastRevers now"), text.c_str());
        WriteOption(L"Welcomed", true);
    } else if (!ReadOption(L"Welcomed", 0)) {
        Balloon(T(L"FastRevers работает", L"FastRevers is running"),
                T(L"Пробел исправляет слово, набранное не в той раскладке; двойной Shift или Pause — вручную. "
                  L"Отменённые исправления запоминаются в exceptions.txt на этом ПК. В сеть ничего не отправляется.",
                  L"Space fixes a word typed in the wrong layout; double Shift or Pause fixes it by hand. "
                  L"Undone fixes are remembered in exceptions.txt on this PC. Nothing is sent anywhere."));
        WriteOption(L"Welcomed", true);
    }

    MSG m;
    while (GetMessageW(&m, nullptr, 0, 0) > 0) {
        TranslateMessage(&m);
        DispatchMessageW(&m);
    }
    UnhookWindowsHookEx(g_kbd);
    if (g_mouse) UnhookWindowsHookEx(g_mouse);
    CloseHandle(mutex);
    return 0;
}
