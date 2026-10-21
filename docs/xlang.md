# X-lang: Полное руководство

**Девиз:** Fast = Easy, Fast = Secure.

## 1. Установка и первый проект

**Зависимости:**
~~~bash
sudo pacman -S rust llvm clang
~~~

**Сборка компилятора:**
~~~bash
cargo build --release
cp target/release/xlang-compiler ~/.local/bin/xc
~~~

**Создание проекта:**
~~~bash
xc new myproject
cd myproject
xc run main.x
~~~

## 2. Синтаксис и типы

Файлы: `.x` (код), `.xx` (модули), `.xxx` (глобальные), `.xh` (заголовки).
Комментарии: `! инлайновый комментарий !`

Типы выводятся автоматически:
- `i64` — целые числа
- `f64` — дробные числа
- `String` — строки
- `Array` — массивы
- `Struct` — структуры

Переменные обязательно инициализируются: `x = 0;`

Ввод/вывод:
~~~xlang
con("Текст ", x);
ci("Введите число: ", x);
~~~

## 3. Переменные и операторы

- Арифметика: `+`, `-`, `*`, `/`, `%`, `^`
- Сравнение: `==`, `!=`, `<`, `>`, `<=`, `>=`
- Компаунд: `+=`, `-=`, `*=`, `/=`
- Указатели: `p = &x; *p = 100;`

## 4. Управление потоком

- `if (x > 0) { ... } else { ... }`
- `while (i < 10) { ... }`
- `for (i = 0; i < 10; i += 1) { ... }`
- `for (x in arr) { ... }`
- `switch (x) { case 1: ... break; default: ... }`
- `break;` и `continue;`

## 5. Функции

~~~xlang
func add(a, b) {
    return a + b;
}
func main {
    con(add(10, 20));
}
~~~
Функции принимают и возвращают `f64`.

## 6. Массивы

~~~xlang
arr = [1, 2, 3];
big = [0; 1000000];
con(arr[0]);
arr[1] = 99;
len(arr);
~~~
Выход за границы вызывает `Runtime Error` (отключается флагом `--nosec`).

## 7. Структуры

~~~xlang
struct Point {
    x, y
}
func main {
    p = Point();
    p.x = 10;
    p.y = 20;
    con("Point: ", p.x, ", ", p.y);
}
~~~

## 8. Макросы ($alias)

~~~xlang
$alias greet {
    con("Hello from macro!");
}
func main { $greet; }
~~~
Для библиотек используйте `.xh` файлы с `#Define Header=Name ... #END`.

## 9. Стандартная библиотека

- **GOIO**: `con()`, `ci()`
- **GOMATH**: `abs`, `min`, `max`, `sqrt`, `powr`, `sin`, `cosin`, `round`, `floor`, `ceil`
- **GOSTRING**: `len`, `to_int`, `to_string`
- **FILEMAN**: `file-new`, `file-read`, `file-open`, `file-write`, `file-close`

## 10. CLI-менеджер

- `xc new <name>` — создать проект.
- `xc run <file>` — скомпилировать и запустить.
- `xc build <file>` — только скомпилировать.

## 11. Режимы компиляции

- `xc main.x -out main` — dynamic (ELF, 16 КБ).
- `xc main.x -static -out main` — static (900 КБ).
- `xc main.x --pure-asm -out main` — pure asm (10 КБ, без libc).
- `xc main.x --target windows -out main.exe` — Windows (PE32+).

## 12. Безопасность (Safe by default)

- Выход за границы массива: `Runtime Error: Index out of bounds`.
- Деление на ноль: `Runtime Error: Division by zero`.
- Переполнение: `Runtime Error: Integer overflow`.
- Неинициализированная переменная: `compile error`.

Всё отключается флагом `--nosec` для максимальной скорости.
