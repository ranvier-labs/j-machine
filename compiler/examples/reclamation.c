int completed;

int remote_sum(int length, int *values) {
  int index = 0;
  int total = 0;
  while (index < length) {
    total = total + values[index];
    index++;
  }
  completed++;
  return total + completed;
}

int main(void) {
  int values[8] = {1, 2, 3, 4, 5, 6, 4, 3};
  int iteration = 0;
  int total = 0;
  while (iteration < 20) {
    total = total + remote_sum(8, values)@1;
    iteration++;
  }
  return total;
}
