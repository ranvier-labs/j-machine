// Minimal regression for erased parameters in StateT/Except compiler closures.
int main(void) {
  int values[2] = {1, 2};
  return values[1];
}
