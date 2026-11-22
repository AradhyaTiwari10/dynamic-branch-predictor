# nested_loop.s - 4 x (outer 10 x inner 4), like traces/nested_loop.mem
# Author : Yashvi
# Result : x10 = 4 * 10 * 4 = 160 (inner-loop iterations)
        addi x10, x0, 0         # iteration count
        addi x7, x0, 0          # r = 0 (repeat counter)
        addi x8, x0, 4
rep:    addi x3, x0, 0          # o = 0 (outer counter)
        addi x4, x0, 10
outer:  addi x1, x0, 0          # n = 0 (inner counter)
        addi x2, x0, 4
inner:  addi x10, x10, 1
        addi x1, x1, 1
        bne  x1, x2, inner      # inner: T,T,T,N
        addi x3, x3, 1
        bne  x3, x4, outer      # outer: taken 9 of 10 times
        addi x7, x7, 1
        bne  x7, x8, rep
        ebreak
