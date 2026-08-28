struct Flags {
  unsigned int code : 4;
  signed int delta : 6;
  _Bool ready : 1;
  unsigned int : 0;
  unsigned int count : 8;
};

struct Flags observed;

struct Flags update(struct Flags input) {
  input.code += 3;
  input.delta--;
  input.ready = 1;
  input.count += 5;
  observed = input;
  return input;
}

int main(void) {
  struct Flags initial = {10, -7, 0, 9};
  struct Flags result = update(initial)@1;
  return result.code + result.delta + result.ready + result.count;
}
