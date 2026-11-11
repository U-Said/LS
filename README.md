# LS — LiteSwitcher

**Русский** · [English](#english)

**LS (LiteSwitcher)** — лёгкий переключатель раскладки RU/EN для Windows — аналог Punto Switcher в одном скрипте AutoHotkey.

![LS: примеры исправления и меню в трее](docs/demo.png)

Набрали `ghbdtn` вместо «привет» — LS заметит это по пробелу, перепечатает слово и переключит раскладку. Если не заметил, исправьте вручную двойным `Shift`. Один файл на 25 КБ, без установки, без словарей и без отправки данных куда-либо.

## Установка

1. Установите [AutoHotkey v2](https://www.autohotkey.com).
2. Скачайте `LS.ahk` и `LS.ico` в одну папку (кнопка **Code → Download ZIP**).
3. Дважды щёлкните по `LS.ahk` — у часов появится значок «LS».

## Как пользоваться

- **Автоисправление.** Набрали слово не в той раскладке и нажали пробел — слово заменяется, раскладка переключается (`ghbdtn` → `привет`, `руддщ` → `hello`).
- **Вручную.** `Pause` или двойной `Shift` исправляет последнее слово; повторное нажатие возвращает обратно.
- **Выделенный текст.** `Shift+Pause`, либо двойной `Shift`, когда только что набранного слова нет.
- **Обучение.** Отмените ошибочную автозамену двойным `Shift` — слово попадёт в `exceptions.txt` и больше не будет исправляться.
- **Меню в трее.** Автопереключение, двойной Shift, автозапуск с Windows, исключения, выход.

## Особенности

- Словаря нет: слово оценивается по правилам русского и английского и по спискам частых слов, поэтому возможны пропуски и ложные срабатывания.
- В терминалах автопереключение выключено. Другие программы можно исключить строкой `@имя_процесса` в `exceptions.txt`.
- Нажатия хранятся только в памяти и только для текущего слова; скрипт ничего не записывает и никуда не отправляет.

---

## English

**LS (LiteSwitcher)** is a lightweight RU/EN keyboard layout switcher for Windows — a Punto Switcher alternative in a single AutoHotkey script.

Typed `ghbdtn` when you meant «привет»? LS notices it when you press Space, retypes the word and switches the layout. If it misses one, fix it yourself with a double `Shift`. One 25 KB file, no installer, no dictionaries, and nothing is sent anywhere.

### Install

1. Install [AutoHotkey v2](https://www.autohotkey.com).
2. Download `LS.ahk` and `LS.ico` into the same folder (**Code → Download ZIP**).
3. Double-click `LS.ahk` — the “LS” icon appears in the system tray.

### Usage

- **Auto-fix.** Type a word in the wrong layout and press Space — the word is replaced and the layout is switched (`ghbdtn` → `привет`, `руддщ` → `hello`).
- **Manual fix.** `Pause` or a double `Shift` converts the last word; press again to revert.
- **Selected text.** `Shift+Pause`, or a double `Shift` when there is no freshly typed word.
- **Learning.** Undo a wrong auto-fix with a double `Shift` — the word is added to `exceptions.txt` and will not be touched again.
- **Tray menu.** Auto-switching, double Shift, start with Windows, exceptions, exit. The menu itself is in Russian.

### Notes

- There is no dictionary: each word is judged by Russian and English spelling rules and lists of common words, so misses and false positives are possible.
- Auto-switching is off in terminals. Exclude other apps with an `@process_name` line in `exceptions.txt`.
- Keystrokes are kept in memory only, and only for the current word; the script logs nothing and sends nothing.

### License

[MIT](LICENSE)
