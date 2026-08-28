int observed = 0;

void record(int value) {
  observed = value + computer();
}

int remote_add(int left, int right) {
  return left + right + computer() * 100;
}

int main(void) {
  record(40)@1;
  return remote_add(20, 22)@1;
}
