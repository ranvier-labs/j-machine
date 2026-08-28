int classify(int value) {
  int result = 0;
  switch (value) {
    case 1:
      result = 10;
      break;
    if (value == 2) {
      case 2:
        result = 20;
        break;
    }
    while (0) {
      case 3:
        result = 30;
        break;
    }
    break;
    default:
      result = 99;
  }
  return result;
}

int direct_case(int value) {
  switch (value)
    case 4:
      return 40;
  return -1;
}

int nested_switch(int outer, int inner) {
  int result = 0;
  switch (outer) {
    case 1:
      switch (inner) {
        case 2:
          result = 12;
          break;
        default:
          result = 19;
      }
      break;
    default:
      result = 99;
  }
  return result;
}

int main(void) {
  return classify(1) + classify(2) + classify(3) + classify(8) +
      direct_case(4) + nested_switch(1, 2);
}
