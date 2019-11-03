@echo off
set name=hdmademo

set ca65flags=-g
set ld65flags=-m %name%.map -Ln %name%.lbl --dbgfile %name%.dbg

ca65 %ca65flags% -l %name%.lst -o %name%.o %name%.asm
ld65 %ld65flags% -C ld65.cfg -o %name%.sfc %name%.o

REM Fix ROM checksum + checksum complement
ucon64 -q --nbak --snes --chk %name%.sfc
