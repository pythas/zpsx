.set noreorder
    .set noat
    .global _start

_start:
    lui $4, 0x9999
    sw $4, 0($0)

    lw $1, 0($0)
    addiu $1, $0, 42

    lui $30, 0xDEAD
    
end_loop:
    j end_loop
    nop
