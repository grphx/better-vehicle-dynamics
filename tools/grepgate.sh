#!/usr/bin/env bash
# Provenance grep gate. Exit 1 if any banned token appears in a tracked file.
# CREDITS.md may contain the non-affiliation disclaimer phrases; nothing else may.
set -u
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not a git repo"; exit 2; }
cd "$ROOT" || exit 2
HARD='RCP_|VPR_|VehiclePhysicsReworked|Vehicle_Physics_Reworked|VehiclePhysicsReworkedMod|Indivual|Step Van:0\.95|Step Van:80|Valuline|1990'"'"'s torque converters'
SOFT='RealisticCarPhysics|Realistic Car Physics|Black Moons'
fail=0
while IFS= read -r -d '' f; do
  if grep -nIE "$HARD" -- "$f" 2>/dev/null; then echo "  ^ HARD banned token in $f"; fail=1; fi
  if [ "$f" != "CREDITS.md" ]; then
    if grep -nIE "$SOFT" -- "$f" 2>/dev/null; then echo "  ^ disclaimer-only phrase outside CREDITS.md in $f"; fail=1; fi
  fi
done < <(git ls-files -z | grep -zv '^tools/grepgate\.sh$')
if [ "$fail" -ne 0 ]; then echo "GREP GATE FAIL"; exit 1; fi
echo "GREP GATE PASS ($(git ls-files | wc -l) tracked files)"
