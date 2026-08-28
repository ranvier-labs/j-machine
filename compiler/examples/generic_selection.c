struct Pair {
  int first;
  int second;
};

int side_effects;

int observe(void) {
  side_effects++;
  return 99;
}

int main(void) {
  int value = 5;
  unsigned int unsigned_value = 6U;
  int *pointer = &value;
  char character = 'a';
  struct Pair pair = {7, 8};

  _Generic(value, int: value, default: pair.first) = 11;
  int *selected_lvalue = &_Generic(unsigned_value,
      unsigned int: value, default: pair.second);
  ++*selected_lvalue;

  return value
      + _Generic(value, int: 1, default: observe())
      + _Generic(unsigned_value, unsigned int: 2, default: observe())
      + _Generic(pointer, int *: 3, default: observe())
      + _Generic(pair, struct Pair: 4, default: observe())
      + _Generic(character, char: 5, default: observe())
      + _Generic(observe(), int: pair.second, default: 0)
      + side_effects;
}
