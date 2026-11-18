#!/usr/bin/env python3
"""Inspeciona um GLB: nós, malhas, materiais, texturas, triângulos, caixa. Uso: inspect_glb.py arquivo.glb"""
import struct,json,sys
f=open(sys.argv[1],'rb').read()
l=struct.unpack('<I',f[12:16])[0];j=json.loads(f[20:20+l])
acc=j['accessors'];tot=0
print('arquivo',sys.argv[1],len(f)//1024,'KB; extensões:',j.get('extensionsUsed'))
print('(se aparecer KHR_draco_mesh_compression é preciso o DRACOLoader)')
print('--- nós');
def walk(i,d=0):
    n=j['nodes'][i];print('  '*d+str(n.get('name')),'mesh' if 'mesh' in n else '',n.get('translation',''),n.get('scale',''))
    for c in n.get('children',[]):walk(c,d+1)
for r in j['scenes'][0]['nodes']:walk(r)
print('--- malhas')
for m in j['meshes']:
    if 0: pass
    t=0
    for p in m['primitives']:
        t+=acc[p['indices']]['count']//3 if 'indices' in p and 'extensions' not in p else (acc[p['attributes']['POSITION']]['count']//3)
    tot+=t;print(' ',m.get('name'),len(m['primitives']),'prims',t,'tris',[j['materials'][p['material']].get('name') for p in m['primitives'] if 'material' in p][:6])
print('--- materiais',len(j['materials']))
for m in j['materials']:
    pb=m.get('pbrMetallicRoughness',{});print(' ',m.get('name'),pb.get('baseColorFactor'),'map' if 'baseColorTexture' in pb else '','met',pb.get('metallicFactor'),'rough',pb.get('roughnessFactor'),m.get('alphaMode',''),'norm' if 'normalTexture' in m else '')
print('--- imagens',[(i.get('name'),i.get('mimeType')) for i in j.get('images',[])],'triângulos total',tot)
