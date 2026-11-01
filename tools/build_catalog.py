"""Build the reviewed B42 fixed-buyback whitelist from local vanilla evidence.

The names below are the complete allowlist. Source-script and translation reads
validate those names; they never discover additional sellable runtime items.
Run with --check to verify checked-in output without changing files.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
LUA_OUTPUT = REPO / "mod/SuQingMFSFixedBuyback_4221/42/media/lua/shared/SuQingMFSFixedBuyback/Catalog.lua"
MANIFEST_OUTPUT = REPO / "docs/catalog-manifest.json"

# Explicit, reviewed vanilla item IDs. These groups are build-time data only.
# A gem-set item appears only in the 800-price group, never in its metal group.
GROUPS = (
    ("currency", 10, "currency", "Money"),
    ("currency", 1000, "currency", "MoneyBundle"),
    ("currency", 50, "currency", "SilverCoin"),
    ("currency", 250, "currency", "GoldCoin"),
    ("jewelry", 100, "silver", """
        Necklace_Silver Necklace_SilverCrucifix NecklaceLong_Silver
        NoseRing_Silver NoseStud_Silver
        Earring_LoopLrg_Silver Earring_LoopMed_Silver
        Earring_LoopSmall_Silver_Both Earring_LoopSmall_Silver_Top Earring_Stud_Silver
        Ring_Right_MiddleFinger_Silver Ring_Left_MiddleFinger_Silver
        Ring_Right_RingFinger_Silver Ring_Left_RingFinger_Silver
        Bracelet_BangleRightSilver Bracelet_BangleLeftSilver
        Bracelet_ChainRightSilver Bracelet_ChainLeftSilver
        BellyButton_DangleSilver BellyButton_RingSilver BellyButton_StudSilver
    """),
    ("jewelry", 300, "gold", """
        Necklace_Gold NecklaceLong_Gold NoseRing_Gold NoseStud_Gold
        Earring_LoopLrg_Gold Earring_LoopMed_Gold
        Earring_LoopSmall_Gold_Both Earring_LoopSmall_Gold_Top Earring_Stud_Gold
        Ring_Right_MiddleFinger_Gold Ring_Left_MiddleFinger_Gold
        Ring_Right_RingFinger_Gold Ring_Left_RingFinger_Gold
        Bracelet_BangleRightGold Bracelet_BangleLeftGold
        Bracelet_ChainRightGold Bracelet_ChainLeftGold
        BellyButton_DangleGold BellyButton_RingGold BellyButton_StudGold
        Ring_Right_MiddleFinger_Signet Ring_Left_MiddleFinger_Signet
        Ring_Right_RingFinger_Signet Ring_Left_RingFinger_Signet
    """),
    ("jewelry", 800, "gem_set", """
        Necklace_GoldRuby Necklace_GoldDiamond Necklace_SilverSapphire
        Necklace_SilverDiamond Necklace_Pearl
        NecklaceLong_GoldDiamond NecklaceLong_SilverEmerald
        NecklaceLong_SilverSapphire NecklaceLong_SilverDiamond NecklaceLong_Amber
        Necklace_Choker_Sapphire Necklace_Choker_Amber Necklace_Choker_Diamond
        Earring_Stone_Sapphire Earring_Stone_Emerald Earring_Stone_Ruby Earring_Pearl
        Earring_Dangly_Sapphire Earring_Dangly_Emerald Earring_Dangly_Ruby
        Earring_Dangly_Diamond Earring_Dangly_Pearl
        Ring_Right_MiddleFinger_SilverDiamond Ring_Left_MiddleFinger_SilverDiamond
        Ring_Right_RingFinger_SilverDiamond Ring_Left_RingFinger_SilverDiamond
        Ring_Right_MiddleFinger_GoldRuby Ring_Left_MiddleFinger_GoldRuby
        Ring_Right_RingFinger_GoldRuby Ring_Left_RingFinger_GoldRuby
        Ring_Right_MiddleFinger_GoldDiamond Ring_Left_MiddleFinger_GoldDiamond
        Ring_Right_RingFinger_GoldDiamond Ring_Left_RingFinger_GoldDiamond
        BellyButton_DangleGoldRuby BellyButton_DangleSilverDiamond
        BellyButton_RingGoldDiamond BellyButton_RingGoldRuby
        BellyButton_RingSilverAmethyst BellyButton_RingSilverDiamond
        BellyButton_RingSilverRuby BellyButton_StudGoldDiamond BellyButton_StudSilverDiamond
    """),
    ("gems", 1000, "loose_gem", "Diamond Ruby Emerald Sapphire Amethyst"),
    ("watches", 100, "watch", """
        WristWatch_Right_ClassicBlack WristWatch_Left_ClassicBlack
        WristWatch_Right_ClassicBrown WristWatch_Left_ClassicBrown
        WristWatch_Right_DigitalBlack WristWatch_Left_DigitalBlack
        WristWatch_Right_DigitalRed WristWatch_Left_DigitalRed
        WristWatch_Right_DigitalDress WristWatch_Left_DigitalDress
    """),
    ("watches", 150, "watch", "WristWatch_Right_ClassicMilitary WristWatch_Left_ClassicMilitary"),
    ("watches", 300, "watch", "WristWatch_Right_ClassicGold WristWatch_Left_ClassicGold Pocketwatch"),
    ("watches", 500, "watch", "WristWatch_Right_Expensive WristWatch_Left_Expensive"),
    ("metals", 25, "metal", "GoldScrap"),
    ("metals", 5, "metal", "SilverScrap"),
    ("metals", 250, "metal", "GoldSheet"),
    ("metals", 50, "metal", "SilverSheet"),
    ("metals", 8000, "metal", "GoldBar"),
    ("metals", 800, "metal", "SilverBar"),
    ("metals", 1000, "metal", "SmallGoldBar"),
    ("metals", 100, "metal", "SmallSilverBar"),
)

# Explicit compatibility names may be included only if a current script exists.
# This build retains neither stale translation-only wedding-ring name.
OPTIONAL_WEDDING_RINGS = ("WeddingRing_Man", "WeddingRing_Woman")

EXCLUDED_GROUPS = {
    "Material is not established as precious metal or gemstone": """
        Locket Necklace_Crucifix Necklace_YingYang Medal_Gold Medal_Silver Medal_Bronze
    """,
    "Plain or nonvaluable accessory": """
        Necklace_DogTag Necklace_DogTag_Female Necklace_DogTag_Male Necklace_Choker
        Bracelet_RightFriendshipTINT Bracelet_LeftFriendshipTINT
    """,
    "Animal bone, teeth, skull, or tusk": """
        Necklace_Teeth NecklaceLong_Teeth Necklace_SkullMammal NecklaceLong_SkullMammal
        Necklace_SkullMammal_Multi NecklaceLong_SkullMammal_Multi
        Necklace_SkullSmall NecklaceLong_SkullSmall
        Necklace_SkullSmall_Multi NecklaceLong_SkullSmall_Multi
        Necklace_BoarTusk Necklace_BoarTusk_Multi Earring_BirdSkull Earring_BoarTusk
        Necklace_Choker_Bone
    """,
    "Keyring is outside the approved jewelry scope": """
        KeyRing KeyRing_Forged_Gold KeyRing_Forged_Silver
    """,
    "Food is never jewelry": "FriedOnionRings FriedOnionRingsCraft",
    "Household alarm clock is not a watch": "AlarmClock2",
}

EXPECTED_COUNTS = {"currency": 4, "jewelry": 88, "gems": 5, "watches": 17, "metals": 8}
SOURCE_FIELDS = ("ItemType", "DisplayCategory", "Tags", "Icon", "ClothingItem", "BodyLocation", "Weight")
ITEM_PATTERN = re.compile(r"^[ \t]*item[ \t]+([A-Za-z0-9_]+)[ \t]*\r?\n[ \t]*\{", re.MULTILINE)


def read_items(game_root: Path) -> dict[str, dict]:
    items: dict[str, dict] = {}
    for path in sorted((game_root / "media/scripts/generated/items").glob("*.txt")):
        source = path.read_text(encoding="utf-8-sig")
        if not re.search(r"\bmodule\s+Base\b", source):
            continue
        for match in ITEM_PATTERN.finditer(source):
            item_type = "Base." + match.group(1)
            position, depth = match.end(), 1
            while depth and position < len(source):
                char = source[position]
                depth += (char == "{") - (char == "}")
                position += 1
            if depth:
                raise ValueError(f"Unclosed item block: {path}:{item_type}")
            body = source[match.end():position - 1]
            fields = {}
            for key, value in re.findall(r"^[ \t]*(\w+)[ \t]*=[ \t]*([^\r\n]*)", body, re.MULTILINE):
                fields[key] = value.rstrip().removesuffix(",").strip()
            definition = {
                "source": path.relative_to(game_root).as_posix(),
                "line": source.count("\n", 0, match.start()) + 1,
                "properties": {key: fields[key] for key in SOURCE_FIELDS if key in fields},
                "obsolete": fields.get("Obsolete", "false").lower() == "true",
            }
            if item_type in items:
                # Some unrelated vanilla seeds have duplicate generated entries.
                # Refuse ambiguity only if that ID is selected for this catalog.
                items[item_type].setdefault("duplicateSources", []).append(definition)
            else:
                items[item_type] = definition
    if not items:
        raise ValueError("No generated vanilla items found; supply --game-root")
    return items


def validate_classification(name: str, kind: str, item: dict) -> str:
    """Verify the reviewed material decision; never select an item by substring."""
    props = item["properties"]
    tags = props.get("Tags", "").lower()
    if item["obsolete"]:
        raise ValueError(f"Obsolete item cannot enter catalog: {name}")
    if kind == "gold":
        if "base:tinygoldscrap" in tags:
            return "Vanilla TinyGoldScrap material tag"
        if name.endswith("_Signet") and props.get("Icon") == "Ring_Gold_Signet":
            return "Reviewed signet ring; vanilla Icon=Ring_Gold_Signet"
        raise ValueError(f"Missing gold evidence: {name}")
    if kind == "silver":
        if "base:tinysilverscrap" not in tags:
            raise ValueError(f"Missing silver evidence: {name}")
        return "Vanilla TinySilverScrap material tag"
    if kind == "gem_set":
        if not any(gem in name for gem in ("Diamond", "Ruby", "Emerald", "Sapphire", "Amethyst", "Pearl", "Amber")):
            raise ValueError(f"Missing gem, pearl, or amber evidence: {name}")
        return "Reviewed gemstone, pearl, or amber jewelry ID and Chinese item name"
    if kind == "watch":
        expected = "base:alarmclock" if name == "Pocketwatch" else "base:alarmclockclothing"
        if props.get("ItemType") != expected:
            raise ValueError(f"Unexpected watch type: {name}")
        return "Explicit watch ID and vanilla alarm-clock item type"
    if props.get("ItemType") != "base:normal":
        raise ValueError(f"Unexpected ordinary item type: {name}")
    return {"currency": "Reviewed currency ID and Chinese item name",
            "metal": "Reviewed precious-metal ID and Chinese item name",
            "loose_gem": "Reviewed loose-gem ID and Chinese item name"}[kind]


def build(game_root: Path) -> tuple[str, str]:
    items = read_items(game_root)
    translation_path = game_root / "media/lua/shared/Translate/CN/ItemName.json"
    translations = json.loads(translation_path.read_text(encoding="utf-8-sig"))
    records: list[dict] = []
    evidence: list[dict] = []
    seen: set[str] = set()
    source_paths = {translation_path}

    def add(name: str, category: str, price: int, kind: str) -> None:
        item_type = "Base." + name
        if item_type in seen:
            raise ValueError(f"Duplicate catalog entry: {item_type}")
        if item_type not in items:
            raise ValueError(f"Unknown vanilla item: {item_type}")
        if item_type not in translations:
            raise ValueError(f"Missing Chinese item name: {item_type}")
        if not isinstance(price, int) or isinstance(price, bool) or price < 1:
            raise ValueError(f"Invalid fixed price: {item_type}")
        item = items[item_type]
        if item.get("duplicateSources"):
            raise ValueError(f"Ambiguous vanilla item definition: {item_type}")
        reason = validate_classification(name, kind, item)
        record = {"itemType": item_type, "category": category, "price": price,
                  "displayName": translations[item_type]}
        records.append(record)
        evidence.append({**record, **item, "classification": kind, "reason": reason})
        seen.add(item_type)
        source_paths.add(game_root / item["source"])

    for category, price, kind, names in GROUPS:
        for name in names.split():
            add(name, category, price, kind)

    optional = []
    for name in OPTIONAL_WEDDING_RINGS:
        exists = "Base." + name in items
        if exists:
            # An appearance in translation alone never creates a valid item.
            add(name, "jewelry", 300, "gold")
        optional.append({"itemType": "Base." + name, "scriptExists": exists,
                         "translationExists": "Base." + name in translations,
                         "included": exists,
                         "reason": "Current script required; translation-only legacy name is not eligible"})

    exclusions = []
    for reason, names in EXCLUDED_GROUPS.items():
        for name in names.split():
            item_type = "Base." + name
            if item_type in seen:
                raise ValueError(f"Excluded item leaked into catalog: {item_type}")
            if item_type not in items:
                raise ValueError(f"Audited exclusion no longer exists: {item_type}")
            exclusions.append({"itemType": item_type, "reason": reason})

    records.sort(key=lambda row: row["itemType"])
    evidence.sort(key=lambda row: row["itemType"])
    counts = dict(sorted(Counter(row["category"] for row in records).items()))
    expected = dict(EXPECTED_COUNTS)
    expected["jewelry"] += sum(entry["included"] for entry in optional)
    if counts != dict(sorted(expected.items())):
        raise ValueError(f"Whitelist coverage changed: {counts}; expected {expected}")
    vanilla_watch_ids = {item_type for item_type, data in items.items()
                         if data["properties"].get("ItemType") == "base:alarmclockclothing"}
    catalog_watch_ids = {row["itemType"] for row in records if row["category"] == "watches"}
    if catalog_watch_ids != vanilla_watch_ids | {"Base.Pocketwatch"}:
        raise ValueError("Current watch coverage is incomplete or contains a non-watch")
    for forbidden in ("OnionRings", "KeyRing", "DogTag", "Skull", "Teeth", "Tusk", "Friendship", "Bone"):
        if any(forbidden in row["itemType"] for row in records):
            raise ValueError(f"Nonvaluable item entered fixed whitelist: {forbidden}")

    lua_lines = [
        "-- Generated by tools/build_catalog.py from reviewed vanilla Build 42 IDs.",
        "-- Fixed allowlist only. No runtime name, substring, or inventory discovery.",
        "SuQingMFSFixedBuyback = SuQingMFSFixedBuyback or {}",
        "local P = SuQingMFSFixedBuyback",
        "P.Catalog = {",
    ]
    for row in records:
        lua_lines.append("    { itemType = %s, category = %s, price = %d, displayName = %s }," % (
            json.dumps(row["itemType"]), json.dumps(row["category"]), row["price"],
            json.dumps(row["displayName"], ensure_ascii=False)))
    lua_lines.extend(("}", "return P.Catalog", ""))
    lua_text = "\n".join(lua_lines)
    manifest = {
        "schemaVersion": 1,
        "catalogCount": len(records),
        "categoryCounts": counts,
        "order": "itemType ascending; case-sensitive",
        "catalogSha256": hashlib.sha256(lua_text.encode("utf-8")).hexdigest(),
        "sources": [{"path": path.relative_to(game_root).as_posix(),
                     "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                    for path in sorted(source_paths)],
        "records": evidence,
        "optionalLegacyNames": optional,
        "auditedExclusions": sorted(exclusions, key=lambda row: row["itemType"]),
    }
    return lua_text, json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-root", type=Path, required=True,
                        help="Project Zomboid directory containing media/scripts/generated/items")
    parser.add_argument("--check", action="store_true", help="Check output without writing")
    args = parser.parse_args()
    try:
        lua_text, manifest_text = build(args.game_root.resolve())
        outputs = ((LUA_OUTPUT, lua_text), (MANIFEST_OUTPUT, manifest_text))
        if args.check:
            stale = [str(path.relative_to(REPO)) for path, text in outputs
                     if not path.exists() or path.read_bytes() != text.encode("utf-8")]
            if stale:
                raise ValueError("Generated output is missing or stale: " + ", ".join(stale))
        else:
            for path, text in outputs:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(text.encode("utf-8"))
    except (OSError, ValueError) as error:
        print(f"Catalog validation failed: {error}", file=sys.stderr)
        return 1
    summary = json.loads(manifest_text)
    print(json.dumps({"ok": True, "checkedOnly": args.check,
                      "catalogCount": summary["catalogCount"],
                      "categoryCounts": summary["categoryCounts"]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
