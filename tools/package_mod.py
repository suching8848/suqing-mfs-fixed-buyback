import csv
import hashlib
import json
import re
from pathlib import Path
import zipfile

root=Path(__file__).resolve().parent.parent
mod=root/'mod/SuQingMFSFixedBuyback_4221'
manifest=json.loads((root/'docs/catalog-manifest.json').read_text(encoding='utf-8-sig'))
(root/'validation').mkdir(exist_ok=True)
(root/'releases').mkdir(exist_ok=True)
with (root/'validation/完整收购价目表.csv').open('w',encoding='utf-8-sig',newline='') as f:
    writer=csv.writer(f)
    writer.writerow(['物品ID','名称','分类','单件交易币'])
    for row in manifest['records']:
        writer.writerow([row['itemType'],row['displayName'],row['category'],row['price']])
info=(mod/'42/mod.info').read_text(encoding='utf-8-sig')
version=re.search(r'^modversion=(\d+\.\d+\.\d+)\s*$',info,re.M).group(1)
archive=root/f'releases/SuQingMFSFixedBuyback_4221_v{version}.zip'
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED) as out:
    for path in sorted(mod.rglob('*')):
        out.write(path,path.relative_to(mod.parent).as_posix())
files={p.relative_to(mod).as_posix():{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(mod.rglob('*')) if p.is_file()}
with zipfile.ZipFile(archive) as verify:
    if verify.testzip(): raise RuntimeError('Package CRC failed')
result={'mod_id':'SuQingMFSFixedBuyback_4221','version':version,'files':files,'archive':str(archive),
        'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'archive_crc_passed':True}
(root/'validation/package_manifest.json').write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps({'files':len(files),'archive':str(archive),'bytes':archive.stat().st_size,'crc':True},ensure_ascii=False))
