# Конфиденциальность FastRevers

**Русский** · [English](#privacy-policy)

Редакция от 26 ноября 2026 г., для FastRevers 2.2. До версии 2.2 программа называлась LiteSwitcher, до 2.1 — LS. Прежние редакции — в истории этого файла в git.

## Кто отвечает

FastRevers — бесплатная программа с открытым кодом (лицензия MIT). Автор — [U-Said](https://github.com/U-Said). Вопросы о конфиденциальности задавайте в [Issues](https://github.com/U-Said/FastRevers/issues). Issues видны всем, поэтому не присылайте туда личные данные. Об уязвимостях сообщайте приватно, как написано в [SECURITY.md](SECURITY.md).

## Что программа обрабатывает на вашем устройстве

- **Нажатия клавиш текущего слова.** FastRevers держит их только в памяти, не больше 100 клавиш, чтобы понять, в той ли раскладке набрано слово. Слово забывается при Enter, Tab, стрелках, клике мышью, переключении окна и сочетаниях клавиш (Ctrl, Alt, Win; на Mac — Cmd). На диск нажатия не записываются.
- **Выделенный текст при ручном исправлении.** Чтобы исправить выделенный текст, FastRevers копирует его через буфер обмена, как Ctrl+C (на Mac — Cmd+C), а потом возвращает прежнее содержимое буфера. Выделение копирует в буфер программа, в которой вы работаете. Поэтому, если в Windows включён журнал буфера обмена (Win+V) или его синхронизация, скопированный фрагмент может туда попасть; на Mac — в менеджеры буфера обмена и Universal Clipboard. Исправленный текст FastRevers помечает, чтобы он туда не попадал.
- **Имя активной программы** (в Windows — имя процесса, на Mac — идентификатор приложения). Оно нужно только для сверки со списком исключений и для того, чтобы не трогать терминалы. Не сохраняется.

## Что записывается на диск и где

- **Настройки.** В Windows — файл `FastRevers.ini`, на Mac — настройки программы в системе (`defaults`, домен `io.github.u-said.ls`).
- **Исключения** — файл `exceptions.txt`. Сюда обычным текстом попадают слова, исправление которых вы отменили, и строки, которые вы добавили сами. В нём могут оказаться имена и другие слова, которые вы набирали.
- **Где лежат эти файлы.** В Windows — рядом с `FastRevers.exe`, а если туда нельзя писать — в `%APPDATA%\FastRevers`. В версии из Microsoft Store — в папке данных пакета (`%LOCALAPPDATA%\Packages\<пакет>\LocalState`). На Mac — в `~/Library/Application Support/FastRevers`. Если папка синхронизируется с облаком (OneDrive, iCloud Drive и т. п.), эти файлы попадут в облако той службы. Поэтому программу лучше держать в несинхронизируемой папке, например `%LOCALAPPDATA%\Programs\FastRevers`.
- **Автозапуск.** Только если вы его включили в меню, или он перенесён с прежней версии (LiteSwitcher или LS), где был включён. В Windows это запись `FastRevers` в разделе `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, в версии из Store — механизм автозапуска самого Store. На Mac — файл `~/Library/LaunchAgents/io.github.u-said.ls.plist`.

## Чего в программе нет

Сетевого кода, телеметрии, аналитики, рекламы, автообновлений и учётных записей. FastRevers ничего не отправляет ни автору, ни кому-либо ещё. Браузер открывается только пунктами меню «Конфиденциальность…» (эта страница) и «Поддержать проект (lava.top)…».

This program will not transfer any information to other networked systems unless specifically requested by the user or the person installing or operating it.

## Поля паролей

В Windows FastRevers пропускает классические поля паролей. Поля паролей в браузерах он не распознаёт, но слово исправляется только после пробела, а в паролях пробелов обычно нет. На Mac нажатия в полях паролей скрывает от программ сама система.

## Сторонние сервисы

- **GitHub** — скачивание программы и Issues. Действует [политика конфиденциальности GitHub](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement).
- **lava.top** — добровольный донат по пункту «Поддержать проект (lava.top)…». Платёж принимает платформа lava.top (LAVALANE LTD, Кипр). Данные плательщика обрабатывают она и её платёжные провайдеры по своим правилам: <https://lava.top/docs/terms>.

## Сайт u-said.github.io/FastRevers

- Сайт размещён на GitHub Pages у GitHub, Inc. (США). GitHub получает ваш IP-адрес и данные браузера, когда вы открываете страницу или скачиваете файл (файлы скачиваются с github.com). Политика GitHub: <https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement>.
- На сайте нет счётчиков статистики и cookies. Сведений о посетителях автор не получает; GitHub показывает автору только общее число скачиваний каждого файла.

## Дети

Программа не собирает данные ни о ком, в том числе о детях.

## Как удалить программу и её данные

Пошагово — в README, раздел [«Удаление»](README.md#удаление) для Windows и для macOS. Версия из Microsoft Store удаляется через «Параметры → Приложения» вместе со всеми своими данными.

## Изменения

Дата редакции указана вверху; все изменения видны в истории этого файла на GitHub.

---

# Privacy policy

[Русский](#конфиденциальность-fastrevers) · **English**

Version of 26 November 2026, for FastRevers 2.2. Before version 2.2 the app was called LiteSwitcher, and LS before 2.1. Earlier versions are in this file's git history.

## Who is responsible

FastRevers is free, open-source software (MIT License) by [U-Said](https://github.com/U-Said). Ask privacy questions in [Issues](https://github.com/U-Said/FastRevers/issues). Issues are public, so do not post personal data there. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## What the app processes on your device

- **The keys of the current word.** FastRevers keeps them in memory only, at most 100 keys, to tell whether the word was typed in the wrong layout. The word is forgotten on Enter, Tab, arrows, a mouse click, a window switch and keyboard shortcuts (Ctrl, Alt, Win; Cmd on a Mac). Keystrokes are never written to disk.
- **Selected text when you convert it by hand.** To convert selected text FastRevers copies it via the clipboard, like Ctrl+C (Cmd+C on a Mac), and then restores the previous clipboard contents. The selection is copied by the app you are working in, so if Windows clipboard history (Win+V) or its sync is on, the copied fragment may be saved there; on a Mac, in clipboard managers and Universal Clipboard. The converted text is marked so that it is not.
- **The name of the active app** (the process name on Windows, the bundle id on a Mac), only to check it against the exceptions list and to leave terminals alone. It is not stored.

## What is written to disk, and where

- **Settings.** `FastRevers.ini` on Windows; the app's preferences on a Mac (`defaults`, domain `io.github.u-said.ls`).
- **Exceptions**, the file `exceptions.txt`. Words whose fix you undid are added to it as plain text, together with lines you add yourself. It may contain names and other words you typed.
- **Location.** On Windows, next to `FastRevers.exe`, or `%APPDATA%\FastRevers` if that folder is read-only. In the Microsoft Store version, the package's data folder (`%LOCALAPPDATA%\Packages\<package>\LocalState`). On a Mac, `~/Library/Application Support/FastRevers`. If the folder is synced to a cloud service (OneDrive, iCloud Drive and the like), these files end up in that service. That is why it is better to keep the app in a folder that is not synced, such as `%LOCALAPPDATA%\Programs\FastRevers`.
- **Start at login.** Only if you turn it on in the menu, or if it is carried over from an earlier version (LiteSwitcher or LS) where it was on. On Windows it is the `FastRevers` value under `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`; in the Store version, the Store's own startup mechanism. On a Mac, the file `~/Library/LaunchAgents/io.github.u-said.ls.plist`.

## What the app does not have

No network code, telemetry, analytics, ads, automatic updates or accounts. FastRevers sends nothing to its author or anyone else. A browser opens only from the menu items “Privacy…” (this page) and “Support the project (lava.top)…”.

This program will not transfer any information to other networked systems unless specifically requested by the user or the person installing or operating it.

## Password fields

On Windows FastRevers skips classic password boxes. It cannot detect password fields in browsers, but a word is only fixed after Space, and passwords rarely contain spaces. On a Mac the system itself hides keystrokes in password fields from other apps.

## Third-party services

- **GitHub**: downloads and Issues, under [GitHub's privacy statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement).
- **lava.top**: voluntary donations from “Support the project (lava.top)…”. The payment is accepted by the lava.top platform (LAVALANE LTD, Cyprus); payer data is processed by it and its payment providers under their own terms: <https://lava.top/docs/terms>.

## Website u-said.github.io/FastRevers

- The website is hosted on GitHub Pages by GitHub, Inc. (USA). GitHub receives your IP address and browser data when you open the page or download a file (files are downloaded from github.com). See the GitHub Privacy Statement: <https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement>.
- The website has no statistics script and sets no cookies. The author receives no data about visitors; GitHub only shows the author the total number of downloads of each file.

## Children

The app collects no data about anyone, children included.

## Removing the app and its data

Step by step in the README, section [Uninstall](README.md#uninstall), for Windows and macOS. The Microsoft Store version is removed in Settings → Apps together with all its data.

## Changes

The version date is at the top; every change is visible in this file's history on GitHub.
