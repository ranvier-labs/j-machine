import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {CompilerWasm,SimulatorWasm} from '../site/runtime.js';
import {DebuggerController,debugImage} from '../site/debugger.js';
import {expectedRoute} from '../site/network/geometry.js';
import {readFramebuffer} from '../site/graphics/framebuffer.js';
import factory from '../dist/simulator_512.js';
const compiled=await WebAssembly.compile(await readFile(new URL('../dist/compiler.wasm',import.meta.url)));
const sim=await SimulatorWasm.create(factory,{nodes:512,wasmBinary:await readFile(new URL('../dist/simulator_512.wasm',import.meta.url))});
try{
  for(const [name,result]of [['mesh512.c',539],['mesh_rainbow.c',256]]){
    const c=await CompilerWasm.fromBytes(compiled),source=await readFile(new URL(`../../compiler/examples/${name}`,import.meta.url),'utf8');
    let reported=0;
    const image=c.compile(source,512,'8x8x8'),d=new DebuggerController(sim,{yieldFrame:()=>Promise.resolve(),batchCycles:1024,onUpdate:snapshot=>{
      const cycle=Number(snapshot?.cycle??0);
      if(cycle-reported>=16384){console.log(`${name}: running at cycle ${cycle}`);reported=cycle;}
    }});d.maxCycles=200000;d.load(image);
    console.log(`${name}: compiled and loaded on 512 nodes`);
    d.network.addBreakpoint({type:'deliver',destination:511});
    assert.equal((await d.execute()).type,'network');
    const selected=d.network.packets.get(d.network.selectedPacket);assert.equal(selected.destination,511);
    assert.equal(selected.delivered,Number(d.snapshot.cycle));
    console.log(`${name}: delivery breakpoint at cycle ${selected.delivered}`);
    assert.equal(selected.hops.length,21);assert.equal(selected.incomplete,false);
    assert.deepEqual(selected.hops.map(h=>[h.node,h.port]),expectedRoute(selected.source,511,[8,8,8]).map(h=>[h.node,h.port]));
    d.network.breakpoints.clear();
    assert.equal((await d.execute()).type,'result');
    assert.equal(sim.peek(0,0x300),0x100000000n+BigInt(result));assert.equal(d.network.dropped,0);
    assert.ok([...d.network.packets.values()].every(p=>!p.incomplete));
    if(name==='mesh_rainbow.c')for(const [n,color]of [[7,0x20],[56,0x60],[448,0xa0],[511,0xe0]]){
      const f=readFramebuffer(debugImage(image),sim,n);assert.equal(f.frame,1);
      for(let y=0;y<8;y++)for(let x=0;x<8;x++)assert.equal(f.words[y*8+x]&0xffffffn,BigInt(color+x*0x180000+y*0x001800));
    }
    console.log(`${name}: ${d.network.cycle} cycles, ${d.network.packets.size} packets, 21-hop route to 511, result ${result}`);
    await writeFile(new URL(`../build/${name}.jmtrace`,import.meta.url),d.network.export({sourcePath:`/examples/${name}`,sourceText:source,image,mesh:'8x8x8',nodes:512}));
  }
}finally{sim.destroy();}
