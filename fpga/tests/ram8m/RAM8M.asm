        org     $0e00
        bra     start
status  fcb     0               ; $0e02: 0=pass, 1=alias/mismatch, 2=wrong map
errors  fdb     0               ; $0e03: number of mismatching pages
first   fdb     $ffff           ; $0e05: first mismatching 8 KiB page
old_s   fdb     0
old_init fcb    0
old_page fcb    0
page    fdb     0

; Run from freshly booted CoCo 3 BASIC. The launcher reserves everything
; above $0dff. Code, saved bytes and private stack stay below $2000 while
; the $2000-$3fff window walks all 1024 pages. IRQ/FIRQ are masked until
; every probed byte is restored. Return in BASIC's normal all-RAM mode.
start   sts     old_s
        lds     #stack_end
        pshs    cc,dp,d,x,y,u
        orcc    #$50
        clr     status
        clra
        clrb
        std     errors
        ldd     #$ffff
        std     first
        ldx     #$ffa1
        lda     $ff91
        bita    #1
        beq     task_ready
        leax    8,x             ; task 1 uses FFA9
task_ready
        lda     ,x
        anda    #$3f
        sta     old_page
        cmpa    #$39            ; expect standard BASIC page for slot 1
        lbne    wrong_map
        lda     $ff90
        sta     old_init
        ora     #$40
        sta     $ff90           ; enable MMU, retain other INIT0 bits
        clr     $ffdf           ; read RAM even when a page resembles ROM

; Save all original marker bytes before writing any pattern. This also
; makes restoration safe when an older 2 MiB core aliases upper banks.
        ldu     #saved
        clra
        clrb
        std     page
save_loop
        lbsr    map_page
        lda     $3fff
        sta     ,u+
        lbsr    advance
        blo     save_loop

        clra
        clrb
        std     page
write_loop
        lbsr    map_page
        lda     page
        eora    page+1
        sta     $3fff
        lbsr    advance
        blo     write_loop

        clra
        clrb
        std     page
verify_loop
        lbsr    map_page
        lda     page
        eora    page+1
        cmpa    $3fff
        beq     next_check
        tst     status
        bne     counted
        ldd     page
        std     first
        inc     status
counted ldd     errors
        addd    #1
        std     errors
next_check
        lbsr    advance
        blo     verify_loop

        ldu     #saved
        clra
        clrb
        std     page
restore_loop
        lbsr    map_page
        lda     ,u+
        sta     $3fff
        lbsr    advance
        blo     restore_loop

        clr     $ff9b           ; standard CPU prefix and video bank zero
        lda     old_page
        sta     ,x
        lda     old_init
        sta     $ff90
exit    puls    cc,dp,d,x,y,u
        lds     old_s
        rts
wrong_map
        lda     #2
        sta     status
        bra     exit

map_page
        ldd     page            ; A=page bits 9:8, B=bits 7:0
        lsla
        lsla
        lsla
        lsla
        sta     $ff9b           ; upper CPU bits; video remains bank zero
        stb     ,x              ; latch all 10 page bits for this slot
        rts
advance ldd     page
        addd    #1
        std     page
        cmpd    #1024
        rts
saved   rmb     1024
        rmb     64
stack_end
        end     $0e00
