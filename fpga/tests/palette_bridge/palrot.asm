        org     $4000

; One EXEC rotates all 16 GIME palette entries and returns to BASIC.
; The table is private: no Super Extended BASIC workspace is modified.
rotate  pshs    cc,a,b,x,y,u
        ldb     phase
        inc     phase
        andb    #$0f
        ldx     #colors
        abx
        ldy     #$ffb0

        orcc    #$50
        sync
        ldb     #16
copy    lda     ,x+
        cmpx    #colors+16
        bne     store
        ldx     #colors
store   sta     ,y+
        decb
        bne     copy
        andcc   #$af
        puls    cc,a,b,x,y,u,pc

phase   fcb     0
colors  fcb     0,3,9,12,18,21,27,30
        fcb     33,36,42,45,51,54,60,63

        end     rotate
