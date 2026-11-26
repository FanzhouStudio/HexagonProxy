// Builds the offline Windows/QEMU runtime. No WSL, Docker daemon or Python required.
// Run with Node 22+, PowerShell 7 and Windows tar.exe. Outputs are intentionally ignored.
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const work = path.join(repo, 'build/linux-runtime');
const out = path.join(work, 'runtime');
fs.mkdirSync(out, {recursive:true});
const sha = (b, algorithm='sha256') => crypto.createHash(algorithm).update(b).digest('hex');
const sources = [];
async function download(url, name, expected) {
  const dest = path.join(work, name);
  if (!fs.existsSync(dest)) {
    console.log('Downloading', name);
    const response = await fetch(url, {signal:AbortSignal.timeout(300000)});
    if (!response.ok) throw new Error(`${response.status}: ${url}`);
    fs.writeFileSync(dest+'.partial', Buffer.from(await response.arrayBuffer()));
    fs.renameSync(dest+'.partial', dest);
  }
  const data = fs.readFileSync(dest);
  if (expected && sha(data, expected.length===128?'sha512':'sha256')!==expected) throw new Error('Digest mismatch: '+name);
  sources.push({url, file:name, sha256:sha(data)});
  return data;
}
function tarEntries(data) {
  const result=[]; let extra={}; let longName='';
  for(let offset=0; offset+512<=data.length;) {
    const h=data.subarray(offset,offset+512); offset+=512;
    if(h.every(b=>b===0)) continue; // APK v2 has concatenated signed/control/data archives.
    const str=(a,b)=>h.subarray(a,b).toString().split('\0')[0];
    const size=parseInt(str(124,136).trim()||'0',8);
    if(!Number.isFinite(size)||size<0||offset+size>data.length) throw new Error('Invalid tar size');
    const body=data.subarray(offset,offset+size); offset+=Math.ceil(size/512)*512;
    const type=str(156,157)||'0';
    if(type==='x'||type==='g') {
      for(let i=0;i<body.length;) {
        const space=body.indexOf(32,i); const len=Number(body.subarray(i,space).toString());
        if(!len||len<3) throw new Error('Invalid pax header');
        const line=body.subarray(space+1,i+len-1).toString();const equal=line.indexOf('=');
        extra[line.slice(0,equal)]=line.slice(equal+1);i+=len;
      }
      continue;
    }
    if(type==='L') {longName=body.toString().replace(/\0.*$/s,'');continue;}
    let name=extra.path||longName||[str(345,500),str(0,100)].filter(Boolean).join('/');
    name=name.replace(/^\.\//,'').replace(/\/$/,'');
    if(name && (name.startsWith('/')||name.split('/').includes('..'))) throw new Error('Unsafe tar path '+name);
    if(name) result.push({name,type,mode:parseInt(str(100,108),8)||0o644,link:extra.linkpath||str(157,257),body:Buffer.from(body)});
    extra={};longName='';
  }
  return result;
}
function tarPack(entries) {
  const parts=[];
  for(const e of entries) {
    const h=Buffer.alloc(512); const body=['0','7','L'].includes(e.type)?e.body:Buffer.alloc(0);
    if(Buffer.byteLength(e.name)>100) throw new Error('USTAR name too long: '+e.name);
    h.write(e.name); const oct=(pos,len,n)=>h.write(n.toString(8).padStart(len-1,'0')+'\0',pos,len,'ascii');
    oct(100,8,e.mode);oct(108,8,0);oct(116,8,0);oct(124,12,body.length);oct(136,12,0);
    h.fill(32,148,156);h.write(e.type||'0',156);if(e.link)h.write(e.link,157,100);
    h.write('ustar\0',257);h.write('00',263);oct(148,7,h.reduce((a,b)=>a+b,0));h[155]=32;
    parts.push(h,body,Buffer.alloc((512-body.length%512)%512));
  }
  return Buffer.concat([...parts,Buffer.alloc(1024)]);
}
function cpioPack(entries) {
  const parts=[];let ino=1;
  for(const e of [...entries,{name:'TRAILER!!!',mode:0,type:'0',body:Buffer.alloc(0)}]) {
    const mode=e.type==='5'?0o040000:e.type==='2'?0o120000:0o100000;
    const body=e.type==='2'?Buffer.from(e.link):e.type==='5'?Buffer.alloc(0):e.body;
    const name=Buffer.from(e.name+'\0');
    const fields=[ino++,mode|e.mode,0,0,1,0,body.length,0,0,0,0,name.length,0];
    const h=Buffer.from('070701'+fields.map(x=>x.toString(16).padStart(8,'0')).join(''));
    parts.push(h,name,Buffer.alloc((4-(110+name.length)%4)%4),body,Buffer.alloc((4-body.length%4)%4));
  }
  return zlib.gzipSync(Buffer.concat(parts),{level:9});
}
const alpine='https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/';
const index=tarEntries(zlib.gunzipSync(await download(alpine+'APKINDEX.tar.gz','APKINDEX.tar.gz'))).find(e=>e.name==='APKINDEX').body.toString();
const packages=index.split('\n\n').map(block=>Object.fromEntries(block.split('\n').filter(l=>l[1]===':').map(l=>[l[0],l.slice(2)])));
const boot=new Map();const visited=new Set();
async function addPackage(name) {
  if(visited.has(name))return;visited.add(name);
  const p=packages.find(p=>p.P===name)||packages.find(p=>(p.p||'').split(' ').some(x=>x.split('=')[0]===name));
  if(!p)throw new Error('Unresolved Alpine dependency '+name);
  const filename=`${p.P}-${p.V}.apk`;
  const data=await download(alpine+filename,filename);
  for(const e of tarEntries(zlib.gunzipSync(data)))if(!e.name.startsWith('.'))boot.set(e.name,e);
  for(const dependency of (p.D||'').split(' ').filter(Boolean)) {
    if(dependency.startsWith('!')||dependency.startsWith('cmd:'))continue;
    await addPackage(dependency.split(/[<>=~]/)[0]);
  }
}
for(const name of ['busybox-static','musl','linux-virt','e2fsprogs','e2fsprogs-extra']) await addPackage(name);
const kernel=[...boot.values()].find(e=>e.name==='boot/vmlinuz-virt');
if(!kernel)throw new Error('Linux kernel missing');
fs.writeFileSync(path.join(out,'vmlinuz'),kernel.body);
for(const e of [...boot.values()]) if(e.name.startsWith('boot/'))boot.delete(e.name);
// Explicit directories are required in initramfs, unlike a tar extraction.
function ensureParents(map) {for(const e of [...map.values()]){let n=path.posix.dirname(e.name);while(n!=='.'){if(!map.has(n))map.set(n,{name:n,type:'5',mode:0o755,body:Buffer.alloc(0)});n=path.posix.dirname(n);}}}
const staticBusybox=[...boot.values()].find(e=>e.name==='bin/busybox.static');
if(!staticBusybox)throw new Error('Static busybox missing');
boot.set('bin/busybox',{...staticBusybox,name:'bin/busybox'});
boot.set('bin/sh',{name:'bin/sh',type:'2',mode:0o777,link:'busybox',body:Buffer.alloc(0)});
for(const [name,source] of [['init','init.sh'],['hexagon/guest-init','guest-init.sh']])boot.set(name,{name,type:'0',mode:0o755,body:fs.readFileSync(path.join(repo,'scripts/linux',source))});
ensureParents(boot);
fs.writeFileSync(path.join(out,'initramfs.gz'),cpioPack([...boot.values()].filter(e=>!e.name.startsWith('usr/share/')).sort((a,b)=>(a.type==='5'?0:1)-(b.type==='5'?0:1)||a.name.split('/').length-b.name.split('/').length)));

// Fetch the upstream OCI image, authenticate anonymously, and pin every layer by digest.
if (!fs.existsSync(path.join(out,'rootfs.tar.gz'))) {
const imageCache=path.join(work,'tuxee-1.5.0-manifest.json');
let headers;
async function registryHeaders(){if(!headers){const r=await fetch('https://auth.docker.io/token?service=registry.docker.io&scope=repository:agent0ai/tuxee:pull');const token=(await r.json()).token;headers={Authorization:'Bearer '+token,Accept:'application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'};}return headers;}
const registry='https://registry-1.docker.io/v2/agent0ai/tuxee/';
async function manifest(ref){const r=await fetch(registry+'manifests/'+ref,{headers:await registryHeaders()});if(!r.ok)throw new Error('Registry manifest '+r.status);return r.json();}
let image=fs.existsSync(imageCache)?JSON.parse(fs.readFileSync(imageCache)):await manifest('1.5.0');
if(image.manifests) image=await manifest(image.manifests.find(m=>m.platform.os==='linux'&&m.platform.architecture==='amd64').digest);
fs.writeFileSync(imageCache,JSON.stringify(image));
const rootfs=new Map();
for(const layer of image.layers) {
  const name=layer.digest.replace(':','-')+'.gz';const dest=path.join(work,name);
  if(!fs.existsSync(dest)){console.log('Downloading OCI layer',layer.size);const r=await fetch(registry+'blobs/'+layer.digest,{headers:await registryHeaders()});if(!r.ok)throw new Error('OCI blob '+r.status);fs.writeFileSync(dest,Buffer.from(await r.arrayBuffer()));}
  const data=fs.readFileSync(dest);if(sha(data)!==layer.digest.slice(7))throw new Error('OCI layer digest mismatch');
  sources.push({url:registry+'blobs/'+layer.digest,file:name,sha256:sha(data)});
  for(const e of tarEntries(zlib.gunzipSync(data))) {
    const base=path.posix.basename(e.name),dir=path.posix.dirname(e.name);
    if(base.startsWith('.wh.')) {
      const target=base==='.wh..wh..opq'?dir:path.posix.join(dir,base.slice(4));
      for(const key of rootfs.keys())if((base!=='.wh..wh..opq'&&key===target)||key.startsWith(target+'/'))rootfs.delete(key);
    } else rootfs.set(e.name,e);
  }
}
// Keep all upstream runtime libraries and license notices; exclude no image contents.
// Use GNU long-name headers for files exceeding USTAR's short name field.
const packed=[];
for(const e of rootfs.values()) {
  let item=e;
  if(Buffer.byteLength(e.name)>100){packed.push({name:'././@LongLink',type:'L',mode:0o644,body:Buffer.from(e.name+'\0')});item={...e,name:e.name.slice(-99)};}
  if(e.link&&Buffer.byteLength(e.link)>100)throw new Error('Long link unsupported: '+e.name);
  packed.push(item);
}
fs.writeFileSync(path.join(out,'rootfs.tar.gz'),zlib.gzipSync(tarPack(packed),{level:9}));
} else if(fs.existsSync(path.join(out,'SOURCES.json'))) {
  sources.push(...JSON.parse(fs.readFileSync(path.join(out,'SOURCES.json'))).sources.filter(s=>s.url.startsWith('https://registry-1.docker.io/')));
}

const qemuBase='https://qemu.weilnetz.de/w64/2026/qemu-w64-setup-20260811';
const qemuHash=(await download(qemuBase+'.sha512','qemu.sha512')).toString().trim().split(/\s/)[0];
await download(qemuBase+'.exe','qemu-installer.exe',qemuHash);
await download('https://api.nuget.org/v3-flatcontainer/7-zip.commandline/25.1.0/7-zip.commandline.25.1.0.nupkg','7zip.zip');
const sevenDir=path.join(work,'7zip');fs.mkdirSync(sevenDir,{recursive:true});
execFileSync('tar.exe',['-xf',path.join(work,'7zip.zip'),'-C',sevenDir]);
function findFile(dir,name){for(const e of fs.readdirSync(dir,{withFileTypes:true})){const p=path.join(dir,e.name);if(e.isFile()&&e.name.toLowerCase()===name)return p;if(e.isDirectory()){const r=findFile(p,name);if(r)return r;}}}
const sevenStandalone=path.join(sevenDir,'tools/x64/7za.exe');
await download('https://www.7-zip.org/a/7z2501-x64.exe','7zip-full.exe');
const fullDir=path.join(work,'7zip-full');fs.mkdirSync(fullDir,{recursive:true});
execFileSync(sevenStandalone,['x','-y','-o'+fullDir,path.join(work,'7zip-full.exe')],{stdio:'ignore'});
const seven=findFile(fullDir,'7z.exe');if(!seven)throw new Error('7z tooling missing');
const qemuDir=path.join(work,'qemu-extracted');fs.mkdirSync(qemuDir,{recursive:true});
execFileSync(seven,['x','-y','-o'+qemuDir,path.join(work,'qemu-installer.exe')],{stdio:'ignore'});
const qemuOut=path.resolve(out,'qemu');
if(!qemuOut.startsWith(path.resolve(work)+path.sep))throw new Error('Unsafe build output');
fs.rmSync(qemuOut,{recursive:true,force:true});fs.mkdirSync(qemuOut,{recursive:true});
function peImports(filename){
  const b=fs.readFileSync(filename), pe=b.readUInt32LE(0x3c), opt=pe+24;
  const sectionStart=opt+b.readUInt16LE(pe+20), n=b.readUInt16LE(pe+6);
  const rvaToOffset=rva=>{for(let i=0;i<n;i++){let s=sectionStart+i*40, va=b.readUInt32LE(s+12);if(rva>=va&&rva<va+Math.max(b.readUInt32LE(s+8),b.readUInt32LE(s+16)))return b.readUInt32LE(s+20)+rva-va;}return -1;};
  const rva=b.readUInt32LE(opt+(b.readUInt16LE(opt)===0x20b?112:96)+8);
  if(!rva)return [];let p=rvaToOffset(rva);const result=[];
  while(p>=0&&p+20<=b.length&&b.readUInt32LE(p+12)){let start=rvaToOffset(b.readUInt32LE(p+12));if(start<0)break;result.push(b.subarray(start,b.indexOf(0,start)).toString());p+=20;}
  return result;
}
const available=new Map(fs.readdirSync(qemuDir).map(n=>[n.toLowerCase(),n]));
const copied=new Set();
function copyBinary(name){const actual=available.get(name.toLowerCase());if(!actual||copied.has(actual))return;copied.add(actual);fs.copyFileSync(path.join(qemuDir,actual),path.join(qemuOut,actual));for(const dependency of peImports(path.join(qemuDir,actual)))copyBinary(dependency);}
copyBinary('qemu-system-x86_64.exe');copyBinary('qemu-img.exe');
for(const name of ['COPYING','COPYING.LIB'])fs.copyFileSync(path.join(qemuDir,name),path.join(qemuOut,name));
fs.mkdirSync(path.join(qemuOut,'share'),{recursive:true});
for(const name of ['bios-256k.bin','bios.bin','vgabios-stdvga.bin','kvmvapic.bin','linuxboot_dma.bin','multiboot_dma.bin','efi-virtio.rom'])fs.copyFileSync(path.join(qemuDir,'share',name),path.join(qemuOut,'share',name));
console.log('Headless QEMU runtime:',copied.size,'executables/libraries; no GTK icons or unused guest firmware');
if(!fs.existsSync(path.join(qemuOut,'qemu-system-x86_64.exe')))throw new Error('QEMU extraction missing executable');
fs.writeFileSync(path.join(out,'SOURCES.json'),JSON.stringify({tuxee:'1.5.0',sources},null,2));
const manifestFiles=[];
function scan(dir){for(const e of fs.readdirSync(dir,{withFileTypes:true})){const p=path.join(dir,e.name);if(e.isDirectory())scan(p);else if(p!==path.join(out,'manifest.json'))manifestFiles.push({path:path.relative(out,p).replaceAll('\\','/'),sha256:sha(fs.readFileSync(p)),size:fs.statSync(p).size});}}
scan(out);
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({version:1,files:manifestFiles},null,2));
const artifact=path.join(repo,'third_party/linux_runtime');fs.mkdirSync(artifact,{recursive:true});
if(fs.existsSync(path.join(artifact,'runtime.zip')))fs.unlinkSync(path.join(artifact,'runtime.zip'));
execFileSync(seven,['a','-tzip','-mx=1','-y',path.join(artifact,'runtime.zip'),'.'],{cwd:out,stdio:'ignore'});
console.log('Built',path.join(artifact,'runtime.zip'),fs.statSync(path.join(artifact,'runtime.zip')).size);
