/*
 * Attributed adaptation of Figure 5.2 in Daniel Maskit, "A Message-Driven
 * Programming System for Fine-Grain Multicomputers," Caltech master's thesis,
 * 1994, DOI 10.7907/Z9J38QKJ. See historical/PROVENANCE.md for the complete
 * source and adaptation record.
 *
 * The published benchmark uses 2,500 sets of 40 messages. This bare-metal
 * regression uses two sets of eight, retains the array of deferred remote
 * return values and its second synchronization loop, and records termination
 * in globals instead of calling exit. The consumer's original return is zero;
 * payload_sum is additional instrumentation proving receipt of all data.
 */

#define RUNS 2
#define ITERATIONS 8
#define TARGET 1

int completed_runs = 0;
int return_sum = 0;
int consumer_count = 0;
int payload_sum = 0;

int consumer(int len, int *array) {
  int i = 0;
  int sum = 0;
  while (i < len) {
    sum = sum + array[i];
    i++;
  }
  payload_sum = payload_sum + sum;
  consumer_count++;
  return 0;
}

void producer(void) {
  int i = 0;
  int j = 0;
  int k = 0;
  int array[8] = {0, 1, 2, 3, 4, 5, 6, 7};
  int returns[ITERATIONS];

  for (k = 0; k < RUNS; k++) {
    for (i = 0; i < ITERATIONS; i++) {
      returns[i] = consumer(sizeof(array), array)@TARGET;
    }
    for (i = 0; i < ITERATIONS; i++) {
      j = returns[i];
      return_sum = return_sum + j;
    }
    completed_runs++;
  }
}

int main(void) {
  producer()@0;
  return 0;
}
