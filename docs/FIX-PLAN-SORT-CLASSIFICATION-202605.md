# План исправлений после in-place разложения (movies / series / метаданные)

Документ зафиксирован по обратной связи и скриншотам (май 2026). Цель — снизить ручное вмешательство: жёстче классифицировать контент, стабилизировать кириллицу и не путать разные шоу при TMDB.

---

## A. Папка `_Workspace/movies`

| ID | Симптом | Гипотеза | Действия |
|----|---------|----------|----------|
| A1 | 2 BD-папки без русского названия (Point Break HDR, The Godfather HDR) | TMDB не сматчился или `Get-TmdbMovieResolvedRuTitle` пустой | Fallback-цепочка: `ru-RU` → `en-US` → безопасная латиница + флаг `needs_ru_title` в CSV; опционально Яндекс/Google по строке `Title Year` для подписи папки (только при явной политике). |
| A2 | В `movies` почти всё латиницей | Политика `preferCyrillic` не применяется к имени **файла** или нет RU в TMDB | Разделить: **папка** BD — приоритет RU; **файл** плоского фильма — шаблон `{TitleRu}.{Year}.{Ext}` с обязательным проходом alternative_titles / en+manual alias map. |
| A3–A6 | Короткие `.mkv` (Bionic, Black Cherry, Aktorët e Kanës, BFF…) — это **Robot Chicken / Archer / Superjail!** | Классификация `movie` по умолчанию + нет эвристики «длительность/размер/паттерн серии» | **Эвристики мультсегментов**: размер &lt; N МБ ИЛИ длительность из ffprobe &lt; T мин → кандидат `cartoon_short` / `series_segment`; белый список паттернов названий RC/Archer/Superjail (расширяемый JSON); перенаправление в `cartoons` + привязка к `tvId` из TMDB search TV. |
| A7 | Скриншот 9: часть RU-имён — это всё ещё Robot Chicken | RU alternative titles совпали с эпизодом RC без проверки `runtime`/типа | После TMDB movie hit — **валидация**: если `belongs_to_collection` / keywords / длина &lt; порога — повторный поиск как **TV episode** по `Search-TmdbTv` + сравнение названия эпизода. |
| A8 | Крупные релизы (Заводной апельсин, Апокалипсис…) верны | Оставить как есть | Регрессионные тесты на этих кейсах. |

**Вопросы к вам (A):**  
1) Порог размера/длительности для «не полнометражка»: например &lt; 400 МБ **или** &lt; 15 мин — ок?  
2) Готовы ли вы хранить локальный `segment-shows.json` (regex → `tvId`, целевая папка) для RC/Archer/Superjail до полноценного ML?

---

## B. Папка `_Workspace/series`

| ID | Симптом | Гипотеза | Действия |
|----|---------|----------|----------|
| B1 | «Всё мультсериалы», но попало в `series` | `destinationsByKind` для `cartoon_series_episode` → `series` или refine не сработал | Проверить `Resolve-MediaInboxContentKindFromTmdbTv` + пороги; для in-place политики — опция **`inboxAssumeAnimated: true`** (все TV в `cartoons` до уточнения). |
| B2 | Папки `509 Chasing Bobby…` — **King of the Hill** | Нет шаблона «компактный код сезон+эпизод» в MediaInbox `folderSeasonContext` | Добавить распознавание родителя `^\d{3,4}\s` (S≤9: `5`+`09`; S10+: `10`+`01`) + `seriesGuess` из соседнего контекста или карты `orphanSeasonFolderSeriesMap` по префиксу сезона. |
| B3 | «Подозрительная сова»: с середины сезона — заглушки «Эпизод N» | Неполный кэш сезона TMDB, второй проход не добрал; strict_mode | Поднять `metadata_second_pass_min_coverage_percent`, при дырах в S**N** — точечный запрос `Get-TmdbTvSeasonEpisodeTitleMap` по диапазону; логировать `episode_gap` в CSV. |
| B4 | Adventure Time, Archer, Brickleberry, Invincible в `series` | Жанр/регион дал `series_episode`, а не cartoon | Усилить `tmdbKindRefinement` для западной анимации; при `animation` в жанрах — **принудительно** `cartoons` для in-place профиля. |
| B5 | Китайское имя папки + внутри Robot Chicken | Неверный `tvId` (другой сериал в TMDB) | **Проверка согласованности**: выбранный `tvId` → выборка 3 случайных эпизодов; если имя файла не коррелирует с эпизодами (Levenshtein / токены) — сброс и второй поиск по **en title** + ручной алиас. |
| B6 | Эпизоды на латинице вместо кириллицы | `ru-RU` пуст для эпизода | Цепочка `ru` → `en` → transliterate policy off; для RC — принудительно брать `name` из `translations` если есть. |

**Вопросы к вам (B):**  
3) In-place профиль: **все** не-аниме-live-action из Sort редки? Если да — включаем `inboxAssumeAnimated` по умолчанию для `workspace-inside-sort.json`.  
4) King of the Hill: подтвердите, что формат **всегда** `SS0EE` в начале имени папки (одна цифра сезона до 9)? Нужны примеры для сезона 10+.

---

## C. Конвейер «сначала веб / потом TMDB id»

Идея: по текущему имени файла/папки → **нормализованный запрос** → (опционально) Google CSE / Яндекс.XML / DDG HTML parse → из сниппета вытащить `themoviedb.org/movie|tv/(\d+)` или Кинопоиск id → уже **прямой** `Get-TmdbTv` / `Get-TmdbMovie`.

| Шаг | Риск | Митигация |
|-----|------|-----------|
| Поиск в Google/Яндекс | Капча, ToS | Только при `WEB_RESOLVE_API_KEY` / сохранённых HTML / rate limit; по умолчанию выкл. |
| Парсинг id из URL | Ошибочный id | Валидация B5 + runtime. |

**Вопросы к вам (C):**  
5) Есть ли у вас **Google Programmable Search** (CSE) key + cx или только ручной браузер?  
6) Нужен ли приоритет **Кинопоиск id** в файле рядом (`series-meta.json`) для спорных папок?

---

## D. Модуль постеров и описаний (отдельный продукт)

Создан каталог **`SeriesMetaExtrasToolkit/`** в монорепо (как `MediaInboxToolkit/`):

- `SeriesMetaExtrasToolkit.ps1` — лаунчер (dry-run по умолчанию в будущем).
- `SeriesMetaExtrasToolkit.Engine.ps1` — заготовка: NFO (Kodi/Jellyfin), `poster.jpg` / `fanart.jpg` из TMDB `images`, опционально `tvshow.nfo` / `movie.nfo`.
- `version.json`, `CHANGELOG.md`, `Bump-Version.ps1`, `Sync-GitHub.ps1`, `Publish-SeriesMetaExtrasStandalone.ps1` — зеркало паттерна публикации (subtree → отдельный GitHub repo, remote по аналогии с `media-inbox`).

Публикация: после создания репозитория `SeriesMetaExtrasToolkit` у вашего GitHub-пользователя добавить remote `series-meta-extras` и вызывать `Publish-SeriesMetaExtrasStandalone.ps1` из корня монорепо.

**Вопросы к вам (D):**  
7) Целевая схема: **Kodi** NFO, **Jellyfin** meta, или оба?  
8) Постеры: только TMDB `w500` или ещё fanart.tv?

---

## Порядок внедрения (рекомендуемый)

1. **Классификация коротких видео + RC/Archer/Superjail** (A3–A7) — максимальный эффект для `movies`.  
2. **Согласованность tvId** (B5) + кириллица эпизодов (B6).  
3. **King of the Hill папки** (B2) + **мульт vs series** (B1, B4).  
4. **Заглушки «Подозрительная сова»** (B3) — донастройка second pass / кэша.  
5. **Веб→id** (C) — за флагом политики.  
6. **SeriesMetaExtrasToolkit** — поэтапно: TMDB-only постер+plot, затем NFO.

После ваших ответов на вопросы 1–8 приоритеты можно сузить и начать с одного PR/ветки (`media-inbox-toolkit` + при необходимости патч `Fetch-VideoMetadata.ps1`).

---

## Ответы пользователя (2026-05-04) — что уже внедрено

- **1–2 (полный метр):** порог по умолчанию **≥ 3600 с** ffprobe помечает релиз как полный метр (`mit_feature_hint` в CSV); короче — допускается переклассификация в сериал при **SxxEyy в имени** и совпадении TV через **DDG→TMDB id** или `Search-TmdbTvSeries` + `Test-SortTitleTokenOverlap`. Дальше: привязка `Get-SortFeatureMeterHintFromSignals` к runtime из TMDB movie.
- **3–4:** без «все мульт по умолчанию»; в **SeriesToolkit** добавлены папки **`NNN …`** и **`NNNN …`** (Царь горы / KOTH).
- **5–6:** авторежим без Google CSE — **DuckDuckGo html**, при пустом результате **Яндекс**; из HTML извлекаются `themoviedb.org/tv|movie/id`.
- **7–8:** в **SeriesMetaExtrasToolkit** описаны режимы `poster_tmdb`, `nfo_kodi`, `sidecar_jellyfin`, `plot_txt` (реализация позже).
