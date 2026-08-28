/* A word string can use MDC's historical length/int-pointer bulk envelope. */

int remote_string_sum;

int remote_checksum(int length, int *data) {
  int index = 0;
  int total = 0;
  while (index < length) {
    total = total + data[index];
    index++;
  }
  remote_string_sum = total;
  return total + computer();
}

int main(void) {
  return remote_checksum(3, (int *)("M" "DC"))@1;
}
