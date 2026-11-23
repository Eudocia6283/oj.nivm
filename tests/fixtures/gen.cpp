#include <cstdlib>
#include <iostream>
#include <random>

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    std::mt19937 random(std::strtoul(argv[1], nullptr, 10));
    const auto generate = [&random]() {
        return static_cast<long long>(random() % 2000000001ULL) - 1000000000LL;
    };
    const auto a = generate();
    const auto b = generate();
    std::cout << a << ' ' << b << '\n';
}
