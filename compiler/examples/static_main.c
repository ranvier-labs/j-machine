static int hidden = 3;

static int bump(void) {
  static int count = 4;
  count = count + 1;
  return count + hidden;
}

int library_value(void);
int library_second(void);

int main(void) {
  int hidden = 100;
  return bump() + bump() + library_value() + library_second() + hidden;
}
