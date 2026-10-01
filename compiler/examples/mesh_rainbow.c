/* Four distant corners of the 8x8x8 mesh render small RGB tiles.
   Inspect routes to nodes 7, 56, 448, and 511; display each node's tile. */
int display_width = 8;
int display_height = 8;
int display_frame;
int display_pixels[64];
int paint_corner(int color) {
  int y = 0;
  while (y < 8) {
    int x = 0;
    while (x < 8) {
      display_pixels[y * 8 + x] = color + x * 0x180000 + y * 0x001800;
      x++;
    }
    y++;
  }
  display_frame = 1;
  return 64;
}
int main(void) {
  int a = paint_corner(0x20)@7;
  int b = paint_corner(0x60)@56;
  int c = paint_corner(0xa0)@448;
  int d = paint_corner(0xe0)@511;
  return a + b + c + d;
}
