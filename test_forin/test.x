.use GOIO
.use GOMATH

func main {
    con("=== For-in Test ===");
    numbers = [10, 20, 30, 40];
    sum = 0;
    for (num in numbers) {
        con("num = ", num);
        sum = sum + num;
    }
    con("Sum = ", sum);

    con("\n=== Math Test ===");
    con("tan(0.785) = ", tan(0.785));
    con("log(2.718) = ", log(2.718));
    con("exp(1.0) = ", exp(1.0));
    con("asin(0.5) = ", asin(0.5));
    con("acos(0.5) = ", acos(0.5));
    con("atan(1.0) = ", atan(1.0));
}
