#!/usr/bin/env bash
# Build the optional ZombieBuddy layer (BetterVehicleDynamicsZB.jar).
#   zb/build.sh [patched-CarController.java]
# With a path, BvdCar.java is regenerated from BVD's patched CarController
# first (default: the entered Necroid source tree, if present).
set -euo pipefail
cd "$(dirname "$0")"
G='G:\SteamLibrary\steamapps\common\ProjectZomboid'
JAVAC="/mnt/c/Program Files/Zulu/zulu-26/bin/javac.exe"
JAR="/mnt/c/Program Files/Zulu/zulu-26/bin/jar.exe"
SRC_CC="${1:-/mnt/c/tools/necroid/src-better-vehicle-dynamics-42/zombie/core/physics/CarController.java}"
OUT=../workshop/BetterVehicleDynamics/42.20/media/java/client

if [ -f "$SRC_CC" ]; then
   python3 -I gen_bvdcar.py "$SRC_CC" src/bvd/zb/BvdCar.java
else
   echo "build: $SRC_CC not found, using the committed BvdCar.java" >&2
fi

mkdir -p build "$OUT"
rm -rf build/*
"$JAVAC" --release 25 -nowarn -Xlint:-removal -cp "$G\\projectzomboid.jar;$G\\ZombieBuddy.jar" -d "$(wslpath -w build)" \
   $(find src -name '*.java' | sed 's|^|./|' | xargs -I{} wslpath -w {})
"$JAR" --create --file "$(wslpath -w "$OUT/BetterVehicleDynamicsZB.jar")" -C "$(wslpath -w build)" .
echo "build: $OUT/BetterVehicleDynamicsZB.jar"
