int power_negative;
int power_positive;
int power_int_min;

int main(void) {
  int q1 = 100 / 7;
  int q2 = -100 / 7;
  int q3 = 100 / -7;
  int r1 = -100 % 7;
  int r2 = 100 % -7;
  int r3 = -100 % 8;
  int r4 = 100 % 8;
  int r5 = (-2147483647 - 1) % 8;
  power_negative = r3;
  power_positive = r4;
  power_int_min = r5;
  return q1 - q2 - q3 + r1 + r2 + r3 + r4 + r5;
}
