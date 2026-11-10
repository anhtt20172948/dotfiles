#include <cstdio>

/// Doxygen comment: @brief adds numbers
int add(int a, int b) {
    if (a > b) { return a + b; }
    for (int i = 0; i < 3; ++i) { std::printf("%d\n", i); }
    return b;
}

class Box {
public:
    explicit Box(int v) : v_(v) {}
    int get() const { return v_; }
private:
    int v_;
};
