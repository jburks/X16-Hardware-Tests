; Tests for checking functionality of VERA SD

; We use this as basis for SD card communication using SPI:
;   http://elm-chan.org/docs/mmc/mmc_e.html

; We try to implement this chart for SD Card initialization:
;   http://elm-chan.org/docs/mmc/m/sdinit.png


SPI_CHIP_DESELECT_AND_SLOW =   %00000010
SPI_CHIP_SELECT_AND_SLOW   =   %00000011

vera_sd_header: 
    .asciiz "VERA - SD:"
    
vera_sd_reset_message:
    .asciiz "Detecting and resetting SD Card ... "
vera_check_sdc_version_message:
    .asciiz "Checking if card is SDC Ver.2+ ... "
vera_sd_initialize_message:
    .asciiz "Initializing SD Card ... "
vera_sd_no_card_detected: 
    .asciiz "No card detected"
vera_sd_timeout_message:    
    .asciiz "Timeout"

   
print_vera_sd_header:
    lda #MARGIN
    sta INDENTATION
    sta CURSOR_X
    
    ldx CURSOR_Y
    inx
    stx CURSOR_Y
    
    lda #COLOR_HEADER
    sta TEXT_COLOR
    lda #<vera_sd_header
    sta TEXT_TO_PRINT
    lda #>vera_sd_header
    sta TEXT_TO_PRINT + 1

    jsr print_text_zero
    
    lda #(MARGIN+INDENT_SIZE)
    sta INDENTATION
    
    jsr move_cursor_to_next_line
    
    rts

    
; ======= Initialize SD Card ========    

vera_initialize_sd_card:

    lda #COLOR_NORMAL
    sta TEXT_COLOR
    
    lda #<vera_sd_initialize_message
    sta TEXT_TO_PRINT
    lda #>vera_sd_initialize_message
    sta TEXT_TO_PRINT + 1
    
    jsr print_text_zero


retry_initialization:
    ; We send command 55 to prepare for command ACMD41
    jsr spi_send_command55
    
    bcs command55_success
command55_timed_out:
    
    ; If carry is unset, we timed out. We print 'Timeout' as an error
    lda #COLOR_ERROR
    sta TEXT_COLOR
    
    lda #<vera_sd_timeout_message
    sta TEXT_TO_PRINT
    lda #>vera_sd_timeout_message
    sta TEXT_TO_PRINT + 1
    
    jsr print_text_zero

    jmp done_with_initialize_do_not_proceed
    
command55_success:

    ; We got our byte of response. We check if the SD Card is not in an IDLE state (which is expected)
    cmp #%0000001   ; IDLE state
    bne command55_not_in_idle_state
    

    ; --- ACMD41 ---
    
    ; We send command ACMD41 to "initiate initialization with ACMD41 with HCS[bit30] flag in the argument"
    jsr spi_send_command41
    
    bcs command41_success
command41_timed_out:
    
    ; If carry is unset, we timed out. We print 'Timeout' as an error
    lda #COLOR_ERROR
    sta TEXT_COLOR
    
    lda #<vera_sd_timeout_message
    sta TEXT_TO_PRINT
    lda #>vera_sd_timeout_message
    sta TEXT_TO_PRINT + 1
    
    jsr print_text_zero

    jmp done_with_initialize_do_not_proceed
    
command41_success:

    ; We got our byte of response. We check if the SD Card is not in an IDLE state (which is expected)
    cmp #%0000000   ; NOT in IDLE state! (we just initialized, so we should not be in IDLE state anymore!)
; FIXME    bne command41_still_in_idle_state
    bne retry_initialization
    
    lda #COLOR_OK
    sta TEXT_COLOR
    
    lda #<ok_message
    sta TEXT_TO_PRINT
    lda #>ok_message
    sta TEXT_TO_PRINT + 1
    
    jsr print_text_zero
    
    jmp done_with_initialize_proceed
    
command41_still_in_idle_state:
    ; The reponse says we are STILL in an IDLE state, which means there is an error
    ldx #41 ; command number to print
    jsr print_spi_cmd_error
    
    jmp done_with_initialize_do_not_proceed
    
command55_not_in_idle_state:
    ; The reponse says we are not in an IDLE state, which means there is an error
    ldx #55 ; command number to print
    jsr print_spi_cmd_error
    
done_with_initialize_do_not_proceed:
    jsr move_cursor_to_next_line

    ; We unselect the card
    lda #SPI_CHIP_DESELECT_AND_SLOW
    sta VERA_SPI_CTRL

    ; TODO: Can we further 'POWER OFF' the card?
    clc
    rts

done_with_initialize_proceed:
    jsr move_cursor_to_next_line
    sec
    rts
    
; ======= Reset SD Card ========    

vera_reset_sd_card:

    lda #COLOR_NORMAL
    sta TEXT_COLOR
    
    lda #<vera_sd_reset_message
    sta TEXT_TO_PRINT
    lda #>vera_sd_reset_message
    sta TEXT_TO_PRINT + 1
    
    jsr print_text_zero
    

    ; === Power ON ===

    ; "Set SPI clock rate between 100 kHz and 400 kHz.
    ;  Set DI and CS high and apply 74 or more clock pulses to SCLK"
       
    ; Note that DI is pulled high (in hardware) so we dont have to do anything in software to arrange that.
    ; We deselect (=CS high) the card by setting a bit to 1 in the CTRL register in VERA. The speed of the clock is set to 390kHz.
    
    lda #SPI_CHIP_DESELECT_AND_SLOW
    sta VERA_SPI_CTRL
    
    ; We apply (at least) 74 clock pulses a reading 10 bytes (10 * 8 = 80 clock pulses) from the card
    ldx #10
spi_dummy_clock_loop:
    jsr spi_read_byte
    dex
    bne spi_dummy_clock_loop
    
    
    ; === Software reset ===
    
    ; "Send a CMD0 with CS low to reset the card. The card samples CS signal on a CMD0 is received successfully. 
    ;  If the CS signal is low, the card enters SPI mode and responds R1 with In Idle State bit set (0x01). 
    ;  Since the CMD0 must be sent as a native command, the CRC field must have a valid value. When once the card 
    ;  enters SPI mode, the CRC feature is disabled and the command CRC and data CRC are not checked by the card, 
    ;  so that command transmission routine can be written with the hardcorded CRC value that valid for only CMD0 
    ;  and CMD8 used in the initialization process."

    ; We set CS low (but keep the clock speed slow)
    lda #SPI_CHIP_SELECT_AND_SLOW
    sta VERA_SPI_CTRL
    
    ; TODO: do we have to read adter the select?
    jsr spi_read_byte
    jsr spi_read_byte
    
    ; We send command 0 to do a software reset
    jsr spi_send_command0
    
    bcs command0_success
command0_timed_out:

    ; If carry is unset, we timed out. We print 'No Card Detected' as a warning
    lda #COLOR_WARNING
    sta TEXT_COLOR
    
    lda #<vera_sd_no_card_detected
    sta TEXT_TO_PRINT
    lda #>vera_sd_no_card_detected
    sta TEXT_TO_PRINT + 1
    
    jsr print_text_zero

    jmp done_with_command0_do_not_proceed
command0_success:
    ; We got a byte of response. We check if the SD Card is not in an IDLE state (which is expected)
    cmp #%0000001   ; IDLE state
    bne command0_not_in_idle_state
    
    lda #COLOR_OK
    sta TEXT_COLOR
    
    lda #<ok_message
    sta TEXT_TO_PRINT
    lda #>ok_message
    sta TEXT_TO_PRINT + 1
    
    jsr print_text_zero
    
    jmp done_with_command0_proceed
    
command0_not_in_idle_state:
    ; The reponse says we are not in an IDLE state, which means there is an error
    ldx #0 ; command number to print
    jsr print_spi_cmd_error
    
done_with_command0_do_not_proceed:
    jsr move_cursor_to_next_line

    ; We unselect the card
    lda #SPI_CHIP_DESELECT_AND_SLOW
    sta VERA_SPI_CTRL

    ; TODO: Can we further 'POWER OFF' the card?
    clc
    rts

done_with_command0_proceed:
    jsr move_cursor_to_next_line
    sec
    rts

; ======= Check SDC Ver.2+ ========    

vera_check_sdc_version:
    
    lda #COLOR_NORMAL
    sta TEXT_COLOR
    
    lda #<vera_check_sdc_version_message
    sta TEXT_TO_PRINT
    lda #>vera_check_sdc_version_message
    sta TEXT_TO_PRINT + 1
    
    jsr print_text_zero
    
    ; We send command 8 (with $01AA) to check for SDC Ver2.+
    jsr spi_send_command8
    
    bcs command8_success
command8_timed_out:
    
    ; If carry is unset, we timed out. We print 'Timeout' as an error
    lda #COLOR_ERROR
    sta TEXT_COLOR
    
    lda #<vera_sd_timeout_message
    sta TEXT_TO_PRINT
    lda #>vera_sd_timeout_message
    sta TEXT_TO_PRINT + 1
    
    jsr print_text_zero

    jmp done_with_command8_do_not_proceed
    
command8_success:

    ; We got our first byte of response. We check if the SD Card is not in an IDLE state (which is expected)
    cmp #%0000001   ; IDLE state
    bne command8_not_in_idle_state
    
    ; Retrieve the additional 4 bytes of the R7 response
	jsr spi_read_byte
	jsr spi_read_byte
	jsr spi_read_byte
	jsr spi_read_byte
    
    ; FIXME: shouldnt we do something with those 4 bytes? (look at schematic)

    lda #COLOR_OK
    sta TEXT_COLOR
    
    lda #<ok_message
    sta TEXT_TO_PRINT
    lda #>ok_message
    sta TEXT_TO_PRINT + 1
    
    jsr print_text_zero
    
    jmp done_with_command8_proceed
    
command8_not_in_idle_state:
    ; The reponse says we are not in an IDLE state, which means there is an error
    ldx #8 ; command number to print
    jsr print_spi_cmd_error
    
done_with_command8_do_not_proceed:
    jsr move_cursor_to_next_line

    ; We unselect the card
    lda #SPI_CHIP_DESELECT_AND_SLOW
    sta VERA_SPI_CTRL

    ; TODO: Can we further 'POWER OFF' the card?
    clc
    rts

done_with_command8_proceed:
    jsr move_cursor_to_next_line
    sec
    rts
    
    

    
spi_send_command0:

    ; The command index requires the highest bit to be 0 and the bit after that to be 1 = $40
    lda #(0 | $40)      
    jsr spi_write_byte
    
    ; Command 0 has no arguments, so sending 4 bytes with value 0
    lda #0
    jsr spi_write_byte
    jsr spi_write_byte
    jsr spi_write_byte
    jsr spi_write_byte
    
    ; Command 0 requires an CRC. Since everything is fixed for this command, the CRC is already known
    lda #$95            ; CRC for command0
    jsr spi_write_byte

    ; We wait for a response
    ldx #20                   ; TODO: how many retries do we want to do?
spi_wait_command0:
    dex
    beq spi_command0_timeout
    jsr spi_read_byte
    tay                       ; we want to keep the original value (so we put it in y for now)
    ; FIXME: Use 65C02 processor so we can use "bit #$80" here
    and #$80
    cmp #$80
    beq spi_wait_command0
    
    tya                       ; we restore the original value (stored in y)

    sec  ; set the carry: we succeeded
    rts

spi_command0_timeout:
    clc  ; clear the carry: we did not succeed
    rts

    
    
spi_send_command8:

    ; The command index requires the highest bit to be 0 and the bit after that to be 1 = $40
    lda #(8 | $40)      
    jsr spi_write_byte
    
    ; Command 8 has two bytes of argument, so sending two bytes with value 0 and then the 2 bytes as argument ($01AA) 
    lda #0
    jsr spi_write_byte
    jsr spi_write_byte
    
    lda #$01
    jsr spi_write_byte
    lda #$AA
    jsr spi_write_byte
    
    ; Command 0 requires an CRC. Since everything is fixed for this command, the CRC is already known
    lda #$87            ; CRC for command8
    jsr spi_write_byte

    ; We wait for a response (which should be R1 + 32 bits = R7)
    ldx #20                   ; TODO: how many retries do we want to do?
spi_wait_command8:
    dex
    beq spi_command8_timeout
    jsr spi_read_byte
    tay                       ; we want to keep the original value (so we put it in y for now)
    ; FIXME: Use 65C02 processor so we can use "bit #$80" here
    and #$80
    cmp #$80
    beq spi_wait_command8
    
    tya                       ; we restore the original value (stored in y)

    sec  ; set the carry: we succeeded
    rts

spi_command8_timeout:
    clc  ; clear the carry: we did not succeed
    rts



spi_send_command55:

    ; The command index requires the highest bit to be 0 and the bit after that to be 1 = $40
    lda #(55 | $40)      
    jsr spi_write_byte
    
    ; Command 55 has no arguments, so sending 4 bytes with value 0
    lda #0
    jsr spi_write_byte
    jsr spi_write_byte
    jsr spi_write_byte
    jsr spi_write_byte
    
    ; Command 0 requires no CRC. So we send another 0
    jsr spi_write_byte

    ; We wait for a response
    ldx #20                   ; TODO: how many retries do we want to do?
spi_wait_command55:
    dex
    beq spi_command55_timeout
    jsr spi_read_byte
    tay                       ; we want to keep the original value (so we put it in y for now)
    ; FIXME: Use 65C02 processor so we can use "bit #$80" here
    and #$80
    cmp #$80
    beq spi_wait_command55
    
    tya                       ; we restore the original value (stored in y)

    sec  ; set the carry: we succeeded
    rts

spi_command55_timeout:
    clc  ; clear the carry: we did not succeed
    rts

    
    
spi_send_command41:

    ; The command index requires the highest bit to be 0 and the bit after that to be 1 = $40
    lda #(41 | $40)      
    jsr spi_write_byte
    
    ; Command 41 has four bytes of argument ($40000000) 
    lda #$40
    jsr spi_write_byte
    lda #0
    jsr spi_write_byte
    jsr spi_write_byte
    jsr spi_write_byte
    
    ; Command 41 requires no CRC. So sending another 0
    jsr spi_write_byte

    ; We wait for a response
    ldx #20                   ; TODO: how many retries do we want to do?
spi_wait_command41:
    dex
    beq spi_command41_timeout
    jsr spi_read_byte
    tay                       ; we want to keep the original value (so we put it in y for now)
    ; FIXME: Use 65C02 processor so we can use "bit #$80" here
    and #$80
    cmp #$80
    beq spi_wait_command41
    
    tya                       ; we restore the original value (stored in y)

    sec  ; set the carry: we succeeded
    rts

spi_command41_timeout:
    clc  ; clear the carry: we did not succeed
    rts

    


spi_read_byte:

    ; "Because the data transfer is driven by serial clock generated by host controller, the host controller 
    ;  must continue to read data, send a 0xFF and get received byte, until a valid response is detected. 
    ;  The DI signal must be kept high during read transfer (send a 0xFF and get the received data). 
    ;  The response is sent back within command response time (NCR), 0 to 8 bytes for SDC, 1 to 8 bytes for MMC."
     
    ; Send 1s (=FF) to the card (MOSI), while keeping the clock running
    lda #$FF
    sta VERA_SPI_DATA
    
    ; VERA is sending the data using SPI to the SD card. This takes some time. We wait until VERA says it has done the sending (and receiving a response).
wait_spi_read_busy:
    bit VERA_SPI_CTRL
    bmi wait_spi_read_busy
    
    ; Read the byte of data VERA got back from the card
    lda VERA_SPI_DATA
    rts


    ; Data in register a will be written using SPI to the SD card (through VERA registers)
spi_write_byte:
    sta VERA_SPI_DATA
    
    ; VERA is sending the data using SPI to the SD card. This takes some time. We wait until VERA says it has done the sending (and receiving a response).
wait_spi_write_busy:
    bit VERA_SPI_CTRL
    bmi wait_spi_write_busy  ; if bit 7 is high (Busy bit) we keep waiting
    
    rts

