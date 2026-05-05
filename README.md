# MediaInboxToolkit

Отдельный инструмент для **входной сортировки** видео (inbox → `Сериалы` / `Фильмы` / `_SortReview`), с русскими именами через TMDB, Blu-ray remux и отчётами CSV/TXT.

**SeriesToolkit** (стабильная линия **0.2.2**) остаётся продуктом нормализации уже разложенных библиотек сериалов. Этот пакет — расширяемый конвейер «до библиотеки»; дальнейшая полировка имён эпизодов — отдельным запуском SeriesToolkit по целевым папкам.

## Требования

- Репозиторий `Script_Rename_ALLVideo`: рядом с каталогом `MediaInboxToolkit` в **корне** лежит `Fetch-VideoMetadata.ps1`.
- Для TMDB: переменная окружения `TMDB_API_KEY` (или см. `Fetch-VideoMetadata.ps1`).

## Быстрый запуск

```powershell
cd <корень репозитория>\MediaInboxToolkit
powershell -NoProfile -ExecutionPolicy Bypass -File .\MediaInboxToolkit.ps1 -UseTmdb -DryRun
```

Минимальный GUI (WinForms):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Start-MediaInboxToolkitGui.ps1
```

Политика по умолчанию: `.\sort-inbox.example.json` (нейтральные пути). Пример разнесённой библиотеки с папками «Сериалы / Фильмы / Аниме / …»: `.\sort-inbox.library-layout-emilian.example.json` — скопируйте и замените `nasShareRoot` на свой UNC; лишние ключи в `destinations` можно удалить. При `-Apply` и `folders.createDestinationRootsOnApply: true` целевые корни из политики **создаются**, если их ещё нет.

После проверки CSV в `LOGS\`: добавьте `-Apply`.

## Оркестратор (inbox → SeriesToolkit)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\MediaInboxToolkit.Orchestrate.ps1 `
  -InboxPath '\\NAS\share\Video\Sort' -UseTmdb -DryRun
```

С `-Apply` и `-RunSeriesToolkitAfter` вторым шагом вызывается `SeriesToolkit\SeriesToolkit.Engine.ps1`. Корни можно задать вручную (`-SeriesToolkitRoots`) и/или взять из последнего `sort-inbox-*.csv` шага 1: `-SeriesToolkitRootsFromLastCsv` (или явный `-SeriesToolkitCsvPath`).

## Публикация в отдельный репозиторий GitHub

Из **корня монорепо** при настроенном remote `media-inbox` → `https://github.com/emildg8/MediaInboxToolkit.git`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\MediaInboxToolkit\Publish-MediaInboxStandalone.ps1 -ForceWithLease
```

`-ForceWithLease` нужен, если на GitHub в `main` уже есть коммиты вне текущего subtree (типично после ручных правок).

После успешного push скрипт **создаёт и отправляет тег** `v<version>` из `version.json`, если такого тега ещё нет на `media-inbox`. На GitHub срабатывает workflow **Release** (`.github/workflows/release.yml`): оформленное описание из `CHANGELOG.md` + ZIP с дистрибутивом и SHA-256.

## Связка с SeriesToolkit

**MediaInboxToolkit** раскладывает файлы по структуре; **SeriesToolkit** (стабильная линия **0.2.2**) полирует имена эпизодов уже в целевых папках. Общий модуль метаданных — `Fetch-VideoMetadata.ps1`.

## Политика (расширения)

- **`destinations`** — любые именованные корни (не только `series` / `cartoons` / `movies` / `review`): например `animeSeries`, `animeMovies`; пути относительно `nasShareRoot`.
- **`destinationsByKind`** — карта вида контента (`MediaInboxToolkit.ContentKinds.ps1`) → имя ключа из `destinations`.
- **`destinationsByKindMinConfidence`** — минимальная уверенность эвристики (0–100), иначе используется прежняя логика (`preferCartoonsSubfolder` / сериал vs фильм).
- **`safety`** — `requireSourceUnderInbox`, `skipSourceIfUnderLibrary` + `libraryRootRelatives`, чтобы не трогать файлы уже в библиотеке.
- **`tmdbKindRefinement`** — уточнение «аниме vs мульт» по TMDB (жанр Animation + регион).
- **`folders.createDestinationRootsOnApply`** — перед переносом создать все каталоги из `destinations`, если отсутствуют.
- **`classification`** — `folderSeasonContext` (папка `Season N` / `N season` + файл `NN.`; опционально `orphanSeasonFolderSeriesMap` для одиночной папки сезона без родителя-шоу), `tvSpecialFilenameBoost` (Robot Chicken Star Wars Episode I→TV), `movies.allowMissingYearIfTmdbMatched`.

## Документация

- [docs/FIX-PLAN-SORT-CLASSIFICATION-202605.md](docs/FIX-PLAN-SORT-CLASSIFICATION-202605.md) — план исправлений после in-place (movies/series, кириллица, RC/Archer, веб→TMDB id).
- [docs/SORT-INBOX-PLAN.md](docs/SORT-INBOX-PLAN.md) — структура NAS, фазы, параметры политики.
- [docs/CLASSIFICATION-ROADMAP.md](docs/CLASSIFICATION-ROADMAP.md) — типы контента 2.x и план сигналов.
- [docs/OFFLINE-METADATA.md](docs/OFFLINE-METADATA.md) — постер и описание рядом с медиа.
- [docs/INSPIRATION-SERIESTOOLKIT.md](docs/INSPIRATION-SERIESTOOLKIT.md) — что перенимаем из SeriesToolkit.
- [docs/GUI-EXE-ROADMAP.md](docs/GUI-EXE-ROADMAP.md) — GUI и сборка EXE.

## Архитектура vNext (каркас)

`MediaInboxToolkit` теперь содержит каркас `Toolkits/`:

- `Toolkits/SeriesToolkit/` — legacy-слот для поэтапной интеграции существующего SeriesToolkit;
- `Toolkits/VideoMetaToolkit/` — отдельный слот под новый модуль описаний/постеров/актёров (`VideoMetaToolkit.ps1` — заготовка launcher).

Текущие рабочие скрипты пока остаются на прежних путях; перенос кода выполняется постепенно.

## Версии и журнал

- `version.json`, `CHANGELOG.md`, `Bump-Version.ps1` — как в SeriesToolkit.
- Ветка Git: **`media-inbox-toolkit`** (см. корневой README репозитория).

## Логи

По умолчанию `.\LOGS\` (каталог в `.gitignore`). Для полного текстового транскрипта прогона (включая ошибки TMDB в консоли) и блока **POST-RUN SUMMARY** в конце файла: `.\Run-DryRunTranscript-Example.ps1` (параметры `-InboxPath` / `-PolicyPath` при необходимости).

**Разложение только внутри Sort** (подкаталог `Sort\_Workspace\…`, затем SeriesToolkit по сериалам): `.\Organize-SortInPlace.ps1` и политика `sort-inbox.workspace-inside-sort.json` (`scope.excludeDirectoryNames`: `_Workspace`). Под `_Workspace` в политике используются **ASCII**-имена (`series`, `movies`, …), чтобы лаунчер не ломался на кодировке консоли; русские имена шоу/эпизодов задаёт TMDB.

**Тот же сценарий, но папка `Video` вместо `_Workspace`:** политика `sort-inbox.video-under-sort.example.json` (исключение сканирования: `Video`). В `folders` заданы `skeletonProfile: ascii`, `workspaceSeriesToolkitSubfolders` и **`skeletonExtraRelatives`** — дополнительные пустые каталоги (документалистика, концерты и т.д.); их создаёт **`.\New-MediaInboxDestinationSkeleton.ps1`** (движок сортировки их не использует, пока не добавите ключи в `destinations` / `destinationsByKind`). **Кириллический обезличенный вариант** тех же правил: `sort-inbox.video-under-sort.cyrillic.example.json` (`nasShareRoot` в примере нейтральный — скопируйте в `sort-inbox.*.local.json` и пропишите свой UNC). Этап «скелет + DryRun»: `.\Invoke-MediaInboxSortStage1.ps1` или `-SkeletonProfile Cyrillic`; ожидание нового CSV после долгого DryRun: `.\Watch-MediaInboxToolkitCsv.ps1`. Перенос: `.\Invoke-MediaInboxSortStage3Apply.ps1` (введите `YES`; `-Force` без паузы). Полный in-place + SeriesToolkit: `.\Organize-SortVideoUnderSort.ps1` (имена подпапок под `Sort\Video` берутся из политики). GUI: пресет политики + кнопка «Создать скелет». Локальные пути — `sort-inbox.<имя>.local.json` (в `.gitignore`).

## Ручная валидация CSV перед переносом

### Быстрый конвейер

1. DryRun → `sort-inbox-*.csv`
2. `.\New-MediaInboxReviewCsv.ps1 -CsvPath <csv>` → `*.review.csv` (колонки `HumanOverride` / `HumanComment` / `HumanDestOverride` уже пустые). По умолчанию **APPLY** только при `Confidence >= 70`. Для **сериалов** с уже собранным путём в `DestFullPath` (фрагмент ` - SxxEyy - `) дополнительно разрешается **APPLY** при `Confidence >= 55` (параметры **`-ApplyMinConfidence`** / **`-SeriesEpisodeStructuredMinConfidence`**, `0` отключает льготу для сериалов).
3. `.\Update-MediaInboxReviewCsvAutoDecide.ps1 -CsvPath <review.csv> -TorrentDirectory "C:\Users\<user>\Downloads"` → `*.auto.csv`  
   Логика торрентов: совпадение `rutracker-…` в **пути** и в **имени `.torrent`**; разбор **метаданных `.torrent`** (имена файлов внутри раздачи) — если имя видеофайла в CSV встречается **ровно в одной** локальной раздаче, применяется эта раздача (в т.ч. номер темы из имени `.torrent`, без id в пути). При **одинаковом** счёте совпадения слов у нескольких раздач: совпадение **имени файла** с листом в `.torrent`, затем **SxxEyy / Exx** в именах файлов раздачи, затем **topic id** в пути; при двух кандидатах и совпадении **mit_dur_s** из CSV с **ffprobe** по файлу — предпочтение раздаче с **одним** видео-листом.  
   Опционально **qBittorrent Web UI** (если **полный путь** `SourceFullPath` в CSV совпадает с путём, который отдаёт клиент в `save_path` + файлы раздачи): тот же базовый URL, что в браузере, **без** завершающего слэша, например `https://хост:порт/qbittorrent`. Если логина нет — учётку не указывайте; при самоподписанном HTTPS: `-QbittorrentSkipCertificateCheck`. Переменные: `MIT_QBIT_WEBUI`, при необходимости `MIT_QBIT_USER` / `MIT_QBIT_PASS`.  
   Если qBittorrent качает в один UNC (например `\\NAS\qBittorrent\...\downloads`), а в CSV уже пути после переноса в сортировку (`\\NAS\emildg8\Video\Sort\...`), задайте пару префиксов: **`-QbittorrentCsvSourcePrefix`** (корень, как в CSV) и **`-QbittorrentDownloadRootPrefix`** (корень каталога загрузок qBittorrent). Относительный хвост пути тогда подставляется под каталог загрузок для поиска в индексе API. То же через `MIT_QBIT_CSV_PREFIX` и `MIT_QBIT_DOWNLOAD_ROOT`. Либо блок **`qbittorrent`** в **`media-library-layout.local.json`** (`webUiUrl`, `csvSourcePrefix`, `downloadRootPrefix`) — подхватывается, если параметры и env пустые. У других пользователей клиент не обязателен — достаточно папки с `.torrent`.
   **Спецвыпуски (без SxxEyy в имени файла):** `media-library-layout.example.json` → **`media-library-layout.local.json`** (в `.gitignore`). Если лежит рядом со скриптом и не заданы **`-MediaLibraryLayoutJson`** / **`MIT_MEDIA_LIBRARY_JSON`**, он подхватывается сам. В JSON: **`videoLibraryRoot`** (UNC до `Video`), **`scanRoots`** (подкаталоги с сериалами: Мультсериалы, Сериалы, Анимесериалы и т.д.). Иначе корень: **`MIT_VIDEO_LIBRARY_ROOT`** или **`-MediaLibraryVideoRoot`**. При запуске строится индекс подпапок; для строк `REVIEW` без эпизода срабатывают **`explicitRules`** (regex имени файла + имени папки + `libraryRoot`). Для **Анимесериалов** при совпадении с **`ovaFilenameRegex`** путь ведёт в подпапку **`ovaSubfolderName`** (например `OVA`). Опциональный fuzzy по `Notes` (`fuzzyEnabled`, `fuzzyUniqueMinScore`) — только один явный победитель. Отключить весь блок «плоско в корень сериала»: **`-SkipCartoonSeriesRootFlat`**. В консоли смотрите **`MediaLibraryRoot`** и **`SeriesIndexEntries`** (должно быть > 0, если NAS доступен).
4. **`.\Prepare-MediaInboxReviewForHuman.ps1 -CsvPath <*.auto.csv>`** → **`*.for-human.csv` + `*.for-human.html`**  
   Откройте HTML в браузере: цветные блоки **REVIEW** (жёлтый) / **APPLY** (зелёный) / **SKIP** (серый), таблицы по разделам.
5. Правки в **`*.for-human.csv`** (Excel / LibreOffice):
   - **`HumanOverride`** — пусто = брать `Decision`; иначе **`APPLY`**, **`SKIP`**, **`REVIEW`** (перекрывает `Decision` при переносе).
   - **`HumanDestOverride`** — полный путь файла назначения, если нужно не то, что в `DestFullPath`.
   - **`HumanComment`** — заметка для себя (на перенос не влияет).
   - Цвет заливки в Excel необязателен; достаточно колонок.
6. `.\Invoke-MediaInboxApplyReviewedCsv.ps1 -CsvPath <ваш исправленный csv>` (с `-WhatIf` для проверки).

### Отдельно только HTML из любого CSV

`.\Export-MediaInboxReviewHtml.ps1 -CsvPath <csv>`

### Сводка цифр

`.\Get-MediaInboxReviewedCsvSummary.ps1 -CsvPath <csv>`
