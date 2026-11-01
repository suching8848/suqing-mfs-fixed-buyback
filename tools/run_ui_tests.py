"""Execute actual MFS/SFB client Lua with UI doubles in the game's Kahlua VM."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-root", type=Path, required=True)
    parser.add_argument("--mfs-media", type=Path, required=True)
    args = parser.parse_args()
    game = args.game_root.resolve()
    mfs = args.mfs_media.resolve()
    shared = REPO / "mod/SuQingMFSFixedBuyback_4221/42/media/lua/shared/SuQingMFSFixedBuyback"
    client = REPO / "mod/SuQingMFSFixedBuyback_4221/42/media/lua/client/SFB_UI.lua"
    sources = [REPO / "tests/ui_prelude.lua", mfs / "lua/client/UI/risky_trade.lua",
               shared / "Catalog.lua", shared / "Core.lua", client, REPO / "tests/ui_assertions.lua"]
    required = sources + [game / "jre64/bin/java.exe", game / "projectzomboid.jar",
                          REPO / "validation/KahluaValidation.class"]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        parser.error("Required local runtime/source missing: " + ", ".join(missing))
    hashes_before = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
    command = [str(game / "jre64/bin/java.exe"), "-cp",
               os.pathsep.join((str(game / "projectzomboid.jar"), str(REPO / "validation"))),
               "KahluaValidation", *map(str, sources)]
    # Kahlua loads the game's stdlib.lua relative to the process directory.
    result = subprocess.run(command, cwd=game, capture_output=True, text=True,
                            encoding="utf-8", errors="replace", timeout=90)
    log = result.stdout + result.stderr
    source_changed = any(hashlib.sha256(path.read_bytes()).hexdigest() != digest
                         for path, digest in hashes_before.items())
    cases = []
    for line in log.splitlines():
        marker = line.find("SFB_UI_TEST|")
        if marker >= 0:
            _, name, status, detail = line[marker:].split("|", 3)
            cases.append({"name": name, "passed": status == "PASS", "detail": detail})
    report = {
        "offline_only": True,
        "ui_rendering_validated": False,
        "game_runtime_validated": False,
        "runtime": "Bundled Project Zomboid JRE; projectzomboid.jar Kahlua",
        "limitations": ["Native UI controls, drawing, fonts and mouse delivery are doubles.",
                        "P.GetRows/P.GetEligibleCount are authoritative-shaped UI stand-ins; backend tests are separate.",
                        "No game was launched and no installed mod was changed."],
        "exitCode": result.returncode,
        "passed": result.returncode == 0 and len(cases) > 0 and not source_changed
                  and all(case["passed"] for case in cases),
        "caseCount": len(cases),
        "failedCount": sum(not case["passed"] for case in cases),
        "sourceChangedDuringRun": source_changed,
        "cases": cases,
        "sourceHashes": [{"path": str(path), "sha256": digest}
                         for path, digest in hashes_before.items()],
        "output": log,
    }
    output = REPO / "validation/ui_report.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("passed", "offline_only", "caseCount", "failedCount", "exitCode")}, ensure_ascii=False))
    for case in cases:
        if not case["passed"]:
            print(case["name"] + ": " + case["detail"])
    if not cases:
        print(log[-6000:])
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
