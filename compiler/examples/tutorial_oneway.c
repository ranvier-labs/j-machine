int observed = 0;

void record(int value) {
  /* Leave time to inspect the caller before this handler finishes. */
  for (int i = 0; i < 1000; i++) {}
  observed = value;
}

int read_observed(void) {
  return observed;
}

int main(void) {
  record(41)@1;
  int independent = 7; /* The caller continues after sending. */
  /* This later value-returning call waits for a result. */
  return independent + read_observed()@1;
}
