// FastRevers for macOS: fixes text typed in the wrong RU/EN keyboard layout.
// A menu bar app (FastRevers.app), no Hammerspoon or anything else needed.
//   Space / Return  - a word typed in the wrong layout is fixed automatically
//   Double Shift    - fix the last word (again - revert); with no fresh word, fix the selected text
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>

#include "ls_core.h"

static const int64_t kMagic = 0x4C53;          // marks our own events so the tap skips them
static const double kTapMaxHold = 0.4;         // s: a longer Shift press is not a tap
static const double kDoubleTapGap = 0.4;       // s between the two taps
static const CGKeyCode kSpaceMark = 0xFFFF;    // a Space inside the word buffer
static const CGEventFlags kDeviceLShift = 0x02, kDeviceRShift = 0x04;
static const CGEventFlags kChordMask = kCGEventFlagMaskCommand | kCGEventFlagMaskControl | kCGEventFlagMaskAlternate;
enum { kMaxKeys = 100 };
enum { LangOther = 0, LangEn = 1, LangRu = 2 };

static const char *const kTerminals[] = {
    "terminal", "iterm2", "alacritty", "kitty", "wezterm", "wezterm-gui", "warp", "hyper", "ghostty", "tabby",
    "com.apple.terminal", "com.googlecode.iterm2", "org.alacritty", "net.kovidgoyal.kitty",
    "com.github.wez.wezterm", "dev.warp.warp-stable", "co.zeit.hyper", "com.mitchellh.ghostty", "org.tabby", NULL};

typedef struct {
    CGKeyCode code;
    bool shift, caps;
} LSKey;

static LSKey g_buf[kMaxKeys + 1];   // keys of the current word
static int g_len;
static NSString *g_bufSourceID;     // layout the word is being typed in
static id g_bufLayout;              // layout the word is shown in after our own fix
static NSString *g_lastAuto;        // the word as it was before the last auto-fix (learning on undo)
static BOOL g_shiftArmed;
static double g_shiftDownAt, g_lastTap;
static BOOL g_optAuto = YES, g_optShift = YES, g_ruUI, g_appExcluded, g_selBusy;
static CFMachPortRef g_tap;
static CGEventSourceRef g_src;
static NSArray *g_sources;          // enabled keyboard layouts (cached)
static NSString *g_excPath;
static NSDate *g_excDate;

static NSString *L(NSString *ru, NSString *en) { return g_ruUI ? ru : en; }

// ------------------------------------------------------------------ text helpers
static BOOL Utf16(NSString *s, unichar *out, int *n)
{
    if (s.length > 128) return NO;
    [s getCharacters:out range:NSMakeRange(0, s.length)];
    *n = (int)s.length;
    return YES;
}

static int ShouldSwitch(NSString *en, NSString *ru, BOOL curIsEn)
{
    unichar a[128], b[128];
    int na, nb;
    if (!Utf16(en, a, &na) || !Utf16(ru, b, &nb)) return 0;
    return ls_should_switch(a, na, b, nb, curIsEn);
}

static BOOL NameExcluded(NSString *s)
{
    unichar b[128];
    int n;
    return s.length && Utf16(s, b, &n) && ls_app_excluded(b, n);
}

// ------------------------------------------------------------------ keyboard layouts
static NSString *SourceID(id s)
{
    return s ? (__bridge NSString *)TISGetInputSourceProperty((__bridge TISInputSourceRef)s, kTISPropertyInputSourceID)
             : nil;
}

static BOOL HasLayout(id s)
{
    return s && TISGetInputSourceProperty((__bridge TISInputSourceRef)s, kTISPropertyUnicodeKeyLayoutData) != NULL;
}

static int SourceLang(id s)
{
    NSString *sid = SourceID(s);
    if (!sid) return LangOther;
    if ([sid containsString:@"Russian"]) return LangRu;
    if ([sid hasSuffix:@".US"] || [sid containsString:@".ABC"] || [sid containsString:@"USExtended"] ||
        [sid containsString:@"USInternational"] || [sid containsString:@"British"] ||
        [sid containsString:@"Australian"] || [sid hasSuffix:@"Canadian"] || [sid hasSuffix:@"Irish"] ||
        [sid containsString:@"Dvorak"] || [sid containsString:@"Colemak"])
        return LangEn;
    NSArray *langs = (__bridge NSArray *)TISGetInputSourceProperty((__bridge TISInputSourceRef)s,
                                                                    kTISPropertyInputSourceLanguages);
    NSString *first = langs.firstObject;
    if ([first hasPrefix:@"ru"]) return LangRu;
    if ([first hasPrefix:@"en"]) return LangEn;
    return LangOther;
}

static NSArray *Sources(void)
{
    if (!g_sources) {
        NSDictionary *filter = @{
            (__bridge NSString *)kTISPropertyInputSourceCategory : (__bridge NSString *)kTISCategoryKeyboardInputSource,
            (__bridge NSString *)kTISPropertyInputSourceIsSelectCapable : @YES,
        };
        g_sources = CFBridgingRelease(TISCreateInputSourceList((__bridge CFDictionaryRef)filter, false)) ?: @[];
    }
    return g_sources;
}

static id CurrentSource(void) { return CFBridgingRelease(TISCopyCurrentKeyboardInputSource()); }

// The English and Russian layouts; the active one is preferred when there are several of a language.
static void FindLayouts(id cur, id __strong *en, id __strong *ru)
{
    *en = nil;
    *ru = nil;
    for (id s in Sources()) {
        if (!HasLayout(s)) continue;
        int lang = SourceLang(s);
        if (lang == LangEn && !*en) *en = s;
        if (lang == LangRu && !*ru) *ru = s;
    }
    if (HasLayout(cur)) {
        int lang = SourceLang(cur);
        if (lang == LangEn) *en = cur;
        if (lang == LangRu) *ru = cur;
    }
}

static void Select(id s)
{
    if (s) TISSelectInputSource((__bridge TISInputSourceRef)s);
}

// Text the keys give in a layout.
static NSString *Render(const LSKey *keys, int n, id source)
{
    CFDataRef data = source ? (CFDataRef)TISGetInputSourceProperty((__bridge TISInputSourceRef)source,
                                                                    kTISPropertyUnicodeKeyLayoutData)
                            : NULL;
    if (!data) return nil;
    const UCKeyboardLayout *layout = (const UCKeyboardLayout *)CFDataGetBytePtr(data);
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < n; i++) {
        if (keys[i].code == kSpaceMark) {
            [s appendString:@" "];
            continue;
        }
        UInt32 mods = (keys[i].shift ? shiftKey : 0) | (keys[i].caps ? alphaLock : 0);
        UInt32 dead = 0;
        UniChar chars[8];
        UniCharCount len = 0;
        if (UCKeyTranslate(layout, keys[i].code, kUCKeyActionDown, (mods >> 8) & 0xFF, LMGetKbdType(),
                           kUCKeyTranslateNoDeadKeysMask, &dead, 8, &len, chars) == noErr &&
            len > 0)
            [s appendString:[NSString stringWithCharacters:chars length:len]];
    }
    return s;
}

static BOOL IsCharKey(CGKeyCode c) { return c <= 35 || (c >= 37 && c <= 47) || c == 50; }

// Converts selected text key by key between the two layouts.
static NSString *MapText(NSString *text, id en, id ru, BOOL toRu)
{
    NSMutableString *from = [NSMutableString string], *to = [NSMutableString string];
    for (int shift = 0; shift < 2; shift++)
        for (CGKeyCode c = 0; c <= 50; c++) {
            if (!IsCharKey(c)) continue;
            LSKey k = {c, shift != 0, false};
            NSString *a = Render(&k, 1, en), *b = Render(&k, 1, ru);
            if (a.length == 1 && b.length == 1 && ![a isEqualToString:b]) {
                [from appendString:toRu ? a : b];
                [to appendString:toRu ? b : a];
            }
        }
    NSUInteger n = text.length;
    if (!n) return text;
    unichar *buf = malloc(n * sizeof(unichar)), *f = malloc(from.length * sizeof(unichar) + 2),
            *t = malloc(to.length * sizeof(unichar) + 2);
    [text getCharacters:buf range:NSMakeRange(0, n)];
    [from getCharacters:f range:NSMakeRange(0, from.length)];
    [to getCharacters:t range:NSMakeRange(0, to.length)];
    ls_map_text(buf, (int)n, f, t, (int)from.length);
    NSString *out = [NSString stringWithCharacters:buf length:n];
    free(buf);
    free(f);
    free(t);
    return out;
}

// ------------------------------------------------------------------ exceptions
static NSDate *ModDate(NSString *path)
{
    return [[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil] fileModificationDate];
}

static void UpdateFrontApp(void)
{
    NSRunningApplication *app = NSWorkspace.sharedWorkspace.frontmostApplication;
    g_appExcluded = NameExcluded(app.localizedName) || NameExcluded(app.bundleIdentifier) ||
                    NameExcluded(app.executableURL.lastPathComponent);
}

static void EnsureExceptionsFile(void)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([fm fileExistsAtPath:g_excPath]) return;
    [fm createDirectoryAtPath:g_excPath.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:nil];
    // words learned by the Hammerspoon version
    NSString *legacy = [NSHomeDirectory() stringByAppendingPathComponent:@".hammerspoon/LS_exceptions.txt"];
    if ([fm fileExistsAtPath:legacy] && [fm copyItemAtPath:legacy toPath:g_excPath error:nil]) return;
    NSString *head = L(@"# Исключения FastRevers. Одно слово в строке — оно не будет автоисправляться.\n"
                       @"# Строка вида @Имя программы отключает автопереключение в этой программе.\n",
                       @"# FastRevers exceptions. One word per line: it will not be auto-fixed.\n"
                       @"# A line like @App Name turns auto-switching off in that app.\n");
    [head writeToFile:g_excPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void LoadExceptions(void)
{
    ls_exc_reset();
    for (int i = 0; kTerminals[i]; i++) ls_app_add_utf8(kTerminals[i]);
    NSData *d = [NSData dataWithContentsOfFile:g_excPath];
    if (d) ls_exc_load(d.bytes, d.length);
    g_excDate = ModDate(g_excPath);
    UpdateFrontApp();
}

static void AddException(NSString *word)
{
    unichar b[128];
    int n;
    if (!word.length || !Utf16(word, b, &n) || ls_exc_has_word(b, n)) return;
    ls_exc_add_word(b, n);
    dispatch_async(dispatch_get_main_queue(), ^{
        EnsureExceptionsFile();
        NSMutableData *data = [NSMutableData dataWithContentsOfFile:g_excPath] ?: [NSMutableData data];
        if (data.length && ((const char *)data.bytes)[data.length - 1] != '\n') [data appendBytes:"\n" length:1];
        [data appendData:[[word stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
        [data writeToFile:g_excPath atomically:YES];
        g_excDate = ModDate(g_excPath);
    });
}

// ------------------------------------------------------------------ synthetic input
static void Post(CGEventRef e)
{
    if (!e) return;
    CGEventSetIntegerValueField(e, kCGEventSourceUserData, kMagic);
    CGEventPost(kCGSessionEventTap, e);
    CFRelease(e);
}

static void PostKey(CGKeyCode code, CGEventFlags flags)
{
    CGEventRef d = CGEventCreateKeyboardEvent(g_src, code, true), u = CGEventCreateKeyboardEvent(g_src, code, false);
    if (d) CGEventSetFlags(d, flags);
    if (u) CGEventSetFlags(u, flags);
    Post(d);
    Post(u);
}

static void PostDeletes(NSUInteger n)
{
    for (NSUInteger i = 0; i < n; i++) PostKey(kVK_Delete, 0);
}

static void PostText(NSString *s)
{
    for (NSUInteger i = 0; i < s.length; i++) {
        UniChar c = [s characterAtIndex:i];
        if (c == ' ') {
            PostKey(kVK_Space, 0);
            continue;
        }
        CGEventRef d = CGEventCreateKeyboardEvent(g_src, 0, true), u = CGEventCreateKeyboardEvent(g_src, 0, false);
        if (d) {
            CGEventKeyboardSetUnicodeString(d, 1, &c);
            CGEventSetFlags(d, 0);
        }
        if (u) {
            CGEventKeyboardSetUnicodeString(u, 1, &c);
            CGEventSetFlags(u, 0);
        }
        Post(d);
        Post(u);
    }
}

// ------------------------------------------------------------------ fixing the selected text
static NSArray *SavePasteboard(NSPasteboard *pb)
{
    NSMutableArray *items = [NSMutableArray array];
    for (NSPasteboardItem *item in pb.pasteboardItems) {
        NSPasteboardItem *copy = [NSPasteboardItem new];
        for (NSPasteboardType type in item.types) {
            NSData *d = [item dataForType:type];
            if (d) [copy setData:d forType:type];
        }
        [items addObject:copy];
    }
    return items;
}

static void ConvertSelection(void)
{
    if (g_selBusy) return;
    id en, ru;
    FindLayouts(CurrentSource(), &en, &ru);
    if (!en || !ru) return;
    g_selBusy = YES;
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    NSArray *saved = SavePasteboard(pb);
    NSInteger count = pb.changeCount;
    PostKey(kVK_ANSI_C, kCGEventFlagMaskCommand);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (pb.changeCount == count) {  // nothing was selected
            g_selBusy = NO;
            return;
        }
        NSString *text = [pb stringForType:NSPasteboardTypeString];
        if (text.length) {
            unichar *b = malloc(text.length * sizeof(unichar));
            [text getCharacters:b range:NSMakeRange(0, text.length)];
            BOOL toRu = ls_latin_wins(b, (int)text.length) != 0;
            free(b);
            [pb clearContents];
            [pb setString:MapText(text, en, ru, toRu) forType:NSPasteboardTypeString];
            [pb setData:[NSData data] forType:@"org.nspasteboard.TransientType"];  // clipboard managers: skip it
            PostKey(kVK_ANSI_V, kCGEventFlagMaskCommand);
            Select(toRu ? ru : en);
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [pb clearContents];
            if (saved.count) {
                [saved.firstObject setData:[NSData data] forType:@"org.nspasteboard.TransientType"];
                [pb writeObjects:saved];
            }
            g_selBusy = NO;
        });
    });
}

// ------------------------------------------------------------------ typing tracker (runs inside the event tap)
static void ClearBuf(void)
{
    g_len = 0;
    g_bufSourceID = nil;
    g_bufLayout = nil;
    g_lastAuto = nil;
}

static BOOL EndsWithSpace(void) { return g_len > 0 && g_buf[g_len - 1].code == kSpaceMark; }

static void Push(CGKeyCode code, BOOL shift, BOOL caps)
{
    if (g_len < kMaxKeys) g_buf[g_len++] = (LSKey){code, shift, caps};
}

// Double Shift: retype the last word in the other layout, or fix the selection.
static void ManualConvert(void)
{
    BOOL any = NO;
    for (int i = 0; i < g_len; i++)
        if (g_buf[i].code != kSpaceMark) any = YES;
    if (!any) {
        ConvertSelection();
        return;
    }
    id cur = g_bufLayout ?: CurrentSource();
    id en, ru;
    FindLayouts(cur, &en, &ru);
    int lang = SourceLang(cur);
    if (!en || !ru || lang == LangOther) return;
    id from = lang == LangEn ? en : ru, next = lang == LangEn ? ru : en;
    NSString *old = Render(g_buf, g_len, from), *neu = Render(g_buf, g_len, next);
    if (!old || !neu) return;
    if (g_lastAuto) AddException(g_lastAuto);  // undoing an auto-fix teaches FastRevers the word
    g_lastAuto = nil;
    PostDeletes(old.length);
    PostText(neu);
    Select(next);
    g_bufLayout = next;
}

// Space / Return after a word: YES when the word was fixed (the key is swallowed and sent again).
static BOOL TryAuto(CGKeyCode tail, CGEventFlags flags)
{
    if (g_appExcluded) return NO;
    id cur = g_bufLayout ?: CurrentSource();
    id en, ru;
    FindLayouts(cur, &en, &ru);
    int lang = SourceLang(cur);
    if (!en || !ru || lang == LangOther) return NO;
    BOOL curIsEn = lang == LangEn;
    id from = curIsEn ? en : ru, alt = curIsEn ? ru : en;
    NSString *curText = Render(g_buf, g_len, from), *altText = Render(g_buf, g_len, alt);
    if (!curText || !altText || !ShouldSwitch(curIsEn ? curText : altText, curIsEn ? altText : curText, curIsEn))
        return NO;
    PostDeletes(curText.length);
    PostText(altText);
    PostKey(tail, flags & (kCGEventFlagMaskShift | kCGEventFlagMaskAlphaShift));
    Select(alt);
    if (tail == kVK_Space) {
        g_lastAuto = curText.lowercaseString;
        Push(kSpaceMark, NO, NO);
        g_bufLayout = alt;
    }
    return YES;
}

static BOOL OnEvent(CGEventType type, CGEventRef e)
{
    if (type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown || type == kCGEventOtherMouseDown) {
        ClearBuf();  // the caret may have moved
        g_shiftArmed = NO;
        g_lastTap = 0;
        return NO;
    }
    CGEventFlags f = CGEventGetFlags(e);
    CGKeyCode code = (CGKeyCode)CGEventGetIntegerValueField(e, kCGKeyboardEventKeycode);
    double now = CFAbsoluteTimeGetCurrent();
    if (type == kCGEventFlagsChanged) {
        if (code == kVK_Shift || code == kVK_RightShift) {
            CGEventFlags mine = code == kVK_Shift ? kDeviceLShift : kDeviceRShift;
            CGEventFlags other = code == kVK_Shift ? kDeviceRShift : kDeviceLShift;
            BOOL down = (f & mine) || ((f & kCGEventFlagMaskShift) && !(f & (kDeviceLShift | kDeviceRShift)));
            if (down) {
                g_shiftArmed = !(f & kChordMask) && !(f & other);
                g_shiftDownAt = now;
                if (!g_shiftArmed) g_lastTap = 0;
            } else {
                BOOL tap = g_shiftArmed && now - g_shiftDownAt <= kTapMaxHold;
                g_shiftArmed = NO;
                if (tap && g_optShift) {
                    if (g_lastTap > 0 && now - g_lastTap <= kDoubleTapGap) {
                        g_lastTap = 0;
                        ManualConvert();
                    } else {
                        g_lastTap = now;
                    }
                } else {
                    g_lastTap = 0;
                }
            }
        } else {  // Command, Option, Control, Caps Lock, Fn
            g_shiftArmed = NO;
            g_lastTap = 0;
        }
        return NO;
    }

    // key down
    g_shiftArmed = NO;
    g_lastTap = 0;
    if (f & kChordMask) {
        ClearBuf();
        return NO;
    }
    if (code == kVK_Delete) {
        if (g_len) g_len--;
        g_lastAuto = nil;
        return NO;
    }
    if (code == kVK_Space) {
        if (!g_len) return NO;
        if (!EndsWithSpace() && g_optAuto && TryAuto(kVK_Space, f)) return YES;
        Push(kSpaceMark, NO, NO);
        return NO;
    }
    if (code == kVK_Return || code == kVK_ANSI_KeypadEnter) {
        BOOL done = g_len && !EndsWithSpace() && g_optAuto && TryAuto(code, f);
        ClearBuf();
        return done;
    }
    if (IsCharKey(code)) {
        NSString *curID = SourceID(CurrentSource());
        NSString *expected = g_bufLayout ? SourceID(g_bufLayout) : g_bufSourceID;
        if (EndsWithSpace() || g_len >= kMaxKeys || (expected && ![expected isEqualToString:curID]))
            ClearBuf();  // a new word, or the layout was switched in the middle of one
        g_lastAuto = nil;
        g_bufLayout = nil;
        g_bufSourceID = curID;
        Push(code, (f & kCGEventFlagMaskShift) != 0, (f & kCGEventFlagMaskAlphaShift) != 0);
        return NO;
    }
    ClearBuf();  // arrows, Tab, Escape...: the caret moved or the word ended
    return NO;
}

static CGEventRef TapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info)
{
    (void)proxy;
    (void)info;
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (g_tap) CGEventTapEnable(g_tap, true);
        return event;
    }
    if (CGEventGetIntegerValueField(event, kCGEventSourceUserData) == kMagic) return event;
    BOOL swallow;
    @autoreleasepool {
        swallow = OnEvent(type, event);
    }
    return swallow ? NULL : event;
}

static BOOL StartTap(void)
{
    if (g_tap) return YES;
    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventFlagsChanged) |
                       CGEventMaskBit(kCGEventLeftMouseDown) | CGEventMaskBit(kCGEventRightMouseDown) |
                       CGEventMaskBit(kCGEventOtherMouseDown);
    g_tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, mask, TapCallback,
                             NULL);
    if (!g_tap) return NO;
    CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(NULL, g_tap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), src, kCFRunLoopCommonModes);
    CFRelease(src);
    CGEventTapEnable(g_tap, true);
    return YES;
}

static BOOL Trusted(BOOL prompt)
{
    NSDictionary *o = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt : @(prompt)};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)o);
}

// ------------------------------------------------------------------ menu bar icon: "FR" in a rounded badge
static NSImage *StatusImage(void)
{
    NSImage *img = [NSImage imageWithSize:NSMakeSize(22, 16)
                                  flipped:NO
                           drawingHandler:^BOOL(NSRect r) {
                               (void)r;
                               NSRect box = NSMakeRect(1.5, 1, 19, 14);
                               [NSColor.blackColor setFill];
                               [[NSBezierPath bezierPathWithRoundedRect:box xRadius:3.5 yRadius:3.5] fill];
                               CGContextRef ctx = NSGraphicsContext.currentContext.CGContext;
                               CGContextSetBlendMode(ctx, kCGBlendModeDestinationOut);  // letters cut out
                               NSDictionary *a = @{
                                   NSFontAttributeName : [NSFont systemFontOfSize:10 weight:NSFontWeightBold],
                                   NSForegroundColorAttributeName : NSColor.blackColor,
                               };
                               NSAttributedString *s = [[NSAttributedString alloc] initWithString:@"FR"
                                                                                       attributes:a];
                               NSSize sz = s.size;
                               [s drawAtPoint:NSMakePoint(NSMidX(box) - sz.width / 2, NSMidY(box) - sz.height / 2)];
                               CGContextSetBlendMode(ctx, kCGBlendModeNormal);
                               return YES;
                           }];
    img.template = YES;
    return img;
}

// ------------------------------------------------------------------ start at login (a LaunchAgent)
static NSString *AgentPath(void)
{
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/io.github.u-said.ls.plist"];
}

static BOOL Translocated(void) { return [NSBundle.mainBundle.bundlePath containsString:@"/AppTranslocation/"]; }

static BOOL LoginEnabled(void)
{
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:AgentPath()];
    return [[d[@"ProgramArguments"] firstObject] isEqual:NSBundle.mainBundle.executablePath];
}

static void ShowAlert(NSString *title, NSString *text)
{
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *a = [NSAlert new];
    a.messageText = title;
    a.informativeText = text;
    [a runModal];
}

static NSString *MoveToApplicationsText(void)
{
    return L(@"macOS запустила FastRevers из временной копии. Перетащите FastRevers.app в папку «Программы» и откройте его оттуда.",
             @"macOS started FastRevers from a temporary copy. Drag FastRevers.app to the Applications folder and open it from there.");
}

static void SetLogin(BOOL on)
{
    NSString *path = AgentPath();
    if (!on) {
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        return;
    }
    if (Translocated()) {
        ShowAlert(L(@"Сначала перенесите FastRevers в «Программы»", @"Move FastRevers to Applications first"), MoveToApplicationsText());
        return;
    }
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary *agent = @{
        @"Label" : @"io.github.u-said.ls",
        @"ProgramArguments" : @[ NSBundle.mainBundle.executablePath ],
        @"RunAtLoad" : @YES,
        @"ProcessType" : @"Interactive",
        @"LimitLoadToSessionType" : @"Aqua",
        @"AssociatedBundleIdentifiers" : @[ NSBundle.mainBundle.bundleIdentifier ?: @"io.github.u-said.ls" ],
    };
    [agent writeToFile:path atomically:YES];
}

// Older names of the app: 2.1.x was LiteSwitcher.app, 2.0.x was LS.app (same bundle id, so settings carry over).
static BOOL IsOldApp(NSString *bundleName)
{
    return [bundleName isEqualToString:@"LiteSwitcher.app"] || [bundleName isEqualToString:@"LS.app"];
}

// An older version registered the login item with its own path: point it at this app.
static void AdoptOldLogin(void)
{
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:AgentPath()];
    NSString *old = [d[@"ProgramArguments"] firstObject];
    if ([old isKindOfClass:NSString.class] && !Translocated() &&
        ([old hasSuffix:@"/LiteSwitcher.app/Contents/MacOS/LiteSwitcher"] || [old hasSuffix:@"/LS.app/Contents/MacOS/LS"]))
        SetLogin(YES);
}

// ------------------------------------------------------------------ the app
@interface LSDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@end

@implementation LSDelegate {
    NSStatusItem *_item;
    NSTimer *_trustTimer, *_excTimer;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
    (void)note;
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    pid_t me = NSProcessInfo.processInfo.processIdentifier;
    for (NSRunningApplication *other in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID ?: @""]) {
        if (other.processIdentifier == me) continue;
        if (!IsOldApp(other.bundleURL.lastPathComponent)) {
            [NSApp terminate:nil];  // already running
            return;
        }
        [other terminate];  // an older version (LiteSwitcher, LS): this copy takes over
        for (int i = 0; i < 50 && !other.terminated; i++)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;  // same bundle id as the older versions: settings carry over
    [ud registerDefaults:@{@"auto" : @YES, @"doubleShift" : @YES}];
    g_optAuto = [ud boolForKey:@"auto"];
    g_optShift = [ud boolForKey:@"doubleShift"];

    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [support stringByAppendingPathComponent:@"FastRevers"];
    for (NSString *oldName in @[ @"LiteSwitcher", @"LS" ]) {  // exceptions of the older versions, newest first
        NSString *oldDir = [support stringByAppendingPathComponent:oldName];
        if (![fm fileExistsAtPath:dir] && [fm fileExistsAtPath:oldDir]) [fm moveItemAtPath:oldDir toPath:dir error:nil];
    }
    g_excPath = [dir stringByAppendingPathComponent:@"exceptions.txt"];
    EnsureExceptionsFile();
    LoadExceptions();
    AdoptOldLogin();

    g_src = CGEventSourceCreate(kCGEventSourceStatePrivate);
    if (g_src) {
        CGEventSourceSetLocalEventsSuppressionInterval(g_src, 0);
        CGEventSourceSetLocalEventsFilterDuringSuppressionState(g_src, kCGEventFilterMaskPermitAllEvents,
                                                                kCGEventSuppressionStateSuppressionInterval);
    }

    _item = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    _item.button.image = StatusImage();
    NSMenu *menu = [NSMenu new];
    menu.delegate = self;
    _item.menu = menu;

    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidActivateApplicationNotification
                                                                object:nil
                                                                 queue:NSOperationQueue.mainQueue
                                                            usingBlock:^(NSNotification *n) {
                                                                (void)n;
                                                                ClearBuf();
                                                                UpdateFrontApp();
                                                            }];
    [NSDistributedNotificationCenter.defaultCenter
        addObserverForName:(__bridge NSString *)kTISNotifyEnabledKeyboardInputSourcesChanged
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *n) {
                    (void)n;
                    g_sources = nil;
                }];
    _excTimer = [NSTimer scheduledTimerWithTimeInterval:3
                                                repeats:YES
                                                  block:^(NSTimer *t) {
                                                      (void)t;
                                                      NSDate *d = ModDate(g_excPath);
                                                      if (d != g_excDate && ![d isEqualToDate:g_excDate]) LoadExceptions();
                                                  }];

    if (Translocated())
        ShowAlert(L(@"Перенесите FastRevers в «Программы»", @"Move FastRevers to Applications"), MoveToApplicationsText());
    [self warnAboutHammerspoon];
    id en, ru;
    FindLayouts(CurrentSource(), &en, &ru);
    if (!en || !ru)
        ShowAlert(L(@"FastRevers: нужны две раскладки", @"FastRevers needs two input sources"),
                  L(@"Добавьте в «Системные настройки → Клавиатура → Источники ввода» раскладки ABC (или США) и «Русская».",
                    @"Add ABC (or U.S.) and Russian in System Settings → Keyboard → Input Sources."));
    if (!Trusted(NO) && ![ud boolForKey:@"accessExplained"]) {  // once, before macOS asks for the access
        ShowAlert(L(@"Зачем FastRevers «Универсальный доступ»", @"Why FastRevers needs Accessibility access"),
                  L(@"Доступ нужен, чтобы видеть нажатия текущего слова и перепечатывать его. Нажатия не сохраняются "
                    @"и никуда не отправляются; на диск записываются только слова, исправление которых вы отменили.",
                    @"Access is needed to see the keys of the current word and retype it. Keystrokes are not saved or "
                    @"sent anywhere; only words whose fix you undid are written to disk."));
        [ud setBool:YES forKey:@"accessExplained"];
    }
    [self startWhenTrusted:YES];
}

- (void)warnAboutHammerspoon
{
    if (![NSRunningApplication runningApplicationsWithBundleIdentifier:@"org.hammerspoon.Hammerspoon"].count) return;
    NSString *init = [NSString stringWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@".hammerspoon/init.lua"]
                                               encoding:NSUTF8StringEncoding
                                                  error:nil];
    if (![init containsString:@"require(\"LS\")"] && ![init containsString:@"require('LS')"]) return;
    ShowAlert(L(@"Старая версия LS работает в Hammerspoon", @"The old LS is running in Hammerspoon"),
              L(@"Иначе каждое слово будет исправляться дважды. Удалите строку require(\"LS\") из ~/.hammerspoon/init.lua "
                @"и выберите в Hammerspoon «Reload Config».",
                @"Otherwise every word is fixed twice. Remove the require(\"LS\") line from ~/.hammerspoon/init.lua "
                @"and choose Reload Config in Hammerspoon."));
}

- (void)startWhenTrusted:(BOOL)prompt
{
    if (Trusted(prompt) && StartTap()) {
        [_trustTimer invalidate];
        _trustTimer = nil;
        [self updateStatus];
        return;
    }
    [self updateStatus];
    if (!_trustTimer)
        _trustTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                      repeats:YES
                                                        block:^(NSTimer *t) {
                                                            (void)t;
                                                            [self startWhenTrusted:NO];
                                                        }];
}

- (void)updateStatus
{
    _item.button.appearsDisabled = g_tap == NULL;
    _item.button.toolTip = g_tap ? @"FastRevers"
                                 : L(@"FastRevers ждёт доступа в «Универсальном доступе»", @"FastRevers needs Accessibility access");
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)flag
{
    (void)app;
    (void)flag;
    [_item.button performClick:nil];  // opened again from Finder: show the menu
    return NO;
}

- (NSMenuItem *)add:(NSMenu *)m title:(NSString *)title action:(SEL)action on:(BOOL)on
{
    NSMenuItem *i = [m addItemWithTitle:title action:action keyEquivalent:@""];
    i.target = self;
    i.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    return i;
}

- (void)menuNeedsUpdate:(NSMenu *)m
{
    [m removeAllItems];
    if (!g_tap) {
        [self add:m title:L(@"Разрешить доступ в «Универсальном доступе»…", @"Allow Accessibility access…")
            action:@selector(openAccessibility:) on:NO];
        [m addItem:NSMenuItem.separatorItem];
    }
    [self add:m title:L(@"Автопереключение", @"Auto-switching") action:@selector(toggleAuto:) on:g_optAuto];
    [self add:m title:L(@"Двойной Shift — исправить", @"Double Shift to fix") action:@selector(toggleShift:) on:g_optShift];
    [self add:m title:L(@"Запускать при входе в систему", @"Open at login") action:@selector(toggleLogin:) on:LoginEnabled()];
    [self add:m title:L(@"Исключения…", @"Exceptions…") action:@selector(openExceptions:) on:NO];
    [self add:m title:L(@"Перечитать исключения", @"Reload exceptions") action:@selector(reloadExceptions:) on:NO];
    [m addItem:NSMenuItem.separatorItem];
    [self add:m title:L(@"Конфиденциальность…", @"Privacy…") action:@selector(openPrivacy:) on:NO];
    [self add:m title:L(@"Поддержать проект (lava.top)…", @"Support the project (lava.top)…") action:@selector(openDonate:) on:NO];
    NSMenuItem *about =[m addItemWithTitle:[NSString stringWithFormat:@"FastRevers %s", LS_VERSION] action:nil keyEquivalent:@""];
    about.enabled = NO;
    NSMenuItem *quit = [m addItemWithTitle:L(@"Выйти из FastRevers", @"Quit FastRevers") action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp;
}

- (void)toggleAuto:(id)sender
{
    (void)sender;
    g_optAuto = !g_optAuto;
    [NSUserDefaults.standardUserDefaults setBool:g_optAuto forKey:@"auto"];
}

- (void)toggleShift:(id)sender
{
    (void)sender;
    g_optShift = !g_optShift;
    [NSUserDefaults.standardUserDefaults setBool:g_optShift forKey:@"doubleShift"];
}

- (void)toggleLogin:(id)sender
{
    (void)sender;
    SetLogin(!LoginEnabled());
}

- (void)openExceptions:(id)sender
{
    (void)sender;
    EnsureExceptionsFile();
    [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:g_excPath]];
}

- (void)reloadExceptions:(id)sender
{
    (void)sender;
    LoadExceptions();
}

- (void)openDonate:(id)sender
{
    (void)sender;
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@LS_DONATE_URL]];
}

- (void)openPrivacy:(id)sender
{
    (void)sender;
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@LS_PRIVACY_URL]];
}

- (void)openAccessibility:(id)sender
{
    (void)sender;
    Trusted(YES);
    [NSWorkspace.sharedWorkspace
        openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}

@end

// ------------------------------------------------------------------ checks run in CI: FastRevers --selftest, FastRevers --render-icon out.png
static id InstalledSource(NSString *sid)
{
    NSDictionary *f = @{(__bridge NSString *)kTISPropertyInputSourceID : sid};
    NSArray *a = CFBridgingRelease(TISCreateInputSourceList((__bridge CFDictionaryRef)f, true));
    return a.firstObject;
}

static int KeysFor(NSString *text, id source, LSKey *out)
{
    int n = 0;
    for (NSUInteger i = 0; i < text.length && n < kMaxKeys; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == ' ') {
            out[n++] = (LSKey){kSpaceMark, false, false};
            continue;
        }
        BOOL found = NO;
        for (int shift = 0; shift < 2 && !found; shift++)
            for (CGKeyCode k = 0; k <= 50 && !found; k++) {
                if (!IsCharKey(k)) continue;
                LSKey key = {k, shift != 0, false};
                NSString *s = Render(&key, 1, source);
                if (s.length == 1 && [s characterAtIndex:0] == c) {
                    out[n++] = key;
                    found = YES;
                }
            }
        if (!found) return -1;
    }
    return n;
}

static int SelfTest(void)
{
    static char report[16384];
    int fails = ls_selftest(report, (int)sizeof report);
    printf("== detector ==\n%s== layouts ==\n", report);
    id us = InstalledSource(@"com.apple.keylayout.US") ?: InstalledSource(@"com.apple.keylayout.ABC");
    if (!us || SourceLang(us) != LangEn) {
        printf("FAIL no U.S./ABC layout\n");
        return fails + 1;
    }
    for (NSString *rid in @[ @"com.apple.keylayout.RussianWin", @"com.apple.keylayout.Russian" ]) {
        id ru = InstalledSource(rid);
        if (!ru || SourceLang(ru) != LangRu) {
            printf("FAIL %s: not found\n", rid.UTF8String);
            fails++;
            continue;
        }
        BOOL pc = [rid hasSuffix:@"Win"];
        struct {
            __unsafe_unretained NSString *typed;
            BOOL inEn;
            __unsafe_unretained NSString *expect;
            int fix;   // expected auto-fix decision, -1 = not checked
            BOOL pcOnly;
        } cases[] = {
            {@"ghbdtn", YES, @"привет", 1, NO},     {@"cgfcb,j", YES, @"спасибо", 1, NO},
            {@"[jhjij", YES, @"хорошо", 1, NO},     {@"hello", YES, @"руддщ", 0, NO},
            {@"руддщ", NO, @"hello", 1, NO},        {@"привет", NO, @"ghbdtn", 0, NO},
            {@"Ghbdtn? vbh!", YES, @"Привет, мир!", -1, YES},
            {@"Руддщб цщкдв", NO, @"Hello, world", -1, YES},
        };
        for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
            if (cases[i].pcOnly && !pc) continue;
            LSKey keys[kMaxKeys];
            id src = cases[i].inEn ? us : ru, other = cases[i].inEn ? ru : us;
            int n = KeysFor(cases[i].typed, src, keys);
            NSString *same = n < 0 ? @"?" : Render(keys, n, src), *conv = n < 0 ? @"?" : Render(keys, n, other);
            NSString *mapped = MapText(cases[i].typed, us, ru, cases[i].inEn);
            BOOL ok = [same isEqualToString:cases[i].typed] && [conv isEqualToString:cases[i].expect] &&
                      [mapped isEqualToString:cases[i].expect];
            int fix = -1;
            if (cases[i].fix >= 0) {
                fix = ShouldSwitch(cases[i].inEn ? same : conv, cases[i].inEn ? conv : same, cases[i].inEn);
                ok = ok && fix == cases[i].fix;
            }
            if (!ok) fails++;
            printf("%s %-9s %s -> keys %s, text %s%s\n", ok ? "ok  " : "FAIL", pc ? "PC" : "Mac", cases[i].typed.UTF8String,
                   conv.UTF8String, mapped.UTF8String, fix < 0 ? "" : fix ? ", switch" : ", keep");
        }
    }
    printf("%d failed\n", fails);
    return fails;
}

static int RenderIcon(NSString *path)
{
    NSImage *img = StatusImage();
    const CGFloat k = 8, w = 22 * k, h = 16 * k, pad = 6 * k;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:(NSInteger)(2 * w + 3 * pad)
                                                                    pixelsHigh:(NSInteger)(h + 2 * pad)
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [[NSColor colorWithWhite:0.92 alpha:1] setFill];
    NSRectFill(NSMakeRect(0, 0, w + 1.5 * pad, h + 2 * pad));
    [[NSColor colorWithWhite:0.16 alpha:1] setFill];
    NSRectFill(NSMakeRect(w + 1.5 * pad, 0, w + 1.5 * pad, h + 2 * pad));
    [img drawInRect:NSMakeRect(pad, pad, w, h)];  // light menu bar: black
    NSImage *white = [NSImage imageWithSize:img.size
                                    flipped:NO
                             drawingHandler:^BOOL(NSRect r) {
                                 [img drawInRect:r];
                                 [NSColor.whiteColor set];
                                 NSRectFillUsingOperation(r, NSCompositingOperationSourceAtop);
                                 return YES;
                             }];
    [white drawInRect:NSMakeRect(w + 2 * pad, pad, w, h)];  // dark menu bar: white
    [NSGraphicsContext restoreGraphicsState];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [png writeToFile:path atomically:YES] ? 0 : 1;
}

static LSDelegate *g_delegate;

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        for (NSString *lang in NSLocale.preferredLanguages)
            if ([lang hasPrefix:@"ru"]) g_ruUI = YES;
        if (argc >= 2 && strcmp(argv[1], "--selftest") == 0) return SelfTest();
        if (argc >= 3 && strcmp(argv[1], "--render-icon") == 0) return RenderIcon(@(argv[2]));
        NSApplication *app = NSApplication.sharedApplication;
        g_delegate = [LSDelegate new];
        app.delegate = g_delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
