/* Narrow strings use one 32-bit character word plus a trailing zero word. */

char *global_text = "hello";
char global_array[] = "world";
char (*global_array_pointer)[6] = &global_array;
_Bool global_address_truth = &global_array;
int static_score_observed;
int static_size_observed;
int static_tail_observed;

int checksum(const char *text, int length) {
  int index = 0;
  int total = 0;
  while (index < length) {
    total = total + text[index];
    index++;
  }
  return total;
}

int static_string_score(void) {
  static char *pointer = "xy";
  static char exact_width[4] = "save";
  static char inferred[] = "q";
  static_size_observed = sizeof(inferred);
  static_tail_observed = inferred[1];
  return pointer[0] + pointer[1] + exact_width[0] + exact_width[3];
}

int main(void) {
  char local[] = "local";
  int inferred_numbers[] = {7, 8, 9};
  char *concatenated = "ab" "cd";
  char *escaped = "\n\x41\101";
  int score = 0;

  if (global_text[0] == 'h' && global_text[4] == 'o' && global_text[5] == 0)
    score = score + 1;
  if (checksum(global_array, 5) == 552 && global_array[5] == 0)
    score = score + 2;
  if (checksum(local, 5) == 523 && local[5] == 0 && sizeof(local) == 6 &&
      sizeof(inferred_numbers) == 3 && inferred_numbers[2] == 9)
    score = score + 4;
  if (checksum(concatenated, 4) == 394 && concatenated[4] == 0)
    score = score + 8;
  if (escaped[0] == 10 && escaped[1] == 'A' && escaped[2] == 'A' &&
      escaped[3] == 0)
    score = score + 16;
  if (sizeof("abc") == 4) score = score + 32;
  if ((*global_array_pointer)[1] == 'o' && global_address_truth == 1)
    score = score + 64;
  static_score_observed = static_string_score();
  if (static_score_observed == 457 && static_size_observed == 2 &&
      static_tail_observed == 0)
    score = score + 128;

  return score;
}
