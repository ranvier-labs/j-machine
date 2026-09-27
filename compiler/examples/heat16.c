/* The heat equation on a 4x4 mesh, solved by Jacobi relaxation: the
   computation the original J-Machine programmers benchmarked. A 16x16 plate
   is split into 4x4 tiles, one per node. Two spots are held hot and two
   cold; every sweep replaces each other cell with the mean of its four
   neighbours. Node 15 runs the solver as one long call from main: each sweep
   it collects every tile's four edges, one word of four 8-bit temperatures
   per edge, one request in flight at a time, and delivers each tile the
   temperatures around it, copied from its neighbours' edges, in one one-way
   message. Receiving it is what makes a tile relax and draw; a tile never
   sends on its own. The result is the total change of the last of 24
   sweeps summed over the plate, so it says how far the plate is from steady
   state. The display maps temperature from black through red to amber. */
int display_width = 4;
int display_height = 4;
int display_frame;
int display_pixels[16];

int sweeps = 24;

/* A tile keeps its temperatures in a 6x6 scratch grid with its halo, so
   relaxation is plain indexing. Edge word k packs four 8-bit temperatures:
   k = 0 the left column, 1 the right column, 2 the top row, 3 the bottom. */
int grid[36];
int fixed[16];
int next[16];
int my_edges[4];
void cache_edges(void) {
  int i = 0;
  int k = 0;
  for (k = 0; k < 4; k++) {
    my_edges[k] = 0;
    for (i = 0; i < 4; i++)
      my_edges[k] = my_edges[k] | (grid[k < 2 ? (i + 1) * 6 + 1 + k * 3 : 7 + i + (k - 2) * 18] << (i * 8));
  }
}
void set_halo(int w0, int w1, int w2, int w3) {
  int i = 0;
  for (i = 0; i < 4; i++) {
    grid[(i + 1) * 6] = (w0 >> (i * 8)) & 255;
    grid[(i + 1) * 6 + 5] = (w1 >> (i * 8)) & 255;
    grid[i + 1] = (w2 >> (i * 8)) & 255;
    grid[31 + i] = (w3 >> (i * 8)) & 255;
  }
}
int relax(void) {
  int x = 0;
  int y = 0;
  int at = 0;
  int value = 0;
  int change = 0;
  for (y = 0; y < 4; y++) {
    for (x = 0; x < 4; x++) {
      at = (y + 1) * 6 + x + 1;
      value = fixed[y * 4 + x] ? grid[at] : (grid[at - 6] + grid[at + 6] + grid[at - 1] + grid[at + 1]) >> 2;
      change = change + (value > grid[at] ? value - grid[at] : grid[at] - value);
      next[y * 4 + x] = value;
    }
  }
  for (y = 0; y < 4; y++) for (x = 0; x < 4; x++) grid[(y + 1) * 6 + x + 1] = next[y * 4 + x];
  return change;
}
void paint(void) {
  int i = 0;
  int t = 0;
  for (i = 0; i < 16; i++) {
    t = grid[(i >> 2) * 6 + 7 + (i & 3)];
    display_pixels[i] = (t << 16) | (((t >> 1) + (t >> 2)) << 8) | (t >> 2);
  }
  display_frame++;
}

/* ---- a tile on nodes 0..14 ---- */
int last_change = 0;
void hold(int x, int y, int value) { fixed[y * 4 + x] = 1; grid[(y + 1) * 6 + x + 1] = value; cache_edges(); paint(); }
int get_edge(int k) { return my_edges[k]; }
int get_change(void) { return last_change; }
void deliver(int w0, int w1, int w2, int w3) {
  set_halo(w0, w1, w2, w3);
  last_change = relax();
  cache_edges();
  paint();
}

/* ---- node 15: the solver loop ---- */
int edges[64];   /* [tile * 4 + k], every tile's edge words this sweep */
int tile_at(int tx, int ty) { return ((ty + 4) & 3) * 4 + ((tx + 4) & 3); }
/* The halo of a tile is made of its neighbours' edges: the left halo is the
   left neighbour's right column, and so on. */
int halo_word(int who, int k) {
  int tx = who & 3;
  int ty = who >> 2;
  if (k == 0) return edges[tile_at(tx - 1, ty) * 4 + 1];
  if (k == 1) return edges[tile_at(tx + 1, ty) * 4];
  if (k == 2) return edges[tile_at(tx, ty - 1) * 4 + 3];
  return edges[tile_at(tx, ty + 1) * 4 + 2];
}
int run(int limit) {
  int s = 0;
  int t = 0;
  int k = 0;
  int total = 0;
  cache_edges();
  paint();
  while (s < limit) {
    for (t = 0; t < 15; t++) for (k = 0; k < 4; k++) edges[t * 4 + k] = get_edge(k)@t;
    for (k = 0; k < 4; k++) edges[60 + k] = my_edges[k];
    for (t = 0; t < 15; t++) deliver(halo_word(t, 0), halo_word(t, 1), halo_word(t, 2), halo_word(t, 3))@t;
    set_halo(halo_word(15, 0), halo_word(15, 1), halo_word(15, 2), halo_word(15, 3));
    last_change = relax();
    cache_edges();
    paint();
    s++;
  }
  for (t = 0; t < 15; t++) total = total + get_change()@t;
  return total + last_change;
}

int main(void) {
  /* Two hot spots near the centre, two cold spots in opposite corners. */
  hold(3, 3, 255)@5; hold(2, 3, 255)@5; hold(3, 2, 255)@5;
  hold(0, 0, 255)@10; hold(1, 0, 255)@10; hold(0, 1, 255)@10;
  hold(0, 0, 0)@0;
  hold(3, 3, 0)@15;
  return run(sweeps)@15;
}
