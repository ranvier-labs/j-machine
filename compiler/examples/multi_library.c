struct Point {
  int x;
  int y;
};

int shared_value = 9;

int twice(int value) {
  return value * 2;
}

int sum_point(struct Point *point) {
  return point->x + point->y;
}
