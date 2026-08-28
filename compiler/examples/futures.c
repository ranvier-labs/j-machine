int remote_completions;

int delayed_add(int value) {
  remote_completions++;
  return value + computer();
}

int main(void) {
  int first;
  int second;

  first = delayed_add(10)@1;
  second = delayed_add(20)@1;

  /* Both messages have been issued before either future is consumed. */
  return first + second;
}
