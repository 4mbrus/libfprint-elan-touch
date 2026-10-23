#!/bin/sh
# Unlock test: 5 tries with the enrolled finger, 3 with a different finger.
# Run as your normal user (no sudo).
OUT="$(dirname "$(readlink -f "$0")")/verify-results.txt"  # git-ignored
: > "$OUT"

try () {  # $1 = label, $2 = prompt
  printf '\n=== %s: touch and hold ~1 s ===\n' "$2"
  r="$(fprintd-verify -f right-index-finger 2>&1 | grep -o 'verify-[a-z-]*' | tail -1)"
  echo "    result: $r"
  echo "$1 $r" >> "$OUT"
  sleep 1
}

for i in 1 2 3 4 5; do try "index_$i" "RIGHT INDEX finger, try $i/5"; done
for i in 1 2 3; do try "middle_$i" "RIGHT MIDDLE finger (should be REJECTED), try $i/3"; done

echo
echo "Summary:"
echo "  right index matched:   $(grep -c '^index.*verify-match' "$OUT")/5"
echo "  middle finger matched: $(grep -c '^middle.*verify-match' "$OUT")/3  (should be 0)"
