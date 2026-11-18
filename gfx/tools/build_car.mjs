// Converte o Car Concept (Khronos, CC-BY 4.0) simplificado em um GLB enxuto para o jogo:
// sem texturas (remove logos/marcas), cores por vértice, 4 rodas separadas e malhas estáticas por classe.
import {NodeIO,Document} from '@gltf-transform/core';
import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
const io=new NodeIO().registerExtensions(ALL_EXTENSIONS);
const src=await io.read(process.argv[2]);
const gam=c=>c.map(v=>Math.pow(Math.max(0,v),1/2.2));
const NAMEC={Mirror:[.55,.58,.62],Disc:[.45,.45,.47],Rim2:[.85,.86,.88],Tireside:[.05,.05,.05],License:[.9,.9,.9]};
const cls=(m)=>{const n=m?m.getName():'';if(/^Paint 1/.test(n))return['p1',[1,1,1]];if(/glass/i.test(n))return['glass',[1,1,1]];
 if(/headlight/i.test(n))return['lights',[.93,.93,.85]];if(/brakelight/i.test(n))return['lights',[.75,.05,.05]];if(/signal/i.test(n))return['lights',[.85,.5,.1]];
 let c=NAMEC[n];if(!c){const f=m&&m.getBaseColorFactor();c=f?gam(f.slice(0,3)):[.2,.2,.2]}if(/Paint 2|Pearl|Graphite/.test(n)&&m){const f=m.getBaseColorFactor();c=gam(f.slice(0,3));c=c.map(v=>Math.max(v,.12))}return['dark',c]};
const W=[['fl',/WheelFrontL/,[.98,.385,1.49]],['fr',/WheelFrontR/,[-.98,.385,1.48]],['rl',/WheelRearL/,[.98,.385,-1.32]],['rr',/WheelRearR/,[-.98,.385,-1.31]]];
const groups={};const G=(k)=>groups[k]||(groups[k]={pos:[],nor:[],col:[],idx:[]});
function add(g,p,Wm,col,off){const a=p.getAttribute('POSITION'),nm=p.getAttribute('NORMAL'),ix=p.getIndices(),base=g.pos.length/3,e=[0,0,0];
 const cnt=a.getCount();for(let i=0;i<cnt;i++){a.getElement(i,e);g.pos.push(Wm[0]*e[0]+Wm[4]*e[1]+Wm[8]*e[2]+Wm[12]-off[0],Wm[1]*e[0]+Wm[5]*e[1]+Wm[9]*e[2]+Wm[13]-off[1],Wm[2]*e[0]+Wm[6]*e[1]+Wm[10]*e[2]+Wm[14]-off[2]);
  if(nm){nm.getElement(i,e);const x=Wm[0]*e[0]+Wm[4]*e[1]+Wm[8]*e[2],y=Wm[1]*e[0]+Wm[5]*e[1]+Wm[9]*e[2],z=Wm[2]*e[0]+Wm[6]*e[1]+Wm[10]*e[2],l=Math.hypot(x,y,z)||1;g.nor.push(x/l,y/l,z/l)}else g.nor.push(0,1,0);g.col.push(col[0],col[1],col[2])}
 const n=ix?ix.getCount():cnt;for(let i=0;i<n;i++)g.idx.push(base+(ix?ix.getScalar(i):i))}
const cen=p=>{const a=p.getAttribute('POSITION'),e=[0,0,0];let x=0,y=0,z=0;for(let i=0;i<a.getCount();i++){a.getElement(i,e);x+=e[0];y+=e[1];z+=e[2]}const n=a.getCount();return[x/n,y/n,z/n]};
src.getRoot().listScenes()[0].traverse(n=>{const mesh=n.getMesh();if(!mesh)return;const Wm=n.getWorldMatrix();
 let wn=null;for(let a=n;a;a=a.getParent&&a.getParent()){const nm=a.getName&&a.getName();for(const w of W)if(nm&&w[1].test(nm)&&/^Wheel/.test(nm))wn=w}
 for(const p of mesh.listPrimitives()){const mn=p.getMaterial()?p.getMaterial().getName():'';if(process.env.LO&&(mn===''||/^(Interior|Floormat|Dashboard|Hardware|Mechanical|Panel Sides)/.test(mn)))continue;const[k,col]=cls(p.getMaterial());let wh=wn;
  if(!wh){const c0=cen(p),c=[Wm[0]*c0[0]+Wm[4]*c0[1]+Wm[8]*c0[2]+Wm[12],Wm[1]*c0[0]+Wm[5]*c0[1]+Wm[9]*c0[2]+Wm[13],Wm[2]*c0[0]+Wm[6]*c0[1]+Wm[10]*c0[2]+Wm[14]];
   for(const w of W)if(Math.hypot(c[0]-w[2][0],c[1]-w[2][1],c[2]-w[2][2])<.42&&Math.abs(c[0])>.7&&k!='glass')wh=w}
  if(wh)add(G('wheel_'+wh[0]),p,Wm,k=='p1'?[.6,.05,.05]:col,wh[2]);else add(G('st_'+k),p,Wm,col,[0,0,0])}});
const doc=new Document(),buf=doc.createBuffer(),scn=doc.createScene('car');
const M={p1:doc.createMaterial('p1').setBaseColorFactor([1,1,1,1]).setRoughnessFactor(.3).setMetallicFactor(0),dark:doc.createMaterial('dark').setBaseColorFactor([1,1,1,1]).setRoughnessFactor(.5),
 glass:doc.createMaterial('glass').setBaseColorFactor([.04,.08,.12,.4]).setAlphaMode('BLEND'),lights:doc.createMaterial('lights').setBaseColorFactor([1,1,1,1])};
let tot=0;
for(const[k,g]of Object.entries(groups)){if(!g.idx.length)continue;const n=g.pos.length/3;const mk=(t,arr,type)=>doc.createAccessor().setType(type).setArray(arr).setBuffer(buf);
 const prim=doc.createPrimitive().setAttribute('POSITION',mk(0,new Float32Array(g.pos),'VEC3')).setAttribute('NORMAL',mk(0,new Float32Array(g.nor),'VEC3')).setAttribute('COLOR_0',mk(0,new Float32Array(g.col),'VEC3')).setIndices(mk(0,n>65535?new Uint32Array(g.idx):new Uint16Array(g.idx),'SCALAR')).setMaterial(M[k.replace('st_','').replace(/^wheel_.*/,'dark')]);
 const node=doc.createNode(k).setMesh(doc.createMesh(k).addPrimitive(prim));const w=W.find(w=>'wheel_'+w[0]==k);if(w)node.setTranslation(w[2]);scn.addChild(node);tot+=g.idx.length/3;console.log(k,n,'verts',g.idx.length/3,'tris')}
const E=(nm,t)=>scn.addChild(doc.createNode(nm).setTranslation(t));
E('seat_driver',[+(process.argv[4]||0),.46,.34]);E('cabin_roof',[0,1.1,.1]);
await io.write(process.argv[3],doc);console.log('total tris',Math.round(tot));
