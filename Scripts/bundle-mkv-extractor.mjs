// Reproducible offline bundler; Node 24 built-in TypeScript erasure, no npm install.
import fs from 'node:fs';import path from 'node:path';import {stripTypeScriptTypes} from 'node:module';
const root=new URL('../ThirdParty/MKVSubtitleExtractor/',import.meta.url);
const modules=new Map();
function visit(id){if(modules.has(id))return;let s=fs.readFileSync(new URL(id,root),'utf8');s=stripTypeScriptTypes(s);const exported=[];
s=s.replace(/import\s+(\{[\s\S]*?\}|\* as \w+)\s+from\s+['"]([^'"]+)['"];?/g,(_,binding,relative)=>{let dep=path.posix.normalize(path.posix.join(path.posix.dirname(id),relative)).replace(/\.js$/,'.ts');visit(dep);return binding.startsWith('*')?`const ${binding.slice(5)}=require(${JSON.stringify(dep)});`:`const ${binding.replace(/\bas\b/g,':')}=require(${JSON.stringify(dep)});`;});
s=s.replace(/export\s+(async\s+)?(function\s*\*?\s*|class\s+|const\s+|let\s+)(\w+)/g,(_,a='',kind,name)=>{exported.push(name);return a+kind+name;});
s=s.replace(/export\s*\{([^}]+)\};?/g,(_,names)=>{exported.push(...names.split(',').map(x=>x.trim()));return '';});
modules.set(id,s+'\n'+exported.map(n=>`exports.${n}=${n};`).join('\n'));}
visit('bridge.ts');
let out=('/* mkv-subtitle-extractor\n'+fs.readFileSync(new URL('LICENSE',root),'utf8').trimEnd()+'\n*/\n')+'(function(global){const modules={'+[...modules].map(([id,s])=>JSON.stringify(id)+':function(require,exports){\n'+s+'\n}').join(',\n')+'};const cache={};function require(id){if(cache[id])return cache[id];const e={};cache[id]=e;modules[id](require,e);return e;}global.CastMKV=require("bridge.ts");})(globalThis);\n';
fs.writeFileSync(new URL('../Resources/MKVSubtitleExtractor.js',import.meta.url),out);
console.log('Bundled',modules.size,'modules,',Buffer.byteLength(out),'bytes');
