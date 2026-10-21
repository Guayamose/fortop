const fs=require('fs'),path=require('path');
const sharp=require(require.resolve('sharp',{paths:[__dirname,process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES||__dirname]}));
const root=path.resolve(process.argv[2]||path.join(__dirname,'../../FORTOP_Brand_Kit_rebuild'));
function walk(p){return fs.readdirSync(p,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(p,e.name)):[path.join(p,e.name)]);}
(async()=>{
 const files=walk(root).filter(p=>p.endsWith('.svg'));
 let done=0;const results=[];
 for(const p of files){
  const rel=path.relative(root,p),out=path.join(root,'09_PREVISUALIZACIONES',rel.replace(/\.svg$/,'.png'));
  fs.mkdirSync(path.dirname(out),{recursive:true});
  const md=await sharp(p).metadata();
  let width=md.width;
  if(/^0[0-4]_/.test(rel))width=Math.max(1200,Math.round(md.width*2));
  if(rel.includes('tarjetas'))width=1700;
  if(rel.includes('A4'))width=1588;
  await sharp(p).resize({width}).png().toFile(out);
  const st=await sharp(out).stats();
  if(st.channels.every(c=>c.min===c.max))throw Error('Blank SVG: '+rel);
  results.push({svg:rel,png:path.relative(root,out),width,rendered:true});done++;
 }
 // Production digital PNGs, each from its own vector.
 for(const bg of ['shadow','pine','honeydew','ivory']){
  for(const n of [192,512,1024])await sharp(path.join(root,`05_DIGITAL/app-icons/FORTOP_app_${bg}_512.svg`)).resize(n,n).png().toFile(path.join(root,`05_DIGITAL/app-icons/FORTOP_app_${bg}_${n}.png`));
  await sharp(path.join(root,`05_DIGITAL/avatares/FORTOP_avatar_${bg}_1024.svg`)).png().toFile(path.join(root,`05_DIGITAL/avatares/FORTOP_avatar_${bg}_1024.png`));
 }
 for(const n of [16,32,48,64])await sharp(path.join(root,`05_DIGITAL/favicon/FORTOP_favicon_${n}.svg`)).png().toFile(path.join(root,`05_DIGITAL/favicon/FORTOP_favicon_${n}.png`));
 await sharp(path.join(root,'05_DIGITAL/app-icons/FORTOP_app_pine_512.svg')).resize(180,180).png().toFile(path.join(root,'05_DIGITAL/app-icons/apple-touch-icon.png'));
 await sharp(path.join(root,'05_DIGITAL/app-icons/FORTOP_app_pine_maskable_512.svg')).png().toFile(path.join(root,'05_DIGITAL/app-icons/FORTOP_app_pine_maskable_512.png'));
 fs.writeFileSync(path.join(root,'resultados_render.json'),JSON.stringify(results,null,2));
 console.log('Rendered '+done+' / '+files.length+' SVGs; digital PNGs complete.');
})().catch(e=>{console.error(e);process.exit(1)});
