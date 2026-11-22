# alternating.s - an if/else on (i & 1) for i = 0..199: branch pattern T,N,T,N
# Author : Yashvi
# Result : x10 = number of even i = 100, x11 = number of odd i = 100
        addi x10, x0, 0         # even count
        addi x11, x0, 0         # odd count
        addi x1, x0, 0          # i = 0
        addi x2, x0, 200
loop:   andi x5, x1, 1          # x5 = i & 1
        addi x10, x10, 1        # assume even
        beq  x5, x0, skip       # even -> taken (T), odd -> not taken (N)
        addi x10, x10, -1       # odd: undo
        addi x11, x11, 1
skip:   addi x1, x1, 1
        bne  x1, x2, loop
        ebreak
