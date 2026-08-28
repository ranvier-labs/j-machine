/*
 * Clean-room executable transcription of Maskit thesis Figure 5.1.
 *
 * The printed program sends 1,000,000 eight-word arrays to TARGET and exits
 * when the remote counter reaches that value. This bare-metal regression uses
 * 40 messages so both simulators finish quickly, replaces exit/msgFree with
 * inspectable globals, and targets logical rank 1. Bulk-message storage is
 * reclaimed automatically by the MDC runtime after consumer returns.
 */

#define ITERATIONS 40
#define TARGET 1

int counter = 0;
int one_way_done = 0;
int payload_sum = 0;

void consumer(int len, int *array) {
  int i = 0;
  int sum = 0;
  while (i < len) {
    sum = sum + array[i];
    i++;
  }
  payload_sum = payload_sum + sum;
  counter++;
  if (counter == ITERATIONS) one_way_done = 1;
}

void producer(void) {
  int i = 0;
  int array[8] = {0, 1, 2, 3, 4, 5, 6, 7};
  for (i = 0; i < ITERATIONS; i++) {
    consumer(sizeof(array), array)@TARGET;
  }
}

int main(void) {
  producer()@0;
  return 0;
}
