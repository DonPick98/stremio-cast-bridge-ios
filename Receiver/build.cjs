const esbuild=require('esbuild'),fs=require('node:fs');
fs.mkdirSync('dist',{recursive:true});
esbuild.buildSync({entryPoints:['src/main.cjs'],outdir:'dist',entryNames:'receiver',bundle:true,splitting:false,format:'iife',platform:'browser',target:['chrome69'],minify:true,legalComments:'eof'});
fs.copyFileSync('index.html','dist/index.html');
fs.copyFileSync('THIRD_PARTY_NOTICES.txt','dist/THIRD_PARTY_NOTICES.txt');
fs.mkdirSync('dist/licenses',{recursive:true});
for(const [source,target] of [['node_modules/@stremio/libass-wasm/LICENSE','libass-wasm.txt'],['node_modules/vtt.js/LICENSE','vtt-js.txt']])fs.copyFileSync(source,'dist/licenses/'+target);
fs.copyFileSync('node_modules/@stremio/libass-wasm/dist/js/COPYRIGHT','dist/licenses/libass-wasm-bundled-libraries.txt');
