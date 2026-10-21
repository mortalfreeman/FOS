.use GOIO

func main {
    con("=== Test 2: String comparison ===");
    password = "secret";
    if (password == "secret") {
        con("Access granted!");
    } else {
        con("Access denied!");
    }

    con("\n=== Test 3: len() function ===");
    name = "X-lang";
    con("Length of string: ", len(name));
    arr = [10, 20, 30, 40];
    con("Length of array: ", len(arr));
}
