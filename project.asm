; =============================================================================
;   ATARI BREAKOUT CLONE - BASIC ASSEMBLY VERSION
;
; =============================================================================

org 0x100

; =============================================================================
;   ENTRY POINT
; =============================================================================
start:
    ; Set Video Mode 03h (80x25 Text)
    mov ax, 0x0003
    int 0x10

    ; Hide Cursor
    mov ah, 0x02
    mov bh, 0x00
    mov dh, 26
    mov dl, 0
    int 0x10

    ; KILL NOISE IMMEDIATELY
    in al, 0x61
    and al, 0xFC
    out 0x61, al

    ; Initialize game state
    mov byte [gameState], 0 ; Start at Welcome
    
    ; Clear brick array manually
    mov di, bricks
    mov cx, 52      ; 4 rows * 13 bricks
    mov al, 0
    rep stosb
    
    call loadHighScore

; =============================================================================
;   MAIN LOOP
; =============================================================================
mainGameLoop:
    mov al, [gameState]
    cmp al, 0
    je State_ShowWelcome
    cmp al, 1
    je State_PlayGame
    cmp al, 2
    je State_ShowGameOver
    cmp al, 3
    je State_ShowWin
    jmp mainGameLoop

State_ShowWelcome:
    call clearScreen
    call drawBorders
    call drawWelcomeText
    call handleWelcomeInput
    jmp mainGameLoop

State_PlayGame:
    call processInput
    call drawPaddle

    ; Ball Timer Logic
    dec byte [ballTimer]
    jnz SkipBallUpdate
    
    mov byte [ballTimer], 1; Reset Timer (Speed)
    call updateBall
    call drawBall
    call drawHUD

SkipBallUpdate:
    call delay
    jmp mainGameLoop

State_ShowGameOver:
    call drawGameOverScreen
    call waitForKey
    jmp ExitGame

State_ShowWin:
    call drawWinScreen
    call waitForKey
    jmp ExitGame

ExitGame:
    mov ax, 0x0003
    int 0x10
    mov ax, 0x4C00
    int 0x21

; =============================================================================
;   INIT LOGIC
; =============================================================================
initGame:
    mov byte [lives], 3
    mov word [score], 0
    mov word [bricksBroken], 0
    mov byte [ballTimer], 1
    
    mov byte [paddleX], 36 ; PADDLE_START_X
    mov byte [prevPaddleX], 36 ; Matches start to avoid erasing border at 0
    call resetBall

    ; Reset Bricks (All to 1)
    mov di, bricks
    mov cx, 52
    mov al, 1
    rep stosb

    call clearScreen
    call drawBorders
    call drawBricks
    mov byte [gameState], 1
    ret

resetBall:
    mov byte [ballX], 40
    mov byte [ballY], 21
    mov byte [ballDX], 1
    mov byte [ballDY], -1
    mov byte [paddleX], 36
    call stopSpeaker        ; Safety silence
    
    mov al, [ballX]
    mov [prevBallX], al
    mov al, [ballY]
    mov [prevBallY], al
    ret

; =============================================================================
;   DRAWING ROUTINES (DIRECT VIDEO MEMORY 0xB800)
; =============================================================================
calcVideoOffset:
    ; Input: DH=Row, DL=Col
    ; Output: DI = Offset in B800
    push ax
    push dx
    
    mov al, 160     ; 80 chars * 2 bytes
    mul dh          ; AX = Row * 160
    xor dh, dh
    shl dx, 1       ; Col * 2
    add ax, dx      ; Total Offset
    mov di, ax
    
    pop dx
    pop ax
    ret

drawBorders:
    push es
    push di
    push ax
    
    mov ax, 0xB800
    mov es, ax

    ; 1. TOP HUD BAR (Row 0, Gray Background 0x70)
    xor di, di      ; Start at 0
    mov ah, 0x70    ; Gray BG
    mov al, ' '     ; Space
    mov cx, 80      ; Full width
    rep stosw

    ; 2. MAIN BOX (White 0x0F)
    
    ; Top Line (Row 1)
    mov dh, 1
    mov dl, 0
    call calcVideoOffset
    
    mov ah, 0x07    ; Light Gray (Standard)
    mov al, '+'
    stosw           ; Left Corner
    
    mov al, '-'
    mov cx, 78
    rep stosw       ; Top Dashes
    
    mov al, '+'
    stosw           ; Right Corner
    
    ; Left Wall (Rows 2 to 24) - FULL HEIGHT
    mov dh, 2
DrawLeftLoop:
    push dx         ; Save Loop Counter
    mov dl, 0
    call calcVideoOffset
    mov ax, 0x07DB  ; Light Gray Solid Block
    stosw
    pop dx          ; Restore Loop Counter
    inc dh
    cmp dh, 25      ; Loop until 24 is done (check 25)
    jne DrawLeftLoop
    
    ; Right Wall (Rows 2 to 23) - AVOID SCROLL
    mov dh, 2
DrawRightLoop:
    push dx         ; Save Loop Counter
    mov dl, 79
    call calcVideoOffset
    mov ax, 0x07DB  ; Light Gray Solid Block
    stosw
    pop dx          ; Restore Loop Counter
    inc dh
    cmp dh, 25      ; Loop until 24 is done (check 25)
    jne DrawRightLoop

    pop ax
    pop di
    pop es
    ret

drawHUD:
    ; Using String Print logic for HUD
    ; Score Text
    mov dh, 0
    mov dl, 2
    mov si, msgScore
    mov bl, 0x70
    call printStringColor

    ; Score Value
    mov ax, [score]
    mov di, numBuffer
    call wordToString
    mov dh, 0
    mov dl, 9
    mov si, numBuffer
    mov bl, 0x70
    call printStringColor

    ; High Score Text
    mov dh, 0
    mov dl, 33
    mov si, msgHiScore
    mov bl, 0x70
    call printStringColor
    
    ; High Score Value
    mov ax, [highScore]
    mov di, numBuffer
    call wordToString
    mov dh, 0
    mov dl, 37
    mov si, numBuffer
    mov bl, 0x70
    call printStringColor

    ; Lives Text
    mov dh, 0
    mov dl, 68
    mov si, msgLives
    mov bl, 0x70
    call printStringColor

    ; Lives Value
    mov ax, 0
    mov al, [lives]
    mov di, numBuffer
    call wordToString
    mov dh, 0
    mov dl, 75
    mov si, numBuffer
    mov bl, 0x70
    call printStringColor
    ret

drawBricks:
    push es
    mov ax, 0xB800
    mov es, ax
    
    mov si, bricks
    mov dh, 5       ; BRICK_START_Y
    mov cx, 0       ; Row Counter

DrawBricksRowLoop:
    cmp cx, 4       ; BRICK_ROWS
    jne DrawBricksContRow
    jmp DrawBricksDone

DrawBricksContRow:
    push cx
    mov dl, 1       ; BRICK_START_X
    mov cx, 0       ; Col Counter

DrawBricksColLoop:
    cmp cx, 13      ; BRICKS_PER_ROW
    je DrawBricksRowDone
    
    cmp byte [si], 1
    jne EraseBrick
    
    ; Determine Color based on pos
    ; Simple Pattern: (Row + Col) % 5
    mov ax, 0       ; Clear AX
    mov al, dh      ; Row
    sub al, 5       ; Normalize Row
    add al, cl      ; + Col
    
    ; Mod 5
    push bx
    mov bl, 5
    div bl
    mov bl, ah      ; Remainder
    
    cmp bl, 0
    je SetColorRed
    cmp bl, 1
    je SetColorOrange
    cmp bl, 2
    je SetColorYellow
    cmp bl, 3
    je SetColorGreen
    
    mov ah, 0x09    ; Blue
    jmp DrawBrickBlock
SetColorRed:
    mov ah, 0x0C    ; Red
    jmp DrawBrickBlock
SetColorOrange:
    mov ah, 0x06    ; Orange
    jmp DrawBrickBlock
SetColorYellow:
    mov ah, 0x0E    ; Yellow
    jmp DrawBrickBlock
SetColorGreen:
    mov ah, 0x0A    ; Green

DrawBrickBlock:
    pop bx
    
    call calcVideoOffset ; Returns DI
    mov al, 219          ; Solid Block
    push cx
    mov cx, 5            ; BRICK_WIDTH
    rep stosw
    pop cx
    jmp NextBrick

EraseBrick:
    call calcVideoOffset
    mov ax, 0x0720       ; Space (Black)
    push cx
    mov cx, 5            ; Width
    rep stosw
    pop cx

NextBrick:
    inc si
    add dl, 6            ; Stride (Width 5 + Gap 1)
    inc cx
    jmp DrawBricksColLoop

DrawBricksRowDone:
    pop cx
    add dh, 2            ; Next Row (+2 for gap)
    inc cx
    jmp DrawBricksRowLoop

DrawBricksDone:
    pop es
    ret

drawPaddle:
    push es
    mov ax, 0xB800
    mov es, ax
    
    ; Erase Old
    mov dh, 22          ; PADDLE_Y
    mov dl, [prevPaddleX]
    call calcVideoOffset
    mov ax, 0x0720      ; Space
    mov cx, 8           ; Width
    rep stosw
    
    ; Draw New
    mov dh, 22
    mov dl, [paddleX]
    call calcVideoOffset
    mov ax, 0x0BDB      ; Cyan Block (0x0B | 0xDB)
    mov cx, 8
    rep stosw
    
    ; Save Pos
    mov al, [paddleX]
    mov [prevPaddleX], al
    
    pop es
    ret

drawBall:
    push es
    mov ax, 0xB800
    mov es, ax
    
    ; Erase Old
    mov dh, [prevBallY]
    mov dl, [prevBallX]
    
    ; Safety: Don't erase Border/HUD?
    cmp dh, 2
    jle SkipBallErase
    cmp dh, 2
    jle SkipBallErase
    cmp dh, 24
    jge SkipBallErase   ; Protects Bottom Row (and Left Wall corner)
    cmp dl, 1
    jle SkipBallErase
    cmp dl, 78
    jge SkipBallErase
    
    call calcVideoOffset
    
    ; SMART ERASE: Check if overlapping paddle (Row 22)
    cmp dh, 22
    jne .doErase
    
    ; Check X range
    mov al, [paddleX]
    cmp dl, al
    jl .doErase
    add al, 8
    cmp dl, al
    jge .doErase
    
    ; Overlap! Repair paddle pixel
    mov ax, 0x0BDB      ; Cyan Block
    stosw
    jmp SkipBallErase

.doErase:
    mov ax, 0x0720      ; Space
    stosw

SkipBallErase:
    ; Draw New
    mov dh, [ballY]
    mov dl, [ballX]
    call calcVideoOffset
    mov ax, 0x0FFE      ; White Square (0xFE)
    stosw
    
    mov al, [ballX]
    mov [prevBallX], al
    mov al, [ballY]
    mov [prevBallY], al
    
    pop es
    ret

drawWelcomeText:
    ; Manually drawing lines on screen
    ; Line 3: Border
    mov dh, 3
    mov dl, 6
    mov si, menuBorder
    mov bl, 0x07    ; Light Gray
    call printStringColor
    
    ; Line 6: WELCOME
    mov dh, 6
    mov dl, 6
    mov si, menuWel
    mov bl, 0x0C
    call printStringColor
    
    ; Line 8: TO ATARI
    mov dh, 8
    mov dl, 6
    mov si, menuTo
    mov bl, 0x0C
    call printStringColor
    
    ; Line 10: ARCADE
    mov dh, 10
    mov dl, 6
    mov si, menuArc
    mov bl, 0x0E
    call printStringColor
    
    ; Line 12: High Score
    mov dh, 12
    mov dl, 6
    mov si, menuScore
    mov bl, 0x0E
    call printStringColor
    
    mov ax, [highScore]
    mov di, numBuffer
    call wordToString
    mov dh, 12
    mov dl, 43
    mov si, numBuffer
    mov bl, 0x0E
    call printStringColor
    
    ; Line 14: Press Enter
    mov dh, 14
    mov dl, 6
    mov si, menuEnt
    mov bl, 0x0F
    call printStringColor
    
    ; Line 16: Border
    mov dh, 16
    mov dl, 6
    mov si, menuBorder
    mov bl, 0x07    ; Light Gray
    call printStringColor
    ret

drawGameOverScreen:
    call updateHighScore
    call clearScreen
    call drawBorders
    
    mov dh, 12
    mov dl, 30
    mov si, msgGameOver
    mov bl, 0x0C
    call printStringColor
    
    mov dh, 14
    mov dl, 30
    mov si, msgScore
    mov bl, 0x0E
    call printStringColor
    
    mov ax, [score]
    mov di, numBuffer
    call wordToString
    mov dh, 14
    mov dl, 37
    mov si, numBuffer
    mov bl, 0x0E
    call printStringColor
    call printStringColor
    
    ; High Score
    
    ; High Score
    mov dh, 15
    mov dl, 30
    mov si, msgHiScore
    mov bl, 0x0F    ; White
    call printStringColor
    
    mov ax, [highScore]
    mov di, numBuffer
    call wordToString
    mov dh, 15
    mov dl, 34
    mov si, numBuffer
    mov bl, 0x0F
    call printStringColor
    ret

drawWinScreen:
    call updateHighScore
    call clearScreen
    call drawBorders
    
    mov dh, 12
    mov dl, 35
    mov si, msgWin
    mov bl, 0x0A
    call printStringColor
    
    mov dh, 14
    mov dl, 30
    mov si, msgScore
    mov bl, 0x0E
    call printStringColor
    
    mov ax, [score]
    mov di, numBuffer
    call wordToString
    mov dh, 14
    mov dl, 37
    mov si, numBuffer
    mov bl, 0x0E
    call printStringColor
    call printStringColor
    
    ; High Score
    
    ; High Score
    mov dh, 15
    mov dl, 30
    mov si, msgHiScore
    mov bl, 0x0F    ; White
    call printStringColor
    
    mov ax, [highScore]
    mov di, numBuffer
    call wordToString
    mov dh, 15
    mov dl, 34
    mov si, numBuffer
    mov bl, 0x0F
    call printStringColor
    ret

; =============================================================================
;   GAME LOGIC
; =============================================================================
updateBall:
    ; Move
    mov al, [ballX]
    add al, [ballDX]
    mov [ballX], al
    mov al, [ballY]
    add al, [ballDY]
    mov [ballY], al

    ; Left Wall (1)
    cmp byte [ballX], 1
    jg CheckRight
    mov byte [ballX], 2
    cmp byte [ballDX], 0
    jge CheckRight
    neg byte [ballDX]
    call playSound
    
CheckRight:
    ; Right Wall (78)
    cmp byte [ballX], 78
    jl CheckTop
    mov byte [ballX], 77
    cmp byte [ballDX], 0
    jle CheckTop
    neg byte [ballDX]
    call playSound

CheckTop:
    ; Top Wall (2)
    cmp byte [ballY], 2
    jg CheckBottom
    mov byte [ballY], 3
    cmp byte [ballDY], 0
    jge CheckBottom
    neg byte [ballDY]
    call playSound

CheckBottom:
    ; Floor (24)
    cmp byte [ballY], 24
    jl CheckPaddle
    
    ; Die
    dec byte [lives]
    call playFailSound
    call stopSpeaker

    push ax
    push dx
    push di
    push es
    mov ax, 0xB800
    mov es, ax
    mov dh, [prevBallY] ; 
    mov dl, [prevBallX]
    call calcVideoOffset
    mov ax, 0x0720  ; Space
    stosw
    pop es
    pop di
    pop dx
    pop ax
    
    cmp byte [lives], 0
    je TriggerGameOver
    
    call resetBall
    call delay
    ret

TriggerGameOver:
    mov byte [gameState], 2
    ret

CheckPaddle:
    ; Paddle Y = 22
    cmp byte [ballY], 21
    jne CheckBricks
    
    mov al, [paddleX]
    cmp byte [ballX], al
    jl CheckBricks
    add al, 8
    cmp byte [ballX], al
    jg CheckBricks
    
    cmp byte [ballDY], 0
    jle CheckBricks
    
    neg byte [ballDY]
    call playSound
    
    ; English Control
    mov al, [ballX]
    sub al, [paddleX]
    cmp al, 2
    jle HitLeft
    cmp al, 5
    jle HitCenter
HitRight:
    mov byte [ballDX], 1
    jmp CheckBricks
HitLeft:
    mov byte [ballDX], -1
    jmp CheckBricks
HitCenter:
    jmp CheckBricks

CheckBricks:
    ; Bricks Y range 5 to 13
    cmp byte [ballY], 5
    jl LogicDone
    cmp byte [ballY], 13
    jge LogicDone
    
    ; Calc Row
    mov ax, 0
    mov al, [ballY]
    sub al, 5
    test al, 1      ; Gap check
    jnz LogicDone
    shr al, 1       ; Row Index
    
    push ax
    mov ax, 0
    mov al, [ballX]
    sub al, 1
    mov bl, 6       ; Stride
    div bl
    mov bl, al      ; Col Index
    pop ax
    
    cmp bl, 13
    jge LogicDone
    
    ; Calc Offset
    mov cx, 13
    mul cx
    add ax, bx      ; Index
    
    mov si, bricks
    add si, ax
    
    cmp byte [si], 1
    je HitBrick
    jmp LogicDone

HitBrick:
    mov byte [si], 0
    add word [score], 10
    call updateHighScore
    call playSound
    call drawBricks     ; FIX: Redraw bricks to show erasure!
    inc word [bricksBroken]
    cmp word [bricksBroken], 52
    jne BounceBrick
    mov byte [gameState], 3

BounceBrick:
    ; Bounce Logic
    mov al, [prevBallY]
    cmp al, [ballY]
    jne VertHit
    neg byte [ballDX]
    jmp LogicDone
VertHit:
    neg byte [ballDY]

LogicDone:
    ret

; =============================================================================
;   INPUT & HELPERS
; =============================================================================
processInput:
    ; Drain Buffer Loop - Process all pending keys, keep the latest valid one
    xor bx, bx      ; BL = 0 (No input)
    
.pDrain:
    mov ah, 0x01
    int 0x16
    jz .pCheck      ; Empty? Check what we found.
    
    mov ah, 0x00
    int 0x16
    
    cmp ah, 0x4B    ; Left
    je .pSave
    cmp ah, 0x4D    ; Right
    je .pSave
    cmp al, 0x1B    ; Esc
    je .pSave
    jmp .pDrain

.pSave:
    mov bl, ah      ; Save Scan Code
    cmp al, 0x1B    ; Special check for ESC char
    jne .pDrain
    mov bl, 0xFF    ; FF for Esc
    jmp .pDrain

.pCheck:
    cmp bl, 0
    je .pRet
    
    cmp bl, 0xFF
    je ExitApp
    cmp bl, 0x4B
    je MoveLeft
    cmp bl, 0x4D
    je MoveRight
    
.pRet:
    ret

ExitApp:
    mov byte [gameState], 0
    ret

MoveLeft:
    sub byte [paddleX], 3
    cmp byte [paddleX], 1
    jge .doneLeft
    mov byte [paddleX], 2 ; Clamp
.doneLeft:
    ret

MoveRight:
    add byte [paddleX], 3
    cmp byte [paddleX], 70 ; 78 - 8
    jl .doneRight
    mov byte [paddleX], 70
.doneRight:
    ret

handleWelcomeInput:
    mov ah, 0x00
    int 0x16
    cmp al, 0x0D
    je StartGameVal
    cmp al, 0x1B
    je RealExitVal
    jmp handleWelcomeInput
StartGameVal:
    call initGame
    ret
RealExitVal:
    mov byte [gameState], 4
    mov ax, 0x4C00
    int 0x21

; =============================================================================
;   UTILS
; =============================================================================
clearScreen:
    push es
    mov ax, 0xB800
    mov es, ax
    xor di, di
    mov cx, 2000    ; 80*25
    mov ax, 0x0720  ; Space
    rep stosw
    pop es
    ret

printStringColor:
    ; DH=Row, DL=Col, SI=Msg, BL=Attr
    push es
    push ax
    
    call calcVideoOffset ; Sets DI
    mov ax, 0xB800
    mov es, ax
    mov ah, bl
    
PrintLoop:
    lodsb
    cmp al, 0
    je PrintDone
    stosw
    jmp PrintLoop
PrintDone:
    pop ax
    pop es
    ret

wordToString:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    
    mov bx, 10
    mov cx, 0
PushChars:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz PushChars
PopChars:
    pop ax
    add al, '0'
    stosb
    loop PopChars
    mov al, 0
    stosb
    
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

delay:
    mov cx, 0x0020
DelayLoop1:
    mov dx, 0x0FFF
DelayLoop2:
    dec dx
    jnz DelayLoop2
    loop DelayLoop1
    ret

waitForKey:
    mov ah, 0x00
    int 0x16
    ret

playSound:
    mov al, 0xB6
    out 0x43, al
    mov ax, 0x0400
    out 0x42, al
    mov al, ah
    out 0x42, al
    in al, 0x61
    or al, 0x03
    out 0x61, al
    mov cx, 0x2000
SoundLoop: loop SoundLoop
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    ret

stopSpeaker:
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    ret

playFailSound:
    mov al, 0xB6
    out 0x43, al
    mov ax, 3000
    out 0x42, al
    mov al, ah
    out 0x42, al
    in al, 0x61
    or al, 0x03
    out 0x61, al
    mov cx, 0xFFFF
FailLoop: loop FailLoop
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    ret

updateHighScore:
    mov ax, [score]
    cmp ax, [highScore]
    jle SkipHS
    mov [highScore], ax
    call saveHighScore
SkipHS:
    ret

loadHighScore:
    mov ah, 0x3D
    mov al, 0
    mov dx, filename
    int 0x21
    jc LoadErr
    mov [fileHandle], ax
    mov bx, [fileHandle]
    mov cx, 2
    mov dx, highScore
    mov ah, 0x3F
    int 0x21
    mov ah, 0x3E
    mov bx, [fileHandle]
    int 0x21
    ret
LoadErr:
    mov word [highScore], 0
    ret

saveHighScore:
    mov ah, 0x3C
    mov cx, 0
    mov dx, filename
    int 0x21
    jc SaveErr
    mov [fileHandle], ax
    mov bx, [fileHandle]
    mov cx, 2
    mov dx, highScore
    mov ah, 0x40
    int 0x21
    mov ah, 0x3E
    mov bx, [fileHandle]
    int 0x21
SaveErr:
    ret

; =============================================================================
;   DATA VARIABLES
; =============================================================================
section .data
    gameState:      db 0
    score:          dw 0
    highScore:      dw 0
    lives:          db 0
    bricksBroken:   dw 0
    
    paddleX:        db 0
    prevPaddleX:    db 0
    
    ballX:          db 0
    ballY:          db 0
    prevBallX:      db 0
    prevBallY:      db 0
    ballDX:         db 0
    ballDY:         db 0
    ballTimer:      db 0
    
    ; Strings
    msgScore:       db 'SCORE:', 0
    msgLives:       db 'LIVES:', 0
    msgGameOver:    db 'GAME OVER', 0
    msgWin:         db 'YOU WIN!', 0
    msgHiScore:     db 'HI:', 0
    
    menuBorder:     db '===================================================================', 0
    menuEmpty:      db '|                                                                 |', 0
    menuWel:        db '|                        W E L C O M E                            |', 0
    menuTo:         db '|                       T O   A T A R I                           |', 0
    menuArc:        db '|                   * BREAKOUT ARCADE 1972 *                      |', 0
    menuScore:      db '|                         HIGH SCORE:                             |', 0
    menuEnt:        db '|---------[    P R E S S   E N T E R   T O   P L A Y    ]---------|', 0
    
    filename:       db 'hiscore.dat', 0
    fileHandle:     dw 0
    
    numBuffer:      db 0,0,0,0,0,0,0,0
    bricks:
    db 0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0