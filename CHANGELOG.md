# CHANGELOG











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
