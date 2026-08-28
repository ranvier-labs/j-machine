/* Multiword structs are transported by value through one MDC envelope. */

struct Pair {
  int left;
  int right;
};

typedef struct Pair (*transform_fn)(struct Pair, int);

int remote_pair_score;

struct Pair transform_pair(struct Pair value, int bias) {
  struct Pair result;
  int delay = 0;
  while (delay < 200) delay++;
  remote_pair_score = value.left * 10 + value.right;
  result.left = value.left + bias;
  result.right = value.right + computer();
  return result;
}

int aggregate_client(struct Pair value) {
  transform_fn transform = transform_pair;
  struct Pair result = transform(value, 5)@0;
  return result.left * 10 + result.right;
}

int main(void) {
  struct Pair value = {7, 3};
  int deferred_score = aggregate_client(value)@1;
  int synchronous_right = (transform_pair(value, 1)@1).right;
  return deferred_score + synchronous_right;
}
