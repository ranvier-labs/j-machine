/* Single-node form of the recursive factorial used as Figure 2.1 in
   Daniel Maskit's 1994 Message-Driven C thesis. */
int factorial(int n) {
  if (n == 0)
    return 1;
  return n * factorial(n - 1);
}

int main(void) {
  return factorial(6);
}
