int values[3] = {1, 2, 3};
_Atomic int counter = 1;
volatile _Atomic unsigned int flags = 0xf0U;
int * _Atomic cursor;

struct Pair {
  int x;
  int y;
};

union Cell {
  int value;
  unsigned int bits;
};

typedef _Atomic(struct Pair) AtomicPair;

_Atomic(struct Pair) pair = {7, 11};
_Atomic struct Pair slots[2];
_Atomic(union Cell) cell = {5};
volatile AtomicPair volatile_pair = {2, 3};

int main(void) {
  _Atomic(int) local = 4;
  int old = local++;
  ++local;
  counter += 2;
  flags |= 0x0fU;
  cursor = values;
  cursor += 2;
  cursor -= 1;
  *cursor = 7;
  cursor--;

  struct Pair initial = pair;
  pair = (struct Pair){13, 17};
  struct Pair copied = pair;

  AtomicPair local_pair = {19, 23};
  struct Pair local_copy = local_pair;

  slots[1] = (struct Pair){29, 31};
  struct Pair array_copy = slots[1];

  AtomicPair *pair_pointer = &pair;
  struct Pair assignment_value =
    (*pair_pointer = (struct Pair){37, 41});
  struct Pair pointer_copy = *pair_pointer;

  cell = (union Cell){43};
  union Cell cell_copy = cell;

  volatile_pair = (struct Pair){47, 53};
  struct Pair volatile_copy = volatile_pair;

  return counter + old + local + flags + *cursor + values[1] +
    initial.x + initial.y + copied.x + copied.y +
    local_copy.x + local_copy.y + array_copy.x + array_copy.y +
    assignment_value.x + assignment_value.y +
    pointer_copy.x + pointer_copy.y + cell_copy.value +
    volatile_copy.x + volatile_copy.y;
}
