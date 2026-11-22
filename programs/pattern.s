# pattern.s - counts multiples of 3 with a mod-3 counter: period-3 branch patterns
# Author : Yashvi
# Result : x10 = number of i in 0..149 with i % 3 == 0 = 50
        addi x10, x0, 0         # count
        addi x1, x0, 0          # i = 0
        addi x2, x0, 150
        addi x6, x0, 0          # k = i % 3
        addi x9, x0, 3
loop:   bne  x6, x0, skip       # k != 0 -> taken: pattern N,T,T
        addi x10, x10, 1        # i is a multiple of 3
skip:   addi x6, x6, 1
        bne  x6, x9, nowrap     # k != 3 -> taken: pattern T,T,N
        addi x6, x0, 0          # wrap k to 0
nowrap: addi x1, x1, 1
        bne  x1, x2, loop
        ebreak
