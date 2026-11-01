from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description='Offline Kahlua trade checks; never launches the game client or opens a save.')
parser.add_argument('--game-root', type=Path, required=True)
parser.add_argument('--mfs-media', type=Path, required=True)
args = parser.parse_args()
game = args.game_root.resolve()
lua = root/'mod/SuQingMFSFixedBuyback_4221/42/media/lua'
trade = args.mfs_media.resolve()/'lua/shared/Trade/TradeShared.lua'
files = [root/'tests/backend_prelude.lua', trade, root/'tests/backend_baseline.lua',
         lua/'shared/SuQingMFSFixedBuyback/Catalog.lua', lua/'shared/SuQingMFSFixedBuyback/Core.lua',
         lua/'shared/SFB_Bootstrap.lua', lua/'server/SFB_Server.lua', root/'tests/backend_assertions.lua']
required = files + [game/'jre64/bin/java.exe', game/'projectzomboid.jar', root/'validation/KahluaValidation.class']
missing = [str(path) for path in required if not path.is_file()]
if missing:
    parser.error('Required local runtime/source missing: '+', '.join(missing))
(root/'validation').mkdir(exist_ok=True)
cmd = [str(game/'jre64/bin/java.exe'),'-cp',os.pathsep.join((str(game/'projectzomboid.jar'),str(root/'validation'))),'KahluaValidation',*map(str,files)]
run = subprocess.run(cmd,cwd=game,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=90)
output=run.stdout+run.stderr
(root/'validation/backend_result.txt').write_text(output,encoding='utf-8')
counts=re.search(r'BACKEND_PASS, (\d+)(?:\.0)?, (\d+)(?:\.0)?',output)
report={'pass':run.returncode==0 and counts is not None,'cases':int(counts[1]) if counts else None,'assertions':int(counts[2]) if counts else None,
        'runtime':'Actual installed Project Zomboid Kahlua VM with inventory/player/network fixtures',
        'offline_only':True,'gameplay_tested':False,'original_mfs_shared_source_executed':str(trade),
        'source_hashes':{str(p.relative_to(root)) if p.is_relative_to(root) else str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
(root/'validation/backend_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(output)
raise SystemExit(0 if report['pass'] else 1)
