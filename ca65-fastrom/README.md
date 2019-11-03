# hdmademo/ca65-fastrom

Identical to [ca65](../ca65) except is using fastrom or "high speed" mode,
thus mostly operates at 3.58MHz.

The code differences are minor, but not immediately obvious to someone
unfamiliar with what's necessary to achieve this.  Let's cover the differences:

# Use of high-speed banks

The most important part of the puzzle is ensuring that code at run-time is
executing out of banks in the SNES memory map that are designated as supporting
high-speed memory.  For LoROM, that's banks $80-FF.

Refer to
[these helpful memory maps](https://forums.nesdev.com/viewtopic.php?p=235113#p235113)
to get a better understanding of the situation.  The image to pay attention to
is labelled **Mode $20 ("LoROM") Memory Map**.  A summation would be:

* Banks $00-7D operate in normal speed (2.68MHz) mode
* Banks $80-FF operate in high speed (3.58MHz) mode when bit 0 of $420D is set to 1

Banks $00-7D are essentially mirrors of banks $80-FD.

But bank $00 is particularly special, as this is where CPU vectors (ex. RESET,
NMI, IRQ, BRK, COP, etc.) reside.  The 65816 unconditionally executes vectors
in bank $00 -- more on that in a moment.

The trickiest part is getting the assembler and linker to understand all of
this.  Both must generate addresses within high-speed bank regions; and
anything within bank $00 will continue to operate at normal speed (2.68MHz).

How I chose to deal with this situation was to keep segment `CODE` (`ROM00`) in
bank $00 (which is also bank $80) and dedicate it entirely to CPU vectors and
"trampoline" code, whilst other segments like `BANK01` (`ROM01`) live within
high-speed bank regions.

# Vector trampolines

You'll see some new `.proc` entries like `RESET_FASTROM` and `NMI_FASTROM`,
alongside the original `RESET` and `NMI` routines doing nothing more than a
single instruction of `jml xxx_FASTROM`.  Why is that?

As mentioned above, the 65816 executes all vectors in bank $00.  That is to
say, when RESET happens, K (a.k.a. PBR or "Program Bank Register") is $00.
When NMI fires, K is $00.  The long jumps (`jml`) allow us to execute our true
reset and NMI code in high-speed mode.

I moved `emptyproc` further up in the code, allowing it to be near/close to the
other common vector points within the `CODE` segment.  I did this because I
hate using `.segment` over and over -- I prefer to organise my code based on
what is in that segment and not switch segments excessively.

# Changing $420D

The final piece to the puzzle is the easiest: setting bit 0 of $420D to 1.
This enables the 3.58MHz access cycle in said banks.

