# TerraMaster NAS + qBittorrent: целевой конвейер

Сценарий для библиотеки на **TerraMaster** (много дисков, SMB `\\HOST\share\Video`) и загрузок через **qBittorrent Web UI** (например `https://192.168.1.100:5443/qbittorrent/`).

## Цель

Новые файлы после завершения раздачи:

1. Имеют **русские** имена (TMDB `ru-RU`, при необходимости SeriesToolkit).
2. Лежат в **нужной категории**: `Фильмы`, `Сериалы`, `Анимесериалы`, `Аниме`, `Мультики`, …
3. Для сериалов: `{Сериал}\Сезон NN\{Сериал} - SxxEyy - {Название}.mkv`, бонусы в `Бонусы\`.

## Рекомендуемая схема каталогов

| Путь (от share) | Назначение |
|-----------------|------------|
| `Video\Sort` | Inbox: всё новое из qBittorrent |
| `Video\Фильмы` | Готовые фильмы |
| `Video\Сериалы` | Живые сериалы |
| `Video\Анимесериалы` | Аниме-сериалы |
| `Video\Аниме` | Аниме-фильмы / OVA-коллекции |
| `Video\Мультики` | Мультфильмы |
| `Video\_НаРазбор` | Неоднозначные случаи |

qBittorrent: категория/путь сохранения → **`Video\Sort`** (или подпапка по типу, если настроите отдельные категории).

## Переменные окружения (ПК или задача Планировщика)

```powershell
$env:TMDB_API_KEY = '<ключ v3 TMDB>'
$env:MIT_INBOX_ROOT = '\\Emilian_TNAS\emildg8\Video\Sort'
```

Опционально для подсказок SxxEyy из торрентов (см. `Resolve-LooseCartoonEpisodesFromTmdb.config.json`):

```powershell
$env:MIT_QBIT_WEBUI = 'https://192.168.1.100:5443'
$env:MIT_QBIT_USER = '...'
$env:MIT_QBIT_PASS = '...'
```

## Этапы конвейера

### 1. Пакетное RU-переименование в Sort (ручная партия или по расписанию)

```powershell
cd <repo>\MediaInboxToolkit\Scripts
# Скопируйте sort-rename.batch.example.json → sort-rename.local.json и задайте sortRoot
powershell -File .\Apply-SortRussianRename.ps1 -ConfigPath .\sort-rename.local.json -Apply
powershell -File .\Update-SortEpisodeRuTitles.ps1 -SortRoot $env:MIT_INBOX_ROOT -Apply
```

Конфиг-пример под TNAS: `sort-inbox.emilian-tnas.example.json` (раскладка в `Video\…`).

### 2. Раскладка в библиотеку (MediaInboxToolkit)

```powershell
cd <repo>\MediaInboxToolkit
Copy-Item .\sort-inbox.emilian-tnas.example.json .\sort-inbox.local.json
powershell -File .\MediaInboxToolkit.ps1 -PolicyPath .\sort-inbox.local.json -InboxPath $env:MIT_INBOX_ROOT -UseTmdb -DryRun
# проверка CSV в LOGS\
powershell -File .\MediaInboxToolkit.ps1 -PolicyPath .\sort-inbox.local.json -InboxPath $env:MIT_INBOX_ROOT -UseTmdb -Apply
```

### 3. Полировка эпизодов (SeriesToolkit)

Только если в папке сериала **нет** лишней вложенности `Сезон N\Сезон N\`. Иначе сначала `Fix-SortNestedSeasonFolders.ps1`.

```powershell
powershell -File ..\SeriesToolkit\SeriesToolkit.ps1 -RootPath '\\Emilian_TNAS\emildg8\Video\Сериалы\Имя сериала' -UseTmdb -Apply
```

Или оркестратор:

```powershell
powershell -File .\Organize-SortVideoUnderSort.ps1 -SortRoot $env:MIT_INBOX_ROOT -PolicyPath .\sort-inbox.local.json -Apply
```

## Автоматизация (план)

| Триггер | Действие |
|---------|----------|
| qBittorrent: завершена загрузка | Переместить в `Video\Sort` (встроенные правила или скрипт Web API) |
| Планировщик Windows / TNAS Task | `Apply-SortRussianRename` + `MediaInboxToolkit -Apply` для `MIT_INBOX_ROOT` |
| Раз в сутки | SeriesToolkit Batch по корням `Анимесериалы`, `Сериалы` |

Полностью «мгновенно при добавлении» потребует: хука qBittorrent → очередь → один воркер MIT (без параллельного ffprobe на десятках remux).

## Ограничения

- Имена файлов в Windows **без двоеточия** (`:` → ` - ` в скриптах).
- Крупные remux: первый прогон MIT с ffprobe на NAS может быть **долгим** — узкий inbox или отключение feature meter в политике для Sort.
- `sort-rename.*.local.json` с персональными UNC **не коммитить** (см. `.gitignore`).
