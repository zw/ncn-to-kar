ncn-to-kar
==========

Karaoke NCN (`.mid`, `.lyr`, `.cur`) to `.kar` file converter, in the style of
[makekar.c][makekar] by "kthx10".

 [makekar]: http://www.un4seen.com/forum/?topic=11559.msg81024#msg81024 "kthx10's NCN-to-KAR implementation in C"

The motivation for this was porting an existing Nick Karaoke (NickWin) track
collection to PyKaraoke.  `makekar` as posted is not multibyte character
set-aware and would generate a separate cursor (/bouncing
ball/what-bit-am-I-meant-to-be-singing) event for each *byte* rather than each
*character*, making diacritical/combining characters in languages like Thai
appear on their own, hanging in the air.  I ran [iconv][] across the lyrics
to transcode them from ISO8859-11 to UTF-8.

 [iconv]: www.gnu.org/software/libiconv/documentation/libiconv/iconv.1.html "`iconv` man page"

I found that a newer PyKaraoke on Linux showed track/artist names in Thai just
fine, but 0.7.1 on Windows 7 didn't, so perhaps the resulting `.kar` files
require a recent version of PyKaraoke?
