int delayed_add(int value) {
  /* Keep the replies pending while the caller does independent work. */
  for (int i = 0; i < 1000; i++) {}
  return value + computer();
}

int main(void) {
  int first = delayed_add(10)@1;
  int second = delayed_add(20)@1;
  int independent = 7;
  return first + second + independent; /* Consume the futures here. */
}
