#!/usr/bin/env bash
# browser-switch.sh — выбор браузера по умолчанию в KDE Plasma 6.
# https://github.com/radiovitea/littlethings
#
# Использование:
#   browser-switch.sh status           — текущий браузер и список всех браузеров
#   browser-switch.sh set ID.desktop   — сделать браузер основным
#   browser-switch.sh next | prev      — следующий / предыдущий браузер по списку
#
# Браузеры — это приложения с категорией WebBrowser, как в «Параметрах
# системы → Приложения по умолчанию». Обычные пакеты и Flatpak.
#
# Вывод (для виджета):
#   current=ID.desktop
#   browser=ID<TAB>Название<TAB>Иконка<TAB>Файл иконки   (по строке на браузер)
#   error=текст ошибки

set -u
shopt -s nullglob

cmd="${1:-status}"
arg="${2:-}"

# Те же типы, что выставляет «Параметры системы → Приложения по умолчанию → Веб-браузер»
MIME_TYPES=(
    x-scheme-handler/http
    x-scheme-handler/https
    text/html
    application/xhtml+xml
    application/x-extension-htm
    application/x-extension-html
    application/x-extension-shtml
    application/x-extension-xht
    application/x-extension-xhtml
)

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
KWRITE="$(command -v kwriteconfig6 || command -v kwriteconfig5 || true)"
KREAD="$(command -v kreadconfig6 || command -v kreadconfig5 || true)"

data_dirs() {
    local d
    local -a dirs
    printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}"
    IFS=: read -ra dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    for d in "${dirs[@]}"; do
        [[ -n "$d" ]] && printf '%s\n' "$d"
    done
    # Flatpak — на случай, если его нет в XDG_DATA_DIRS у plasmashell
    printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/exports/share"
    printf '%s\n' "/var/lib/flatpak/exports/share"
}

# Все .desktop-файлы: по одному на ID, первый по приоритету каталогов
# (пользовательский ~/.local/share/applications перекрывает системный)
declare -A DESKTOP_PATH=()
declare -A DESKTOP_ID=()
collect_desktop_files() {
    local base dir f rel id
    while IFS= read -r base; do
        dir="$base/applications"
        [[ -d "$dir" ]] || continue
        for f in "$dir"/*.desktop "$dir"/*/*.desktop; do
            rel="${f#"$dir"/}"
            id="${rel//\//-}"
            [[ -n "${DESKTOP_PATH[$id]+x}" ]] && continue
            DESKTOP_PATH[$id]="$f"
            DESKTOP_ID[$f]="$id"
        done
    done < <(data_dirs)
}

# Название и иконка из [Desktop Entry]; пусто, если приложение скрыто
# или не подходит ($2 = 1 — требовать категорию WebBrowser)
read_entry() {
    awk -v need_browser="$2" '
        /^\[/ { main = ($0 == "[Desktop Entry]"); next }
        !main { next }
        /^Name=/ && name == "" { name = substr($0, 6) }
        /^Icon=/ && icon == "" { icon = substr($0, 6) }
        /^Type=/      { type = substr($0, 6) }
        /^Exec=/      { exec = substr($0, 6) }
        /^TryExec=/   { tryexec = substr($0, 9) }
        /^NoDisplay=/ { nodisplay = substr($0, 11) }
        /^Hidden=/    { hidden = substr($0, 8) }
        /^Categories=/ { categories = ";" substr($0, 12) ";" }
        END {
            if (type != "Application" || exec == "" || hidden == "true") exit
            if (need_browser == 1 && (nodisplay == "true" || index(categories, ";WebBrowser;") == 0)) exit
            printf "%s\t%s\t%s\n", name, icon, tryexec
        }
    ' "$1"
}

# Файл иконки по имени из Icon= — запасной вариант, если тема значков
# не находит иконку по имени
icon_file() {
    local name="$1" base f size
    [[ -n "$name" ]] || return 0
    if [[ "$name" == /* ]]; then
        [[ -f "$name" ]] && printf '%s\n' "$name"
        return 0
    fi
    while IFS= read -r base; do
        for f in "$base/icons/hicolor/scalable/apps/$name.svg" \
                 "$base/icons/hicolor/scalable/apps/$name.svgz"; do
            [[ -f "$f" ]] && { printf '%s\n' "$f"; return 0; }
        done
        for size in 256 128 96 64 48 32 24 16; do
            f="$base/icons/hicolor/${size}x${size}/apps/$name.png"
            [[ -f "$f" ]] && { printf '%s\n' "$f"; return 0; }
        done
        for f in "$base/pixmaps/$name.svg" "$base/pixmaps/$name.png"; do
            [[ -f "$f" ]] && { printf '%s\n' "$f"; return 0; }
        done
    done < <(data_dirs)
}

tryexec_ok() {
    local t="$1"
    [[ -z "$t" ]] && return 0
    if [[ "$t" == /* ]]; then [[ -x "$t" ]]; else command -v "$t" >/dev/null; fi
}

# Строки «ID<TAB>Название<TAB>Иконка», отсортированные по названию
list_browsers() {
    local -a candidates=()
    local f id name icon tryexec entry
    ((${#DESKTOP_PATH[@]})) || return 0
    mapfile -t candidates < <(grep -l -E '^Categories=(.*;)?WebBrowser(;|$)' -- "${DESKTOP_PATH[@]}" 2>/dev/null)
    for f in "${candidates[@]}"; do
        id="${DESKTOP_ID[$f]}"
        entry="$(read_entry "$f" 1)"
        [[ -n "$entry" ]] || continue
        IFS=$'\t' read -r name icon tryexec <<< "$entry"
        tryexec_ok "$tryexec" || continue
        printf '%s\t%s\t%s\n' "$id" "${name:-${id%.desktop}}" "$icon"
    done | sort -f -t $'\t' -k2,2
}

current_default() {
    local v="" f
    if [[ -n "$KREAD" ]]; then
        # kde-mimeapps.list по стандарту главнее, если он есть
        for f in kde-mimeapps.list mimeapps.list; do
            v="$("$KREAD" --file "$f" --group "Default Applications" \
                --key x-scheme-handler/https 2>/dev/null)"
            [[ -n "$v" ]] && break
        done
    fi
    if [[ -z "$v" ]] && command -v xdg-mime >/dev/null; then
        v="$(xdg-mime query default x-scheme-handler/https 2>/dev/null)"
    fi
    v="${v%%;*}"
    printf '%s\n' "$v"
}

set_default() {
    local id="$1" f mime
    local -a files=(mimeapps.list)
    [[ -f "$CONFIG_HOME/kde-mimeapps.list" ]] && files+=(kde-mimeapps.list)

    for f in "${files[@]}"; do
        for mime in "${MIME_TYPES[@]}"; do
            "$KWRITE" --file "$f" --group "Default Applications" --key "$mime" "$id"
        done
    done
    # --notify есть не во всех версиях kwriteconfig, поэтому с запасным вариантом
    "$KWRITE" --file kdeglobals --group General --key BrowserApplication --notify "$id" 2>/dev/null \
        || "$KWRITE" --file kdeglobals --group General --key BrowserApplication "$id"

    # Обновляем кэш KDE в фоне, чтобы ссылки сразу открывались в новом браузере
    if command -v kbuildsycoca6 >/dev/null; then
        (kbuildsycoca6 >/dev/null 2>&1 &)
    fi
}

collect_desktop_files
mapfile -t BROWSERS < <(list_browsers)
error=""
target=""

case "$cmd" in
    status) ;;
    set)
        target="${arg}"
        [[ -z "$target" || "$target" == *.desktop ]] || target="$target.desktop"
        ;;
    next|prev)
        if ((${#BROWSERS[@]} == 0)); then
            error="Браузеры не найдены"
        else
            cur="$(current_default)"
            idx=-1
            for i in "${!BROWSERS[@]}"; do
                [[ "${BROWSERS[$i]%%$'\t'*}" == "$cur" ]] && { idx=$i; break; }
            done
            n=${#BROWSERS[@]}
            if [[ "$cmd" == next ]]; then
                idx=$(( (idx + 1) % n ))
            else
                idx=$(( idx < 0 ? n - 1 : (idx - 1 + n) % n ))
            fi
            target="${BROWSERS[$idx]%%$'\t'*}"
        fi
        ;;
    *)
        echo "Использование: $0 status | set ID.desktop | next | prev" >&2
        exit 2
        ;;
esac

if [[ "$cmd" != status && -z "$error" ]]; then
    if [[ -z "$target" ]]; then
        error="Не указан браузер"
    elif [[ -z "${DESKTOP_PATH[$target]+x}" ]] \
        || [[ -z "$(read_entry "${DESKTOP_PATH[$target]}" 0)" ]]; then
        error="Не найдено приложение $target"
    elif [[ -z "$KWRITE" ]]; then
        error="Не найден kwriteconfig6"
    else
        set_default "$target"
    fi
fi

current="$(current_default)"
printf 'current=%s\n' "$current"

# Текущий браузер показываем, даже если у него нет категории WebBrowser
listed=0
for row in "${BROWSERS[@]}"; do
    [[ "${row%%$'\t'*}" == "$current" ]] && listed=1
done
if ((listed == 0)) && [[ -n "$current" && -n "${DESKTOP_PATH[$current]+x}" ]]; then
    entry="$(read_entry "${DESKTOP_PATH[$current]}" 0)"
    if [[ -n "$entry" ]]; then
        IFS=$'\t' read -r name icon _ <<< "$entry"
        BROWSERS+=("$current"$'\t'"${name:-${current%.desktop}}"$'\t'"$icon")
    fi
fi

for row in "${BROWSERS[@]}"; do
    IFS=$'\t' read -r id name icon <<< "$row"
    printf 'browser=%s\t%s\t%s\t%s\n' "$id" "$name" "$icon" "$(icon_file "$icon")"
done
printf 'error=%s\n' "$error"

[[ -z "$error" ]]
