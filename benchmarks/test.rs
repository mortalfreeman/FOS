fn main() {
    let mut sum: f64 = 0.0;
    for i in 0..50000000 {
        sum += (i * i) as f64;
    }
    println!("{:.2}", sum);
}
