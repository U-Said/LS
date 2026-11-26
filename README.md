# LiteSwitcher

**Русский** · [English](#english)

**LiteSwitcher** — лёгкий переключатель раскладки RU/EN для Windows и macOS, альтернатива Punto Switcher. Одна маленькая программа без установки: скачали, распаковали, запустили.

![LiteSwitcher: примеры исправления и меню в трее](docs/demo.png)

Набрали `ghbdtn` вместо «привет» — LiteSwitcher заметит это по пробелу, перепечатает слово и переключит раскладку. Если не заметил, исправьте вручную двойным `Shift`. Без словарей и без отправки данных куда-либо.

**Нравится LiteSwitcher? [Поддержите проект донатом](https://app.lava.top/4179967925)** ([подробнее](#поддержать-проект))

## Скачать

| Система | Файл |
|---|---|
| **Windows 10/11** на Intel или AMD (x64) | [LiteSwitcher-Windows.zip](https://github.com/U-Said/LiteSwitcher/releases/latest/download/LiteSwitcher-Windows.zip) |
| **Windows 11 на ARM**: Snapdragon (Surface Pro 11/12 и др.) | [LiteSwitcher-Windows-arm64.zip](https://github.com/U-Said/LiteSwitcher/releases/latest/download/LiteSwitcher-Windows-arm64.zip) |
| **macOS 11+**, Apple Silicon и Intel | [LiteSwitcher-macOS.zip](https://github.com/U-Said/LiteSwitcher/releases/latest/download/LiteSwitcher-macOS.zip) |

Ничего дополнительно ставить не нужно: ни AutoHotkey, ни Hammerspoon, ни библиотек.

[Конфиденциальность](PRIVACY.md) · [Политика подписи кода](CODE_SIGNING.md) · [Безопасность](SECURITY.md) · [Удаление](#удаление)

## Коротко

![LiteSwitcher коротко: как начать, клавиши, что важно знать](docs/billboard.png)

## Windows

### Запуск

1. Скачайте архив для своего процессора и распакуйте в папку, которая не синхронизируется с облаком, например `%LOCALAPPDATA%\Programs\LiteSwitcher` (вставьте этот путь в адресную строку Проводника).
2. Запустите `LiteSwitcher.exe`. Если Windows покажет «Система Windows защитила ваш компьютер», нажмите **Подробнее → Выполнить в любом случае**: программа не подписана платным сертификатом.
3. У часов появится значок LiteSwitcher. Чтобы программа запускалась сама, включите в меню значка **Запускать вместе с Windows**.

Настройки (`LiteSwitcher.ini`) и исключения (`exceptions.txt`) лежат рядом с `LiteSwitcher.exe`, так что папку можно переносить целиком. Если в эту папку нельзя писать, они хранятся в `%APPDATA%\LiteSwitcher`. Права администратора не нужны.

**Обновление.** Значок LiteSwitcher → **Выход**, замените `LiteSwitcher.exe` новым и запустите.

**Переход с LS 2.0.** До версии 2.1 программа называлась LS. Положите `LiteSwitcher.exe` в папку, где лежит `LS.exe`, и запустите. LiteSwitcher сам закроет LS и заберёт его настройки, исключения и автозапуск, если он был включён (выключенный в «Параметрах» останется выключенным), и сообщит об этом. После этого `LS.exe` можно удалить.

**Переход с версии на AutoHotkey.** Положите `LiteSwitcher.exe` в ту же папку, где был `LS.ahk`: исключения подхватятся. Старый скрипт и его автозапуск LiteSwitcher сам не трогает: если LS.ahk ещё запущен или остался в автозагрузке, программа подскажет, как его закрыть и убрать. Автозапуск LiteSwitcher включите в его меню.

### Как пользоваться

- **Автоисправление.** Набрали слово не в той раскладке и нажали пробел — слово заменяется, раскладка переключается (`ghbdtn` → `привет`, `руддщ` → `hello`).
- **Вручную.** `Pause` или двойной `Shift` исправляет последнее слово; повторное нажатие возвращает обратно.
- **Выделенный текст.** `Shift+Pause`, либо двойной `Shift`, когда только что набранного слова нет. Буфер обмена потом возвращается как был.
- **Обучение.** Отмените ошибочную автозамену двойным `Shift` — слово попадёт в `exceptions.txt` и больше не будет исправляться.
- **Меню в трее.** Автопереключение, двойной Shift, автозапуск с Windows, исключения, «Конфиденциальность…», «Поддержать проект (lava.top)…», выход.

## macOS

> Версия для macOS собирается и проходит автоматические проверки на Mac (раскладки, распознавание слов), но вживую на Mac ещё не испытана. Если что-то работает не так — напишите в [Issues](https://github.com/U-Said/LiteSwitcher/issues).

### Запуск

1. Скачайте `LiteSwitcher-macOS.zip`, распакуйте и перетащите **LiteSwitcher.app** в папку **Программы**.
2. Откройте LiteSwitcher. Приложение не заверено Apple, поэтому при первом запуске macOS его остановит. Откройте **Системные настройки → Конфиденциальность и безопасность** и внизу нажмите **Всё равно открыть**. В macOS 14 и старше можно проще: правый щелчок по LiteSwitcher.app → **Открыть**.
3. Разрешите LiteSwitcher управлять компьютером: **Конфиденциальность и безопасность → Универсальный доступ** → включите LiteSwitcher. Через пару секунд значок в строке меню станет ярким — можно печатать.
4. Проверьте, что в системе есть две раскладки: английская (**ABC** или **США**) и **Русская** или **Русская — ПК**.
5. Чтобы LiteSwitcher запускался сам, включите в его меню **Запускать при входе в систему**.

После обновления macOS может перестать считать LiteSwitcher доверенным. Тогда удалите его из **Универсального доступа** кнопкой «−» и включите снова.

**Переход с LS 2.0.** Перетащите LiteSwitcher.app в «Программы» и откройте: он сам закроет LS и заберёт его настройки, исключения и запуск при входе, если он был включён. Затем удалите LS.app в Корзину, а строку LS в **Универсальном доступе** — кнопкой «−», и включите там LiteSwitcher.

**Переход с версии для Hammerspoon.** Уберите строку `require("LS")` из `~/.hammerspoon/init.lua` и выберите в Hammerspoon **Reload Config**. Выученные исключения перенесутся сами.

### Как пользоваться

- **Автоисправление.** Набрали слово не в той раскладке и нажали пробел или Return — слово заменяется, раскладка переключается.
- **Вручную.** Двойной `Shift` исправляет последнее слово; повторное нажатие возвращает обратно.
- **Выделенный текст.** Двойной `Shift`, когда только что набранного слова нет.
- **Обучение.** Отмените ошибочную автозамену двойным `Shift` — слово попадёт в исключения (`~/Library/Application Support/LiteSwitcher/exceptions.txt`).
- **Меню в строке меню.** Автопереключение, двойной Shift, запуск при входе, исключения, «Конфиденциальность…», «Поддержать проект (lava.top)…», выход. Язык меню — как у системы.

## Особенности

- Словаря нет: слово оценивается по правилам русского и английского и по спискам частых слов, поэтому возможны пропуски и ложные срабатывания.
- В терминалах автопереключение выключено. Другие программы можно исключить строкой `@имя_программы` в файле исключений.
- В полях паролей macOS сама скрывает нажатия от LiteSwitcher. В Windows LiteSwitcher не трогает классические поля паролей; поле пароля в браузере он не распознаёт, но слово исправляется только после пробела, а в паролях пробелов обычно нет.
- Нажатия хранятся только в памяти и только для текущего слова. На диск LiteSwitcher записывает только своё: настройки (в Windows — `LiteSwitcher.ini`, на Mac — настройки программы в системе), файл исключений `exceptions.txt`, куда обычным текстом попадают слова, для которых вы отменили исправление, и запись автозапуска, если он включён. В сеть программа ничего не отправляет: сетевого кода в ней нет, браузер открывается только пунктами «Конфиденциальность…» и «Поддержать проект (lava.top)…». Чтобы исправить выделенный текст, LiteSwitcher копирует его через буфер обмена, как Ctrl+C, а потом возвращает прежнее содержимое. Если в Windows включён журнал буфера обмена (Win+V) или его синхронизация, скопированный фрагмент может туда попасть (на Mac — в менеджеры буфера обмена). Исправленный текст LiteSwitcher помечает, чтобы он туда не попадал. Подробно — в [PRIVACY.md](PRIVACY.md).

## Удаление

**Windows**

1. В меню значка снимите **Запускать вместе с Windows** и выберите **Выход**.
2. Удалите папку с `LiteSwitcher.exe` — там же лежат `LiteSwitcher.ini` и `exceptions.txt`.
3. Если есть папка `%APPDATA%\LiteSwitcher`, удалите и её.
4. Если программу уже удалили, не выключив автозапуск, уберите его в **Параметры → Приложения → Автозагрузка** или командами ниже. Сообщение, что раздел или параметр не найден, значит, что записи уже нет.

```
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v LiteSwitcher /f
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run" /v LiteSwitcher /f
```

**macOS**

1. В меню LiteSwitcher снимите **Запускать при входе в систему** и выберите **Выйти из LiteSwitcher**.
2. Перетащите LiteSwitcher.app в Корзину.
3. Удалите папку `~/Library/Application Support/LiteSwitcher` и, если остался, файл `~/Library/LaunchAgents/io.github.u-said.ls.plist`.
4. Удалите настройки командой `defaults delete io.github.u-said.ls` в Терминале.
5. Уберите LiteSwitcher из **Конфиденциальность и безопасность → Универсальный доступ** кнопкой «−» или командой `tccutil reset Accessibility io.github.u-said.ls`.

## Поддержать проект

LiteSwitcher бесплатный, без рекламы и с открытым кодом. Если программа вам пригодилась, можно сказать спасибо донатом:
**https://app.lava.top/4179967925** → кнопка «Отправить донат». Эту же страницу открывает пункт меню «Поддержать проект (lava.top)…».

- Сумму, валюту и способ оплаты вы выбираете на странице lava.top; что доступно, зависит от страны и банка.
- Платёж принимает платформа lava.top (LAVALANE LTD, Кипр) по своим условиям: https://lava.top/docs/terms (юридическую силу имеет английская версия).
- Донат добровольный, ничего не открывает в программе и не возвращается.

## Сборка из исходников

- **Windows** (Visual Studio 2022 с C++): `cmake -S . -B build -A x64` (или `-A ARM64`), затем `cmake --build build --config Release`. Проверки: `build\Release\LiteSwitcher.exe --selftest report.txt` и `tools\e2e_windows.ps1`.
- **macOS** (Xcode Command Line Tools): `bash macos/build.sh`, проверка: `build/macos/LiteSwitcher.app/Contents/MacOS/LiteSwitcher --selftest`.
- Логика распознавания общая для обеих систем: `core/ls_core.c`. Прежние версии-скрипты лежат в `legacy/`.

## Политика подписи кода (Code signing policy)

Как собираются выпуски, кто вносит и проверяет изменения и кто утверждает подпись — в [CODE_SIGNING.md](CODE_SIGNING.md).

## Названия

Punto Switcher — продукт компании «Яндекс», Caramba Switcher — продукт своего правообладателя; названия принадлежат их владельцам. LiteSwitcher с ними не связан.

---

## English

**LiteSwitcher** is a lightweight RU/EN keyboard layout switcher for Windows and macOS, a Punto Switcher alternative. One small app, no installer: download, unzip, run.

![LiteSwitcher: fix examples and the menu](docs/demo-en.png)

Typed `ghbdtn` when you meant «привет»? LiteSwitcher notices it when you press Space, retypes the word and switches the layout. If it misses one, fix it yourself with a double `Shift`. No dictionaries, and nothing is sent anywhere.

**Like LiteSwitcher? [Support the project with a donation](https://app.lava.top/4179967925)** ([details](#support-the-project))

## Download

| System | File |
|---|---|
| **Windows 10/11** on Intel or AMD (x64) | [LiteSwitcher-Windows.zip](https://github.com/U-Said/LiteSwitcher/releases/latest/download/LiteSwitcher-Windows.zip) |
| **Windows 11 on ARM**: Snapdragon (Surface Pro 11/12 etc.) | [LiteSwitcher-Windows-arm64.zip](https://github.com/U-Said/LiteSwitcher/releases/latest/download/LiteSwitcher-Windows-arm64.zip) |
| **macOS 11+**, Apple Silicon and Intel | [LiteSwitcher-macOS.zip](https://github.com/U-Said/LiteSwitcher/releases/latest/download/LiteSwitcher-macOS.zip) |

Nothing else to install: no AutoHotkey, no Hammerspoon, no libraries.

[Privacy](PRIVACY.md#privacy-policy) · [Code signing policy](CODE_SIGNING.md) · [Security](SECURITY.md#security-policy) · [Uninstall](#uninstall)

## At a glance

![LiteSwitcher at a glance: getting started, keys, good to know](docs/billboard-en.png)

## Windows (English)

1. Unzip the archive for your CPU into a folder that is not synced to the cloud, for example `%LOCALAPPDATA%\Programs\LiteSwitcher` (paste this path into the File Explorer address bar), and run `LiteSwitcher.exe`. If Windows says “Windows protected your PC”, click **More info → Run anyway**: the app is not signed with a paid certificate.
2. The LiteSwitcher icon appears next to the clock. To start it automatically, tick **Start with Windows** in its menu.
3. Settings (`LiteSwitcher.ini`) and exceptions (`exceptions.txt`) are kept next to `LiteSwitcher.exe`, or in `%APPDATA%\LiteSwitcher` if that folder is read-only. No admin rights needed.

**Usage.** Space fixes a word typed in the wrong layout. `Pause` or a double `Shift` converts the last word (again to revert). `Shift+Pause`, or a double `Shift` with no fresh word, converts the selected text; the clipboard is restored afterwards. Undoing a wrong auto-fix adds the word to `exceptions.txt`. The tray menu: auto-switching, double Shift, start with Windows, exceptions, “Privacy…”, “Support the project (lava.top)…”, exit.

**Coming from LS 2.0?** Up to version 2.1 the app was called LS. Put `LiteSwitcher.exe` into the folder with `LS.exe` and run it. LiteSwitcher closes LS, takes over its settings, exceptions and autostart if it was on (if it was turned off in Settings, it stays off), and tells you so. You can delete `LS.exe` afterwards.

**Coming from the AutoHotkey version?** Put `LiteSwitcher.exe` into the folder with `LS.ahk`: your exceptions are kept. LiteSwitcher does not touch the old script or its autostart itself: if LS.ahk is still running or still in Startup, it tells you how to close and remove it. Turn on LiteSwitcher's own autostart in its menu.

## macOS (English)

> The macOS version is built and passes automated checks on a Mac (layouts, word detection), but has not been tried by hand on a real Mac yet. If something misbehaves, please open an [issue](https://github.com/U-Said/LiteSwitcher/issues).

1. Unzip `LiteSwitcher-macOS.zip` and drag **LiteSwitcher.app** to **Applications**.
2. Open LiteSwitcher. It is not notarized, so macOS blocks the first launch: open **System Settings → Privacy & Security** and click **Open Anyway** at the bottom (on macOS 14 and older: right-click LiteSwitcher.app → **Open**).
3. Allow LiteSwitcher in **Privacy & Security → Accessibility**. A few seconds later its icon in the menu bar turns solid and LiteSwitcher is working.
4. You need two input sources: an English one (**ABC** or **U.S.**) and **Russian** or **Russian – PC**.
5. To start LiteSwitcher automatically, tick **Open at login** in its menu.

After an update macOS may stop trusting LiteSwitcher: remove it from **Accessibility** with “−” and enable it again.

**Coming from LS 2.0?** Drag LiteSwitcher.app to Applications and open it: it closes LS and takes over its settings, exceptions and login item if it was on. Then move LS.app to the Trash, remove LS from **Accessibility** with “−” and enable LiteSwitcher there.

**Usage.** Space or Return fixes a word typed in the wrong layout. A double `Shift` converts the last word (again to revert), or the selected text when there is no fresh word. Undoing a wrong auto-fix adds the word to `~/Library/Application Support/LiteSwitcher/exceptions.txt`.

**Coming from the Hammerspoon version?** Remove `require("LS")` from `~/.hammerspoon/init.lua` and choose **Reload Config**. Learned exceptions are moved over automatically.

## Notes

- There is no dictionary: each word is judged by Russian and English spelling rules and lists of common words, so misses and false positives are possible.
- Auto-switching is off in terminals. Exclude other apps with an `@app_name` line in the exceptions file.
- macOS hides keystrokes in password fields from LiteSwitcher. On Windows LiteSwitcher skips classic password boxes; it cannot detect password fields in browsers, but a word is only fixed after Space, and passwords rarely contain spaces.
- Keystrokes are kept in memory only, for the current word. On disk LiteSwitcher writes only its own data: settings (`LiteSwitcher.ini` on Windows, the app's preferences on a Mac), the exceptions file `exceptions.txt`, where words whose fix you undid are added as plain text, and the start-at-login entry if you turn it on. It sends nothing over the network: there is no network code, and a browser opens only from “Privacy…” and “Support the project (lava.top)…”. To convert selected text LiteSwitcher copies it via the clipboard, like Ctrl+C, and then restores the previous contents. If Windows clipboard history (Win+V) or its sync is on, the copied fragment may be saved there (on a Mac, in clipboard managers); the converted text is marked so that it is not. Details: [PRIVACY.md](PRIVACY.md#privacy-policy).

## Uninstall

**Windows**

1. Untick **Start with Windows** in the icon's menu and choose **Exit**.
2. Delete the folder with `LiteSwitcher.exe`; `LiteSwitcher.ini` and `exceptions.txt` are there too.
3. If there is a `%APPDATA%\LiteSwitcher` folder, delete it as well.
4. If you already deleted the app with autostart on, remove it in **Settings → Apps → Startup** or with the commands below. A “not found” message means the entry is already gone.

```
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v LiteSwitcher /f
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run" /v LiteSwitcher /f
```

**macOS**

1. Untick **Open at login** in the LiteSwitcher menu and choose **Quit LiteSwitcher**.
2. Move LiteSwitcher.app to the Trash.
3. Delete `~/Library/Application Support/LiteSwitcher` and, if it is still there, `~/Library/LaunchAgents/io.github.u-said.ls.plist`.
4. Delete the settings with `defaults delete io.github.u-said.ls` in Terminal.
5. Remove LiteSwitcher from **Privacy & Security → Accessibility** with “−”, or run `tccutil reset Accessibility io.github.u-said.ls`.

## Support the project

LiteSwitcher is free, ad-free and open source. If it is useful to you, you can say thanks with a donation:
**https://app.lava.top/4179967925** → the «Отправить донат» (Send a donation) button. The menu item “Support the project (lava.top)…” opens the same page.

- You choose the amount, currency and payment method on the lava.top page; what is available depends on your country and bank.
- The payment is accepted by the lava.top platform (LAVALANE LTD, Cyprus) under its terms: https://lava.top/docs/terms (the English version prevails).
- The donation is voluntary, unlocks nothing in the app and is non-refundable.

## Building

- **Windows** (Visual Studio 2022 with C++): `cmake -S . -B build -A x64` (or `-A ARM64`), then `cmake --build build --config Release`.
- **macOS** (Xcode Command Line Tools): `bash macos/build.sh`.
- The detector is shared by both apps: `core/ls_core.c`. The old script versions are in `legacy/`.

## Code signing policy

How releases are built, who commits and reviews changes and who approves signing: [CODE_SIGNING.md](CODE_SIGNING.md).

## Trademarks

Punto Switcher is a product of Yandex, Caramba Switcher belongs to its respective owner; all names are the property of their owners. LiteSwitcher is not affiliated with them.

## License

[MIT](LICENSE). Copyright (c) 2026 U-Said.
