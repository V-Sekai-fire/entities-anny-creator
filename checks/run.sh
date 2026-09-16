#!/usr/bin/env bash
# Runs every check and its planted control against a Godot binary, headless.
#   checks/run.sh <godot.exe>
# A check passes with exit 0; its control passes with exit 0 only when the planted defect failed.
set -u
G="${1:?path to a godot editor binary}"
cd "$(dirname "$0")/.."
"$G" --headless --path . --import > checks/import.log 2>&1
fails=0
for c in topology export parity shaped_export; do
  for m in "" "--plant"; do
    log="checks/${c}${m}.log"
    "$G" --headless --quit-after 20000 --path . -s "res://checks/check_${c}.gd" -- $m > "$log" 2>&1
    code=$?
    verdict=$(grep -h "DONE\|planted control\|^FAIL" "$log" | tail -1)
    printf '%-14s %-8s exit=%d  %s\n' "$c" "${m:-run}" "$code" "$verdict"
    [ "$code" -eq 0 ] || fails=$((fails + 1))
  done
done
echo "$fails of 8 runs failed"
exit $fails
