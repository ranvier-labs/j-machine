int sum_and_update(int *values, int count) {
  int index = 0;
  int total = 0;
  for (index = 0; index < count; index++) {
    total = total + values[index];
  }
  values[2] = 10;
  return total;
}

int main(void) {
  int data[4] = {1, 2, 3, 4};
  int value = 5;
  int *pointer = &value;
  int before = sum_and_update(data, 4);
  *pointer = *pointer + 7;
  return before + data[2] + *pointer + sizeof(data) + sizeof(int);
}
