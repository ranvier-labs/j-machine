/*
 * Maskit, Figure 2.1.  The thesis uses the placement name `next`; this
 * executable form defines it as the next allocated computer in the ring.
 */
int factorial(int n) {
  int answer;
  if (!n) {
    answer = 1;
  } else {
    int next = (computer() + 1) % computers();
    int i = factorial(n - 1)@next;
    answer = n * i;
  }
  return answer;
}

int main(void) {
  return factorial(6);
}
