#!/bin/sh
# Meta+W: открыть или закрыть «Обзор», дождавшись конца анимации слайда
# https://github.com/radiovitea/littlethings

effects() {
    qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.activeEffects
}
toggle() {
    qdbus6 org.kde.kglobalaccel /component/kwin \
        org.kde.kglobalaccel.Component.invokeShortcut Overview
}

# «Обзор» уже открыт: закрываем, как обычный Meta+W
if effects | grep -qx overview; then
    toggle
    exit 0
fi

# Ждём, пока закончится слайд (не дольше 3 секунд)
i=0
while effects | grep -qx slide && [ "$i" -lt 60 ]; do
    sleep 0.05
    i=$((i + 1))
done

# Открываем; если KWin проглотил вызов, пробуем ещё (до 4 раз)
n=0
while [ "$n" -lt 4 ]; do
    toggle
    sleep 0.3
    effects | grep -qx overview && exit 0
    n=$((n + 1))
done
