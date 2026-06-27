int main(void) {
    int a = 3;

    if (a) a = 0;
    return a ? a : a ? a : a;
}
