# loop.s - 20 runs of a 10-iteration loop (same branch pattern as traces/loop.mem)
# Author : Yashvi
# Result : x10 = 20 * (0+1+...+9) = 900
        addi x10, x0, 0         # x10 = sum
        addi x3, x0, 0          # j = 0 (outer counter)
        addi x4, x0, 20         # outer limit
outer:  addi x1, x0, 0          # i = 0
        addi x2, x0, 10         # inner limit
inner:  add  x10, x10, x1       # sum += i
        xori x5, x1, 3          # extra ALU work in the loop body
        addi x1, x1, 1          # i++
        bne  x1, x2, inner      # taken 9 times, not taken once
        addi x3, x3, 1          # j++
        bne  x3, x4, outer
        ebreak
