typedef int word_t;
typedef word_t word_pair_t[2];
typedef word_t *word_pointer_t;

struct Pair {
  word_t x;
  word_t y;
};

typedef struct Pair Pair;

int sum_pair(Pair *pair) {
  return pair->x + pair->y;
}

int main(void) {
  word_pair_t words = {7, 9};
  word_pointer_t cursor = words;
  Pair pair;

  pair.x = cursor[0];
  pair.y = cursor[1];
  return sum_pair(&pair) + sizeof(word_t) + (word_t)3;
}
