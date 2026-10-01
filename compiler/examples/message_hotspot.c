/* Four senders converge on node 5 of a 4x4 mesh. Watch its queues and links.
   Display node 5: each sender paints a pair of columns as its calls complete. */
int display_width = 8;
int display_height = 8;
int display_frame;
int display_pixels[64];

int paint(int lane, int row) {
  int color = (lane + 1) * 0x302010 + row * 0x030508;
  display_pixels[row * 8 + lane * 2] = color;
  display_pixels[row * 8 + lane * 2 + 1] = color;
  display_frame++;
  return 1;
}
int burst(int lane) {
  int row = 0;
  int total = 0;
  while (row < 8) { total = total + paint(lane, row)@5; row++; }
  return total;
}
int main(void) {
  int a = burst(0)@3;
  int b = burst(1)@12;
  int c = burst(2)@15;
  int d = burst(3)@0;
  return a + b + c + d;
}
