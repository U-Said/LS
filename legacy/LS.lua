-- LS (LiteSwitcher) for macOS — a lightweight RU/EN keyboard layout switcher for Hammerspoon.
--
-- Install: put this file into ~/.hammerspoon/ and add this line to ~/.hammerspoon/init.lua:
--     require("LS")
--
--   Space / Return   — a word typed in the wrong layout is fixed automatically
--   Double Shift     — fix the last word (again — revert); with no fresh word, fix the selected text
--
-- Needs two input sources: an English one (ABC / U.S.) and "Russian" or "Russian – PC".

local M = {}

local etypes = hs.eventtap.event.types
local props = hs.eventtap.event.properties
local newKey = hs.eventtap.event.newKeyEvent
local MAGIC = 0x4C53            -- marks our own synthetic events so the tap ignores them
local KEY_DELETE, KEY_SPACE, KEY_RETURN, KEY_ENTER = 51, 49, 36, 76
local KEY_LSHIFT, KEY_RSHIFT = 56, 60
local KEY_C, KEY_V = 8, 9       -- physical keys, the same in any layout

-- ------------------------------------------------------------------ UTF-8 helpers
local function chars(s)
  local t = {}
  for c in s:gmatch(utf8.charpattern) do t[#t + 1] = c end
  return t
end

local function has(s, c) return s:find(c, 1, true) ~= nil end

local function lower(c)
  local cp = utf8.codepoint(c)
  if cp < 128 then return c:lower() end
  if cp >= 0x410 and cp <= 0x42F then return utf8.char(cp + 0x20) end
  if cp == 0x401 then return "ё" end
  return c
end

local function lowerArr(a)
  local t = {}
  for i = 1, #a do t[i] = lower(a[i]) end
  return t
end

local function isLat(c) return #c == 1 and c >= "a" and c <= "z" end

local function isCyr(c)
  if #c ~= 2 then return false end
  local cp = utf8.codepoint(c)
  return (cp >= 0x430 and cp <= 0x44F) or cp == 0x451
end

local function isDigit(c) return #c == 1 and c >= "0" and c <= "9" end

-- ------------------------------------------------------------------ layout tables (47 keys, ANSI order)
local function layout(lowerRow, upperRow)
  local arr = chars(lowerRow .. upperRow)
  local idx = {}
  for i, c in ipairs(arr) do if not idx[c] then idx[c] = i end end
  return { arr = arr, idx = idx }
end

local US  = layout("`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./",
                   "~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?")
local PC  = layout("ё1234567890-=йцукенгшщзхъ\\фывапролджэячсмитьбю.",          -- "Russian – PC"
                   "Ё!\"№;%:?*()_+ЙЦУКЕНГШЩЗХЪ/ФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,")
local MAC = layout("]1234567890-=йцукенгшщзхъёфывапролджэячсмитьбю/",           -- Apple "Russian"
                   "[!\"№%:,.;()_+ЙЦУКЕНГШЩЗХЪЁФЫВАПРОЛДЖЭЯЧСМИТЬБЮ?")

local function convert(arr, from, to)
  local out = {}
  for i, c in ipairs(arr) do
    local k = from.idx[c]
    out[i] = k and to.arr[k] or c
  end
  return out
end

-- ------------------------------------------------------------------ detector
local RUV = "аеёиоуыэюя"

local function makeSet(words)
  local s = { [""] = true }
  for w in words:gmatch("%S+") do s[w] = true end
  return s
end

local CommonEn = makeSet(
  "the be to of and in that have it for not on with he as you do at this but his by from they we say her she or an " ..
  "will my one all would there their what so up out if about who get which go me when make can like time no just him " ..
  "know take people into year your good some could them see other than then now look only come its over think also " ..
  "back after use two how our work first well way even new want because any these give day most us is are was were " ..
  "been has had did am being here very much more many such those own same too where why while should must may might " ..
  "each every both few again once before between under through during without against around off down still never " ..
  "always often really maybe yes ok okay hello hi hey thanks thank please sorry love help need find tell ask try call " ..
  "keep let put seem feel become leave mean name home world life hand part place case week number point fact group " ..
  "problem thing man woman child school state family house company system program question money right left long " ..
  "little big great small old high low next last best better sure true false null file code data test user login " ..
  "email password google windows linux python java script http https ftp www html css xml json sql php pdf txt jpg " ..
  "jpeg png gif svg exe dll zip rar mp3 mp4 usb cpu gpu ram ssd hdd wifi api url uri sdk ide git npm pip src cmd ssh " ..
  "vpn dns tcp udp ip id ui ux qa pr vs tv pc db js ts cs py md rb kb mb gb px pt hr br td tr th ul ol li div img " ..
  "btn std str int ptr len num max min avg tmp msg cfg app dev prod docs lib bin etc usr var opt i.e e.g fly sky dry " ..
  "cry shy spy fry myth sync lynx hymn crypt gym printf sprintf fprintf scanf kubectl href rgba rgb stdin stdout " ..
  "stderr nginx mkdir chmod chown sudo grep curl wget argv argc args kwargs utf ascii uuid guid tsx jsx yml yaml " ..
  "toml csv tsv sqlite mysql redis nodejs webpack eslint pytest numpy scipy github gitlab vscode powershell dotnet " ..
  "nuget xcode docker async await const struct enum void bool char float double string array object class public " ..
  "private static return import export function default brew zsh bash macos")

local CommonRu = makeSet(
  "и в не на я что он с как а то по это она этот к но они мы все всё у же вы за бы так от его её ее из ты да нет " ..
  "для о мне меня был была было были быть есть ещё еще уже или если когда только вот тоже себя свой мой твой наш " ..
  "ваш их там тут здесь где кто чем чтобы до ли ну под при над без про через после очень можно надо нужно будет " ..
  "буду будем раз два три год день время дело жизнь рука человек люди слово место лицо друг дом сам сама само " ..
  "самый который которая которые этого этом эта эти тот та те того тем том них него неё нее ним ней нас нам вас " ..
  "вам тебя тебе себе мной тобой один одна одно ничего никогда всегда сейчас теперь потом тогда потому почему " ..
  "зачем куда откуда сколько какой какая какие такой такая такие другой другие новый большой хорошо плохо " ..
  "спасибо пожалуйста привет пока ладно давай может могу можешь хочу хочешь знаю знаешь думаю говорит сказал " ..
  "сказала сделать делать работа работать вопрос ответ более менее много мало также либо ведь даже лишь уж " ..
  "вдруг почти совсем просто конечно наверное кстати например значит вообще именно сегодня завтра вчера утро " ..
  "вечер ночь ща шт ша ок здравствуйте добрый доброе понял поняла ясно точно типа короче блин норм нормально " ..
  "дела чё че щас")

local Onsets = makeSet(
  "b bl br c ch chr cl cr d dr dw f fl fr g gh gl gn gr h j k kl kn kr l m n p ph phr pl pr ps q r rh s sc sch scr " ..
  "sh shr sk sl sm sn sp sph spl spr st str sv sw t th thr tr ts tw v w wh wr x z")

local Codas = makeSet(
  "b bb bs bt bts c ch ck cks cs ct cts d dd dds ds dth dz f ff ffs fs ft fth fths fts g gg gs gh ghs ght ghts gm gn " ..
  "gns h hm hn hs k ks l lb lbs lc lch ld lds lf lfs lfth lk lks ll lls lm lms ln lp lps lpt ls lt lth lts ltz lv m " ..
  "mb mbs mm mn mns mp mps mpt mpts ms mth n nc nch nct ncts nd nds ng ngs ngst ngth ngths nk nks nn ns nst nt nth " ..
  "nths nts ntz nx nz p pp ps pt pth pths pts r rb rbs rc rch rd rds rf rfs rg rgs rk rks rl rld rlds rls rm rms " ..
  "rmth rn rns rp rps rpt rr rs rsh rst rsts rt rth rths rts rtz rv rz s sc sh sk sks sm sms sp sps ss st sts t tch " ..
  "th thm thms ths ts tt tts tz v vs w wd wds wk wks wl wls wn wns ws wt wth x xt xth xts z zz")

local BadEn = makeSet(
  "vb vc vd vf vg vh vj vk vm vp vq vt vw vx vz zx xz qq wx wq wj hx hj hq kx kq kz kj pq pz cx cj cv cf cg cp cw " ..
  "bx bq dx dq fq fx fz fv gq gx mq mx mz mj lx lq tq tx sx zc zd zf zg zj zk zp zq zr zs zv zw xj xk xg")

local function badRu(p, c)
  local pv = has(RUV, p)
  if c == "ь" or c == "ъ" then return pv or p == "й" or p == "ь" or p == "ъ" or p == "-" end
  if p == "-" then return false end
  if p == "ъ" then return not has("еёюя", c) end
  if p == "ь" then return has("ыйау", c) end
  if c == "ы" then return pv or has("жшчщйгкх", p) end
  if p == "ё" then return has(RUV, c) end
  if p == "й" then return has("йёэ", c) end
  if c == "щ" then return has("гджзклпсфхцчшщ", p) end
  if p == "щ" then return not has("аеёиоун", c) end
  if p == "ч" then return has("бгджзпфхцсяю", c) end
  if p == "ж" then return has("фхцчшптзя", c) end
  if p == "ш" then return has("жзчцфхбгдя", c) end
  if p == "ц" then return has("бгджзпфхчшяюё", c) end
  if p == "ф" then return has("бвгджзпхц", c) end
  if p == "э" then return c == "э" end
  return false
end

local function ruPlausible(w)                 -- w: array of lowercase chars
  local n = #w
  if n < 3 then return false end
  if has("ъьы", w[1]) or w[n] == "ъ" then return false end
  local hasV, run = false, 0
  for i = 1, n do
    local c = w[i]
    if c == "-" then
      if i == 1 or i == n then return false end
      run = 0
    else
      if not isCyr(c) then return false end
      if has(RUV, c) then
        hasV = true; run = 0
      elseif c ~= "ь" and c ~= "ъ" then
        run = run + 1
        if run > 5 then return false end
      end
      if i > 1 then
        local p = w[i - 1]
        if badRu(p, c) then return false end
        if i > 2 and p == c and w[i - 2] == c then return false end
      end
    end
  end
  return hasV
end

local function enPlausibleWord(w)             -- w: lowercase ASCII string
  local n = #w
  if n == 0 then return false end
  local first, last, run, strong = 0, 0, 0, false
  for i = 1, n do
    local c = w:sub(i, i)
    if not isLat(c) then return false end
    if has("aeiouy", c) then
      if first == 0 then first = i end
      last = i; run = 0
      if c ~= "y" then strong = true end
    else
      run = run + 1
      if run > 5 then return false end
    end
    if i < n then
      local d = w:sub(i + 1, i + 1)
      if c == "q" and d ~= "u" then return false end
      if c == "j" and not has("aeiouy", d) then return false end
      if BadEn[c .. d] then return false end
    elseif c == "q" or c == "j" then
      return false
    end
  end
  if not strong then return false end
  return Onsets[w:sub(1, first - 1)] == true and Codas[w:sub(last + 1)] == true
end

-- A token like "file.txt" or "don't": split on non-letters.
local function enPlausibleToken(t)            -- t: array of lowercase chars
  local any, part = false, {}
  for i = 1, #t + 1 do
    local c = t[i]
    if c and isLat(c) then
      part[#part + 1] = c
    elseif #part > 0 then
      local w = table.concat(part)
      part = {}
      if enPlausibleWord(w) then
        if #w >= 2 then any = true end
      elseif #w > 3 then
        return false
      end
    end
  end
  return any
end

local function trimTo(a, pred)
  local i, j = 1, #a
  while i <= j and not pred(a[i]) do i = i + 1 end
  while j >= i and not pred(a[j]) do j = j - 1 end
  local t = {}
  for k = i, j do t[#t + 1] = a[k] end
  return t
end

local function allLat(a)
  if #a == 0 then return false end
  for _, c in ipairs(a) do if not isLat(c) then return false end end
  return true
end

local exceptions = {}

-- en / ru: what the typed keys give in each layout (arrays of chars); curIsEn: which one is active.
local function shouldSwitch(en, ru, curIsEn)
  local cur = curIsEn and en or ru
  local letters, hasLower = 0, false
  for _, c in ipairs(cur) do
    if isDigit(c) then return false end
    local l = lower(c)
    if isLat(l) or isCyr(l) then
      letters = letters + 1
      if l == c then hasLower = true end
    end
  end
  if letters >= 2 and not hasLower then return false end        -- ABBREVIATIONS are left alone
  en, ru = lowerArr(en), lowerArr(ru)
  if exceptions[table.concat(curIsEn and en or ru)] then return false end
  local enCore, ruCore = trimTo(en, isLat), trimTo(ru, isCyr)
  local enS, ruS = table.concat(enCore), table.concat(ruCore)
  if curIsEn then
    if #ruCore < 2 then return false end
    if exceptions[enS] or CommonEn[enS] then return false end
    if CommonRu[ruS] then return true end
    return ruPlausible(ruCore) and not enPlausibleToken(enCore)
  end
  if #enCore < 2 or not allLat(enCore) then return false end
  if exceptions[ruS] or CommonRu[ruS] then return false end
  if CommonEn[enS] then return true end
  return #enCore >= 3 and not ruPlausible(ruCore) and enPlausibleWord(enS)
end

-- ------------------------------------------------------------------ state, settings, exceptions
local buf = {}                 -- characters of the current word exactly as they are on screen
local lastAuto = nil           -- original text of the last auto-fix (for learning on undo)
local shiftArmed, shiftDownAt, lastTap = false, 0, nil
local excludedApps = {}
local TERMINALS = { "terminal", "iterm2", "alacritty", "kitty", "wezterm", "warp", "hyper", "ghostty" }
local excFile = hs.configdir .. "/LS_exceptions.txt"

M.auto = hs.settings.get("LS.auto") ~= false
M.doubleShift = hs.settings.get("LS.doubleShift") ~= false

local function loadExceptions()
  exceptions, excludedApps = {}, {}
  for _, t in ipairs(TERMINALS) do excludedApps[t] = true end
  local f = io.open(excFile, "r")
  if not f then return end
  for line in f:lines() do
    local s = table.concat(lowerArr(chars((line:gsub("^%s+", ""):gsub("%s+$", "")))))
    if s ~= "" and s:sub(1, 1) ~= "#" then
      if s:sub(1, 1) == "@" then excludedApps[s:sub(2)] = true else exceptions[s] = true end
    end
  end
  f:close()
end

local function ensureExcFile()
  local f = io.open(excFile, "r")
  if f then f:close() return end
  f = io.open(excFile, "w")
  if not f then return end
  f:write("# LS exceptions. One word per line — it will not be auto-fixed.\n" ..
          "# A line like @app name (lowercase) turns auto-switching off in that app.\n")
  f:close()
end

local function addException(word)
  if not word or word == "" or exceptions[word] then return end
  exceptions[word] = true
  ensureExcFile()
  local f = io.open(excFile, "a")
  if f then f:write(word, "\n") f:close() end
end

local function clear() buf = {}; lastAuto = nil end

local function appExcluded()
  local app = hs.application.frontmostApplication()
  local name = app and app:name()
  return name ~= nil and excludedApps[name:lower()] == true
end

-- ------------------------------------------------------------------ layouts
local function isEnId(id)
  return id:find("%.US$") or id:find("%.ABC") or id:find("USExtended") or id:find("USInternational")
      or id:find("British") or id:find("Australian") or id:find("Canadian$") or id:find("Irish$")
end

local function findLayouts()
  local en, ru
  for _, id in ipairs(hs.keycodes.layouts(true) or {}) do
    if id:find("Russian") then ru = ru or id
    elseif isEnId(id) then en = en or id end
  end
  return en, ru
end

-- Returns: curIsEn (or nil when the active layout is neither), en id, ru id, ru table.
local function layoutState()
  local en, ru = findLayouts()
  if not en or not ru then return nil end
  local cur = hs.keycodes.currentSourceID() or ""
  local curIsEn
  if cur:find("Russian") then curIsEn = false
  elseif cur == en or isEnId(cur) then curIsEn = true
  else return nil end
  return curIsEn, en, ru, (ru:find("RussianWin") and PC or MAC)
end

-- ------------------------------------------------------------------ synthetic input
local function post(ev)
  ev:setProperty(props.eventSourceUserData, MAGIC)
  ev:post()
end

local function tapKey(code, mods)
  post(newKey(mods or {}, code, true))
  post(newKey(mods or {}, code, false))
end

local function typeChars(arr)
  for _, c in ipairs(arr) do
    if c == " " then
      tapKey(KEY_SPACE)
    else
      local d, u = newKey({}, 0, true), newKey({}, 0, false)
      d:setUnicodeString(c); u:setUnicodeString(c)
      post(d); post(u)
    end
  end
end

-- ------------------------------------------------------------------ fixing the selected text
local selBusy = false

local function convertSelection()
  if selBusy then return end
  local curIsEn, en, ru, ruTab = layoutState()
  if not en then return end
  selBusy = true
  local saved = hs.pasteboard.getContents()
  local count = hs.pasteboard.changeCount()
  tapKey(KEY_C, { "cmd" })
  hs.timer.doAfter(0.2, function()
    if hs.pasteboard.changeCount() == count then selBusy = false return end   -- nothing selected
    local text = hs.pasteboard.getContents()
    if text and text ~= "" then
      local arr, lat, cyr = chars(text), 0, 0
      for _, c in ipairs(arr) do
        local l = lower(c)
        if isLat(l) then lat = lat + 1 elseif isCyr(l) then cyr = cyr + 1 end
      end
      local toRu = lat >= cyr
      local out = toRu and convert(arr, US, ruTab) or convert(arr, ruTab, US)
      hs.pasteboard.setContents(table.concat(out))
      tapKey(KEY_V, { "cmd" })
      hs.keycodes.currentSourceID(toRu and ru or en)
    end
    hs.timer.doAfter(0.4, function()                                          -- restore the clipboard
      if saved then hs.pasteboard.setContents(saved) else hs.pasteboard.clearContents() end
      selBusy = false
    end)
  end)
end

-- ------------------------------------------------------------------ fixing the last word
local function manualConvert()
  local any = false
  for _, c in ipairs(buf) do if c ~= " " then any = true break end end
  if not any then convertSelection() return end
  local curIsEn, en, ru, ruTab = layoutState()
  if curIsEn == nil then return end
  local neu = curIsEn and convert(buf, US, ruTab) or convert(buf, ruTab, US)
  if lastAuto then addException(lastAuto); lastAuto = nil end   -- undoing an auto-fix => remember the word
  for _ = 1, #buf do tapKey(KEY_DELETE) end
  typeChars(neu)
  hs.keycodes.currentSourceID(curIsEn and ru or en)
  buf = neu
end

-- Called on Space / Return before the key reaches the app. true => word fixed, key already re-sent.
local function tryAuto(tailKey)
  local curIsEn, en, ru, ruTab = layoutState()
  if curIsEn == nil or appExcluded() then return false end
  local alt = curIsEn and convert(buf, US, ruTab) or convert(buf, ruTab, US)
  if not shouldSwitch(curIsEn and buf or alt, curIsEn and alt or buf, curIsEn) then return false end
  for _ = 1, #buf do tapKey(KEY_DELETE) end
  typeChars(alt)
  tapKey(tailKey)
  hs.keycodes.currentSourceID(curIsEn and ru or en)
  if tailKey == KEY_SPACE then
    lastAuto = table.concat(lowerArr(buf))
    buf = alt
    buf[#buf + 1] = " "
  end
  return true
end

-- ------------------------------------------------------------------ event tap
local function handle(e)
  if e:getProperty(props.eventSourceUserData) == MAGIC then return false end
  local t = e:getType()

  if t == etypes.leftMouseDown or t == etypes.rightMouseDown or t == etypes.otherMouseDown then
    clear(); shiftArmed = false; lastTap = nil
    return false
  end

  if t == etypes.flagsChanged then
    local code, f = e:getKeyCode(), e:getFlags()
    if code == KEY_LSHIFT or code == KEY_RSHIFT then
      local now = hs.timer.secondsSinceEpoch()
      if f.shift then
        shiftArmed = not (f.cmd or f.alt or f.ctrl)
        shiftDownAt = now
        if not shiftArmed then lastTap = nil end
      else
        local tap = shiftArmed and (now - shiftDownAt) <= 0.3
        shiftArmed = false
        if tap and M.doubleShift then
          if lastTap and now - lastTap <= 0.4 then
            lastTap = nil
            manualConvert()
          else
            lastTap = now
          end
        end
      end
    else
      shiftArmed = false; lastTap = nil
    end
    return false
  end

  -- keyDown
  shiftArmed = false; lastTap = nil
  local f, code = e:getFlags(), e:getKeyCode()
  if f.cmd or f.ctrl or f.alt then clear() return false end
  if code == KEY_DELETE then
    buf[#buf] = nil; lastAuto = nil
    return false
  end
  if code == KEY_SPACE then
    if #buf == 0 then return false end
    if buf[#buf] ~= " " and M.auto and tryAuto(KEY_SPACE) then return true end
    buf[#buf + 1] = " "
    return false
  end
  if code == KEY_RETURN or code == KEY_ENTER then
    local done = #buf > 0 and buf[#buf] ~= " " and M.auto and tryAuto(KEY_RETURN)
    clear()
    return done
  end
  local cs = chars(e:getCharacters() or "")
  if #cs == 1 and (US.idx[cs[1]] or PC.idx[cs[1]] or MAC.idx[cs[1]]) then
    if buf[#buf] == " " or #buf >= 100 then clear() end
    lastAuto = nil
    buf[#buf + 1] = cs[1]
    return false
  end
  clear()
  return false
end

M.tap = hs.eventtap.new(
  { etypes.keyDown, etypes.flagsChanged, etypes.leftMouseDown, etypes.rightMouseDown, etypes.otherMouseDown },
  function(e)
    local ok, swallow = pcall(handle, e)
    if not ok then clear() return false end
    return swallow == true
  end)

M.appWatcher = hs.application.watcher.new(function(_, event)
  if event == hs.application.watcher.activated then clear() end
end)

-- ------------------------------------------------------------------ menu bar
local RU_UI = ((hs.host.locale.preferredLanguages() or {})[1] or ""):sub(1, 2) == "ru"
local function L(ru, en) return RU_UI and ru or en end

M.menu = hs.menubar.new()
if M.menu then
  M.menu:setTitle("LS")
  M.menu:setTooltip(L("LS — двойной Shift: исправить раскладку", "LS — double Shift: fix the layout"))
  M.menu:setMenu(function()
    loadExceptions()                       -- pick up edits of the exceptions file
    return {
      { title = L("Автопереключение", "Auto-switching"), checked = M.auto, fn = function()
          M.auto = not M.auto; hs.settings.set("LS.auto", M.auto) end },
      { title = L("Двойной Shift — исправить", "Double Shift to fix"), checked = M.doubleShift, fn = function()
          M.doubleShift = not M.doubleShift; hs.settings.set("LS.doubleShift", M.doubleShift) end },
      { title = L("Исключения…", "Exceptions…"), fn = function()
          ensureExcFile(); hs.execute('open -t "' .. excFile .. '"') end },
      { title = "-" },
      { title = L("Выключить LS", "Turn LS off"), fn = function() M.stop() end },
    }
  end)
end

function M.start()
  loadExceptions()
  if not hs.accessibilityState(true) then
    hs.alert.show(L("LS: разрешите Hammerspoon в «Универсальном доступе»",
                    "LS: allow Hammerspoon in Accessibility settings"), 6)
  end
  local en, ru = findLayouts()
  if not en or not ru then
    hs.alert.show(L("LS: добавьте раскладки ABC (U.S.) и «Русская»",
                    "LS: add the ABC (U.S.) and Russian input sources"), 6)
  end
  M.tap:start()
  M.appWatcher:start()
  return M
end

function M.stop()
  M.tap:stop()
  M.appWatcher:stop()
  if M.menu then M.menu:delete(); M.menu = nil end
  return M
end

-- Detector self-test: require("LS").selfTest() in the Hammerspoon console.
function M.selfTest()
  local out = {}
  local function row(typed, curIsEn)
    local a = chars(typed)
    local alt = curIsEn and convert(a, US, PC) or convert(a, PC, US)
    local sw = shouldSwitch(curIsEn and a or alt, curIsEn and alt or a, curIsEn)
    out[#out + 1] = typed .. " -> " .. table.concat(alt) .. " : " .. (sw and "SWITCH" or "keep")
  end
  for _, s in ipairs({ "ghbdtn", "rfr", "xnj", "relf", "ytn", "k.,jdm", "cgfcb,j", "vjcrdf", "[jhjij", "e;t",
                       "hello", "the", "printf", "file.txt", "google.com", "pdf", "grep", "world", "don't",
                       "HTTP", "abc123", "kubectl", "strength" }) do row(s, true) end
  for _, s in ipairs({ "руддщ", "цщкдв", "еру", "ершы", "сщьзгеук", "цштвщц", "привет", "днк", "хорошо",
                       "компьютер", "спс", "молоко" }) do row(s, false) end
  return table.concat(out, "\n")
end

LS = M            -- keep a global reference so the event tap is not garbage-collected
return M.start()
