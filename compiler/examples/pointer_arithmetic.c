int main(void) {
  int values[6] = {10, 20, 30, 40, 50, 60};
  int *begin = values;
  int *cursor = begin + 4;
  cursor--;
  int distance = cursor - begin;
  int via_commuted_add = *(2 + begin);
  int encoded_address = (int)cursor;
  int *round_trip = (int *)encoded_address;
  int null_equal = (int *)0 == (int *)0;
  int ordered = cursor > begin;
  int same_element = &values[2] == begin + 2;
  return *cursor + distance + via_commuted_add + *round_trip
      + null_equal + ordered + same_element;
}
