int add2(int a, int b) {
  return a + b;
}

int main(void) {
  return add2(10, add2(20, 3));
}
