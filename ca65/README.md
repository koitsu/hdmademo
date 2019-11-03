# hdmademo/ca65

## Required tools

* Microsoft Windows 7 or newer (may work on Vista or XP; unsure)
* General familiarity with Command Prompt (`cmd.exe`)
* [cc65](https://github.com/cc65/cc65) version 2.18 or newer (Specifically `ca65`/`ld65`)
  * Refer to the [Windows Snapshot link](https://github.com/cc65/cc65/blob/master/README.md) to get the latest Windows binaries
  * **Older versions will not work!**  See below for details
* [ucon64](http://ucon64.sourceforge.net/) version 2.1.0 or newer
  * Used to fix ROM checksum (`ld65` cannot generate them itself)

## Building

Run `make.bat`.  If everything works, you should end up with an `hdmademo.sfc`
file that is 256KB (262144 bytes) in size.

The current `make.bat` lacks error checking, so errors during assembly or linking
or ucon64 will be ignored.  For now, it's up to you to figure out what's wrong.

## Graphics

Please refer to the main [hdmademo/README.md](../README.md) for details.  That said:
these graphics should really be regenerated from present-day image conversion tools
like [Superfamiconv](https://github.com/Optiroc/SuperFamiconv).

## About older ca65

ca65 versions 2.17 and older
[contained a quirk](https://github.com/cc65/cc65/pull/885)
that originally caused me a great amount of pain.  Thankfully rainwarrior
(a.k.a. Brad Smith) happened to hear my frustrations and submitted some
patches which got merged in May 2019.  Thus, version 2.18 and newer contains
said patch/fix.

For those curious about the technical specifics:

Prior to version 2.18, declaration of segments (ex. `.segment "BANK01"`) had
to be done **before** any underlying code made use of labels within them.
Failure to do this would result in ca65 generating incorrect addresses for said
labels, rather than deferring their resolution to ld65 to fill in during the
linking stage.  There were a couple workarounds for this, but they all were
fairly icky.

