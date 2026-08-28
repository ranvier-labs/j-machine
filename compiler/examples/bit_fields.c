struct Packed {
  unsigned int low : 3;
  signed int delta : 5;
  unsigned int : 4;
  unsigned int marker : 4;
  unsigned int : 0;
  _Bool ready : 1;
  volatile unsigned int high : 31;
  int tail;
};

union Overlay {
  signed int signed_part : 8;
  unsigned int bits : 4;
};

struct Crossing {
  unsigned int wide : 30;
  unsigned int next : 4;
  unsigned int rest : 28;
};

struct Packed state;
union Overlay overlay;
int observed[6];
struct Packed initialized = {3, -2, 10, 1, 9, 4};
struct Packed designated = {
  .high = 5,
  .low = 2,
  .delta = -1,
  .marker = 11,
  .ready = 1,
  .tail = 6
};
struct Crossing crossing = {1, 10, 0xabc};

int main(void) {
  struct Packed local = {1, -4, 12, 1, 3, 2};
  state.low = 5;
  state.delta = -3;
  state.marker = 9;
  state.ready = 7;
  state.high = 0x7fffffff;

  int prior = state.low++;
  state.delta += 2;
  ++state.ready;
  state.high >>= 28;

  overlay.signed_part = -2;

  observed[0] = state.low;
  observed[1] = state.delta;
  observed[2] = state.ready;
  observed[3] = state.high;
  observed[4] = prior;
  observed[5] = overlay.bits;

  return sizeof(struct Packed) + observed[0] + observed[1] + observed[2]
      + observed[3] + observed[4] + observed[5]
      + initialized.low + initialized.delta + initialized.ready
      + initialized.marker + initialized.high + initialized.tail
      + designated.low + designated.delta + designated.ready
      + designated.marker + designated.high + designated.tail
      + local.low + local.delta + local.marker + local.ready + local.high
      + local.tail + crossing.wide + crossing.next + crossing.rest;
}
