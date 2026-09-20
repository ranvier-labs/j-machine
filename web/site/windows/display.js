import { element, button, observe } from './common.js';
import { readFramebuffer } from '../graphics/framebuffer.js';
import { describeWord } from '../runtime.js';
import { basename } from '../core/filesystem.js';

export function displayWindow(ide) {
  const root=element('div','network-window display-window'),tools=element('div','tool-strip'),view=element('select'),palette=element('select');
  view.ariaLabel='Display arrangement';view.replaceChildren(new Option('Auto arrangement','auto'),new Option('Selected node','node'),new Option('Node mosaic (up to 16)','mosaic'));
  palette.ariaLabel='Pixel format';palette.replaceChildren(new Option('RGB 0xRRGGBB','rgb'),new Option('Grayscale 0–255','gray'));
  const stage=element('div','display-stage'),canvas=element('canvas'),status=element('div','network-status'),pixel=element('output','pixel-inspection');
  canvas.tabIndex=0;canvas.ariaLabel='Program graphical output. Arrow keys inspect pixels. Plus and minus adjust zoom.';
  stage.append(canvas); let frames=[],cursor=0,zoom=1,layoutWidth=1,tileColumns=1;
  const focusFrame=()=>frames.find(f=>f.node===ide.selectedNode)??frames[0];
  const inspect=()=>{
    const f=focusFrame();if(!f){pixel.textContent='';return;}cursor=Math.max(0,Math.min(f.words.length-1,cursor));
    pixel.textContent=`N${f.node} (${cursor%f.width}, ${Math.floor(cursor/f.width)}) [0x${(f.base+cursor).toString(16)}] ${describeWord(f.words[cursor])}`;
    canvas.setAttribute('aria-description',pixel.textContent);
  };
  const exportImage=()=>{if(!frames.length)return;const anchor=document.createElement('a');anchor.download=`j-machine-display-${ide.debug.snapshot.cycle}.png`;anchor.href=canvas.toDataURL('image/png');anchor.click();};
  tools.append(view,palette,button('Go to node','Choose the node whose framebuffer is displayed',()=>ide.services.jumpNode()),
    button('−','Zoom display out',()=>{zoom=Math.max(.25,zoom/1.5);size();}),button('+','Zoom display in',()=>{zoom=Math.min(8,zoom*1.5);size();}),
    button('Watch pixel','Break when the inspected pixel changes',()=>ide.perform(()=>{const f=focusFrame();if(!f)throw new Error('No framebuffer is available.');ide.debug.addWatchpoint(f.node,f.base+cursor);ide.emit('machine');})),
    button('Save PNG','Download the displayed framebuffer as a PNG image',exportImage));
  const size=()=>{canvas.style.width=`${Math.max(160,layoutWidth*8)*zoom}px`;};
  const render=observe(ide,['machine','state','display'],()=>{
    if(!ide.debug){status.textContent='Compile a graphical example to draw here.';return;}
    if(root.hidden||root.closest('[hidden]'))return;
    if(ide.archiveTrace){status.textContent='The display reads the live machine. Return to Live in Causal History to inspect it.';return;}
    // Auto shows the mosaic when more than one node in the selected group draws.
    const mosaic=view.value!=='node', groupStart=Math.floor(ide.selectedNode/16)*16;
    let first=mosaic?groupStart:ide.selectedNode, count=mosaic?Math.min(16,ide.simulator.nodes-first):1;
    frames=Array.from({length:count},(_,i)=>readFramebuffer(ide.debug.info,ide.simulator,first+i,palette.value)).filter(Boolean);
    if(view.value==='auto'&&frames.length<=1){first=ide.selectedNode;count=1;frames=frames.length&&frames[0].node===first?frames:[readFramebuffer(ide.debug.info,ide.simulator,first,palette.value)].filter(Boolean);}
    if(!frames.length){status.textContent='Waiting for display_width, display_height, and display_pixels globals (integer RGB pixels).';canvas.width=1;canvas.height=1;return;}
    const w=Math.max(...frames.map(f=>f.width)),h=Math.max(...frames.map(f=>f.height));tileColumns=Math.ceil(Math.sqrt(frames.length));
    layoutWidth=w*tileColumns;canvas.width=layoutWidth;canvas.height=h*Math.ceil(frames.length/tileColumns);
    const ctx=canvas.getContext('2d');frames.forEach((f,i)=>ctx.putImageData(new ImageData(f.pixels,f.width,f.height),(i%tileColumns)*w,Math.floor(i/tileColumns)*h));size();
    status.textContent=`${basename(ide.compiledPath??'')} · ${frames.length===1?`NODE ${frames[0].node}`:`NODES ${first}–${first+count-1}, row order`} · ${w}×${h} pixels per node · frame ${frames[0].frame??'—'} · cycle ${ide.debug.snapshot.cycle}`;inspect();
  });
  view.onchange=render;palette.onchange=render;
  canvas.onkeydown=e=>{
    const f=focusFrame();if(!f)return;const delta={ArrowLeft:-1,ArrowRight:1,ArrowUp:-f.width,ArrowDown:f.width}[e.key];
    if(delta!==undefined){e.preventDefault();cursor+=delta;inspect();}
    else if(['+','=','-'].includes(e.key)){e.preventDefault();zoom=Math.max(.25,Math.min(8,zoom*(e.key==='-'?1/1.5:1.5)));size();}
  };
  canvas.onclick=e=>{
    const f=focusFrame();if(!f)return;const rect=canvas.getBoundingClientRect(),x=Math.floor((e.clientX-rect.left)/rect.width*canvas.width),y=Math.floor((e.clientY-rect.top)/rect.height*canvas.height);
    const tile=Math.floor(y/f.height)*tileColumns+Math.floor(x/f.width),chosen=frames[tile];
    if(chosen){cursor=(y%f.height)*f.width+x%f.width;if(chosen.node!==ide.selectedNode)ide.selectNode(chosen.node);pixel.textContent=`N${chosen.node} (${x%f.width}, ${y%f.height}) [0x${(chosen.base+cursor).toString(16)}] ${describeWord(chosen.words[cursor])}`;}canvas.focus();
  };
  root.append(tools,status,stage,pixel);render();return{id:'display',title:'GRAPHICAL DISPLAY',element:root,onFocus:()=>canvas.focus(),onResize:render,exportImage};
}
