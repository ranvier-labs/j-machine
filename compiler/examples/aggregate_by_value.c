/* Full-width local aggregate parameter/result ABI, including indirect CALL. */

struct Pair {
  int x;
  int y;
};

typedef struct Pair Pair;

struct Wrapped {
  Pair value;
  int bias;
};

union Word {
  int signed_value;
  unsigned int unsigned_value;
};

typedef Pair (*combine_fn)(Pair, Pair);

Pair make_pair(int x, int y) {
  Pair result;
  result.x = x;
  result.y = y;
  return result;
}

Pair add_pairs(Pair left, Pair right) {
  left.x = left.x + right.x;
  left.y = left.y + right.y;
  return left;
}

struct Wrapped wrap_pair(Pair value, int bias) {
  struct Wrapped result;
  result.value = value;
  result.bias = bias;
  return result;
}

union Word preserve_word(union Word value) {
  return value;
}

int main(void) {
  Pair first = {3, 5};
  Pair second = {7, 11};
  Pair sum = add_pairs(first, second);
  Pair nested = add_pairs(make_pair(1, 2), sum);
  combine_fn combine = add_pairs;
  Pair indirect = combine(first, second);
  struct Wrapped wrapped = wrap_pair(indirect, 13);
  Pair copy;
  union Word word = {23};
  copy = wrapped.value;

  return sum.x + sum.y + nested.x + nested.y +
         indirect.x + indirect.y + wrapped.bias +
         make_pair(17, 19).y + first.x + first.y +
         second.x + second.y + copy.x + copy.y +
         (copy = make_pair(20, 22)).x +
         preserve_word(word).signed_value;
}
