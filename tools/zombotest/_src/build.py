# Regenerates the scenarios one level up: python3 build.py . ..   (each .body has a --@COMMON@ marker replaced by common.inc)
import sys, pathlib
src = pathlib.Path(sys.argv[1]); out = pathlib.Path(sys.argv[2])
common = pathlib.Path(src / "common.inc").read_text()
for body in sorted(src.glob("*.body")):
    text = body.read_text().replace("--@COMMON@", common)
    (out / (body.stem + ".lua")).write_text(text)
    print("wrote", body.stem + ".lua")
