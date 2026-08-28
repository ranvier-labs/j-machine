int remote_total;

int sum_array(int length, int *values) {
  int index = 0;
  int total = 0;
  while (index < length) {
    total = total + values[index];
    index++;
  }
  remote_total = total;
  return total + computer();
}

int main(void) {
  int values[8] = {0, 1, 2, 3, 4, 5, 6, 7};
  return sum_array(sizeof(values), values)@1;
}
