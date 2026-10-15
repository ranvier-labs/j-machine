int observed = 7;

void record(int value) {
  observed = value;
}

int read_observed(void) {
  return observed;
}

int main(void) {
  record(41)@1;
  int remote = read_observed()@1;
  return observed * 100 + remote;
}
