int main(void) {
  int x = 1;
  int total = 0;

  while (x < 20) {
    x++;
    if ((x & 1) == 0 && x != 10) {
      total = total + x;
    }
    if (x >= 14) {
      break;
    }
  }

  if (x == 14 || (total = 999)) {
    total = total + 0;
  }
  return total + ((3 << 2) ^ 1);
}
