.set noreorder
    .set noat
    .global _start

_start:
    lui $4, 0xABCD
    sw $4, 0($0)
    addu $1, $0, $0

    lw $1, 0($0)
    addu $2, $1, $0
    addu $3, $1, $0

    lui $30, 0xDEAD

end_loop:
    j end_loop
    nop
