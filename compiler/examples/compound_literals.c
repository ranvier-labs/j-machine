/* C99 compound literals are addressable objects, not temporary scalars. */

struct Pair {
  int x;
  int y;
};

struct Box {
  int value;
  int *pointer;
};

int sum_pair(struct Pair value) {
  return value.x + value.y;
}

int main(void) {
  /* The omitted pointer subobject must be an invalid ADDR null capability. */
  struct Box box = {7};
  struct Pair *mutable = &(struct Pair){4, 5};
  int *scalar = &(int){11};
  struct Pair *first = 0;
  int same_object = 0;
  int unevaluated = 0;

  mutable->x += 2;

  for (int index = 0; index < 2; index++) {
    struct Pair *current = &(struct Pair){index, 10};
    if (index == 0)
      first = current;
    else
      same_object = first == current && current->x == 1;
  }

  return !box.pointer + mutable->x + mutable->y +
         (int[]){7, 8, 9}[1] + *scalar +
         sum_pair((struct Pair){2, 3}) + same_object +
         (struct Pair){12, 13}.y +
         ((struct Pair){1, 2}.x = 9) +
         (char[]){"hi"}[1] +
         sizeof((int[3]){++unevaluated, 2, 3}) + unevaluated * 100;
}
