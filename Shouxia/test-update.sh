#!/bin/sh
set -eu
cd "$(dirname "$0")"
swiftc -typecheck Sources/*.swift
python3 - <<'PY'
import re,pathlib,tempfile,json,shutil
source=pathlib.Path('Sources/EngineUpdater.swift').read_text()
scripts={name:code for name,code in re.findall(r'static let (\w+) = #"""\n(.*?)\n"""#',source,re.S)}
for code in scripts.values(): compile(code,'updater','exec')
with tempfile.TemporaryDirectory() as tmp:
 root=pathlib.Path(tmp); pkg=root/'yt_dlp'; staged=root/'staged'; meta=root/'wheel'/'yt_dlp-new.dist-info'; oldmeta=root/'yt_dlp-old.dist-info'; state=root/'state'
 for d in [pkg,staged,meta,oldmeta,state]: d.mkdir(parents=True)
 (pkg/'version.py').write_text('old'); (staged/'version.py').write_text('new'); (meta/'METADATA').write_text('new'); (oldmeta/'METADATA').write_text('old')
 (state/'stage.json').write_text(json.dumps({'package':str(pkg),'staged':str(staged),'metadata':str(meta)}))
 def run(name): exec(scripts[name].replace('/tmp/shouxia-engine-update',str(state)),{})
 run('installScript'); assert (pkg/'version.py').read_text()=='new'; assert not oldmeta.exists(); assert (root/meta.name/'METADATA').read_text()=='new'
 run('rollbackScript'); assert (pkg/'version.py').read_text()=='old'; assert oldmeta.exists(); assert not (root/meta.name).exists(); assert (state/'installing').exists()
 # Recovery must be repeatable until service restart is verified.
 run('rollbackScript'); assert (pkg/'version.py').read_text()=='old'
 (state/'installing').unlink()
 original=shutil.copytree
 def fail(*args,**kwargs): raise OSError('injected failure')
 shutil.copytree=fail
 try:
  try: run('installScript')
  except OSError: pass
  else: raise AssertionError('expected error')
 finally: shutil.copytree=original
 assert (pkg/'version.py').read_text()=='old'; assert not (state/'installing').exists()
 # Partial install failure is recovered from the complete journal.
 count=[0]
 def fail_install(*args,**kwargs):
  count[0]+=1
  if count[0]==4: raise OSError('partial install')
  return original(*args,**kwargs)
 shutil.copytree=fail_install
 try:
  try: run('installScript')
  except OSError: pass
 finally: shutil.copytree=original
 run('rollbackScript'); assert (pkg/'version.py').read_text()=='old'; assert (oldmeta/'METADATA').read_text()=='old'
print('Engine transaction: package + metadata, repeatable rollback, backup failure, partial install recovery passed')
PY
