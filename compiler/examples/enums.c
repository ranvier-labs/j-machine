enum Flag {
  FLAG_ZERO,
  FLAG_START = 3,
  FLAG_MASK = (FLAG_START << 2) | 1,
  FLAG_NEGATIVE = -5,
  FLAG_HALF = FLAG_NEGATIVE / 2,
  FLAG_REMAINDER = FLAG_NEGATIVE % 2,
  FLAG_TRUTH = (FLAG_MASK > 10) && (FLAG_ZERO == 0),
  FLAG_SHORT_AND = 0 && (1 / 0),
  FLAG_SHORT_OR = 1 || (1 << 99)
};

typedef enum Flag Flag;

int global_mask = FLAG_MASK;

int select_flag(Flag flag) {
  int values[FLAG_TRUTH + 1] = {2, 7};

  switch (flag) {
    case FLAG_MASK:
      return global_mask + values[1] + sizeof(enum Flag)
          + FLAG_HALF - FLAG_REMAINDER;
    default:
      return 0;
  }
}

int main(void) {
  Flag flag = FLAG_MASK;
  return select_flag(flag);
}
