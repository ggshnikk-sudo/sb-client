#!/usr/bin/env bash
# Устанавливает лаунчеры SkinBase и CapeForge в меню приложений Linux.
# Запуск: ./install-linux.sh   (из папки launchers/linux)
set -e

DIR="$HOME/.local/share/skinbase-client"
APPS="$HOME/.local/share/applications"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$DIR" "$APPS"
cp "$SCRIPT_DIR/open-app.sh" "$DIR/open-app.sh"
chmod +x "$DIR/open-app.sh"

ICON="$DIR/app-icon.png"
if [ -f "$SCRIPT_DIR/../../ui/app-icon.png" ]; then
  cp "$SCRIPT_DIR/../../ui/app-icon.png" "$ICON"
fi

ICON_LINE=""
[ -f "$ICON" ] && ICON_LINE="Icon=$ICON"

cat > "$APPS/skinbase.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=SkinBase
GenericName=Хранилище плащей Minecraft
Comment=skins.ggshnikk.online в отдельном окне
Exec=$DIR/open-app.sh https://skinbase-dov.pages.dev
$ICON_LINE
Terminal=false
Categories=Network;Game;Utility;
StartupWMClass=skinbase-dov.pages.dev
EOF

cat > "$APPS/capeforge.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=CapeForge
GenericName=Редактор плащей Minecraft
Comment=capes.ggshnikk.online в отдельном окне
Exec=$DIR/open-app.sh https://capeforge.i3667563.workers.dev/
$ICON_LINE
Terminal=false
Categories=Graphics;Game;Utility;
StartupWMClass=capeforge.i3667563.workers.dev
EOF

echo "Готово:"
echo "  $APPS/skinbase.desktop"
echo "  $APPS/capeforge.desktop"
echo "Лаунчеры появятся в меню приложений (может потребоваться перелогин или update-desktop-database ~/.local/share/applications)."
