struct Pair {
  int x;
  int y;
};

int sum_words(const int * restrict words) {
  return words[0] + words[1];
}

int main(void) {
  const int words[2] = {4, 6};
  volatile int counter = 2;
  int mutable[1] = {1};
  int * const cursor = mutable;
  const struct Pair pair = {7, 8};

  cursor[0] = cursor[0] + 2;
  counter = counter + 1;
  return sum_words(words) + pair.x + pair.y + cursor[0] + counter;
}
