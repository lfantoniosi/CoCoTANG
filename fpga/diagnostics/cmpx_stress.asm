        pragma 6809

; Exact JSR/RTS + CMPX stress sequence from Color BASIC startup.
;
; FPGA CoCo 2 ROM image layout:
;   image $0000-$1FFF -> CPU $A000-$BFFF and vectors $FFF2-$FFFF
;   image $2000-$3FFF -> CPU $8000-$9FFF
;
; This is assembled from $A000-$DFFF as a file-layout convenience. Bytes at
; assembler address $C000 become image offset $2000 and CPU address $8000.

FAIL_CODE      equ     $0104
FAIL_X         equ     $0105
FAIL_ROM_WORD  equ     $0107

        org     $A000
reset:
        clr     >FAIL_CODE
        jmp     test_setup

        fill    $FF,$A0C2-*
        org     $A0C2
test_setup:
        orcc    #$50            ; mask IRQ/FIRQ immediately before the test
        lds     #$7F00          ; JSR must write $A0CB at $7EFF/$7EFE

        org     $A0C8
test_loop:
        jsr     return_only     ; pushes $A0CB, then AD19 immediately RTS
        ldx     #$4558
        cmpx    $8000
        lbeq    $8002           ; exact match jumps through ROM back to A0C8

compare_failed:
        lda     #$E1
        sta     >FAIL_CODE
        stx     >FAIL_X
        ldd     $8000
        std     >FAIL_ROM_WORD
failed:
        bra     failed

        fill    $FF,$A0F0-*
        org     $A0F0
unexpected_interrupt:
        orcc    #$50
        lda     #$F0
        sta     >FAIL_CODE
unexpected_hang:
        bra     unexpected_hang

        fill    $FF,$AD19-*
        org     $AD19
return_only:
        rts

        fill    $FF,$BFF2-*
        org     $BFF2
        fdb     unexpected_interrupt     ; $FFF2 SWI3
        fdb     unexpected_interrupt     ; $FFF4 SWI2
        fdb     unexpected_interrupt     ; $FFF6 FIRQ
        fdb     unexpected_interrupt     ; $FFF8 IRQ
        fdb     unexpected_interrupt     ; $FFFA SWI
        fdb     unexpected_interrupt     ; $FFFC NMI
        fdb     reset

; File offset $2000 is presented to the CPU as $8000. The comparison word is
; followed by an extended JMP back to the exact JSR address.
        org     $C000
        fdb     $4558
        jmp     test_loop

        fill    $FF,$DFFF-*
        org     $DFFF
        fcb     $FF
