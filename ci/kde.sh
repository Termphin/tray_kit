#!/usr/bin/env bash
set -euo pipefail

app=example/build/linux/x64/debug/bundle/tray_kit_example
mkdir -p out

kded5 >out/kded.log 2>&1 &
sleep 5
plasmashell >out/plasmashell.log 2>&1 &
sleep 20

"$app" >out/app.log 2>&1 &
app_pid=$!

dart run tool/tray_probe.dart | tee out/probe.log
sleep 3
import -window root out/kde.png || true
kill "$app_pid" || true

grep -q 'tray_kit: shown supported=true' out/app.log
grep -q 'tray_kit: hello' out/app.log
echo "KDE: icon registered, read and clicked"
