#define LIMIT 10

int total = 0;

int main(void) {
  int i = 0;
  for (i = 0; i < LIMIT; i++) {
    if (i == 5)
      continue;
    total = total + i;
  }
  return total;
}
