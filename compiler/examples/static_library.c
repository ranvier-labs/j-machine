static int hidden = 20;

static int bump(void) {
  static int count = 1;
  count = count + 1;
  return hidden + count;
}

int library_value(void) {
  return bump();
}

int library_second(void) {
  return bump();
}
