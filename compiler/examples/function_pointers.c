typedef int (*binary_fn)(int, int);

int add(int lhs, int rhs) {
  return lhs + rhs;
}

int subtract(int lhs, int rhs) {
  return lhs - rhs;
}

binary_fn global_operation = add;

int apply(binary_fn operation, int lhs, int rhs) {
  return operation(lhs, rhs);
}

int main(void) {
  static binary_fn persistent_operation = subtract;
  binary_fn operation = global_operation;
  binary_fn null_operation = (binary_fn)0;
  int first = apply(operation, 40, 2);
  operation = &subtract;
  return first + (*operation)(50, 8) + persistent_operation(60, 18) +
         (global_operation != null_operation) + (null_operation == 0);
}
