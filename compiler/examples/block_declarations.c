int value = 7, other = 2;

_Static_assert(8 * 8 * 8 == 512, "the FPGA mesh rank space is 512 nodes");

int helper(int input) {
  return input + 3;
}

int get_value(void) {
  return value;
}

int storage_classes(register int input) {
  _Static_assert(3 > 0, "the register loop has a positive trip count");
  auto int total = input;
  for (register int index = 0; index < 3; index++) {
    total += index;
  }
  return total;
}

int invoke(int value) {
  int (*helper)(int) = 0;
  {
    int helper(int), local = 5;
    extern int value;
    return helper(value) + local;
  }
}

int main(void) {
  int value = 100;
  {
    extern int value, other;
    value += other;
  }
  {
    extern int get_value(void);
    return invoke(4) + value + get_value() + storage_classes(5);
  }
}
