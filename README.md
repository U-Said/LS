# LS — LiteSwitcher

**Русский** · [English](#english)

**LS (LiteSwitcher)** — лёгкий переключатель раскладки RU/EN для Windows и macOS, аналог Punto Switcher. Одна маленькая программа без установки: скачали, распаковали, запустили.

![LS: примеры исправления и меню в трее](docs/demo.png)

Набрали `ghbdtn` вместо «привет» — LS заметит это по пробелу, перепечатает слово и переключит раскладку. Если не заметил, исправьте вручную двойным `Shift`. Без словарей и без отправки данных куда-либо.

## Скачать

| Система | Файл |
|---|---|
| **Windows 10/11** на Intel или AMD (x64) | [LS-Windows.zip](https://github.com/U-Said/LS/releases/latest/download/LS-Windows.zip) |
| **Windows 11 на ARM**: Snapdragon (Surface Pro 11/12 и др.) | [LS-Windows-arm64.zip](https://github.com/U-Said/LS/releases/latest/download/LS-Windows-arm64.zip) |
| **macOS 11+**, Apple Silicon и Intel | [LS-macOS.zip](https://github.com/U-Said/LS/releases/latest/download/LS-macOS.zip) |

Ничего дополнительно ставить не нужно: ни AutoHotkey, ни Hammerspoon, ни библиотек.

## Коротко

![LS коротко: как начать, клавиши, что важно знать](docs/billboard.png)

## Windows

### Запуск

1. Скачайте архив для своего процессора и распакуйте в любую папку, например `Документы\LS`.
2. Запустите `LS.exe`. Если Windows покажет «Система Windows защитила ваш компьютер», нажмите **Подробнее → Выполнить в любом случае**: программа не подписана платным сертификатом.
3. У часов появится значок LS. Чтобы LS запускался сам, включите в меню значка **Запускать вместе с Windows**.

Настройки (`LS.ini`) и исключения (`exceptions.txt`) лежат рядом с `LS.exe`, так что папку можно переносить целиком. Права администратора не нужны.

**Переход с версии на AutoHotkey.** Положите `LS.exe` в ту же папку, где был `LS.ahk`: исключения подхватятся, старый скрипт закроется сам, а его автозапуск заменится новым.

**Обновление.** Значок LS → **Выход**, замените `LS.exe` новым и запустите.

### Как пользоваться

- **Автоисправление.** Набрали слово не в той раскладке и нажали пробел — слово заменяется, раскладка переключается (`ghbdtn` → `привет`, `руддщ` → `hello`).
- **Вручную.** `Pause` или двойной `Shift` исправляет последнее слово; повторное нажатие возвращает обратно.
- **Выделенный текст.** `Shift+Pause`, либо двойной `Shift`, когда только что набранного слова нет. Буфер обмена потом возвращается как был.
- **Обучение.** Отмените ошибочную автозамену двойным `Shift` — слово попадёт в `exceptions.txt` и больше не будет исправляться.
- **Меню в трее.** Автопереключение, двойной Shift, автозапуск с Windows, исключения, выход.

## macOS

> Версия для macOS собирается и проходит автоматические проверки на Mac (раскладки, распознавание слов), но вживую на Mac ещё не испытана. Если что-то работает не так — напишите в [Issues](https://github.com/U-Said/LS/issues).

### Запуск

1. Скачайте `LS-macOS.zip`, распакуйте и перетащите **LS.app** в папку **Программы**.
2. Откройте LS. Приложение не заверено Apple, поэтому при первом запуске macOS его остановит. Откройте **Системные настройки → Конфиденциальность и безопасность** и внизу нажмите **Всё равно открыть**. В macOS 14 и старше можно проще: правый щелчок по LS.app → **Открыть**.
3. Разрешите LS управлять компьютером: **Конфиденциальность и безопасность → Универсальный доступ** → включите LS. Через пару секунд значок LS в строке меню станет ярким — можно печатать.
4. Проверьте, что в системе есть две раскладки: английская (**ABC** или **США**) и **Русская** или **Русская — ПК**.
5. Чтобы LS запускался сам, включите в его меню **Запускать при входе в систему**.

После обновления LS macOS может перестать считать его доверенным. Тогда удалите LS из **Универсального доступа** кнопкой «−» и включите снова.

**Переход с версии для Hammerspoon.** Уберите строку `require("LS")` из `~/.hammerspoon/init.lua` и выберите в Hammerspoon **Reload Config**. Выученные исключения перенесутся сами.

### Как пользоваться

- **Автоисправление.** Набрали слово не в той раскладке и нажали пробел или Return — слово заменяется, раскладка переключается.
- **Вручную.** Двойной `Shift` исправляет последнее слово; повторное нажатие возвращает обратно.
- **Выделенный текст.** Двойной `Shift`, когда только что набранного слова нет.
- **Обучение.** Отмените ошибочную автозамену двойным `Shift` — слово попадёт в исключения (`~/Library/Application Support/LS/exceptions.txt`).
- **Меню LS в строке меню.** Автопереключение, двойной Shift, запуск при входе, исключения, выход. Язык меню — как у системы.

## Особенности

- Словаря нет: слово оценивается по правилам русского и английского и по спискам частых слов, поэтому возможны пропуски и ложные срабатывания.
- В терминалах автопереключение выключено. Другие программы можно исключить строкой `@имя_программы` в файле исключений.
- В полях паролей macOS сама скрывает нажатия от LS. В Windows LS не трогает классические поля паролей; поле пароля в браузере он не распознаёт, но слово исправляется только после пробела, а в паролях пробелов обычно нет.
- Нажатия хранятся только в памяти и только для текущего слова; LS ничего не записывает и никуда не отправляет.

## Сборка из исходников

- **Windows** (Visual Studio 2022 с C++): `cmake -S . -B build -A x64` (или `-A ARM64`), затем `cmake --build build --config Release`. Проверки: `build\Release\LS.exe --selftest report.txt` и `tools\e2e_windows.ps1`.
- **macOS** (Xcode Command Line Tools): `bash macos/build.sh`, проверка: `build/macos/LS.app/Contents/MacOS/LS --selftest`.
- Логика распознавания общая для обеих систем: `core/ls_core.c`. Прежние версии-скрипты лежат в `legacy/`.

---

## English

**LS (LiteSwitcher)** is a lightweight RU/EN keyboard layout switcher for Windows and macOS, a Punto Switcher alternative. One small app, no installer: download, unzip, run.

![LS: fix examples and the menu](docs/demo-en.png)

Typed `ghbdtn` when you meant «привет»? LS notices it when you press Space, retypes the word and switches the layout. If it misses one, fix it yourself with a double `Shift`. No dictionaries, and nothing is sent anywhere.

## Download

| System | File |
|---|---|
| **Windows 10/11** on Intel or AMD (x64) | [LS-Windows.zip](https://github.com/U-Said/LS/releases/latest/download/LS-Windows.zip) |
| **Windows 11 on ARM**: Snapdragon (Surface Pro 11/12 etc.) | [LS-Windows-arm64.zip](https://github.com/U-Said/LS/releases/latest/download/LS-Windows-arm64.zip) |
| **macOS 11+**, Apple Silicon and Intel | [LS-macOS.zip](https://github.com/U-Said/LS/releases/latest/download/LS-macOS.zip) |

Nothing else to install: no AutoHotkey, no Hammerspoon, no libraries.

## At a glance

![LS at a glance: getting started, keys, good to know](docs/billboard-en.png)

## Windows (English)

1. Unzip the archive for your CPU into any folder and run `LS.exe`. If Windows says “Windows protected your PC”, click **More info → Run anyway**: the app is not signed with a paid certificate.
2. The LS icon appears next to the clock. To start LS automatically, tick **Start with Windows** in its menu.
3. Settings (`LS.ini`) and exceptions (`exceptions.txt`) are kept next to `LS.exe`. No admin rights needed.

**Usage.** Space fixes a word typed in the wrong layout. `Pause` or a double `Shift` converts the last word (again to revert). `Shift+Pause`, or a double `Shift` with no fresh word, converts the selected text; the clipboard is restored afterwards. Undoing a wrong auto-fix adds the word to `exceptions.txt`.

**Coming from the AutoHotkey version?** Put `LS.exe` into the folder with `LS.ahk`: your exceptions are kept, the old script closes itself and its autostart is replaced.

## macOS (English)

> The macOS version is built and passes automated checks on a Mac (layouts, word detection), but has not been tried by hand on a real Mac yet. If something misbehaves, please open an [issue](https://github.com/U-Said/LS/issues).

1. Unzip `LS-macOS.zip` and drag **LS.app** to **Applications**.
2. Open LS. It is not notarized, so macOS blocks the first launch: open **System Settings → Privacy & Security** and click **Open Anyway** at the bottom (on macOS 14 and older: right-click LS.app → **Open**).
3. Allow LS in **Privacy & Security → Accessibility**. A few seconds later the LS icon in the menu bar turns solid and LS is working.
4. You need two input sources: an English one (**ABC** or **U.S.**) and **Russian** or **Russian – PC**.
5. To start LS automatically, tick **Open at login** in its menu.

After an update macOS may stop trusting LS: remove it from **Accessibility** with “−” and enable it again.

**Usage.** Space or Return fixes a word typed in the wrong layout. A double `Shift` converts the last word (again to revert), or the selected text when there is no fresh word. Undoing a wrong auto-fix adds the word to `~/Library/Application Support/LS/exceptions.txt`.

**Coming from the Hammerspoon version?** Remove `require("LS")` from `~/.hammerspoon/init.lua` and choose **Reload Config**. Learned exceptions are moved over automatically.

## Notes

- There is no dictionary: each word is judged by Russian and English spelling rules and lists of common words, so misses and false positives are possible.
- Auto-switching is off in terminals. Exclude other apps with an `@app_name` line in the exceptions file.
- macOS hides keystrokes in password fields from LS. On Windows LS skips classic password boxes; it cannot detect password fields in browsers, but a word is only fixed after Space, and passwords rarely contain spaces.
- Keystrokes are kept in memory only, and only for the current word; LS logs nothing and sends nothing.

## Building

- **Windows** (Visual Studio 2022 with C++): `cmake -S . -B build -A x64` (or `-A ARM64`), then `cmake --build build --config Release`.
- **macOS** (Xcode Command Line Tools): `bash macos/build.sh`.
- The detector is shared by both apps: `core/ls_core.c`. The old script versions are in `legacy/`.

## License

[MIT](LICENSE)
