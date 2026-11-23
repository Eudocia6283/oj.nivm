#include <cstdio>

int main() {
    long long a, b;
    if (std::scanf("%lld%lld", &a, &b) != 2) return 1;
    std::printf("%lld\n", b + a);
}
