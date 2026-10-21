.use GOIO
func main {
    x = 10;
    x += 5;
    con("x after += 5: ", x);
    x *= 2;
    con("x after *= 2: ", x);

    arr = [1, 2, 3];
    con("arr[1] = ", arr[1]);

    con("Testing bounds check (arr[5] should fail):");
    con(arr[5]);
}
