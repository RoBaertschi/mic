int main(void) {
    for (int a = 0; a < 3; a++) {
        break;
        continue;
    }

    switch (1) { case 1: 1; default: 2; default: 3; case 1: 3; case 1 + 1: 4; }

    for (;;);
}
