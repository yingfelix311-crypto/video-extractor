from pathlib import Path
import subprocess,unittest,tempfile,shutil,hashlib,sys,os
ROOT=Path(__file__).resolve().parents[2]
SCRIPT=ROOT/'distribution/macos/安装原版.command'
class InstallerTests(unittest.TestCase):
 def test_plan_requires_no_payload_or_environment_changes(self):
  result=subprocess.run(['bash',str(SCRIPT),'--plan'],text=True,capture_output=True)
  self.assertEqual(result.returncode,0,result.stderr)
  for expected in ['SwiftUI','2 CPU','2 GiB','127.0.0.1:8081','不导入','Windows']:
   self.assertIn(expected,result.stdout)
 def test_unknown_argument_stops_before_install(self):
  result=subprocess.run(['bash',str(SCRIPT),'--invalid'],text=True,capture_output=True)
  self.assertEqual(result.returncode,2)
  self.assertIn('不支持的参数',result.stderr)
 def test_unbuilt_payload_stops_before_any_tool_is_run(self):
  result=subprocess.run(['bash',str(SCRIPT),'--verify-only'],text=True,capture_output=True)
  self.assertNotEqual(result.returncode,0)
  self.assertIn('安装包不完整',result.stderr)
class PreflightTests(unittest.TestCase):
 def run_check(self,command,*args):
  return subprocess.run(['bash','-c','source "$1"; '+command+' "${@:2}"','test',str(ROOT/'distribution/macos/preflight.sh'),*map(str,args)],capture_output=True,text=True,errors="replace")
 def test_conflicting_runtime_is_not_modified(self):
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder).resolve();base=root/'bundle';home=root/'user';(base/'runtime/bin').mkdir(parents=True);(home/'.local/bin').mkdir(parents=True)
   (base/'runtime/bin/docker').write_bytes(b'new');old=home/'.local/bin/docker';old.write_bytes(b'existing');(base/'runtime-files.txt').write_text('bin/docker\n')
   result=self.run_check('runtime_preflight',base,home);self.assertNotEqual(result.returncode,0);self.assertEqual(old.read_bytes(),b'existing')
 def test_matching_runtime_is_reused(self):
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder).resolve();base=root/'bundle';home=root/'user';(base/'runtime/bin').mkdir(parents=True);(home/'.local/bin').mkdir(parents=True)
   for file in [base/'runtime/bin/docker',home/'.local/bin/docker']:file.write_bytes(b'same')
   (base/'runtime-files.txt').write_text('bin/docker\n');self.assertEqual(self.run_check('runtime_preflight',base,home).returncode,0)
 def test_conflicting_profile_is_not_modified(self):
  with tempfile.TemporaryDirectory() as folder:
   p=Path(folder)/'colima.yaml';original='cpu: 8\nmemory: 8\ndisk: 20\n';p.write_text(original)
   self.assertNotEqual(self.run_check('profile_preflight',p).returncode,0);self.assertEqual(p.read_text(),original)
 def test_backend_journal_only_resumes_the_recorded_container(self):
  with tempfile.TemporaryDirectory() as folder:
   marker=Path(folder)/'pending';marker.write_text('a'*64+'\n')
   self.assertEqual(self.run_check('init_journal_matches',marker,'a'*64).returncode,0)
   self.assertNotEqual(self.run_check('init_journal_matches',marker,'b'*64).returncode,0)
   self.assertEqual(marker.read_text(),'a'*64+'\n')
 def test_missing_journal_never_claims_ownership(self):
  with tempfile.TemporaryDirectory() as folder:
   self.assertNotEqual(self.run_check('init_journal_matches',Path(folder)/'missing','a'*64).returncode,0)
 def test_compatible_profile_passes(self):
  with tempfile.TemporaryDirectory() as folder:
   p=Path(folder)/'colima.yaml';p.write_text('cpu: 2\nmemory: 2\ndisk: 20\narch: aarch64\nvmType: vz\nmountType: virtiofs\nruntime: docker\n')
   self.assertEqual(self.run_check('profile_preflight',p).returncode,0)
class RecoveryFlowTests(unittest.TestCase):
 def run_case(self,owned):
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder).resolve();base=root/'bundle';home=root/'user';base.mkdir();(base/'runtime/bin').mkdir(parents=True)
   app=Path('/Users/felix/Applications/Video Extractor.app')
   if not app.exists():self.skipTest('Original app fixture unavailable')
   shutil.copytree(app,base/'Video Extractor.app')
   for name in ['runtime.env','preflight.sh','backend_setup.py']:shutil.copy2(ROOT/'distribution/macos'/name,base/name)
   shutil.copytree(ROOT/'Shouxia/BackendPlugins',base/'BackendPlugins')
   script=(ROOT/'distribution/macos/安装原版.command').read_text().replace('install_home="$HOME"','install_home='+repr(str(home)))
   (base/'安装原版.command').write_text(script)
   tools=home/'.local/bin';tools.mkdir(parents=True)
   state=home/'test-state';state.mkdir();(state/'owner').write_text('1.0.0' if owned else '<no value>')
   docker_code=f"#!{sys.executable}\n"+"""import sys,pathlib
home=pathlib.Path(__file__).resolve().parents[2];state=home/'test-state';a=sys.argv[3:];command=a[0]
with (state/'calls').open('a') as f:f.write(' '.join(a)+'\\n')
if command=='inspect':
 fmt=a[a.index('--format')+1] if '--format' in a else ''
 if 'HostIp' in fmt:print('127.0.0.1:8081')
 elif 'Mounts' in fmt:print(home/'Downloads/MeTube')
 elif '.Id' in fmt:print('c'*64)
 elif 'Labels' in fmt:print((state/'owner').read_text())
elif command=='exec':
 if 'pip' in a:
  marker=state/'pip-attempted'
  if not marker.exists():marker.write_text('yes');sys.exit(7)
 else:print('2026.10.10.233141')
"""
   for name,code in [('docker',docker_code),('colima','#!/bin/bash\nexit 0\n'),('limactl','#!/bin/bash\nexit 0\n')]:
    (base/'runtime/bin'/name).write_text(code);(base/'runtime/bin'/name).chmod(0o755);shutil.copy2(base/'runtime/bin'/name,tools/name)
   for name in ['curl','open']:(tools/name).write_text('#!/bin/bash\nexit 0\n');(tools/name).chmod(0o755)
   (base/'runtime-files.txt').write_text('bin/docker\nbin/colima\nbin/limactl\n')
   profile=home/'.colima/metube/colima.yaml';profile.parent.mkdir(parents=True);profile.write_text('cpu: 2\nmemory: 2\ndisk: 20\narch: aarch64\nvmType: vz\nmountType: virtiofs\nruntime: docker\n')
   journal=home/'Library/Application Support/Shouxia/installer-state';journal.mkdir(parents=True)
   if owned:(journal/'backend-init.pending').write_text('c'*64+'\n')
   sums=[]
   for file in sorted(base.rglob('*')):
    if file.is_file():sums.append(hashlib.sha256(file.read_bytes()).hexdigest()+'  '+file.relative_to(base).as_posix())
   (base/'SHA256SUMS.txt').write_text('\n'.join(sums)+'\n')
   first=subprocess.run(['bash',str(base/'安装原版.command')],capture_output=True,text=True,errors="replace")
   if owned:
    self.assertNotEqual(first.returncode,0);self.assertTrue((journal/'backend-init.pending').exists());self.assertFalse((home/'Applications/Video Extractor.app').exists())
    second=subprocess.run(['bash',str(base/'安装原版.command')],capture_output=True,text=True,errors="replace")
    self.assertEqual(second.returncode,0,second.stdout+second.stderr);self.assertFalse((journal/'backend-init.pending').exists());self.assertEqual((journal/'backend-init.complete').read_text(),'c'*64+'\n')
    self.assertEqual((state/'calls').read_text().count('-m pip install'),2)
   else:
    self.assertEqual(first.returncode,0,first.stdout+first.stderr);self.assertNotIn('-m pip install',(state/'calls').read_text());self.assertFalse((state/'pip-attempted').exists())
 def test_interrupted_owned_container_resumes_pinned_initialization(self):self.run_case(True)
 def test_existing_user_container_never_has_engine_reinstalled(self):self.run_case(False)

if __name__=='__main__':unittest.main()
