# CHANGELOG

## 0.2.20 - 2026-05-06 22:00:00 +03:00
- **`sort-inbox.skeleton-extras-adventure-time-umbrella.example.json`** / **`.cyrillic.example.json`** — дополнительный вариант **`folders.skeletonExtraRelatives`**: зонт **`Время приключений`** с тремя подпапками (Финн и Джейк / Далёкие земли / Фионна и Кейк) под `cartoons` или **`Мультсериалы`**.
- **`README.md`** — ссылка на эти фрагменты рядом с описанием скелета.

## 0.2.19 - 2026-05-06 18:30:00 +03:00
- **`MediaInboxToolkit.Engine.ps1`** — исправлено создание **отдельной папки сериала на каждый эпизод** (например «King of the Hill 801 …»): если в строке поиска/угадывании шоу попали код `801` + название эпизода, а TMDB не вернул короткое имя, **имя папки сериала** и кэш TMDB теперь берутся от **основы названия** (`Get-SortTvShowTitleFromPollutedGuess` / нормализация в `Normalize-SortSeriesSearchQuery`). Типичный случай — имена файлов вида `… 801 Patch …` без `S08E01`.

## 0.2.18 - 2026-05-06 17:00:00 +03:00
- **`MediaInboxToolkit.Engine.ps1`** — в **`classification.cartoonMovieBasenameRegexes`** (массив regex по имени файла): при `cls.Kind=movie` и совпадении с шаблоном выставляется вид контента **`cartoon_movie`** (уверенность ≥ 62, причина `cartoon_movie_basename_policy`), чтобы направлять в **`destinationsByKind.cartoon_movie`** без ожидания TMDB.
- **`sort-inbox.video-under-sort*.example.json`** — пример regex для **Alice in Wonderland (1951)**.
- **`docs/REVIEW-111-torrent-link-requests.md`** — нумерованный список 111 строк `REVIEW` для привязки HTML раздач.
- **`README.md`** — описание ключа **`cartoonMovieBasenameRegexes`**.

## 0.2.17 - 2026-05-06 15:30:00 +03:00
- **`Invoke-MediaInboxApplyReviewedCsv.ps1`** — назначение может лежать под **`MediaLibraryVideoRoot`** (корень `Video` на NAS: параметр **`-MediaLibraryVideoRoot`**, иначе `MIT_VIDEO_LIBRARY_ROOT`, иначе **`videoLibraryRoot`** из `media-library-layout.local.json`). Источник по-прежнему только под **`-InboxRoot`** (по умолчанию `…\Video\Sort`). Устраняет отказ `path_outside_inbox` при переносе из Sort в `Мультсериалы` / `Фильмы` и т.д.

## 0.2.16 - 2026-05-06 14:00:00 +03:00
- **`New-MediaInboxReviewCsv.ps1`** — параметры **`-ApplyMinConfidence`** (по умолчанию 70) и **`-SeriesEpisodeStructuredMinConfidence`** (по умолчанию 55): для строк с `DestRootKey=series` и фрагментом ` - SxxEyy - ` в `DestFullPath` можно помечать **APPLY** при более низкой уверенности, не ослабляя порог для фильмов.
- **`Update-MediaInboxReviewCsvAutoDecide.ps1`** — развязка «ничьей» между торрент-хинтами с одинаковым счётом слов: лист = имя файла, номер эпизода в именах файлов `.torrent`, rutracker id в пути; при двух кандидатах и близости **mit_dur_s** к **ffprobe** — предпочтение раздаче с одним видео-листом. Подключён **`MediaInboxFfprobe.ps1`**.
- **`MediaLibraryLayout` / `media-library-layout.*.json`** — блок **`qbittorrent`**: `webUiUrl`, `csvSourcePrefix`, `downloadRootPrefix` (если не заданы параметры скрипта и не заданы `MIT_QBIT_*`).
- **`media-library-layout.example.json`** — пример **explicitRule** `ArcherExtrasPerfectDay` (узкий `Perfect Day` + папка Archer); у **RobotChicken** расширен **`fileRegex`** до `Robot[.\s]+Chicken` (имена с пробелом, без точки). **`README.md`** и **`sort-inbox.video-under-sort.cyrillic.example.json`** — заметки про qBit, ffprobe и политику TMDB.

## 0.2.15 - 2026-05-06 12:00:00 +03:00
- Корневой **`.gitignore`** — явная строка **`MediaInboxToolkit/media-library-layout.local.json`**, чтобы локальный UNC и правила библиотеки не попадали в коммиты.
- Зафиксирован проверенный сценарий на реальном dry-run CSV (~4000 строк, `\\Emilian_TNAS\emildg8\Video\Sort`): **`New-MediaInboxReviewCsv.ps1`** → **`Update-MediaInboxReviewCsvAutoDecide.ps1`** с **`-TorrentDirectory`** (`%USERPROFILE%\Downloads`, сотни `.torrent`). При доступном NAS и **`media-library-layout.local.json`**: **`MediaLibraryRoot`** резолвится в `Video`, индекс сериалов (**`SeriesIndexEntries`**) в порядка **300** имён папок; доля **`REVIEW`** после автодоразметки **~128** строк (без торрентов было **~321**).

## 0.2.14 - 2026-05-05 23:30:00 +03:00
- **`media-library-layout.*.json`** — опциональный ключ **`videoLibraryRoot`**: UNC до каталога `Video` (приоритет: `-MediaLibraryVideoRoot` → `MIT_VIDEO_LIBRARY_ROOT` → `videoLibraryRoot` в JSON → эвристика по пути CSV).
- **`Update-MediaInboxReviewCsvAutoDecide.ps1`** — если рядом есть **`media-library-layout.local.json`**, он читается без параметров и без `MIT_MEDIA_LIBRARY_JSON`.

## 0.2.13 - 2026-05-05 22:00:00 +03:00
- **`MediaLibraryLayout.ps1`** + **`media-library-layout.example.json`** — описание реальной библиотеки на NAS: корень `Video` (UNC или `MIT_VIDEO_LIBRARY_ROOT`), сканирование папок сериалов (`scanRoots`: Мультсериалы / Сериалы / Анимесериалы и т.д.), каталог для эпизодов с разбором `SxxEyy` (`seriesEpisodeDestinationDir`).
- **`Update-MediaInboxReviewCsvAutoDecide.ps1`** — спецвыпуски без эпизода в имени: **явные правила** `explicitRules` (regex имени файла + папки на диске + `libraryRoot`); опционально **осторожный fuzzy** по токенам имени и полям `tmdb_tv_query` / `tmdb_movie_query` в `Notes` только при **единственном** кандидате с порогом `fuzzyUniqueMinScore` (`fuzzyEnabled` по умолчанию выкл.).
- Для ветки **Анимесериалы**: при совпадении имени с `ovaFilenameRegex` (OVA/ONA/Спешл/Special и т.д.) назначение в подпапку **`ovaSubfolderName`** (например `OVA`) внутри каталога сериала.
- Локальный конфиг: скопировать пример в **`media-library-layout.local.json`** (в `.gitignore`) или путь через **`-MediaLibraryLayoutJson`** / **`MIT_MEDIA_LIBRARY_JSON`**.

## 0.2.12 - 2026-05-06 04:00:00 +03:00
- `Update-MediaInboxReviewCsvAutoDecide.ps1` — **спецвыпуски без номера серии в имени**: при пустом `Get-EpisodeInfo` и существующей папке сериала под `Video\\cartoons\\<имя>` файл назначается в **корень** этой папки (`auto_series_root_flat`, правило `cartoon_series_root_flat`). Первый набор правил: Robot Chicken / `Робоцып` (`Get-FlatSpecialLibraryRules`). Отключение: `-SkipCartoonSeriesRootFlat`.
- Тот же скрипт — `Resolve-SeriesFromPath` допускает **сезон 0** (например S00); общий корень `Video\` через `Get-VideoLibraryRootFromPath`.

## 0.2.11 - 2026-05-06 02:30:00 +03:00
- `Update-MediaInboxReviewCsvAutoDecide.ps1` — расширен `Get-EpisodeInfo`: `S01.E02`, разделители `_S01E02_` / `.S01E02.`, последнее вхождение `SxxEyy` (например `…3S03E01`), «слепленный» `701` = S7E01 + имя шоу из начала имени, `Eps21-22`, хвост `… сезон (номер)` с опциональным тегом `[релизер]`, поля `Season`/`Series` для репаса без паттерна только в пути.

## 0.2.10 - 2026-05-06 01:00:00 +03:00
- `Update-MediaInboxReviewCsvAutoDecide.ps1` — сопоставление с qBittorrent при **переносе** файлов: `-QbittorrentCsvSourcePrefix` + `-QbittorrentDownloadRootPrefix` (или `MIT_QBIT_CSV_PREFIX` / `MIT_QBIT_DOWNLOAD_ROOT`) подставляют путь «как в каталоге загрузок» для строк CSV под корнем сортировки.
- `README.md` — пример сценария UNC downloads → Sort.

## 0.2.9 - 2026-05-05 22:30:00 +03:00
- `Qbittorrent-WebApi.ps1` — если Web UI **без пароля**: сначала запрос `app/webapiVersion`, без `auth/login`; безопасный доступ к полям (`content_path` и др. могут отсутствовать в старых API / при StrictMode).
- Проверка ответа `auth/login`: тело `Fails.` считается ошибкой.

## 0.2.8 - 2026-05-05 20:00:00 +03:00
- `TorrentBencode.ps1` — разбор `.torrent` (bencode): `info` SHA1, имена видеофайлов из раздачи; исправлен `path` как одна строка (не только список сегментов).
- `Update-MediaInboxReviewCsvAutoDecide.ps1` — слова для fuzzy из метаданных раздачи; **уникальное** совпадение имени видеофайла с одной раздачей → `auto_from_rutracker_leaf` / `auto_from_torrent_leaf_unique`; опционально **qBittorrent Web API** (`-QbittorrentWebUiUrl`, учётные данные или `MIT_QBIT_WEBUI` / `MIT_QBIT_USER` / `MIT_QBIT_PASS`, `-QbittorrentSkipCertificateCheck` для локального HTTPS).
- `Qbittorrent-WebApi.ps1` — логин и индекс полных путей файлов по `info_hash`, сопоставляемому с локальными `.torrent`.
- `README.md` — параметры qBit и переменные окружения.
- Пояснение в `.cursor/rules/media-inbox-toolkit.mdc`: когда `Bump-Version.ps1` не дописывает CHANGELOG.

## 0.2.7 - 2026-05-05 12:00:00 +03:00
- `Update-MediaInboxReviewCsvAutoDecide.ps1` — сопоставление по **одинаковому Rutracker topic id** в пути источника и в имени `.torrent` (`rutracker-NNNNNNN`), до fuzzy; в логе решения `auto_from_rutracker_topic`, правило `tracker_topic_repath_apply`.
- Тот же скрипт — доп. паттерн пути для «Adventure Time with Finn and Jake … Season N».
- `README.md` — кратко: зачем id из пути/торрента и почему не парсим профиль Rutracker по URL.










## 0.2.6 - 2026-05-06 00:53:59 +03:00
- `Export-MediaInboxReviewHtml.ps1` — цветной HTML-отчёт (REVIEW / APPLY / SKIP отдельными таблицами).
- `Prepare-MediaInboxReviewForHuman.ps1` — `*.for-human.csv` с колонками `HumanOverride` / `HumanComment` / `HumanDestOverride` + автогенерация HTML.
- `Invoke-MediaInboxApplyReviewedCsv.ps1` — учёт `HumanOverride` и `HumanDestOverride` при переносе.
- `New-MediaInboxReviewCsv.ps1` / `Update-MediaInboxReviewCsvAutoDecide.ps1` — сохранение и проброс Human-колонок.
- `README.md` — пошаговый «человеческий» конвейер проверки.
- Snapshot: OLD/MediaInboxToolkit_v0.2.5_20260506-005359 (launcher MediaInboxToolkit.ps1).

## 0.2.5 - 2026-05-05 18:52:07 +03:00
- CSV auto-decision: torrent hints + _Workspace exclusion for sort-inbox.video-under-sort policies
- Snapshot: OLD/MediaInboxToolkit_v0.2.4_20260505-185207 (launcher MediaInboxToolkit.ps1).

## 0.2.4 - 2026-05-05 18:12:52 +03:00
- `Toolkits/README.md` + `Toolkits/SeriesToolkit/README.md` — каркас новой иерархии, где `MediaInboxToolkit` выступает основной оболочкой, а `SeriesToolkit` отмечен как legacy-slot для поэтапного переноса.
- `Toolkits/VideoMetaToolkit/README.md` + `Toolkits/VideoMetaToolkit/VideoMetaToolkit.ps1` — отдельная подпапка и launcher-заготовка под новый модуль описаний/постеров/актёров.
- `REPO-LAYOUT.md` и `MediaInboxToolkit/README.md` — добавлен раздел про архитектуру vNext и правила постепенной миграции без поломки текущих путей.
- `MediaInboxToolkit.ps1` — заметка в `.NOTES` про новый каркас `Toolkits`.
- `Invoke-MediaInboxApplyReviewedCsv.ps1` + `Get-MediaInboxReviewedCsvSummary.ps1` — workflow ручной разметки CSV (`Decision=APPLY/SKIP/REVIEW`) и перенос только подтверждённых строк.
- `New-MediaInboxReviewCsv.ps1` — подготовка review-копии CSV с колонками `Decision`/`DecisionNote` и дефолтной предразметкой.
- `Update-MediaInboxReviewCsvAutoDecide.ps1` — расширен: поддержка `-TorrentDirectory`, fuzzy match по именам `.torrent`, доп. автоперенаправление review-эпизодов в `cartoons`.
- `sort-inbox.video-under-sort*.example.json` — в `scope.excludeDirectoryNames` добавлен `_Workspace`, чтобы не тянуть legacy-шум в новые dryrun.
- Snapshot: OLD/MediaInboxToolkit_v0.2.3_20260505-181252 (launcher MediaInboxToolkit.ps1).

## 0.2.3 - 2026-05-05 02:38:26 +03:00
- `sort-inbox.video-under-sort.cyrillic.example.json` — обезличенный пресет с кириллическими корнями под `Video\Sort\Video\…`, `folders.workspaceSeriesToolkitSubfolders` для SeriesToolkit.
- `sort-inbox.video-under-sort.example.json` — расширенный скелет: `folders.skeletonExtraRelatives` (документалистика, концерты, спорт и др.) + `workspaceSeriesToolkitSubfolders`.
- `New-MediaInboxDestinationSkeleton.ps1` — создаёт также `skeletonExtraRelatives`; параметр `-SkipSkeletonExtras` отключает доп. каталоги.
- `Organize-SortVideoUnderSort.ps1` — подпапки для batch SeriesToolkit из политики (`workspaceSeriesToolkitSubfolders`).
- `Start-MediaInboxToolkitGui.Engine.ps1` — пресет политики (ASCII / кириллица / нейтральный) и кнопка создания скелета.
- `Watch-MediaInboxToolkitCsv.ps1` — ожидание нового `sort-inbox-*.csv` в `LOGS\`.
- `Invoke-MediaInboxSortStage1.ps1` / `Invoke-MediaInboxSortStage3Apply.ps1` — параметр `-SkeletonProfile Cyrillic|Ascii`.
- `sort-inbox.example.json` — в `meta` и `folders` задокументированы опциональные ключи скелета.
- `README.md` — описание кириллического скелета и Watch.
- Snapshot: OLD/MediaInboxToolkit_v0.2.2_20260505-023826 (launcher MediaInboxToolkit.ps1).

## 0.2.2 - 2026-05-05 02:20:55 +03:00
- `sort-inbox.video-under-sort.example.json` — разложение внутри `Video\Sort\Video\…`, `scope.excludeDirectoryNames: ["Video"]`, те же `destinationsByKind`, что у workspace-in-sort.
- `New-MediaInboxDestinationSkeleton.ps1` — только создание корней из `destinations` (без движка и без переноса).
- `Invoke-MediaInboxSortStage1.ps1` — этап 1: скелет + `MediaInboxToolkit` DryRun на `SortRoot`.
- `Invoke-MediaInboxSortStage3Apply.ps1` — только `MediaInboxToolkit -Apply` (перенос по политике); SeriesToolkit — через `Organize-SortVideoUnderSort.ps1`.
- `Organize-SortVideoUnderSort.ps1` — аналог `Organize-SortInPlace.ps1`, корень сериалов `Sort\Video\…` и политика по умолчанию `sort-inbox.video-under-sort.example.json`.
- `README.md`: ссылки на новые сценарии; корень `.gitignore`: `MediaInboxToolkit/sort-inbox.*.local.json` для локальных путей NAS.
- `MediaInboxToolkit.ps1`: уточнение в `.NOTES` про exclude для `Video`.
- Snapshot: OLD/MediaInboxToolkit_v0.2.1_20260505-022055 (launcher MediaInboxToolkit.ps1).

## 0.2.1 - 2026-05-04 18:42:21 +03:00
- `.github/workflows/release.yml` — при push тега `v*.*.*` сборка ZIP (без `.git` / `.github` / `OLD` / `LOGS`) и публикация Release через `softprops/action-gh-release`; `zip_path` в `GITHUB_OUTPUT` (глоб `*.zip` на Linux не подхватывался); `draft: false`.
- `.github/scripts/Build-MediaInboxRelease.ps1` + `.github/templates/release-body.md.template` — красивое описание на русском: секции «Что нового» из `CHANGELOG.md`, состав архива, ffprobe/WinGet, ссылки, SHA-256.
- `Publish-MediaInboxStandalone.ps1` — после `main` создаёт аннотированный тег `v<version>`, если его ещё нет на `media-inbox`; устойчивое удаление worktree `_mit_publish_tmp`.
- `README.md`: как связаны тег, workflow и ZIP.
- Snapshot: OLD/MediaInboxToolkit_v0.2.0_20260504-184221 (launcher MediaInboxToolkit.ps1).

## 0.2.0 - 2026-05-04 18:19:15 +03:00
- `Fetch-VideoMetadata.ps1`: `Find-TmdbTvEpisodeByTitleFuzzy`, `Test-SortEpisodeTitleFuzzyEquals` — поиск S/E по названию эпизода в сезонах TMDB (скан сверху вниз).
- Политика `classification.shortFormEpisodeTitleGuess`: включение, `maxDurationSec`, `maxBasenameChars`, `maxSeasonsToScanPerShow`, привязка `pathContainsToTmdbTvId` (пример Robot Chicken / TMDB 1433).
- Движок: `Invoke-MediaInboxEpisodeTitleFuzzyReclassify` после featureMeter/web — короткий файл без `SxxEyy`, кандидаты из пути, веб-ссылок TMDB и (для многословных имён) `Search-TmdbTvSeries`; `SortSource: mit_episode_title_fuzzy`.
- Пример `sort-inbox.example.json` дополнен блоком `shortFormEpisodeTitleGuess`.
- Snapshot: OLD/MediaInboxToolkit_v0.1.9_20260504-181915 (launcher MediaInboxToolkit.ps1).

## 0.1.9 - 2026-05-04 18:04:25 +03:00
- ffprobe+featureMeter; webTmdbResolve DDG/Яндекс→TMDB; переклассификация movie→series при SxxEyy и совпадении TV.
- Snapshot: OLD/MediaInboxToolkit_v0.1.8_20260504-180425 (launcher MediaInboxToolkit.ps1).

## 0.1.8 - 2026-05-04 17:34:51 +03:00
- docs: FIX-PLAN-SORT-CLASSIFICATION-202605; README ссылка; отсылка к SeriesMetaExtrasToolkit.
- Snapshot: OLD/MediaInboxToolkit_v0.1.7_20260504-173451 (launcher MediaInboxToolkit.ps1).

## 0.1.7 - 2026-05-04 16:22:19 +03:00
- scope.excludeDirectoryNames; Organize-SortInPlace + sort-inbox.workspace-inside-sort.json.
- Подкаталоги `_Workspace` в политике in-place — ASCII (`series`, `movies`, …) для стабильного запуска из консоли Windows.
- Snapshot: OLD/MediaInboxToolkit_v0.1.6_20260504-162219 (launcher MediaInboxToolkit.ps1).

## 0.1.6 - 2026-05-04 15:48:06 +03:00
- orphanSeasonFolderSeriesMap (одиночная папка сезона); эпизод NN. без пробела после точки; SortSource folder_season_episode_orphan_map.
- Выравнивание ContentKindGuess: boost 57 для `folder_season_episode_orphan_map` (как у контекста папки).
- Snapshot: OLD/MediaInboxToolkit_v0.1.5_20260504-154806 (launcher MediaInboxToolkit.ps1).

## 0.1.5 - 2026-05-04 03:49:24 +03:00
- Контекст папки Season+NN.; Robot Chicken Star Wars TV-special; fallback поиск TMDB movie; allowMissingYearIfTmdbMatched (политика).
- Выравнивание ContentKindGuess к series_episode после контекста папки (корректный destinationsByKind).
- Snapshot: OLD/MediaInboxToolkit_v0.1.4_20260504-034924 (launcher MediaInboxToolkit.ps1).

## 0.1.4 - 2026-05-04 03:43:58 +03:00
- ContentKinds: кириллица через Unicode-кодпоинты (исправлен ParseError на некоторых кодировках файла).
- Snapshot: OLD/MediaInboxToolkit_v0.1.3_20260504-034358 (launcher MediaInboxToolkit.ps1).

## 0.1.3 - 2026-05-04 03:34:42 +03:00
- TMDB жанры 16+регион; Fetch: Get-TmdbGenreIdsFromMediaObject; createDestinationRootsOnApply; пример sort-inbox.library-layout-emilian; GUI MVP.
- Snapshot: OLD/MediaInboxToolkit_v0.1.2_20260504-033442 (launcher MediaInboxToolkit.ps1).

## 0.1.2 - 2026-05-04 03:22:37 +03:00
- destinationsByKind + safety; destRootKey в CSV; Orchestrate: корни SeriesToolkit из sort-inbox CSV.
- Snapshot: `OLD/MediaInboxToolkit_v0.1.1_20260504-032237` (изменился `MediaInboxToolkit.ps1`).

## 0.1.1 - 2026-05-04 03:11:28 +03:00
- Интеграция ContentKinds в CSV; scope.videoOnly в примере политики; документация CLASSIFICATION/OFFLINE/INSPIRATION/GUI; Publish-MediaInboxStandalone.ps1; исправлен расчёт относительного пути от inbox для эвристик.
- Snapshot: `OLD/MediaInboxToolkit_v0.1.0_20260504-031128` (изменился `MediaInboxToolkit.ps1`).

## 0.1.0 - 2026-05-04 12:00:00 +03:00
- Выделен отдельный продукт **MediaInboxToolkit** в каталоге репозитория `MediaInboxToolkit/` (ветка `media-inbox-toolkit`): движок `MediaInboxToolkit.Engine.ps1`, launcher `MediaInboxToolkit.ps1`, политика `sort-inbox.example.json`, план `docs/SORT-INBOX-PLAN.md`.
- **SeriesToolkit 0.2.1** зафиксирован как стабильная линия нормализации сериалов; расширенный inbox-конвейер развивается здесь и по возможности вызывает общий `Fetch-VideoMetadata.ps1` и в перспективе сценарии SeriesToolkit как модуль пост-обработки (см. README).
- Перенесена функциональность бывших версий 0.2.x (черновик в SeriesToolkit): кириллица TMDB, кэш сезонов, Blu-ray remux, плоские `Фильмы`, год из имени файла, StrictMode JSON.

### История переноса из черновика SeriesToolkit 0.2.x
- Плоская выкладка фильмов в `Фильмы\Имя.mkv`; BD — `Фильмы\Русское имя\` без папки года.
- TMDB: `Search-TmdbMovie`, `Get-TmdbTvResolvedRuDisplayName`, `Get-TmdbMovieResolvedRuTitle`, `Get-TmdbTvSeasonEpisodeTitleMap`, alternative titles для фильмов (`titles`).
