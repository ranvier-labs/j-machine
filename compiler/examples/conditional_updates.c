int selected_trace;
int null_observed;
int pointer_observed;
int compound_trace;
unsigned int unsigned_trace;

int select_value(int value) {
  selected_trace = selected_trace * 10 + value;
  return value;
}

int main(void) {
  int values[4] = {10, 20, 30, 40};
  int index = 0;

  /* Both nested update lvalues must evaluate index++ exactly once. */
  int old = values[index++]++;
  int prefix = ++values[index++];

  /* The unselected conditional arm must not execute. */
  int selected = 1 ? select_value(3) : select_value(7);
  int nested = 0 ? 1 : 1 ? 5 : 9;

  int loop = 0;
  int sum = 0;
  do {
    ++loop;
    if (loop == 2) continue;
    sum = sum + loop;
    if (loop == 4) break;
  } while (loop < 10);

  int *pointer = values;
  ++pointer;
  int *chosen = 0 ? 0 : pointer;
  int *null_pointer = 1 ? 0 : pointer;
  null_observed = null_pointer == 0;
  pointer_observed = pointer ? 1 : 0;

  int compound = 20;
  int checksum = 0;
  compound += 5; checksum = checksum + compound;
  compound -= 3; checksum = checksum + compound;
  compound *= 2; checksum = checksum + compound;
  compound /= 4; checksum = checksum + compound;
  compound %= 6; checksum = checksum + compound;
  compound <<= 3; checksum = checksum + compound;
  compound >>= 2; checksum = checksum + compound;
  compound |= 5; checksum = checksum + compound;
  compound ^= 3; checksum = checksum + compound;
  compound &= 10; checksum = checksum + compound;
  compound_trace = checksum;

  /* A compound-assignment lvalue is also evaluated exactly once. */
  int side_index = 0;
  values[side_index++] += 5;
  int *compound_pointer = values;
  compound_pointer += 2;
  compound_pointer -= 1;

  unsigned int wrap = 0xffffffffU;
  wrap += 2U;
  wrap *= 3U;
  wrap <<= 31U;
  wrap >>= 31U;
  wrap -= 2U;
  wrap /= 5U;
  wrap %= 7U;
  wrap &= 3U;
  wrap ^= 7U;
  wrap |= 8U;
  unsigned_trace = wrap;

  return old + prefix + selected + nested + sum + loop + selected_trace +
    index + values[0] + values[1] + *chosen + null_observed + pointer_observed +
    compound_trace + side_index + *compound_pointer + (unsigned_trace == 13U);
}
