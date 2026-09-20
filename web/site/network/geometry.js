export const PORTS = ['LOCAL', '−X', '+X', '−Y', '+Y', '−Z', '+Z'];
export const OPPOSITE = [0, 2, 1, 4, 3, 6, 5];
export function dimensions(mesh) {
  if (!/^\d+x\d+x\d+$/.test(mesh)) throw new Error('Invalid mesh dimensions.');
  const dims = mesh.split('x').map(Number);
  if (dims.some(n => n < 1 || n > 32) || dims.reduce((a, b) => a * b) > 512) throw new Error('Unsupported mesh dimensions.');
  return dims;
}
export function coordinates(id, dims) {
  return [id % dims[0], Math.floor(id / dims[0]) % dims[1], Math.floor(id / (dims[0] * dims[1]))];
}
export function nodeAt([x, y, z], dims) {
  return [x, y, z].every((n, i) => Number.isInteger(n) && n >= 0 && n < dims[i]) ? x + dims[0] * (y + dims[1] * z) : null;
}
export function encodedNode(value, dims) {
  return value & 0x80000000 ? (value & 0x7fffffff) : nodeAt([value & 31, (value >>> 5) & 31, (value >>> 10) & 63], dims);
}
export function neighbor(node, port, dims) {
  const xyz = coordinates(node, dims);
  if (port === 0) return node;
  xyz[Math.floor((port - 1) / 2)] += port % 2 ? -1 : 1;
  return nodeAt(xyz, dims);
}
export function expectedRoute(from, to, dims) {
  const route = [], dest = coordinates(to, dims); let current = from;
  for (let axis = 0; axis < 3; axis++) {
    while (coordinates(current, dims)[axis] !== dest[axis]) {
      const port = 1 + axis * 2 + Number(coordinates(current, dims)[axis] < dest[axis]);
      const next = neighbor(current, port, dims); route.push({ node: current, port, next }); current = next;
    }
  }
  return route;
}
export const planeAxes = plane => ({ XY: [0, 1, 2], XZ: [0, 2, 1], YZ: [1, 2, 0] })[plane] ?? [0, 1, 2];
