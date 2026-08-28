struct AlignedPair {
  int head;
  _Alignas(8) int tail;
};

_Alignas(8) int global_aligned = 5;
extern _Alignas(8) int global_aligned;

static _Alignas(16) int static_aligned = 7;

int aligned_parameter(struct AlignedPair value) {
  if (((unsigned long)&value & 7U) != 0U) return 1000;
  return value.head + value.tail;
}

int main(void) {
  int prefix = 3;
  _Alignas(8) int local_aligned = 11;
  _Alignas(0) _Alignas(_Alignof(int) * 16) int strongest_aligned = 13;
  struct AlignedPair pair = {17, 19};

  int score = _Alignof(int);
  if (((unsigned long)&global_aligned & 7U) == 0U) score = score + 2;
  if (((unsigned long)&static_aligned & 15U) == 0U) score = score + 4;
  if (((unsigned long)&local_aligned & 7U) == 0U) score = score + 8;
  if (((unsigned long)&strongest_aligned & 15U) == 0U) score = score + 16;
  if (_Alignof(struct AlignedPair) == 8) score = score + 32;
  if (sizeof(struct AlignedPair) == 16) score = score + 64;
  if (((unsigned long)&pair & 7U) == 0U) score = score + 128;
  if (&pair.tail - &pair.head == 8) score = score + 256;
  if (((unsigned long)&(struct AlignedPair){1, 2} & 7U) == 0U)
    score = score + 512;
  return score + prefix + global_aligned + static_aligned +
    local_aligned + strongest_aligned + aligned_parameter(pair);
}
