/* The dynamic envelope is 7 fixed words + one length + 1013 payload words. */

int values[1023];
int remote_was_entered;

int consume(int length, int *data) {
  remote_was_entered = 1;
  return length + data[0];
}

int main(void) {
  return consume(1013, values)@1;
}
