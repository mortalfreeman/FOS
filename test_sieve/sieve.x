.use GOIO
func main {
    count = 0;
    for (i = 2; i < 20; i = i + 1) {
        p = 1;
        for (j = 2; j * j <= i; j = j + 1) {
            if (i % j == 0) { p = 0; break; }
        }
        if (p == 1) { count = count + 1; }
    }
    con("Primes in 2..20: ", count);
}
