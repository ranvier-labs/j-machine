/* Four workers render a 2x2 mosaic. Open Graphical Display, choose mosaic.
   Each node owns a 16x16 RGB framebuffer. Arithmetic uses scale 128. */
int display_width = 16;
int display_height = 16;
int display_frame;
int display_pixels[256];

int render_tile(void) {
  int tile = computer();
  int y = 0;
  while (y < 16) {
    int x = 0;
    while (x < 16) {
      int cr = (x + (tile & 1) * 16) * 12 - 256;
      int ci = (y + (tile >> 1) * 16) * 12 - 192;
      int zr = 0;
      int zi = 0;
      int step = 0;
      while (step < 16 && zr * zr + zi * zi < 65536) {
        int next = ((zr * zr - zi * zi) >> 7) + cr;
        zi = ((2 * zr * zi) >> 7) + ci;
        zr = next;
        step++;
      }
      display_pixels[y * 16 + x] = step == 16 ? 0 : step * 0x0f0905;
      x++;
    }
    y++;
  }
  display_frame++;
  return 256;
}

int main(void) {
  int a = render_tile()@1;
  int b = render_tile()@2;
  int c = render_tile()@3;
  int local = render_tile();
  return local + a + b + c;
}
