/* C11 function specifiers and C99 external-inline linkage semantics. */

int inline advance(int value) {
  return value + 1;
}

int inline static inline local_twice(int value) {
  return value * 2;
}

void _Noreturn fail_forever(void);

void fail_forever(void) {
  for (;;) {
  }
}

int main(void) {
  return advance(20) + local_twice(10);
}
