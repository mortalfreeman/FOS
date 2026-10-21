.use GOIO
func main {
    x = 10;
    arr = [1, 2, 3];
    con("x = ", x);
    con("arr[0] = ", arr[0]);
    con("arr[1] = ", arr[1]);
    con("arr[2] = ", arr[2]);
    arr[1] = 99;
    con("arr[1] after change = ", arr[1]);
    con("x after change = ", x);
}
