import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
const root=path.resolve(import.meta.dirname,'..');
const cache=path.join(root,'build/native-toolchain');fs.mkdirSync(cache,{recursive:true});
const base='https://download.qt.io/online/qtsdkrepository/windows_x86/desktop/';
async function get(url){const r=await fetch(url,{signal:AbortSignal.timeout(300000)});if(!r.ok)throw Error(`${r.status}: ${url}`);return Buffer.from(await r.arrayBuffer());}
const yamlSource=path.join(cache,'yaml-cpp');
const webview=path.join(cache,'webview2');
if(!process.argv.includes('--list')&&!fs.existsSync(path.join(webview,'build/native/include/WebView2.h'))){
  const archive=path.join(cache,'webview2.zip');if(!fs.existsSync(archive))fs.writeFileSync(archive,await get('https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/1.0.4370.26/microsoft.web.webview2.1.0.4370.26.nupkg'));
  if(crypto.createHash('sha256').update(fs.readFileSync(archive)).digest('hex')!=='1c0dacac84b70109b3fd42f90c53a0ba942abc3a87590d7a4e0ccd86e4a06cf4')throw Error('WebView2 SDK digest mismatch');
  fs.mkdirSync(webview,{recursive:true});execFileSync('tar.exe',['-xf',archive,'-C',webview]);
}
if(!process.argv.includes('--list')&&!fs.existsSync(path.join(yamlSource,'CMakeLists.txt'))){
  const archive=path.join(cache,'yaml-cpp.tar.gz');if(!fs.existsSync(archive))fs.writeFileSync(archive,await get('https://api.github.com/repos/jbeder/yaml-cpp/tarball/0.8.0'));
  const digest=crypto.createHash('sha256').update(fs.readFileSync(archive)).digest('hex');
  if(digest!=='46c4f7f574c1ee0975406144624088f7ff775667a163591dbc942d315bf0c77a')throw Error('yaml-cpp source digest mismatch');
  fs.mkdirSync(yamlSource,{recursive:true});execFileSync('tar.exe',['-xf',archive,'-C',yamlSource,'--strip-components=1']);
}
if(process.argv.includes('--list')){console.log((await get(base)).toString());process.exit(0);}
const version=process.env.HEXAGON_QT_VERSION||'6102';
const repository=base+'qt6_'+version+'/qt6_'+version+'/';
const xml=(await get(repository+'Updates.xml')).toString();
fs.writeFileSync(path.join(cache,'Updates.xml'),xml);
const tag=(s,n)=>s.match(new RegExp(`<${n}>([\\s\\S]*?)</${n}>`))?.[1]||'';
const packages=[...xml.matchAll(/<PackageUpdate>([\s\S]*?)<\/PackageUpdate>/g)].map(m=>m[1]);
const pkg=packages.find(p=>tag(p,'Name')===`qt.qt6.${version}.win64_msvc2022_64`);
if(!pkg)throw Error('Qt MSVC package not found: '+packages.map(p=>tag(p,'Name')).join(','));
const dir=path.join(cache,'Qt');fs.mkdirSync(dir,{recursive:true});
const seven=path.join(root,'build/linux-runtime/7zip-full/7z.exe');
if(!fs.existsSync(seven))throw Error('Build the Linux runtime first to provision the portable 7-Zip build tool.');
for(const archive of tag(pkg,'DownloadableArchives').split(',').map(a=>a.trim()).filter(a=>/qtbase|qtsvg|qttools/.test(a))){
  const url=repository+tag(pkg,'Name')+'/'+tag(pkg,'Version')+archive;
  const dest=path.join(cache,archive);
  console.log('Qt component:',archive);
  if(!fs.existsSync(dest))fs.writeFileSync(dest,await get(url));
  const expected=(await get(url+'.sha1')).toString().trim().split(/\s/)[0];
  if(crypto.createHash('sha1').update(fs.readFileSync(dest)).digest('hex')!==expected)throw Error('Qt archive checksum mismatch');
  execFileSync(seven,['x','-y','-o'+dir,dest],{stdio:'ignore'});
}
console.log('Qt extracted:',dir);
