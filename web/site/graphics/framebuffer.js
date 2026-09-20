export function framebufferLayout(info, simulator, node = 0) {
  const address = name => info.globals.find(g => g.name === `${name}[0]`)?.address;
  const base = address('display_pixels'), widthAddress = address('display_width'), heightAddress = address('display_height');
  if (base === undefined || widthAddress === undefined || heightAddress === undefined) return null;
  const integer = addr => { const value = simulator.peek(node,addr); return value >> 32n === 1n ? Number(value & 0xffffffffn) : 0; };
  const width = integer(widthAddress), height = integer(heightAddress);
  const allocated = info.globals.filter(g => /^display_pixels\[\d+\]$/.test(g.name)).length;
  if (width < 1 || height < 1 || width > 256 || height > 256 || width * height > 16384 || width * height > allocated) return null;
  return { node, base, width, height, frame: address('display_frame') === undefined ? null : integer(address('display_frame')) };
}
export function readFramebuffer(info, simulator, node = 0, palette = 'rgb') {
  const layout = framebufferLayout(info,simulator,node); if (!layout) return null;
  const pixels = new Uint8ClampedArray(layout.width * layout.height * 4), words = [];
  for(let i=0;i<layout.width*layout.height;i++) {
    const word=simulator.peek(node,layout.base+i),data=Number(word&0xffffffffn);words.push(word);
    const rgb=word>>32n!==1n ? [190,90,180] : palette==='gray' ? [data&255,data&255,data&255] : [(data>>>16)&255,(data>>>8)&255,data&255];
    pixels.set([...rgb,255],i*4);
  }
  return {...layout,pixels,words};
}
