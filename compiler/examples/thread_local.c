_Thread_local int counter = 3;
static _Thread_local int internal_total = 4;
extern _Thread_local int counter;

int update(int amount) {
  extern _Thread_local int counter;
  _Thread_local static int calls = 1;
  counter += amount;
  calls++;
  internal_total += calls;
  return counter + calls + internal_total + computer();
}

int main(void) {
  int local = update(2);
  int remote = update(5)@1;
  return local + remote;
}
