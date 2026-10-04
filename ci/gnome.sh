#!/usr/bin/env bash
set -euo pipefail

mode=${1:-with-extension}
app=example/build/linux/x64/debug/bundle/tray_kit_example
mkdir -p out
export XDG_RUNTIME_DIR=$(mktemp -d)
chmod 700 "$XDG_RUNTIME_DIR"

if [ "$mode" = with-extension ]; then
  gsettings set org.gnome.shell disable-user-extensions false
  gsettings set org.gnome.shell enabled-extensions "['ubuntu-appindicators@ubuntu.com']"
else
  gsettings set org.gnome.shell enabled-extensions "[]"
fi

gnome-shell --wayland --headless --virtual-monitor 1280x800 --unsafe-mode \
  >out/gnome-shell-$mode.log 2>&1 &
for _ in $(seq 60); do
  [ -S "$XDG_RUNTIME_DIR/wayland-0" ] && break
  sleep 1
done
sleep 10

WAYLAND_DISPLAY=wayland-0 GDK_BACKEND=wayland "$app" >out/app-$mode.log 2>&1 &
app_pid=$!

if [ "$mode" = with-extension ]; then
  dart run tool/tray_probe.dart | tee out/probe-gnome.log
  sleep 3
  gdbus call --session --dest org.gnome.Shell.Screenshot \
    --object-path /org/gnome/Shell/Screenshot \
    --method org.gnome.Shell.Screenshot.Screenshot false false \
    "$PWD/out/gnome.png" || true
  kill "$app_pid" || true
  grep -q 'tray_kit: shown supported=true' out/app-$mode.log
  grep -q 'tray_kit: hello' out/app-$mode.log
  echo "GNOME: icon registered, read and clicked"
else
  sleep 15
  kill "$app_pid" || true
  grep -q 'tray_kit: shown supported=false' out/app-$mode.log
  echo "GNOME without the extension: no tray, as reported"
fi
