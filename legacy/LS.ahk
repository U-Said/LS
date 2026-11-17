; LS — лёгкий переключатель раскладки (аналог Punto Switcher) для AutoHotkey v2.
;   Pause или двойной Shift  — исправить последнее слово (ещё раз — вернуть обратно)
;   Shift+Pause              — исправить выделенный текст
;   Автопереключение         — слово проверяется после пробела
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
FileEncoding "UTF-8"
SetKeyDelay -1, -1

global RuV := "аеёиоуыэюя"
global TabEN := "``qwertyuiop[]asdfghjkl;'zxcvbnm,./~QWERTYUIOP{}ASDFGHJKL:`"ZXCVBNM<>?@#$^&|"
global TabRU := "ёйцукенгшщзхъфывапролджэячсмитьбю.ЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,`"№;:?/"

global CommonEn := MakeSet(
    "the be to of and in that have it for not on with he as you do at this but his by from they we say her she or an "
  . "will my one all would there their what so up out if about who get which go me when make can like time no just him "
  . "know take people into year your good some could them see other than then now look only come its over think also "
  . "back after use two how our work first well way even new want because any these give day most us is are was were "
  . "been has had did am being here very much more many such those own same too where why while should must may might "
  . "each every both few again once before between under through during without against around off down still never "
  . "always often really maybe yes ok okay hello hi hey thanks thank please sorry love help need find tell ask try call "
  . "keep let put seem feel become leave mean name home world life hand part place case week number point fact group "
  . "problem thing man woman child school state family house company system program question money right left long "
  . "little big great small old high low next last best better sure true false null file code data test user login "
  . "email password google windows linux python java script http https ftp www html css xml json sql php pdf txt jpg "
  . "jpeg png gif svg exe dll zip rar mp3 mp4 usb cpu gpu ram ssd hdd wifi api url uri sdk ide git npm pip src cmd ssh "
  . "vpn dns tcp udp ip id ui ux qa pr vs tv pc db js ts cs py md rb kb mb gb px pt hr br td tr th ul ol li div img "
  . "btn std str int ptr len num max min avg tmp msg cfg app dev prod docs lib bin etc usr var opt i.e e.g fly sky dry "
  . "cry shy spy fry myth sync lynx hymn crypt gym printf sprintf fprintf scanf kubectl href rgba rgb stdin stdout "
  . "stderr nginx mkdir chmod chown sudo grep curl wget argv argc args kwargs utf ascii uuid guid tsx jsx yml yaml "
  . "toml csv tsv sqlite mysql redis nodejs webpack eslint pytest numpy scipy github gitlab vscode powershell dotnet "
  . "nuget xcode docker async await const struct enum void bool char float double string array object class public "
  . "private static return import export function default")

global CommonRu := MakeSet(
    "и в не на я что он с как а то по это она этот к но они мы все всё у же вы за бы так от его её ее из ты да нет "
  . "для о мне меня был была было были быть есть ещё еще уже или если когда только вот тоже себя свой мой твой наш "
  . "ваш их там тут здесь где кто чем чтобы до ли ну под при над без про через после очень можно надо нужно будет "
  . "буду будем раз два три год день время дело жизнь рука человек люди слово место лицо друг дом сам сама само "
  . "самый который которая которые этого этом эта эти тот та те того тем том них него неё нее ним ней нас нам вас "
  . "вам тебя тебе себе мной тобой один одна одно ничего никогда всегда сейчас теперь потом тогда потому почему "
  . "зачем куда откуда сколько какой какая какие такой такая такие другой другие новый большой хорошо плохо "
  . "спасибо пожалуйста привет пока ладно давай может могу можешь хочу хочешь знаю знаешь думаю говорит сказал "
  . "сказала сделать делать работа работать вопрос ответ более менее много мало также либо ведь даже лишь уж "
  . "вдруг почти совсем просто конечно наверное кстати например значит вообще именно сегодня завтра вчера утро "
  . "вечер ночь ща шт ша ок здравствуйте добрый доброе понял поняла ясно точно типа короче блин норм нормально "
  . "дела чё че щас")

global Onsets := MakeSet(
    "b bl br c ch chr cl cr d dr dw f fl fr g gh gl gn gr h j k kl kn kr l m n p ph phr pl pr ps q r rh s sc sch scr "
  . "sh shr sk sl sm sn sp sph spl spr st str sv sw t th thr tr ts tw v w wh wr x z")

global Codas := MakeSet(
    "b bb bs bt bts c ch ck cks cs ct cts d dd dds ds dth dz f ff ffs fs ft fth fths fts g gg gs gh ghs ght ghts gm gn "
  . "gns h hm hn hs k ks l lb lbs lc lch ld lds lf lfs lfth lk lks ll lls lm lms ln lp lps lpt ls lt lth lts ltz lv m "
  . "mb mbs mm mn mns mp mps mpt mpts ms mth n nc nch nct ncts nd nds ng ngs ngst ngth ngths nk nks nn ns nst nt nth "
  . "nths nts ntz nx nz p pp ps pt pth pths pts r rb rbs rc rch rd rds rf rfs rg rgs rk rks rl rld rlds rls rm rms "
  . "rmth rn rns rp rps rpt rr rs rsh rst rsts rt rth rths rts rtz rv rz s sc sh sk sks sm sms sp sps ss st sts t tch "
  . "th thm thms ths ts tt tts tz v vs w wd wds wk wks wl wls wn wns ws wt wth x xt xth xts z zz")

global BadEn := MakeSet(
    "vb vc vd vf vg vh vj vk vm vp vq vt vw vx vz zx xz qq wx wq wj hx hj hq kx kq kz kj pq pz cx cj cv cf cg cp cw "
  . "bx bq dx dq fq fx fz fv gq gx mq mx mz mj lx lq tq tx sx zc zd zf zg zj zk zp zq zr zs zv zw xj xk xg")

global Terminals := "windowsterminal cmd powershell pwsh conhost openconsole putty mintty alacritty wezterm-gui"

; ---------------------------------------------------------------- состояние
global buf := []            ; набранные клавиши текущего слова: {vk, sc, shift, caps}
global bufLayout := 0       ; раскладка, в которой буфер «напечатан» после конвертации
global lastAuto := ""       ; исходный текст последней автозамены (для обучения по отмене)
global lastFg := 0
global lastShiftTap := 0
global exceptions := Map()
global excludedApps := Map()
global IniFile := A_ScriptDir "\LS.ini"
global ExcFile := A_ScriptDir "\exceptions.txt"
global StartupLnk := A_Startup "\LS.lnk"
global optAuto := IniRead(IniFile, "Options", "Auto", "1") = "1"
global optDoubleShift := IniRead(IniFile, "Options", "DoubleShift", "1") = "1"

if (A_Args.Length = 2 && A_Args[1] = "--selftest") {
    SelfTest(A_Args[2])
    ExitApp
}

LoadExceptions()
BuildTray()

global ih := InputHook("V L0 I")      ; V — клавиши проходят дальше, I — игнорировать наш собственный ввод
ih.KeyOpt("{All}", "N")
ih.OnKeyDown := OnKey
ih.Start()

; ---------------------------------------------------------------- горячие клавиши
Pause::ManualConvert()
+Pause::ConvertSelection()
~LShift up::ShiftTap("LShift")
~RShift up::ShiftTap("RShift")
~*LButton::ResetState()
~*RButton::ResetState()
~*MButton::ResetState()

ResetState() {
    global lastShiftTap
    ClearBuf()
    lastShiftTap := 0
}

ShiftTap(name) {
    global lastShiftTap
    if !optDoubleShift
        return
    if (A_PriorKey != name) {           ; с Shift что-то набирали — это не «тап»
        lastShiftTap := 0
        return
    }
    now := A_TickCount
    if (lastShiftTap && now - lastShiftTap <= 400) {
        lastShiftTap := 0
        ManualConvert()
    } else
        lastShiftTap := now
}

; ---------------------------------------------------------------- отслеживание набора
OnKey(hook, vk, sc) {
    global lastShiftTap, lastFg, lastAuto, bufLayout
    if (vk = 0x10 || vk = 0xA0 || vk = 0xA1)
        return
    lastShiftTap := 0
    if (vk = 0x11 || vk = 0x12 || (vk >= 0xA2 && vk <= 0xA5) || vk = 0x5B || vk = 0x5C || vk = 0x14 || vk = 0x13)
        return
    fg := WinExist("A")
    if (fg != lastFg) {
        lastFg := fg
        ClearBuf()
    }
    if (GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P") || GetKeyState("LWin", "P") || GetKeyState("RWin", "P")) {
        ClearBuf()
        return
    }
    if (vk = 0x08) {                    ; Backspace
        if buf.Length
            buf.Pop()
        lastAuto := ""
        return
    }
    if (vk = 0x20) {                    ; пробел — конец слова
        if !buf.Length
            return
        if (!EndsWithSpace() && optAuto && TryAuto())
            return
        PushKey(0x20, 0x39, false)
        return
    }
    if IsCharVk(vk) {
        if (EndsWithSpace() || buf.Length >= 100)
            ClearBuf()
        lastAuto := ""
        bufLayout := 0
        PushKey(vk, sc & 0xFF, GetKeyState("Shift", "P"))
        return
    }
    ClearBuf()
}

ClearBuf() {
    global buf, bufLayout, lastAuto
    buf := []
    bufLayout := 0
    lastAuto := ""
}

EndsWithSpace() {
    return buf.Length && buf[buf.Length].vk = 0x20
}

IsCharVk(vk) {
    return (vk >= 0x30 && vk <= 0x39) || (vk >= 0x41 && vk <= 0x5A) || (vk >= 0xBA && vk <= 0xC0)
        || (vk >= 0xDB && vk <= 0xDF) || vk = 0xE2
}

PushKey(vk, sc, shift) {
    buf.Push({vk: vk, sc: sc, shift: shift, caps: GetKeyState("CapsLock", "T")})
}

; ---------------------------------------------------------------- раскладки
Lang(hkl) {
    return hkl & 0x3FF
}

; Возвращает раскладку активного окна; target — окно/контрол с фокусом ввода.
CurrentLayout(&target) {
    target := WinExist("A")
    if !target
        return 0
    try {
        f := ControlGetFocus("ahk_id " target)
        if f
            target := f
    }
    tid := DllCall("GetWindowThreadProcessId", "ptr", target, "ptr", 0, "uint")
    return DllCall("GetKeyboardLayout", "uint", tid, "ptr")
}

FindLayouts(&en, &ru) {
    en := 0, ru := 0
    n := DllCall("GetKeyboardLayoutList", "int", 0, "ptr", 0, "int")
    list := []
    if (n <= 0)
        return list
    b := Buffer(n * A_PtrSize, 0)
    n := DllCall("GetKeyboardLayoutList", "int", n, "ptr", b, "int")
    Loop n {
        h := NumGet(b, (A_Index - 1) * A_PtrSize, "ptr")
        list.Push(h)
        if (Lang(h) = 0x09 && !en)
            en := h
        if (Lang(h) = 0x19 && !ru)
            ru := h
    }
    return list
}

NextLayout(cur) {
    list := FindLayouts(&en, &ru)
    if (en && ru)
        return Lang(cur) = 0x19 ? en : ru
    if (list.Length < 2)
        return cur
    for i, h in list
        if (h = cur)
            return list[Mod(i, list.Length) + 1]
    return list[1]
}

SwitchLayout(target, hkl) {
    if (target && hkl)
        try PostMessage(0x50, 0, hkl, , "ahk_id " target)
}

; Текст, который дают набранные клавиши в раскладке hkl.
Render(hkl) {
    static state := Buffer(256, 0), out := Buffer(32, 0)
    s := ""
    for k in buf {
        if (k.vk = 0x20) {
            s .= " "
            continue
        }
        NumPut("uchar", k.shift ? 0x80 : 0, state, 0x10)
        NumPut("uchar", k.caps ? 1 : 0, state, 0x14)
        n := DllCall("ToUnicodeEx", "uint", k.vk, "uint", k.sc, "ptr", state, "ptr", out, "int", 8, "uint", 4, "ptr", hkl, "int")
        if (n > 0)
            s .= StrGet(out, n, "UTF-16")
    }
    return s
}

; ---------------------------------------------------------------- исправление последнего слова
ManualConvert() {
    global bufLayout, lastAuto
    any := false
    for k in buf
        if (k.vk != 0x20) {
            any := true
            break
        }
    if !any {
        ConvertSelection()
        return
    }
    cur := CurrentLayout(&target)
    if bufLayout
        cur := bufLayout
    next := NextLayout(cur)
    if (!next || next = cur)
        return
    old := Render(cur), neu := Render(next)
    if (lastAuto != "") {               ; отмена автозамены => запомнить слово как исключение
        AddException(lastAuto)
        lastAuto := ""
    }
    Send("{BS " StrLen(old) "}{Text}" neu)
    SwitchLayout(target, next)
    bufLayout := next
}

; Вызывается после пробела (он уже напечатан). true — слово исправлено.
TryAuto() {
    global bufLayout, lastAuto
    FindLayouts(&en, &ru)
    if (!en || !ru)
        return false
    if AppExcluded()
        return false
    cur := CurrentLayout(&target)
    if bufLayout
        cur := bufLayout
    if (Lang(cur) = 0x09)
        curIsEn := true
    else if (Lang(cur) = 0x19)
        curIsEn := false
    else
        return false
    alt := curIsEn ? ru : en
    curText := Render(cur), altText := Render(alt)
    if !ShouldSwitch(curIsEn ? curText : altText, curIsEn ? altText : curText, curIsEn)
        return false
    Send("{BS " (StrLen(curText) + 1) "}{Text}" altText " ")
    SwitchLayout(target, alt)
    PushKey(0x20, 0x39, false)
    bufLayout := alt
    lastAuto := StrLower(curText)
    return true
}

AppExcluded() {
    try {
        name := StrLower(RegExReplace(WinGetProcessName("A"), "i)\.exe$"))
        return excludedApps.Has(name)
    }
    return false
}

; ---------------------------------------------------------------- исправление выделенного текста
ConvertSelection() {
    static busy := false
    if busy
        return
    busy := true
    CurrentLayout(&target)
    saved := ClipboardAll()
    A_Clipboard := ""
    Send("^c")
    if ClipWait(0.4) {
        t := A_Clipboard
        if (t != "") {
            conv := TableAuto(t, &toRu)
            A_Clipboard := conv
            Send("^v")
            FindLayouts(&en, &ru)
            SwitchLayout(target, toRu ? ru : en)
            Sleep(250)
        }
    }
    A_Clipboard := saved                ; вернуть буфер обмена
    busy := false
}

TableConvert(s, toRu) {
    from := toRu ? TabEN : TabRU, to := toRu ? TabRU : TabEN
    r := ""
    Loop Parse, s {
        i := InStr(from, A_LoopField, true)
        r .= i ? SubStr(to, i, 1) : A_LoopField
    }
    return r
}

TableAuto(s, &toRu) {
    lat := 0, cyr := 0
    Loop Parse, s {
        o := Ord(A_LoopField)
        if ((o >= 65 && o <= 90) || (o >= 97 && o <= 122))
            lat++
        else if ((o >= 0x410 && o <= 0x44F) || o = 0x451 || o = 0x401)
            cyr++
    }
    toRu := lat >= cyr
    return TableConvert(s, toRu)
}

; ---------------------------------------------------------------- эвристика автопереключения
MakeSet(words) {
    m := Map()
    for w in StrSplit(words, " ")
        m[w] := 1
    m[""] := 1
    return m
}

IsLat(c) {
    o := Ord(c)
    return o >= 97 && o <= 122
}

IsCyr(c) {
    o := Ord(c)
    return (o >= 0x430 && o <= 0x44F) || o = 0x451
}

TrimTo(s, cyr) {
    a := 1, b := StrLen(s)
    while (a <= b && !(cyr ? IsCyr(SubStr(s, a, 1)) : IsLat(SubStr(s, a, 1))))
        a++
    while (b >= a && !(cyr ? IsCyr(SubStr(s, b, 1)) : IsLat(SubStr(s, b, 1))))
        b--
    return SubStr(s, a, b - a + 1)
}

AllLat(s) {
    if (s = "")
        return false
    Loop Parse, s
        if !IsLat(A_LoopField)
            return false
    return true
}

BadRu(p, c) {
    pv := InStr(RuV, p) > 0
    if (c = "ь" || c = "ъ")
        return pv || p = "й" || p = "ь" || p = "ъ" || p = "-"
    if (p = "-")
        return false
    if (p = "ъ")
        return !InStr("еёюя", c)
    if (p = "ь")
        return InStr("ыйау", c) > 0
    if (c = "ы")
        return pv || InStr("жшчщйгкх", p) > 0
    if (p = "ё")
        return InStr(RuV, c) > 0
    if (p = "й")
        return InStr("йёэ", c) > 0
    if (c = "щ")
        return InStr("гджзклпсфхцчшщ", p) > 0
    if (p = "щ")
        return !InStr("аеёиоун", c)
    if (p = "ч")
        return InStr("бгджзпфхцсяю", c) > 0
    if (p = "ж")
        return InStr("фхцчшптзя", c) > 0
    if (p = "ш")
        return InStr("жзчцфхбгдя", c) > 0
    if (p = "ц")
        return InStr("бгджзпфхчшяюё", c) > 0
    if (p = "ф")
        return InStr("бвгджзпхц", c) > 0
    if (p = "э")
        return c = "э"
    return false
}

RuPlausible(w) {
    n := StrLen(w)
    if (n < 3)
        return false
    if (InStr("ъьы", SubStr(w, 1, 1)) || SubStr(w, n, 1) = "ъ")
        return false
    hasV := false, run := 0, p := "", pp := ""
    Loop n {
        c := SubStr(w, A_Index, 1)
        if (c = "-") {
            if (A_Index = 1 || A_Index = n)
                return false
            run := 0
        } else {
            if !IsCyr(c)
                return false
            if InStr(RuV, c) {
                hasV := true
                run := 0
            } else if (c != "ь" && c != "ъ") {
                run++
                if (run > 5)
                    return false
            }
            if (A_Index > 1) {
                if BadRu(p, c)
                    return false
                if (A_Index > 2 && p = c && pp = c)
                    return false
            }
        }
        pp := p
        p := c
    }
    return hasV
}

EnPlausibleWord(w) {
    n := StrLen(w)
    if !n
        return false
    first := 0, last := 0, run := 0, strong := false
    Loop n {
        c := SubStr(w, A_Index, 1)
        if !IsLat(c)
            return false
        if InStr("aeiouy", c) {
            if !first
                first := A_Index
            last := A_Index
            run := 0
            if (c != "y")
                strong := true
        } else {
            run++
            if (run > 5)
                return false
        }
        if (A_Index < n) {
            d := SubStr(w, A_Index + 1, 1)
            if (c = "q" && d != "u")
                return false
            if (c = "j" && !InStr("aeiouy", d))
                return false
            if BadEn.Has(c . d)
                return false
        } else if (c = "q" || c = "j")
            return false
    }
    if !strong
        return false
    return Onsets.Has(SubStr(w, 1, first - 1)) && Codas.Has(SubStr(w, last + 1))
}

; Токен вроде "file.txt" или "don't": делим по не-буквам.
EnPlausibleToken(t) {
    any := false, start := 0, n := StrLen(t)
    Loop n + 1 {
        i := A_Index
        if (i <= n && IsLat(SubStr(t, i, 1))) {
            if !start
                start := i
            continue
        }
        if !start
            continue
        part := SubStr(t, start, i - start)
        start := 0
        if EnPlausibleWord(part) {
            if (StrLen(part) >= 2)
                any := true
        } else if (StrLen(part) > 3)
            return false
    }
    return any
}

; en / ru — что получается из набранных клавиш в каждой раскладке; curIsEn — какая активна.
ShouldSwitch(en, ru, curIsEn) {
    cur := curIsEn ? en : ru
    letters := 0, lower := false
    Loop Parse, cur {
        c := A_LoopField
        if IsDigit(c)
            return false
        up := StrUpper(c), lo := StrLower(c)
        if StrCompare(up, lo, true) {           ; это буква
            letters++
            if StrCompare(c, up, true)
                lower := true
        }
    }
    if (letters >= 2 && !lower)                 ; АББРЕВИАТУРЫ не трогаем
        return false
    en := StrLower(en), ru := StrLower(ru)
    if exceptions.Has(curIsEn ? en : ru)
        return false
    enCore := TrimTo(en, false), ruCore := TrimTo(ru, true)
    if curIsEn {
        if (StrLen(ruCore) < 2)
            return false
        if (exceptions.Has(enCore) || CommonEn.Has(enCore))
            return false
        if CommonRu.Has(ruCore)
            return true
        return RuPlausible(ruCore) && !EnPlausibleToken(enCore)
    }
    if (StrLen(enCore) < 2 || !AllLat(enCore))
        return false
    if (exceptions.Has(ruCore) || CommonRu.Has(ruCore))
        return false
    if CommonEn.Has(enCore)
        return true
    return StrLen(enCore) >= 3 && !RuPlausible(ruCore) && EnPlausibleWord(enCore)
}

; Самотест детектора: AutoHotkey64.exe LS.ahk --selftest out.txt
SelfTest(path) {
    en := ["ghbdtn", "rfr", "xnj", "relf", "ytn", "k.,jdm", "cgfcb,j", "vjcrdf", "[jhjij", "e;t", "ghbdtn?",
           "hello", "the", "printf", "file.txt", "google.com", "pdf", "grep", "world", "don't", "HTTP", "abc123", "kubectl", "strength"]
    ru := ["руддщ", "цщкдв", "еру", "ершы", "сщьзгеук", "цштвщц", "привет", "днк", "хорошо", "компьютер", "спс", "молоко"]
    out := "== набрано в EN ==`r`n"
    for s in en {
        r := TableConvert(s, true)
        out .= s " -> " r " : " (ShouldSwitch(s, r, true) ? "ПЕРЕКЛЮЧИТЬ" : "оставить") "`r`n"
    }
    out .= "== набрано в RU ==`r`n"
    for s in ru {
        e := TableConvert(s, false)
        out .= s " -> " e " : " (ShouldSwitch(e, s, false) ? "ПЕРЕКЛЮЧИТЬ" : "оставить") "`r`n"
    }
    if FileExist(path)
        FileDelete(path)
    FileAppend(out, path)
}

; ---------------------------------------------------------------- исключения, настройки, трей
LoadExceptions() {
    global exceptions, excludedApps
    exceptions := Map()
    excludedApps := Map()
    for t in StrSplit(Terminals, " ")
        excludedApps[t] := 1
    if !FileExist(ExcFile)
        return
    try Loop Read, ExcFile {
        s := StrLower(Trim(A_LoopReadLine))
        if (s = "" || SubStr(s, 1, 1) = "#")
            continue
        if (SubStr(s, 1, 1) = "@")
            excludedApps[SubStr(s, 2)] := 1
        else
            exceptions[s] := 1
    }
}

EnsureExcFile() {
    if FileExist(ExcFile)
        return
    FileAppend("# Исключения LS. Одно слово в строке — оно не будет автоисправляться.`r`n"
        . "# Строка вида @имя_процесса (без .exe) отключает автопереключение в этой программе.`r`n", ExcFile)
}

AddException(word) {
    if (word = "" || exceptions.Has(word))
        return
    exceptions[word] := 1
    try {
        EnsureExcFile()
        FileAppend(word "`r`n", ExcFile)
    }
}

BuildTray() {
    m := A_TrayMenu
    m.Delete()
    m.Add("Автопереключение", ToggleAuto)
    m.Add("Двойной Shift — исправить", ToggleShift)
    m.Add("Запускать вместе с Windows", ToggleStartup)
    m.Add("Исключения…", OpenExceptions)
    m.Add("Перечитать исключения", (*) => LoadExceptions())
    m.Add()
    m.Add("Выход", (*) => ExitApp())
    if optAuto
        m.Check("Автопереключение")
    if optDoubleShift
        m.Check("Двойной Shift — исправить")
    if FileExist(StartupLnk)
        m.Check("Запускать вместе с Windows")
    if FileExist(A_ScriptDir "\LS.ico")
        try TraySetIcon(A_ScriptDir "\LS.ico")
    A_IconTip :="LS — Pause или двойной Shift: исправить раскладку"
}

ToggleAuto(name, *) {
    global optAuto
    optAuto := !optAuto
    A_TrayMenu.ToggleCheck(name)
    IniWrite(optAuto ? "1" : "0", IniFile, "Options", "Auto")
}

ToggleShift(name, *) {
    global optDoubleShift
    optDoubleShift := !optDoubleShift
    A_TrayMenu.ToggleCheck(name)
    IniWrite(optDoubleShift ? "1" : "0", IniFile, "Options", "DoubleShift")
}

ToggleStartup(name, *) {
    if FileExist(StartupLnk)
        FileDelete(StartupLnk)
    else
        FileCreateShortcut(A_ScriptFullPath, StartupLnk, A_ScriptDir, , "LS", FileExist(A_ScriptDir "\LS.ico") ? A_ScriptDir "\LS.ico" : "")
    A_TrayMenu.ToggleCheck(name)
}

OpenExceptions(*) {
    EnsureExcFile()
    Run('notepad.exe "' ExcFile '"')
}
