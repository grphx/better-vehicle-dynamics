#!/usr/bin/env python3
"""Derive the ZombieBuddy companion class bvd.zb.BvdCar from BVD's patched
CarController source (the Necroid src tree), so the manual-install Java and the
ZombieBuddy Java run the same drivetrain code.

The patched CarController replaces vanilla's class outright. Under ZombieBuddy
vanilla's class stays in place and only its entry points are hooked, so this
script turns the patched source into a per-vehicle companion object:

  * vanilla's public fields (vehicleObject, engineForce, clientControls, ...)
    are read and written on the real controller via `this.cc.<field>`;
  * vanilla's private fields that other vanilla code reads back (isGas, isGasR,
    isBreak, vehicleSteering) are kept here and pushed to the controller by
    Hooks after every hooked call;
  * BVD's own state, specs and helpers stay as they are;
  * methods that are unchanged from vanilla, or debug-only, are dropped so
    vanilla's own versions keep serving them.

Usage: gen_bvdcar.py <patched CarController.java> <out BvdCar.java>
"""
import re
import sys

VANILLA_PUBLIC_FIELDS = [
    "vehicleObject", "clientForce", "engineForce", "brakingForce", "isEnable",
    "acceleratorOn", "brakeOn", "speed", "clientControls",
]
OWN_NESTED = ["EngineSpec", "GearboxSpec", "ConverterSpec", "VehicleSpec",
              "BulletVariables", "ControlState"]
# Members vanilla already provides identically (or debug-only drawing).
DROP_METHODS = [
    r"public CarController\.GearInfo findGear\(",
    r"public CarController\.ClientControls getClientControls\(",
    r"public boolean isGas\(\)",
    r"public boolean isGasR\(\)",
    r"public boolean isBreak\(\)",
    r"public boolean isGasPedalPressed\(\)",
    r"public boolean isBrakePedalPressed\(\)",
    r"public void debug\(\)",
    r"private void renderClosestPointToOtherVehicle\(",
    r"public void drawRect\(",
    r"public void drawCircle\(",
    r"public CarController\(BaseVehicle vehicle\)",
    r"public static final class ClientControls",
    r"public static final class GearInfo",
    r"static \{",
]


def block_end(src, start):
    """Index just past the brace block whose '{' is the first at/after start."""
    i = src.index("{", start)
    depth = 0
    while True:
        c = src[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        elif c == '"':
            i = src.index('"', i + 1)
            while src[i - 1] == "\\":
                i = src.index('"', i + 1)
        elif c == "'":
            i = src.index("'", i + 2 if src[i + 1] == "\\" else i + 1)
        elif src.startswith("//", i):
            i = src.index("\n", i)
        i += 1


def drop_member(src, pattern):
    removed = 0
    while True:
        m = re.search(r"^[ \t]*" + pattern, src, re.M)
        if not m:
            return src, removed
        end = block_end(src, m.start())
        # take the leading comment block with it
        start = m.start()
        while True:
            prev = src.rfind("\n", 0, start - 1)
            line = src[prev + 1:start - 1] if prev >= 0 else ""
            if line.strip().startswith("//"):
                start = prev + 1
            else:
                break
        src = src[:start] + src[end:].lstrip("\n")
        removed += 1


def main(inp, out):
    src = open(inp, encoding="utf8").read()

    # The bridge handshake is the only part of BVD's constructor that vanilla's
    # constructor does not already do.
    ctor = re.search(r"public CarController\(BaseVehicle vehicle\) \{", src)
    ctor_body = src[ctor.end():block_end(src, ctor.start()) - 1]
    handshake = ctor_body[:ctor_body.index("this.loadLUATables();")]

    for pat in DROP_METHODS:
        src, n = drop_member(src, pat)
        if n == 0:
            sys.exit("gen_bvdcar: member not found: " + pat)

    # Nested classes keep their own fields; only the outer class is rewritten.
    nested_at = src.index("   public static final class BulletVariables")
    src, nested = src[:nested_at], src[nested_at:]
    for f in VANILLA_PUBLIC_FIELDS:
        src, n = re.subn(r"^[ \t]*public [\w.<>\[\] ]*\b" + f + r"\b\s*(=[^;]*)?;\n", "", src, count=1, flags=re.M)
        if n != 1:
            sys.exit("gen_bvdcar: field declaration not found: " + f)
        src = re.sub(r"\bthis\." + f + r"\b", "this.cc." + f, src)
    src = re.sub(r"^[ \t]*public static CarController\.GearInfo\[\] gears[^\n]*\n", "", src, flags=re.M)
    # Another vehicle's controller is driven by its own companion.
    src = re.sub(r"(\w+)\.getController\(\)\.shouldBeActive\(\)", r"Hooks.shouldBeActive(\1.getController())", src)
    src += nested

    for n in OWN_NESTED:
        src = src.replace("CarController." + n, "BvdCar." + n)
    # BVD's tyre-mark slots live in Splat under ZombieBuddy (vanilla's
    # IsoFloorBloodSplat has no such constants).
    src = src.replace("zombie.iso.IsoFloorBloodSplat.BVD_TIREMARK_", "Splat.TIREMARK_")
    # BVD's patched WorldSimulation owns massScaler; under ZombieBuddy it is BvdWorld's.
    src = src.replace("WorldSimulation.instance.massScaler", "BvdWorld.massScaler")

    src = src.replace("package zombie.core.physics;",
                      "// GENERATED by zb/gen_bvdcar.py from BVD's patched CarController.java.\n"
                      "// Do not edit by hand: change the Necroid patch and regenerate.\n"
                      "package bvd.zb;\n\n"
                      "import zombie.core.physics.Bullet;\n"
                      "import zombie.core.physics.CarController;\n"
                      "import zombie.core.physics.Transform;", 1)
    cls = "public final class CarController {"
    assert src.count(cls) == 1
    src = src.replace(cls,
                      "public final class BvdCar {\n"
                      "   // The vanilla controller this companion drives.\n"
                      "   final CarController cc;\n\n"
                      "   BvdCar(CarController cc) {\n"
                      "      this.cc = cc;\n"
                      + handshake.rstrip() + "\n\n"
                      "      this.loadLUATables();\n"
                      "   }\n", 1)
    if "CarController(" in src.replace("BvdCar(CarController cc)", ""):
        sys.exit("gen_bvdcar: stray CarController constructor reference")
    open(out, "w", encoding="utf8", newline="\n").write(src)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
