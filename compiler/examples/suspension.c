int visits;

int leaf(int value) {
  visits++;
  return value + computer();
}

int middle(int value) {
  int result;
  visits++;
  result = leaf(value)@0;

  /* This read takes FUT, saves the process, and executes SUSPEND. */
  return result + computer();
}

int main(void) {
  return middle(40)@1;
}
