void sink(int a, int b, int c, int d, int e, int f) {
  (void)a;
  (void)b;
  (void)c;
  (void)d;
  (void)e;
  (void)f;
}

int main(void) {
  /* Twenty message words exceed the architectural eight-word SEND FIFO. */
  sink(1, 2, 3, 4, 5, 6)@1;
  return 77;
}
