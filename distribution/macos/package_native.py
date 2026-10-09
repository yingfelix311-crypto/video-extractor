"""Package the exact installed native app; never copy user/backend data."""
from pathlib import Path
import argparse,hashlib,json,plistlib,subprocess,shutil,zipfile
ROOT=Path(__file__).resolve().parents[2]
def digest(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def inventory(root):
 return {p.relative_to(root).as_posix():digest(p) for p in sorted(root.rglob('*')) if p.is_file()}
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--app',type=Path,required=True);parser.add_argument('--runtime-root',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
 app=args.app;info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
 if info['CFBundleIdentifier']!='local.felix.shouxia' or info['CFBundleExecutable']!='Shouxia':raise ValueError('Only the original native app may be distributed')
 if (app/'Contents/Frameworks/Electron Framework.framework').exists():raise ValueError('Electron client is not the original app')
 subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
 output=args.output;output.mkdir(parents=True,exist_ok=True);name='Video-Extractor-Native-1.0.0-macOS-arm64';bundle=output/name
 if bundle.exists():raise ValueError('Output bundle already exists; choose a new output directory')
 bundle.mkdir();subprocess.run(['ditto',str(app),str(bundle/'Video Extractor.app')],check=True)
 if inventory(app)!=inventory(bundle/'Video Extractor.app'):raise ValueError('Native app files differ from installed original')
 subprocess.run(['codesign','--verify','--deep','--strict',str(bundle/'Video Extractor.app')],check=True)
 for name_ in ['安装原版.command','runtime.env','preflight.sh']:
  shutil.copy2(ROOT/'distribution/macos'/name_,bundle/name_)
 shutil.copy2(ROOT/'docs/INSTALL-MAC.md',bundle/'安装说明.md')
 runtime=bundle/'runtime';(runtime/'bin').mkdir(parents=True)
 for tool,version in [('colima','0.10.3'),('docker','29.8.2'),('limactl','2.2.0')]:
  source=args.runtime_root/'bin'/tool;flags=['--version'] if tool!='colima' else ['version'];reported=subprocess.check_output([str(source),*flags],text=True,stderr=subprocess.STDOUT)
  if version not in reported:raise ValueError(f'Unexpected {tool} version: {reported}')
  shutil.copy2(source,runtime/'bin'/tool)
 shutil.copytree(args.runtime_root/'share/lima',runtime/'share/lima')
 shutil.copytree(ROOT/'distribution/macos/licenses',bundle/'licenses')
 files=inventory(runtime);(bundle/'runtime-files.txt').write_text('\n'.join(files)+'\n')
 manifest={'product':'original SwiftUI/AVFoundation app','version':info['CFBundleShortVersionString'],'sourceCommit':subprocess.check_output(['git','rev-parse','origin/main'],cwd=ROOT,text=True).strip(),'originalAppFiles':inventory(app),'runtimeFiles':files,'backend':'fixed digest in runtime.env; no container state, VM disk, user history, cookies, subscriptions or downloaded videos included','status':'private prerelease, ad-hoc signed, not notarized; clean-Mac end-to-end verification required'}
 (bundle/'ORIGINAL-MANIFEST.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 sums=inventory(bundle);(bundle/'SHA256SUMS.txt').write_text('\n'.join(f'{value}  {file}' for file,value in sums.items())+'\n')
 archive=output/(name+'.zip')
 subprocess.run(['ditto','-c','-k','--keepParent',str(bundle),str(archive)],check=True)
 (output/'SHA256SUMS.txt').write_text(digest(archive)+'  '+archive.name+'\n')
 shutil.copy2(ROOT/'docs/INSTALL-MAC.md',output/'INSTALL.md')
 shutil.copy2(bundle/'ORIGINAL-MANIFEST.json',output/'ORIGINAL-MANIFEST.json')
 print('Original bundle byte-for-byte verification passed:',len(manifest['originalAppFiles']),'files')
 print('Installer archive:',archive)
if __name__=='__main__':main()
