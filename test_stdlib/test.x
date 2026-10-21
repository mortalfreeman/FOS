.use GOIO
.use GOMATH
.use GOSTRING

func main {
    con("=== Test abs ===");
    con("abs(-5.5) = ", abs(-5.5));
    con("abs(3.14) = ", abs(3.14));

    con("\n=== Test min/max ===");
    con("min(10, 20) = ", min(10, 20));
    con("max(10, 20) = ", max(10, 20));

    con("\n=== Test sqrt ===");
    con("sqrt(25) = ", sqrt(25));

    con("\n=== Test to_int ===");
    con("to_int(\"123\") = ", to_int("123"));
    con("to_int(3.99) = ", to_int(3.99));

    con("\n=== Test to_string ===");
    s = to_string(42.5);
    con("to_string(42.5) = ", s);
}
