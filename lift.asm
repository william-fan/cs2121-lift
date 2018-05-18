.include "m2560def.inc"

.dseg
.org 0x200
queue: ;queue for storing user's commands
.byte 500

SecondCounter:
.byte 2
TempCounter:
.byte 2
IsMoving: 
.byte 2
IsStopped:  
.byte 2
IsOpened:
.byte 2
EmergencyClosed: ;check if door closed in emergency
.byte 2
EmergencyMessageShown: ;check if emergency message shown
.byte 2
TempCounter4: 
.byte 2
TempCounter5:
.byte 2
CurrFloor:
.byte 2
TargetFloor:  
.byte 2   
threesec:   ;3 sec counter
.byte 8  



.macro do_lcd_command
        ldi r16, @0
        rcall lcd_command 
        rcall lcd_wait
.endmacro

.macro do_lcd_reg
        mov r16, @0
        rcall lcd_data    ;lcd from register
        rcall lcd_wait
.endmacro

.macro do_lcd_data
        ldi r16, @0
        rcall lcd_data  ;lcd from variable
        rcall lcd_wait
.endmacro

.macro clear
  ldi YL, low(@0)
  ldi YH, high(@0)    ;clear variable
  clr temp1
  st Y+, temp1
  st Y, temp1
.endmacro

.macro lcd_set
        sbi PORTA, @0
.endmacro
.macro lcd_clr
        cbi PORTA, @0
.endmacro



.cseg

rjmp RESET

.org INT0addr
   jmp EXT_INT0
.org OVF0addr
  jmp Timer0OVF
.org OVF3addr
   jmp Timer3OVF
.org OVF4addr
  jmp Timer4OVF
.org OVF5addr
  jmp Timer5OVF


.def row = r16            ; current row number
.def col = r17            ; current column number
.def rmask = r18          ; mask for current row during scan
.def cmask = r19          ; mask for current column during scan
.def temp1 = r20
.def temp2 = r21
.def debounce = r22 
.def emergency = r23
.def brightness = r24   ;strobe brightness
.def bleh=r25   


.equ PORTADIR = 0xF0      ; PD7-4: output, PD3-0, input
.equ INITCOLMASK = 0xEF   ; scan from the rightmost column,
.equ INITROWMASK = 0x01   ; scan from the top row
.equ ROWMASK = 0x0F       ; for obtaining input from Port D
.equ LCD_RS = 7
.equ LCD_E = 6
.equ LCD_RW = 5
.equ LCD_BE = 4

RESET:
  ldi temp1, low(RAMEND)  ; initialize the stack
  out SPL, temp1
  ldi temp1, high(RAMEND)
  out SPH, temp1

  ldi xl, low(queue)
  ldi xh, high(queue)

  ldi zl, low(queue)
  ldi zh, high(queue)

  ; Init lift states variables
  clear TargetFloor
  clear CurrFloor
  clear IsMoving
  clear IsStopped
  clear IsOpened
  clear EmergencyClosed
  clr bleh
  clear threesec
  
  
  sei
  
  ldi temp1, 0b00000001
	sts DDRH, temp1 
	
	/*ldi temp1, (1 << CS50)
	sts TCCR5B, temp1
	ldi temp1, (1<< WGM50)|(1<<COM5A1)
	sts TCCR5A, temp1 */


  ; Init push button interrupt
  ldi temp1, (2 << ISC00)
  sts EICRA, temp1
  in temp1, EIMSK
  ori temp1, (1<<INT0)
  out EIMSK, temp1

  ;Init Timer 0
  clear TempCounter
  clear SecondCounter
  ldi temp1, 0b00000000
  out TCCR0A, temp1
  ldi temp1, 0b00000100
  out TCCR0B, temp1
  ldi temp1, 1<<TOIE0
  sts TIMSK0, temp1



	ldi temp1, 0b10000000
	sts DDRH, temp1 


  ;Init Timer 3 and led
  ldi brightness, 255
  ldi temp1, 0b0010000
  out DDRE, temp1
  ldi temp1, (1 << CS30)
  sts TCCR3B, temp1
  ldi temp1, (1<< WGM30)|(1<<COM3B1)
  sts TCCR3A, temp1
  ldi temp1, 0b0000011
   sts TCCR3B, temp1
   ldi temp1, 1<<TOIE3		; turns overflow interrupt bit on
   sts TIMSK3, temp1

  clear TempCounter5
 ;Init Timer 5
  
  ldi temp1, 0b00000000
  sts TCCR5A, temp1
  ldi temp1, 0b00000100
  sts TCCR5B, temp1
  ldi temp1, 1<<TOIE5
  sts TIMSK5, temp1

  ;Init Timer 4
  clear TempCounter4
  ldi temp1, 0b00000000
  sts TCCR4A, temp1
  ldi temp1, 0b00000100
  sts TCCR4B, temp1
  ldi temp1, 1<<TOIE4
  sts TIMSK4, temp1

  ldi temp1, PORTADIR     ; PA7:4/PA3:0, out/in
  sts DDRL, temp1
  ser temp1               ; PORTC is output
  out DDRC, temp1
  out PORTC, temp1

  ;LCD init.
  ser r16
  out DDRF, r16
  out DDRA, r16
  clr r16
  out PORTF, r16
  out PORTA, r16

  clr emergency

  do_lcd_command 0b00111000 ; 2x5x7
  rcall sleep_5ms
  do_lcd_command 0b00111000 ; 2x5x7
  rcall sleep_1ms
  do_lcd_command 0b00111000 ; 2x5x7
  do_lcd_command 0b00111000 ; 2x5x7
  do_lcd_command 0b00001000 ; display off?
  do_lcd_command 0b00000001 ; clear display
  do_lcd_command 0b00000110 ; increment, no display shift
  do_lcd_command 0b00001110 ; Cursor on, bar, no blink


  do_lcd_data '0'

main:
  cpi emergency, 1   
  breq keypad
  lds temp1, IsStopped
  cpi temp1, 1
  breq checkMove

checkMove:
  lds temp1, IsMoving
  cpi temp1, 1
  breq keypad
  rcall GetNextFloor

keypad:
  ldi cmask, INITCOLMASK  ; initial column mask
  clr col                 ; initial column

colloop:
  cpi col, 4
  breq main               ; If all keys are scanned, repeat.
  sts PORTL, cmask        ; Otherwise, scan a column.
  ldi temp1, 0xFF         ; Slow down the scan operation.

delay:
  dec temp1
  brne delay
  
  
 
  lds temp1, PINL         ; Read PORTL
  andi temp1, ROWMASK     ; Get the keypad output value
  cpi temp1, 0xF          ; Check if any row is low
  breq nextcol
                          ; If yes, find which row is low
  ldi rmask, INITROWMASK  ; Initialize for row check
  clr row

rowloop:
  cpi row, 4
  breq nextcol
  mov temp2, temp1
  and temp2, rmask
  breq convert
  inc row
  lsl rmask
  jmp rowloop

nextcol:
  lsl cmask
  inc col
  jmp colloop

convert:
  cpi col, 3
  breq letters

  cpi row, 3
  breq symbols
  mov temp1, row
  lsl temp1
  add temp1, row
  add temp1, col
  inc temp1

numbers:
  cpi debounce, 1
  breq main
  ldi debounce, 1
  cp bleh, temp1  ;check if we're pressing the same floor more than once
  breq Here
  mov bleh, temp1


  st z+, temp1        ;add to queue
Here:
  jmp convert_end

zero:
  clr temp1
  rjmp numbers

letters:
  ldi temp1, 'A'
  add temp1, row
  jmp convert_end

symbols:
  cpi col, 0
  breq star
  cpi col, 1
  breq zero
  ldi temp1, '#'
  jmp convert_end

star:
  ;ldi temp1, '*'
  cpi debounce, 1
  breq convert_end
  ldi debounce, 1

  cpi emergency, 0
  breq start_emergency
  rcall StopEmergency
  jmp convert_end

start_emergency:
  ldi emergency, 1
  rcall StartEmergency
  jmp convert_end


convert_end:
  jmp main

halt:
  rjmp halt


StopEmergency:

  push temp1
  clr emergency
  clr brightness
  sts EmergencyClosed, emergency
  sts EmergencyMessageShown, emergency
  sts OCR3BL, brightness
  sts OCR3BH, brightness


EndStopEmergency:
  pop temp1
  ret

StartEmergency:
  push temp1

  lds temp1, IsStopped
  cpi temp1, 1
  brne EmergencyMove
  ;close lift door
  ldi temp1, 4
  sts TempCounter4, temp1
  ldi temp1, 1
  sts IsOpened, temp1

EmergencyMove:
  clr temp1
  sts TargetFloor, temp1
  ldi temp1, 1
  sts IsMoving, temp1

EndStartEmergency:
  pop temp1
  ret

; Take target floor from queue and move the lift
GetNextFloor:
  ;check if queue is empty
  cp xl, zl
  cpc xh, zh
  breq EndGetNextFloor

  ld temp1, x+
  sts TargetFloor, temp1
  ldi temp1, 1
  sts IsMoving, temp1

EndGetNextFloor:
  ret


EXT_INT0:
   push temp1
   in temp1, SREG
   push temp1
  ldi temp1, 4
   sts TempCounter4, temp1

END0:
   pop temp1
  out SREG, temp1
   pop temp1
   reti



;; Timer for handling debouncing
Timer0OVF:
  push temp1
  in temp1, SREG
  push temp1
  push YH
  push YL
  push r25
  push r24

  cpi debounce, 1
  brne EndIF
  lds r24, TempCounter
  lds r25, TempCounter+1
  adiw r25:r24, 1         ; Increase the temporary counter by one.
  cpi r24, low(30)
  ldi temp1, high(30)
  cpc r25, temp1
  brne NotSecond

  clr debounce
  clear TempCounter

  lds r24, SecondCounter
  lds r25, SecondCounter+1
  adiw r25:r24, 1         ; Increase the second counter by one.

  sts SecondCounter, r24
  sts SecondCounter+1, r25
  rjmp EndIF

NotSecond:
  sts TempCounter, r24
  sts TempCounter+1, r25

EndIF:
  pop r24
  pop r25
  pop YL
  pop YH
  pop temp1
  out SREG, temp1
  pop temp1
  reti

SHOW_EMERGENCY_MSG:
  push temp1
  do_lcd_command 0b00000001 ; clear display
  do_lcd_command 0b00000110 ; increment, no display shift
  do_lcd_command 0b00001110 ; Cursor on, bar, no blink
  do_lcd_data 'E'
  do_lcd_data 'm'
  do_lcd_data 'e'
  do_lcd_data 'r'
  do_lcd_data 'g'
  do_lcd_data 'e'
  do_lcd_data 'n'
  do_lcd_data 'c'
  do_lcd_data 'y'
  do_lcd_command 0b11000000 ; Second row
  do_lcd_data 'C'
  do_lcd_data 'a'
  do_lcd_data 'l'
  do_lcd_data 'l'
  do_lcd_data ' '
  do_lcd_data '0'
  do_lcd_data '0'
  do_lcd_data '0'
  
  ldi temp1, 1
  sts EmergencyMessageShown, temp1
  
END_SHOW_EMERGENCY:
  pop temp1
  ret

;; Timer for emergency lights
TIMER3OVF:
  push temp1
  cpi emergency, 0
  breq EndIF3
  dec brightness
  sts OCR3BL, brightness
  sts OCR3BH, brightness
  lds temp1, EmergencyClosed ; check if lift has reached ground floor and closed
  cpi temp1, 0
  breq EndIF3
  lds temp1, EmergencyMessageShown ; makes sure message is shown once
  cpi temp1, 1
  breq EndIF3
  rcall SHOW_EMERGENCY_MSG

EndIF3:
  pop temp1
  reti

;; Timer for simulating lift opening, waiting and closing
Timer4OVF:
  push temp1
  in temp1, SREG
  push temp1
  push temp2
  push YH
  push YL
  push r25
  push r24
  lds temp1, IsStopped
  cpi temp1, 1
  brne EndIF4
 
  lds r24, TempCounter4
  lds r25, TempCounter4+1
  adiw r25:r24, 1         ; Increase the temporary counter by one.

CheckLiftOpen:
  cpi r24, low(1)
  ldi temp1, high(1)
  cpc r25, temp1
  breq LiftOpened

CheckLiftClose:
  lds temp1, IsOpened
  cpi temp1, 1
  brne NotClosed
  cpi r24, low(5)
  ldi temp1, high(5)
  cpc r25, temp1
  breq LiftClosed
  rjmp NotClosed
  
LiftOpened:
  rcall MotorOn
  ldi temp1, 1
  sts IsOpened, temp1
  rcall PrintOpen
  
  rcall LightsOpen

  ;ldi temp1, 0b10000001     ;open pattern
  ;out PORTC,temp1
  rcall MotorOff
  rjmp NotClosed
  
  lds temp1, threesec
  inc temp1
  cpi temp1, 3
  sts threesec, temp1
  brne LiftOpened
  
  //rcall end

LiftClosed:
  rcall MotorOn
  clear TempCounter4
  clr temp1
  sts IsOpened, temp1
  sts IsStopped, temp1
  rcall PrintClose
 
  /*do_lcd_command 0b00000001 ; clear display
  do_lcd_command 0b00000110 ; increment, no display shift
  do_lcd_command 0b00001110 ; Cursor on, bar, no blink
  
  do_lcd_data 'C'
  do_lcd_data 'L'
  do_lcd_data 'O'
  do_lcd_data 'S'
  do_lcd_data 'I'
  do_lcd_data 'N'
  do_lcd_data 'G'*/
  

  ;ldi temp1, 0b11111111   ;close pattern
  ;out PORTC,temp1
  rcall LightsClose

  rcall MotorOff
  cpi emergency, 1          ;checks for emergency
  brne BeforeEnd4       
  lds temp1, CurrFloor
  cpi temp1, 0            ;checks if we're on level 0
  brne BeforeEnd4
  ldi temp1, 1
  sts EmergencyClosed, temp1
  
BeforeEnd4:
  rjmp EndIF4

NotClosed:
  sts TempCounter4, r24
  sts TempCounter4+1, r25

EndIF4:
  pop r24
  pop r25
  pop YL
  pop YH
  pop temp2
  pop temp1
  out SREG, temp1
  pop temp1
  reti
/*end:
  clr bleh
  sts PORTH,bleh*/
MotorOn:
  ldi bleh, 50
  sts PORTH,bleh     ;spin motor for one second
CloseOneSecond:
  rcall sleep_5ms
  inc bleh       ;Opening takes one second
  cpi bleh, 100
  brne CloseOneSecond
  clr bleh
  ret
MotorOff:
  ldi bleh, 0
  sts PORTH,bleh
  ret
LightsOpen:
  ldi temp1, 0b10000001     ;open pattern
  out PORTC,temp1
  ret
LightsClose:  
  ldi temp1, 0b11111111   ;close pattern
  out PORTC,temp1
  ret
PrintClose:
  do_lcd_command 0b00000001 ; clear display
  do_lcd_command 0b00000110 ; increment, no display shift
  do_lcd_command 0b00001110 ; Cursor on, bar, no blink
  
  do_lcd_data 'C'
  do_lcd_data 'L'
  do_lcd_data 'O'
  do_lcd_data 'S'
  do_lcd_data 'E'
  do_lcd_data 'D'
  ret

PrintOpen:
  do_lcd_command 0b00000001 ; clear display
  do_lcd_command 0b00000110 ; increment, no display shift
  do_lcd_command 0b00001110 ; Cursor on, bar, no blink
  
  do_lcd_data 'O'
  do_lcd_data 'P'
  do_lcd_data 'E'
  do_lcd_data 'N'
  do_lcd_data 'E'
  do_lcd_data 'D'
  ret




;; Timer for simulating lift moving
Timer5OVF:
  push temp1
  in temp1, SREG
  push temp1
  push temp2
  push YH
  push YL
  push r25
  push r24

  lds temp1, IsStopped
  cpi temp1, 1
  breq EndIF5

  lds temp1, IsMoving
  cpi temp1, 1            ; check if lift is moving
  brne EndIF5

  lds r24, TempCounter5
  lds r25, TempCounter5+1
  adiw r25:r24, 1         ; Increase the temporary counter by one.
  cpi r24, low(2)
  ldi temp1, high(2)
  cpc r25, temp1
  brne NotTwoSecond5

  lds temp1, CurrFloor
  lds temp2, TargetFloor

  cp temp1, temp2
  brlo MoveUp

  cp temp1, temp2
  breq IsArrive

MoveDown:
  rcall twosec
  rcall IndicateDown
  dec temp1
  sts CurrFloor, temp1
  rjmp ShowCurrFloor

MoveUp:
  rcall twosec
  rcall IndicateUp
  inc temp1
  sts CurrFloor, temp1
  rjmp ShowCurrFloor

IsArrive:
  clr temp2
  sts IsMoving, temp2
  ldi temp2, 1
  sts IsStopped, temp2
  /*do_lcd_command 0b00000001 ; clear display
  do_lcd_command 0b00000110 ; increment, no display shift
  do_lcd_command 0b00001110 ; Cursor on, bar, no blink
  
  do_lcd_data 'O'
  do_lcd_data 'P'
  do_lcd_data 'E'
  do_lcd_data 'N'
  do_lcd_data 'I'
  do_lcd_data 'N'
  do_lcd_data 'G'*/
  rjmp BeforeEnd

ShowCurrFloor:
  subi temp1, -'0'
  do_lcd_command 0b00000001 ; clear display
  do_lcd_command 0b00000110 ; increment, no display shift
  do_lcd_command 0b00001110 ; Cursor on, bar, no blink
  do_lcd_reg temp1
  

BeforeEnd:
  clear TempCounter5
  rjmp EndIF5

NotTwoSecond5:
  sts TempCounter5, r24
  sts TempCounter5+1, r25

EndIF5:
  pop r24
  pop r25
  pop YL
  pop YH
  pop temp2
  pop temp1
  out SREG, temp1
  pop temp1
  reti
  
twosec:
  lds bleh, threesec
  inc bleh
  cpi bleh, 2
  sts threesec, bleh
  brne twosec
  ret
  ;;
  ;;  Send a command to the LCD (r16)
  ;;
IndicateUp:
   ldi bleh, 0b10000000     ;indicate lift is going up pattern
   out PORTC,bleh
   clr bleh
   ret
   
IndicateDown:
   ldi bleh, 0b00000001     ;indicate light is going down pattern pattern
   out PORTC,bleh
   clr bleh
   ret
  

lcd_command:
  out PORTF, r16
  rcall sleep_1ms
  lcd_set LCD_E
  rcall sleep_1ms
  lcd_clr LCD_E
  rcall sleep_1ms
  ret

lcd_data:
  out PORTF, r16
  lcd_set LCD_RS
  rcall sleep_1ms
  lcd_set LCD_E
  rcall sleep_1ms
  lcd_clr LCD_E
  rcall sleep_1ms
  lcd_clr LCD_RS
  ret

lcd_wait:
  push r16
  clr r16
  out DDRF, r16
  out PORTF, r16
  lcd_set LCD_RW
lcd_wait_loop:
  rcall sleep_1ms
  lcd_set LCD_E
  rcall sleep_1ms
  in r16, PINF
  lcd_clr LCD_E
  sbrc r16, 7
  rjmp lcd_wait_loop
  lcd_clr LCD_RW
  ser r16
  out DDRF, r16
  pop r16
  ret

.equ F_CPU = 16000000
.equ DELAY_1MS = F_CPU / 4 / 1000 - 4
        ;;  4 cycles per iteration - setup/call-return overhead

sleep_1ms:
  push r24
  push r25
  ldi r25, high(DELAY_1MS)
  ldi r24, low(DELAY_1MS)
delayloop_1ms:
  sbiw r25:r24, 1
  brne delayloop_1ms
  pop r25
  pop r24
  ret

sleep_5ms:
  rcall sleep_1ms
  rcall sleep_1ms
  rcall sleep_1ms
  rcall sleep_1ms
  rcall sleep_1ms
  ret
