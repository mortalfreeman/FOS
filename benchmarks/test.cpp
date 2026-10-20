#include <iostream>
int main() {
    double sum = 0;
    for(int i = 0; i < 50000000; i++) {
        sum += i * i;
    }
    std::cout << sum << std::endl;
    return 0;
}
