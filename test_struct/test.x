.use GOIO

struct Point {
    x, y
}

func main {
    con("=== Struct Test ===");
    p = Point();
    p.x = 10;
    p.y = 20;
    con("p.x = ", p.x);
    con("p.y = ", p.y);

    p.x = p.x + 5;
    con("after p.x += 5: p.x = ", p.x);
}
