/*
 * Attributed adaptation of Figure 2.1 in Daniel Maskit, "A Message-Driven
 * Programming System for Fine-Grain Multicomputers," Caltech master's thesis,
 * 1994, DOI 10.7907/Z9J38QKJ. The thesis uses the placement name `next`; this
 * executable form defines it as the next allocated computer in the ring. See
 * historical/PROVENANCE.md for the complete source and adaptation record.
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
