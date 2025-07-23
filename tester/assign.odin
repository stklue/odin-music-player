package main

import "core:fmt"

Foo::struct {
    x, y: f32
}

Bar::struct {
    x, y: f32,
    s: string
}

main::proc() {
    x: [dynamic]Foo
    append(&x, Foo{})
    fmt.printfln("%p, %d, %v", &x,&x, x)
    y: [dynamic]Bar
    append(&y, Bar{})
    fmt.println(&y, y)
}