#include <iostream>
#include <cstdint>
int main() {
    double sum = 0;
    for(int64_t i = 0; i < 50000000; i++) {
        sum += (double)(i * i);
    }
    std::cout << sum << std::endl;
    return 0;
}
