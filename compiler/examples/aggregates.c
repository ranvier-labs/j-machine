struct Pair {
  int x;
  int y;
};

union Cell {
  int scalar;
  int words[2];
};

struct Outer {
  struct Pair pair;
  int tail;
};

struct Node {
  int value;
  struct Node *next;
};

int main(void) {
  struct Pair pairs[3];
  struct Pair *pointer = pairs;
  struct Outer outer;
  union Cell cell;
  struct Pair copy;

  pairs[0].x = 2;
  pairs[0].y = 3;
  pairs[1].x = 5;
  pairs[1].y = 7;
  pairs[2].x = 11;
  pairs[2].y = 13;
  (pointer + 2)->y = 17;

  outer.pair.x = 19;
  outer.pair.y = 23;
  outer.tail = 29;

  cell.words[0] = 31;
  cell.words[1] = 37;
  copy = pairs[1];
  struct Pair initialized = pairs[0];
  struct Pair literal = {41, 43};
  union Cell cell_copy = cell;
  struct Node nodes[2];
  nodes[1].value = 47;
  nodes[0].next = &nodes[1];

  return pointer[0].x + (pointer + 1)->y + pointer[2].y
      + outer.pair.x + outer.pair.y + outer.tail
      + cell.scalar + cell.words[1]
      + sizeof(struct Pair) + sizeof(struct Outer) + sizeof(union Cell)
      + ((pointer + 2) - pointer)
      + copy.x + copy.y + initialized.x + initialized.y
      + literal.x + literal.y + cell_copy.words[0] + cell_copy.words[1]
      + nodes[0].next->value + sizeof(struct Node);
}
