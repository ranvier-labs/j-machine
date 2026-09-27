/* Conway's Life on a 4x4 mesh. Each node owns a 4x4 tile of a 16x16 torus
   and draws it, so the node mosaic shows the whole board. Node 15 runs the
   game as one long call from main: each generation it collects every tile's
   four edges, packed into one word, with a value-returning call, one
   request in flight at a time, assembles each tile's halo from its
   neighbours' edges, and delivers it with a one-way message. Receiving that
   halo is what makes a tile compute and draw its next generation; a tile
   never sends on its own, so no node is ever flooded. The result is the
   number of live cells after 16 generations, which a plain single-machine
   simulation of the same rules reproduces. */
int display_width = 4;
int display_height = 4;
int display_frame;
int display_pixels[16];

int generations = 16;

/* A tile is one word: bit y*4+x. Its edges are one word too: bits 0..3 the
   top row, 4..7 the bottom row, 8..11 the left column, 12..15 the right
   column. A halo is one word: bits 0..5 the row above with its corners,
   6..11 the row below, 12..15 the column to the left, 16..19 the right. */
int cell(int board, int x, int y) { return (board >> (y * 4 + x)) & 1; }
int edges_of(int board) {
  int i = 0;
  int e = 0;
  for (i = 0; i < 4; i++)
    e = e | (cell(board, i, 0) << i) | (cell(board, i, 3) << (4 + i)) | (cell(board, 0, i) << (8 + i)) | (cell(board, 3, i) << (12 + i));
  return e;
}
int grid[36];   /* the tile with its halo, 6x6, for plain-index counting */
int step(int board, int halo) {
  int x = 0;
  int y = 0;
  int at = 0;
  int n = 0;
  int next = 0;
  for (x = 0; x < 6; x++) { grid[x] = (halo >> x) & 1; grid[30 + x] = (halo >> (6 + x)) & 1; }
  for (y = 0; y < 4; y++) {
    at = (y + 1) * 6;
    grid[at] = (halo >> (12 + y)) & 1;
    grid[at + 5] = (halo >> (16 + y)) & 1;
    for (x = 0; x < 4; x++) grid[at + 1 + x] = cell(board, x, y);
  }
  for (y = 0; y < 4; y++) {
    for (x = 0; x < 4; x++) {
      at = (y + 1) * 6 + x + 1;
      n = grid[at - 7] + grid[at - 6] + grid[at - 5] + grid[at - 1] + grid[at + 1] + grid[at + 5] + grid[at + 6] + grid[at + 7];
      if (n == 3 || (n == 2 && grid[at])) next = next | (1 << (y * 4 + x));
    }
  }
  return next;
}
void paint(int board) {
  int i = 0;
  for (i = 0; i < 16; i++) display_pixels[i] = (board >> i) & 1 ? 0xd7ae68 : 0x101010;
  display_frame++;
}
int count(int board) {
  int i = 0;
  int alive = 0;
  for (i = 0; i < 16; i++) alive = alive + ((board >> i) & 1);
  return alive;
}

/* ---- a tile on nodes 0..14 ---- */
int board = 0;
int edges = 0;
void set_board(int b) { board = b; edges = edges_of(b); paint(b); }
int get_edges(void) { return edges; }
int get_board(void) { return board; }
void deliver(int halo) { board = step(board, halo); edges = edges_of(board); paint(board); }

/* ---- node 15: the game loop ---- */
int all_edges[16];
int seeds[16];
int tile_at(int tx, int ty) { return ((ty + 4) & 3) * 4 + ((tx + 4) & 3); }
int halo_of(int who) {
  int tx = who & 3;
  int ty = who >> 2;
  int up = all_edges[tile_at(tx, ty - 1)];
  int down = all_edges[tile_at(tx, ty + 1)];
  return ((all_edges[tile_at(tx - 1, ty - 1)] >> 7) & 1) | (((up >> 4) & 15) << 1) | (((all_edges[tile_at(tx + 1, ty - 1)] >> 4) & 1) << 5)
       | (((all_edges[tile_at(tx - 1, ty + 1)] >> 3) & 1) << 6) | ((down & 15) << 7) | ((all_edges[tile_at(tx + 1, ty + 1)] & 1) << 11)
       | (((all_edges[tile_at(tx - 1, ty)] >> 12) & 15) << 12) | (((all_edges[tile_at(tx + 1, ty)] >> 8) & 15) << 16);
}
void seed(int tile, int b) { seeds[tile] = b; }
int run(int limit) {
  int gen = 0;
  int t = 0;
  int alive = 0;
  for (t = 0; t < 15; t++) set_board(seeds[t])@t;
  board = seeds[15];
  paint(board);
  while (gen < limit) {
    for (t = 0; t < 15; t++) all_edges[t] = get_edges()@t;
    all_edges[15] = edges_of(board);
    for (t = 0; t < 15; t++) deliver(halo_of(t))@t;
    board = step(board, halo_of(15));
    paint(board);
    gen++;
  }
  for (t = 0; t < 15; t++) alive = alive + count(get_board()@t);
  return alive + count(board);
}

int main(void) {
  /* A glider in tile 0, an R-pentomino in tile 5, a second glider heading
     the other way in tile 10, and a blinker in tile 15. Rows are nibbles. */
  seed(0, 0x0742)@15;
  seed(5, 0x0236)@15;
  seed(10, 0x0471)@15;
  seed(15, 0x0070)@15;
  return run(generations)@15;
}
