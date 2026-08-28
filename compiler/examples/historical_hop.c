/* Maskit, Figure 3.3: traverse the allocated machine four times. */
#define NUM_REPS 4

/* Architectural observation replaces the thesis program's host printf. */
int hop_visits;
int hop_last;
int hop_done;

void Hop(int size, int *rep) {
  int next = (computer() + 1) % computers();

  if (computer() == 0) {
    (*rep)++;
  }

  if (*rep <= NUM_REPS) {
    hop_visits++;
    hop_last = computer() * (*rep);
    Hop(sizeof(int), rep)@next;
  } else {
    hop_done = *rep;
  }
}

int main(void) {
  int rep = 0;
  Hop(sizeof(rep), &rep);
  return 0;
}
