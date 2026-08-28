struct Point {
  int x;
  int y;
};

extern int shared_value;
int twice(int value);
int sum_point(struct Point *point);

int main(void) {
  struct Point point = {4, 5};
  return twice(shared_value) + sum_point(&point) + sizeof(struct Point);
}
