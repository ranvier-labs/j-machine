/*
 * The historical MDC target is word addressed: every integer scalar object,
 * including char, occupies one 32-bit MDP payload word.  The types remain
 * distinct C types and signedness controls promotion and arithmetic.
 */

unsigned int global_max = 0xffffffffU;
signed char global_negative = -7;
_Bool global_truth = 19;
_Bool global_falsehood = 0;

unsigned int add_unsigned(unsigned int left, unsigned int right) {
  return left + right;
}

unsigned long divide_unsigned_long(unsigned long value, unsigned long divisor) {
  return value / divisor;
}

short preserve_short(short value) {
  return value;
}

_Bool preserve_bool(_Bool value) {
  return value;
}

int main(void) {
  unsigned int maximum = global_max;
  unsigned int zero = 0;
  unsigned char byte_rank = (unsigned char)-1;
  signed char signed_byte = -2;
  char plain_char = -1;
  char newline = '\n';
  unsigned char hexadecimal_character = '\xff';
  unsigned short short_rank = (unsigned short)-1;
  unsigned long long_rank = 0xffffffffUL;
  unsigned int *pointer = &maximum;
  _Bool truth = maximum;
  _Bool falsehood = 0;
  _Bool pointer_truth = pointer;
  _Bool old_truth = truth--;
  _Bool decremented_zero = 0;
  decremented_zero--;
  falsehood = maximum;
  int score = 0;

  if (maximum + 2 == 1) score = score + 1;
  if (zero - 1 == maximum) score = score + 2;
  if (maximum * 2 == (unsigned int)-2) score = score + 4;
  if (maximum / 03U == 1431655765U) score = score + 8;
  if (maximum % 3U == 0U) score = score + 16;
  if (maximum >> 31 == 1) score = score + 32;
  if (maximum > 7) score = score + 64;
  if (-maximum == 1) score = score + 128;
  if (byte_rank + 2 == 1) score = score + 256;
  if (signed_byte >> 1 == -1) score = score + 512;
  if (plain_char < 0 && global_negative == -7 && newline == 10 &&
      hexadecimal_character == 255 && '\101' == 'A') score = score + 1024;
  if (sizeof(char) == 1 && sizeof(short) == 1 && sizeof(int) == 1 &&
      sizeof(long) == 1) score = score + 2048;
  if (add_unsigned(maximum, 2) == 1) score = score + 4096;
  if (divide_unsigned_long(long_rank, 5UL) == 858993459UL) score = score + 8192;
  if (preserve_short((short)-9) == -9 && short_rank > 1 && *pointer == maximum)
    score = score + 16384;
  if (global_truth == 1 && global_falsehood == 0 && truth == 0 &&
      old_truth == 1 && decremented_zero == 1 && falsehood == 1 &&
      pointer_truth == 1 && (_Bool)pointer == 1 && (_Bool)0 == 0 &&
      (_Bool)add_unsigned == 1 && preserve_bool(maximum) == 1 &&
      sizeof(_Bool) == 1)
    score = score + 32768;

  return score;
}
