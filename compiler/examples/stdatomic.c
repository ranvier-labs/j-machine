#include <stdatomic.h>

struct Pair {
  int x;
  int y;
};

typedef _Atomic(struct Pair) AtomicPair;

int values[4] = {1, 2, 3, 4};
atomic_int counter = ATOMIC_VAR_INIT(5);
atomic_uint bits = 3U;
int * _Atomic cursor;
AtomicPair pair = {1, 2};
atomic_flag flag = ATOMIC_FLAG_INIT;

int main(void) {
  atomic_int local;
  atomic_init(&local, 10);

  int score = atomic_load(&counter);
  atomic_store_explicit(&counter, 7, memory_order_release);
  score += atomic_exchange(&counter, 9);

  int expected = 8;
  score += atomic_compare_exchange_strong(&counter, &expected, 11);
  score += expected;
  score += atomic_compare_exchange_weak_explicit(
    &counter, &expected, 13,
    memory_order_acq_rel, memory_order_acquire);

  score += atomic_fetch_add(&counter, 4);
  score += atomic_fetch_sub_explicit(&counter, 2, memory_order_seq_cst);
  score += atomic_fetch_or(&bits, 8U);
  score += atomic_fetch_xor_explicit(&bits, 2U, memory_order_relaxed);
  score += atomic_fetch_and(&bits, 7U);

  atomic_store(&cursor, values);
  int *old_pointer = atomic_fetch_add(&cursor, 2);
  score += *old_pointer;
  score += *atomic_load_explicit(&cursor, memory_order_acquire);
  old_pointer = atomic_fetch_sub(&cursor, 1);
  score += *old_pointer;

  score += atomic_flag_test_and_set(&flag);
  score += atomic_flag_test_and_set_explicit(&flag, memory_order_acquire);
  atomic_flag_clear_explicit(&flag, memory_order_release);
  score += atomic_flag_test_and_set(&flag);

  struct Pair loaded = atomic_load(&pair);
  score += loaded.x + loaded.y;
  atomic_store(&pair, (struct Pair){4, 5});
  struct Pair old_pair = atomic_exchange(&pair, (struct Pair){6, 7});
  score += old_pair.x + old_pair.y;

  struct Pair expected_pair = {0, 0};
  score += atomic_compare_exchange_strong(
    &pair, &expected_pair, (struct Pair){8, 9});
  score += expected_pair.x + expected_pair.y;
  score += atomic_compare_exchange_weak_explicit(
    &pair, &expected_pair, (struct Pair){8, 9},
    memory_order_seq_cst, memory_order_acquire);

  AtomicPair local_pair;
  atomic_init(&local_pair, (struct Pair){10, 11});
  loaded = atomic_load_explicit(&local_pair, memory_order_relaxed);
  score += loaded.x + loaded.y;
  score += atomic_load(&local);

  score += atomic_is_lock_free(&counter);
  score += atomic_is_lock_free(&pair);
  score += kill_dependency(atomic_load(&counter));
  score += ATOMIC_INT_LOCK_FREE + ATOMIC_POINTER_LOCK_FREE +
    ATOMIC_LLONG_LOCK_FREE;

  atomic_signal_fence(memory_order_acq_rel);
  atomic_thread_fence(memory_order_seq_cst);
  return score;
}
