/* Distinct unsigned scalar types cross the historical call(args)@rank ABI. */

unsigned int remote_observed;
_Bool remote_bool_observed;

unsigned int remote_wrap(unsigned int value) {
  remote_observed = value;
  return value + 2U;
}

_Bool remote_truth(_Bool value) {
  remote_bool_observed = value;
  return value;
}

int main(void) {
  unsigned int result;
  _Bool truth;
  result = remote_wrap(0xffffffffU)@1;
  truth = remote_truth(0xffffffffU)@1;
  return (result == 1U) + 2 * (truth == 1);
}
