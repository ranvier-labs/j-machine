import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { CompilerWasm, SimulatorWasm } from '../site/runtime.js';
import { debugImage } from '../site/debugger.js';
import { readFramebuffer } from '../site/graphics/framebuffer.js';
const module = await WebAssembly.compile(await readFile(new URL('../dist/compiler.wasm',import.meta.url)));
const examples = [['rule110.c',2,'2x1x1',24],['distributed_mandelbrot.c',4,'2x2x1',1024],['message_hotspot.c',16,'4x4x1',32]];
for (const [name,nodes,mesh,result] of examples) test(`graphical example ${name} compiles, finishes, and renders exact pixels`,async t=>{
  const compiler=await CompilerWasm.fromBytes(module),source=await readFile(new URL(`../../compiler/examples/${name}`,import.meta.url),'utf8');
  const image=compiler.compile(source,nodes,mesh),info=debugImage(image);
  const factory=(await import(`../dist/simulator_${nodes}.js`)).default;
  const sim=await SimulatorWasm.create(factory,{nodes,wasmBinary:await readFile(new URL(`../dist/simulator_${nodes}.wasm`,import.meta.url))});t.after(()=>sim.destroy());
  sim.traceEnabled(false);sim.loadImage(image);
  let cycle=0;while(cycle<6000000&&sim.peek(0,0x300)===0n){sim.step(1000);cycle+=1000;}
  assert.equal(sim.peek(0,0x300),0x100000000n+BigInt(result),`${name} at ${cycle} cycles`);
  if(name==='rule110.c'){
    const frame=readFramebuffer(info,sim,0);assert.equal(frame.width,32);assert.equal(frame.frame,24);
    let cells=Array.from({length:32},(_,i)=>Number(i===30));
    for(let y=0;y<24;y++){
      for(let x=0;x<32;x++)assert.equal(frame.words[y*32+x]&0xffffffn,cells[x]?0xe4d6adn:0x10151cn);
      cells=cells.map((_,x)=>(110>>(cells[(x+31)%32]*4+cells[x]*2+cells[(x+1)%32]))&1);
    }
  }else if(name==='distributed_mandelbrot.c'){
    for(let n=0;n<4;n++){
      const f=readFramebuffer(info,sim,n);assert.equal(f.frame,1);
      for(let y=0;y<16;y++)for(let x=0;x<16;x++){
        const cr=(x+(n%2)*16)*12-256,ci=(y+Math.floor(n/2)*16)*12-192;let zr=0,zi=0,step=0;
        while(step<16&&zr*zr+zi*zi<65536){const next=((zr*zr-zi*zi)>>7)+cr;zi=((2*zr*zi)>>7)+ci;zr=next;step++;}
        assert.equal(f.words[y*16+x]&0xffffffn,BigInt(step===16?0:step*0x0f0905));
      }
    }
  }else{
    const f=readFramebuffer(info,sim,5);assert.equal(f.frame,32);
    for(let y=0;y<8;y++)for(let x=0;x<8;x++)assert.equal(f.words[y*8+x]&0xffffffn,BigInt((Math.floor(x/2)+1)*0x302010+y*0x030508));
  }
  console.log(`${name}: ${cycle} cycles, ${result}`);
});
