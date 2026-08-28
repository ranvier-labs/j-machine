int global_left = 2, global_right = 3, global_zero;

struct Pair {
  int x, y;
};

int add(int left, int right), identity(int value);
int *return_null(void);
int accepts_pointer(int *pointer);

int remote_seen;

int add(int left, int right) {
  return left + right;
}

int identity(int value) {
  return value;
}

int *return_null(void) {
  return 0;
}

int accepts_pointer(int *pointer) {
  return !pointer;
}

int remote_add(int value) {
  remote_seen = value;
  return value + 1;
}

int static_tick(void) {
  static int left = 1, right = 2;
  left++;
  right += 2;
  return left * 10 + right;
}

int main(void) {
  int trace = 0, selected = 0, local_sum = 0;
  int outer_i = 9;
  struct Pair pair = {2, 3};

  selected = (trace += 1, trace += 2, 7);
  int call_value = add((trace += 4, 5), 6);

  for (int i = 0, j = 4; i < 4; i++, j--) {
    local_sum += i * j;
  }
  local_sum += outer_i;

  int jumped = 0;
  goto count;
skipped:
  jumped = 100;
count:
  jumped += 1;
  if (jumped < 3) {
    goto count;
  }
  goto nested;
  goto skipped;
  {
    int skipped_initialization = 99;
nested:
    jumped += 4;
  }

  int remote_value = remote_add((trace += 8, 5))@1;
  int static_total = static_tick() + static_tick();

  int pointer_truth = 0;
  int *initialized_null = 0;
  pointer_truth += !initialized_null;
  pointer_truth += accepts_pointer(0);
  pointer_truth += return_null() == 0;
  int *pointer = &pair.x;
  if (pointer && !((int *)0)) {
    pointer_truth += 1;
  }
  while (pointer) {
    pointer_truth += 2;
    pointer = 0;
  }
  pointer = &pair.y;
  for (; pointer; pointer = 0) {
    pointer_truth += 4;
  }

  return global_left + global_right + global_zero + pair.x + pair.y +
      local_sum + trace + selected + call_value + jumped + remote_value +
      static_total + pointer_truth + identity(0);
}
