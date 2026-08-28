typedef int (*binary_fn)(int, int);

int unused(int lhs, int rhs) {
  return lhs - rhs;
}

int remote_add(int lhs, int rhs) {
  return lhs + rhs + computer();
}

int main(void) {
  binary_fn operation = remote_add;
  int result = operation(20, 22)@1;
  return result;
}
