/* Nested C99 initializers, designators, brace elision, and later overrides. */

struct Pair {
  int x;
  int y;
};

struct Outer {
  struct Pair pair;
  int tail;
};

struct Text {
  char text[4];
  int value;
};

union Choice {
  int scalar;
  int words[3];
  int *pointers[3];
};

int global_array[6] = {[2] = 5, 6, [0] = 1};
struct Outer global_outer = {
  .tail = 9,
  .pair = {.y = 4, .x = 3}
};
int inferred[] = {[4] = 7, 8};
struct Text global_text = {.value = 2, .text = "abc"};
union Choice global_union = {.words = {[1] = 11, [2] = 13}};

struct Pair make_pair(int x, int y) {
  struct Pair result = {.x = x, .y = y};
  return result;
}

int main(void) {
  static struct Outer persistent = {
    .pair.x = 10,
    .tail = 12,
    .pair.y = 11
  };
  struct Pair values[3] = {
    [2] = make_pair(22, 23),
    [0] = {.y = 18, .x = 17},
    [1] = {20, 21}
  };
  struct Outer brace_elided = {1, 2, 3};
  struct Outer nested = {{4, 5}, 6};
  union Choice choice = {.pointers = {[1] = 0}};
  union Choice union_continuation = {.words[1] = 14, 15};
  struct Outer chained_continuation = {.pair.x = 40, 41, 42};
  struct Pair *literal = &(struct Pair){.y = 31, .x = 30};
  struct Text local_text = {.value = 8, .text = {"xy"}};
  int overridden[2] = {[0] = 1, [0] = 9};
  struct Pair first_inferred = {50, 51};
  struct Pair inferred_pairs[] = {first_inferred, make_pair(52, 53)};

  return global_array[0] + global_array[2] + global_array[3] +
         global_outer.pair.x + global_outer.pair.y + global_outer.tail +
         sizeof(inferred) + inferred[4] + inferred[5] +
         global_text.text[2] + global_text.value +
         global_union.words[0] + global_union.words[1] +
         global_union.words[2] +
         persistent.pair.x + persistent.pair.y + persistent.tail +
         values[0].x + values[0].y + values[1].x + values[1].y +
         values[2].x + values[2].y +
         brace_elided.pair.x + brace_elided.pair.y + brace_elided.tail +
         nested.pair.x + nested.pair.y + nested.tail +
         !choice.pointers[0] + !choice.pointers[1] +
         !choice.pointers[2] + literal->x + literal->y +
         union_continuation.words[1] + union_continuation.words[2] +
         chained_continuation.pair.x + chained_continuation.pair.y +
         chained_continuation.tail +
         local_text.text[0] + local_text.text[1] +
         local_text.text[2] + local_text.value + overridden[0] +
         sizeof(inferred_pairs) + inferred_pairs[0].x +
         inferred_pairs[0].y + inferred_pairs[1].x + inferred_pairs[1].y;
}
