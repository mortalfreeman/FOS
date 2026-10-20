.use GOIO

func main {
    sum = 0;
    for (i = 0; i < 50000000; i = i + 1) {
        sum = sum + i * i;
    }
    con(sum);
}
