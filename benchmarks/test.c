#include <stdio.h>
int main() {
    double sum = 0;
    for(int i = 0; i < 50000000; i++) {
        sum += i * i;
    }
    printf("%.2f\n", sum);
    return 0;
}
