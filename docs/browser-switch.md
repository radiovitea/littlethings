# browser-switch — браузер по умолчанию прямо из панели Плазмы

Плазмоид для KDE Plasma 6. В панели видна иконка текущего браузера по умолчанию, а сменить его можно в один клик, без похода в «Параметры системы → Приложения по умолчанию».

Пригодится, если основной браузер приходится менять часто: например, для работы нужен один, а для себя другой.

## Как пользоваться

- **Клик по иконке** открывает список всех установленных браузеров, текущий отмечен галочкой. Нажми на нужный, и он станет основным.
- **Колёсико** над иконкой переключает на следующий или предыдущий браузер, не открывая список.
- **Сочетание клавиш** переключает на следующий браузер. Назначается в настройках виджета, раздел «Комбинации клавиш».

## Как работает

В списке те же браузеры, что и в «Параметрах системы»: приложения с категорией `WebBrowser` из обычных пакетов и из Flatpak. Скрытые (`NoDisplay`, `Hidden`) и неустановленные (`TryExec`) пропускаются.

При выборе браузера виджет меняет то же, что и «Параметры системы»:
- `~/.config/mimeapps.list` (и `kde-mimeapps.list`, если он есть): `x-scheme-handler/http`, `x-scheme-handler/https`, `text/html`, `application/xhtml+xml` и `application/x-extension-*`;
- `~/.config/kdeglobals`: `[General] BrowserApplication`.

Потом в фоне запускается `kbuildsycoca6`, чтобы ссылки из других программ сразу открывались в новом браузере.

## Что нужно

- KDE Plasma 6
- `kwriteconfig6` и `kreadconfig6`: входят в Plasma 6, отдельно ставить не нужно

## Установка

```
git clone https://github.com/radiovitea/littlethings.git
cd littlethings
kpackagetool6 -t Plasma/Applet -i plasmoids/browser-switch
```

Потом «Добавить виджеты» → найди «Браузер по умолчанию» → перетащи на панель.

## Обновление

```
cd littlethings
git pull
rm -rf ~/.local/share/plasma/plasmoids/org.viktor.browserswitch
kpackagetool6 -t Plasma/Applet -i plasmoids/browser-switch
systemctl --user restart plasma-plasmashell
```

Поверх старой версии `kpackagetool6 -i` не ставит и пишет `already exists`, поэтому старую сначала удаляем. Виджет на панели после перезапуска сам подхватит новую версию.

## Скрипт без виджета

Вся логика лежит в `plasmoids/browser-switch/contents/code/browser-switch.sh`. Его можно запускать из терминала или повесить на свою комбинацию клавиш:

```
browser-switch.sh status                  # текущий браузер и список всех
browser-switch.sh set librewolf.desktop   # сделать основным
browser-switch.sh next                    # следующий по списку
browser-switch.sh prev                    # предыдущий
```

## Как удалить

Убери виджет с панели и выполни:

```
kpackagetool6 -t Plasma/Applet -r org.viktor.browserswitch
```

Браузером по умолчанию останется тот, что был выбран последним.
