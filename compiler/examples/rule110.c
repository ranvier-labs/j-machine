/* A space-time diagram of Rule 110. The display is 32 columns by 24 rows.
   White pixels are live cells; the initial row contains one live cell. */
int display_width = 32;
int display_height = 24;
int display_frame;
int display_pixels[768];

int main(void) {
  int cells[32];
  int next[32];
  int x = 0;
  while (x < 32) { cells[x] = x == 30; x++; }
  int y = 0;
  while (y < 24) {
    x = 0;
    while (x < 32) {
      display_pixels[y * 32 + x] = cells[x] ? 0xe4d6ad : 0x10151c;
      int left = cells[(x + 31) % 32];
      int right = cells[(x + 1) % 32];
      int pattern = left * 4 + cells[x] * 2 + right;
      next[x] = (110 >> pattern) & 1;
      x++;
    }
    x = 0;
    while (x < 32) { cells[x] = next[x]; x++; }
    display_frame++;
    y++;
  }
  return 24;
}
