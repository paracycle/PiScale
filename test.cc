#include <linux/joystick.h>
#include <stdio.h>

int main() {
  printf("%lu", JSIOCGVERSION);
}
