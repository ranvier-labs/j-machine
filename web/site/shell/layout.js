export const leaf = id => ({ type: 'leaf', id });
export const split = (axis, ratio, first, second, id = crypto.randomUUID()) => ({ type: 'split', id, axis, ratio, first, second });
export function leaves(node) { return !node ? [] : node.type === 'leaf' ? [node.id] : [...leaves(node.first), ...leaves(node.second)]; }
export function without(node, id) {
  if (!node || (node.type === 'leaf' && node.id === id)) return null;
  if (node.type === 'leaf') return node;
  const first = without(node.first, id), second = without(node.second, id);
  return !first ? second : !second ? first : { ...node, first, second };
}
function replace(node, id, replacement) {
  if (!node) return node;
  if (node.type === 'leaf') return node.id === id ? replacement : node;
  return { ...node, first: replace(node.first, id, replacement), second: replace(node.second, id, replacement) };
}
export function restoreLayout(value, allowed) {
  const seen = new Set(), splitIds = new Set();
  function visit(node, depth) {
    if (!node || depth > 24) return null;
    if (node.type === 'leaf') {
      if (!allowed.includes(node.id) || seen.has(node.id)) return null;
      seen.add(node.id); return leaf(node.id);
    }
    if (node.type !== 'split' || !['x', 'y'].includes(node.axis)) return null;
    const first = visit(node.first, depth + 1), second = visit(node.second, depth + 1);
    if (!first || !second) return first ?? second;
    const id = typeof node.id === 'string' && !splitIds.has(node.id) ? node.id : crypto.randomUUID();
    splitIds.add(id);
    return split(node.axis, Number.isFinite(node.ratio) ? Math.max(.12, Math.min(.88, node.ratio)) : .5, first, second, id);
  }
  return visit(value, 0);
}
export function tilePositions(tree) {
  const result=new Map();
  const visit=(node,x,y,width,height)=>{
    if(!node)return;
    if(node.type==='leaf'){result.set(node.id,{x,y,width,height});return;}
    if(node.axis==='x'){visit(node.first,x,y,width*node.ratio,height);visit(node.second,x+width*node.ratio,y,width*(1-node.ratio),height);}
    else{visit(node.first,x,y,width,height*node.ratio);visit(node.second,x,y+height*node.ratio,width,height*(1-node.ratio));}
  };visit(tree,0,0,1,1);return result;
}
export class TileLayout {
  constructor(tree = null) { this.tree = tree; this.focused = leaves(tree)[0] ?? null; this.zoomed = null; }
  open(id, { relativeTo = this.focused, edge = 'right', atRoot = false, ratio = .5 } = {}) {
    if (leaves(this.tree).includes(id)) { this.focused = id; this.zoomed = null; return; }
    if (!this.tree) this.tree = leaf(id);
    else if (atRoot) {
      const before = ['left', 'top'].includes(edge);
      this.tree = split(['left', 'right'].includes(edge) ? 'x' : 'y', Math.max(.12, Math.min(.88, ratio)), before ? leaf(id) : this.tree, before ? this.tree : leaf(id));
    }
    else {
      if (!leaves(this.tree).includes(relativeTo)) relativeTo = leaves(this.tree).at(-1);
      const before = ['left', 'top'].includes(edge), target = leaf(relativeTo);
      this.tree = replace(this.tree, relativeTo, split(['left', 'right'].includes(edge) ? 'x' : 'y', .5,
        before ? leaf(id) : target, before ? target : leaf(id)));
    }
    this.focused = id; this.zoomed = null;
  }
  close(id) {
    const order = leaves(this.tree), index = order.indexOf(id);
    this.tree = without(this.tree, id);
    if (this.focused === id) this.focused = leaves(this.tree)[Math.max(0, index - 1)] ?? null;
    if (this.zoomed === id) this.zoomed = null;
  }
  move(id, target, edge) { if (id === target) return; this.tree = without(this.tree, id); this.open(id, { relativeTo: target, edge }); }
  resize(id, ratio) {
    const visit = node => !node || node.type === 'leaf' ? node : { ...node,
      ratio: node.id === id ? Math.max(.12, Math.min(.88, ratio)) : node.ratio,
      first: visit(node.first), second: visit(node.second) };
    this.tree = visit(this.tree);
  }
  resizeFocused(axis, delta) {
    let match;
    const visit = node => {
      if (!node || node.type === 'leaf') return node?.id === this.focused;
      const first = visit(node.first), second = visit(node.second);
      if ((first || second) && node.axis === axis && !match) match = { node, first };
      return first || second;
    };
    visit(this.tree);
    if (match) this.resize(match.node.id, match.node.ratio + delta * (match.first ? 1 : -1));
  }
  cycle(direction = 1) {
    const order = leaves(this.tree);
    this.focused = order[(order.indexOf(this.focused) + direction + order.length) % order.length] ?? null;
    if (this.zoomed) this.zoomed = this.focused;
    return this.focused;
  }
  zoom(id = this.focused) { if (id) { this.focused = id; this.zoomed = this.zoomed === id ? null : id; } }
}
