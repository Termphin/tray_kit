#!/usr/bin/env bash
set -euo pipefail

app=example/build/linux/x64/debug/bundle/tray_kit_example
mkdir -p out

has_watcher() {
  dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus.NameHasOwner string:org.kde.StatusNotifierWatcher 2>/dev/null |
    grep -q 'boolean true'
}

kded5 >out/kded.log 2>&1 &
sleep 5
dbus-send --session --print-reply --dest=org.kde.kded5 /kded \
  org.kde.kded5.loadModule string:statusnotifierwatcher | tee -a out/kded.log
for _ in $(seq 30); do has_watcher && break; sleep 1; done
has_watcher

plasmashell >out/plasmashell.log 2>&1 &
sleep 20

"$app" >out/app.log 2>&1 &
app_pid=$!

dart run tool/tray_probe.dart 2>&1 | tee out/probe.log
sleep 3
import -window root out/kde.png || true
kill "$app_pid" || true

grep -q 'tray_kit: shown supported=true' out/app.log
grep -q 'tray_kit: hello' out/app.log
echo "KDE: icon registered, read and clicked"
