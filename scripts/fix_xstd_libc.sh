#!/bin/bash
set -e
cd ~/FOS

echo "==> Обновление xstd (добавление sys_write, memcpy, memset)..."
cat > xstd/src/lib.rs << 'EOF'
#![no_std]

use core::arch::asm;
use core::panic::PanicInfo;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    unsafe { sys_exit(1) }
}

unsafe fn syscall3(n: usize, a1: usize, a2: usize, a3: usize) -> usize {
    let ret: usize;
    asm!(
        "syscall",
        inlateout("rax") n => ret,
        in("rdi") a1,
        in("rsi") a2,
        in("rdx") a3,
        lateout("rcx") _,
        lateout("r11") _,
        options(nostack)
    );
    ret
}

#[no_mangle]
pub extern "C" fn sys_exit(code: usize) -> ! {
    unsafe {
        syscall3(60, code, 0, 0);
        loop {}
    }
}

#[no_mangle]
pub extern "C" fn sys_write(fd: usize, buf: *const u8, count: usize) -> usize {
    unsafe { syscall3(1, fd, buf as usize, count) }
}

// Реализация memcpy для LLVM
#[no_mangle]
pub unsafe extern "C" fn memcpy(dest: *mut u8, src: *const u8, n: usize) -> *mut u8 {
    let mut i = 0;
    while i < n {
        *dest.add(i) = *src.add(i);
        i += 1;
    }
    dest
}

// Реализация memset для LLVM
#[no_mangle]
pub unsafe extern "C" fn memset(dest: *mut u8, c: i32, n: usize) -> *mut u8 {
    let mut i = 0;
    while i < n {
        *dest.add(i) = c as u8;
        i += 1;
    }
    dest
}

#[no_mangle]
pub unsafe extern "C" fn memcmp(s1: *const u8, s2: *const u8, n: usize) -> i32 {
    let mut i = 0;
    while i < n {
        let a = *s1.add(i);
        let b = *s2.add(i);
        if a != b { return (a as i32) - (b as i32); }
        i += 1;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn bcmp(s1: *const u8, s2: *const u8, n: usize) -> i32 {
    memcmp(s1, s2, n)
}

#[no_mangle]
pub extern "C" fn rust_eh_personality() {}

#[no_mangle]
pub extern "C" fn malloc(size: usize) -> *mut u8 {
    unsafe {
        let current_brk = syscall3(12, 0, 0, 0);
        let new_brk = current_brk + ((size + 7) & !7);
        syscall3(12, new_brk, 0, 0);
        current_brk as *mut u8
    }
}

#[no_mangle]
pub extern "C" fn strlen(s: *const u8) -> usize {
    let mut len = 0;
    unsafe {
        while *s.add(len) != 0 { len += 1; }
    }
    len
}

#[no_mangle]
pub extern "C" fn strcpy(dest: *mut u8, src: *const u8) -> *mut u8 {
    let mut i = 0;
    unsafe {
        while *src.add(i) != 0 {
            *dest.add(i) = *src.add(i);
            i += 1;
        }
        *dest.add(i) = 0;
    }
    dest
}

#[no_mangle]
pub extern "C" fn strcat(dest: *mut u8, src: *const u8) -> *mut u8 {
    let mut i = 0;
    unsafe {
        while *dest.add(i) != 0 { i += 1; }
        let mut j = 0;
        while *src.add(j) != 0 {
            *dest.add(i) = *src.add(j);
            i += 1; j += 1;
        }
        *dest.add(i) = 0;
    }
    dest
}

#[no_mangle]
pub extern "C" fn print_str(s: *const u8) {
    let len = strlen(s);
    unsafe { sys_write(1, s, len); }
}

#[no_mangle]
pub extern "C" fn print_num(val: f64) {
    let mut num = val as i64;
    let mut buf = [0u8; 32];
    let mut i = 0;
    
    if num == 0 {
        unsafe { sys_write(1, b"0.00\0".as_ptr(), 4); }
        return;
    }
    
    let is_neg = num < 0;
    if is_neg { num = -num; }
    
    while num > 0 {
        buf[i] = (num % 10) as u8 + b'0';
        num /= 10;
        i += 1;
    }
    
    if is_neg {
        buf[i] = b'-';
        i += 1;
    }
    
    let mut j = 0;
    while j < i / 2 {
        let tmp = buf[j];
        buf[j] = buf[i - j - 1];
        buf[i - j - 1] = tmp;
        j += 1;
    }
    
    buf[i] = b'.';
    buf[i+1] = b'0';
    buf[i+2] = b'0';
    buf[i+3] = b'\0';
    i += 4;
    
    unsafe { sys_write(1, buf.as_ptr(), i); }
}
EOF

echo "==> Пересборка xstd и компилятора..."
cargo build --release -p xstd
cp target/release/libxstd.a .

cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск теста..."
cp libxstd.a ~/test_zero_full/
cd ~/test_zero_full
xc zero.x -out zero
./zero

echo -e "\nПроверка зависимостей (ldd):"
ldd ./zero || echo "Нет динамических зависимостей (статика)!"
