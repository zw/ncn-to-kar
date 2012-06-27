#!/usr/bin/env perl
#
# Combine an "NCN" (e.g. Nick Karaoke) track's separate components (.mid MIDI,
# .lyr lyric, .cur cursor/timing info) into a single .kar file.
#
# Copyright (c) 2012 Isaac Wilcox.
#
# makekar.c (of unknown licence) posted by "kxth10" at:
#    http://www.un4seen.com/forum/?topic=11559.msg81024#msg81024
# was used as an initial template, but this Perl implementation is
# substantially different.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
use warnings;
use strict;

use Encode;
use MIDI;

if (scalar(@ARGV) != 4) {
    print <<END;
Usage:
    $0 <MIDI file> <lyric file> <cursor file> <KAR file>
where:
    <lyric file> is encoded in UTF-8 and has DOS line endings
        and has the song title on its own on the first line
        and has the artist name on its own on the second line
        and the song lyric starts on the fifth line
    <KAR file> is the name of the MIDI-with-embedded-stuff to create
END
    exit 1;
}

my ($midi_filename, $lyric_filename, $cursor_filename, $kar_filename) = @ARGV;

if (! (-r $midi_filename and -r $lyric_filename and -r $cursor_filename
       and ! -e $kar_filename)) {
    print <<END;
Some file that should exist doesn't, or vice versa.
END
    exit 1;
}

open(my $lyric_fh, "<", $lyric_filename)
    or die "can't open lyric file $lyric_filename: $!";
binmode($lyric_fh, ":encoding(UTF-8)");

open(my $cursor_fh, "<", $cursor_filename)
    or die "can't open cursor file $cursor_filename: $!";
binmode($cursor_fh);

binmode(STDOUT, ":utf8");

my $opus = MIDI::Opus->new({ 'from_file' => $midi_filename, 'no_parse' => 1 });

if ($opus->ticks() & 0x8000) {
    die <<EOM;
Only MIDI tracks using ticks-per-beat timing are supported, but this track uses
frames-per-second / ticks-per-frame timing.
EOM
}

# Includes both the lyric and its timing information.
my $karaoke_track = MIDI::Track->new;

$karaoke_track->new_event('track_name', 0, "Words");

my $song_title = <$lyric_fh>;
$song_title =~ s/[\r\n]+$//;
#chomp($song_title);
$karaoke_track->new_event('text_event', 0, encode("UTF-8", '@T' . $song_title));

my $artist_name = <$lyric_fh>;
$artist_name =~ s/[\r\n]+$//;
#chomp($artist_name);
$karaoke_track->new_event('text_event', 0, encode("UTF-8", '@T' . $artist_name));

# FIXME: could display these as @I (info) lines?
my $discard;
$discard = <$lyric_fh>; # Musical key in Nick Karaoke tracks
$discard = <$lyric_fh>; # Blank line in Nick Karaoke tracks

# For absolute-to-relative cursor timestamp conversion.
my $previous_absolute_timestamp = 0;

# Accumulate the full lyric as a simple lump of indexable text.
my $full_lyric = "";

while (my $line = <$lyric_fh>) {
    my @abstract_characters = ();

    $full_lyric .= $line;
    $line =~ s/[\r\n]+$//;
    next if $line =~ m//;

    # I think '/' means something similar to newline in karaoke cursors.
    # makekar adds one to the start of each line, so do the same here.
    # FIXME be sure
    $line = "/$line";
    my @graphic_characters = split(//, $line);

    # An abstract character can be encoded by a single graphic character or a
    # base graphic character with all its combining graphic characters.
    # PyKaraoke needs to be fed a complete abstract character at a time,
    # otherwise it'll show the combining graphic characters floating around,
    # isolated from the base graphic character they apply to.
    while (scalar(@graphic_characters)) {
        my $abstract_character = shift(@graphic_characters);
        # Let's assume an abstract character's components are never split over
        # lines.
        while (scalar(@graphic_characters) && $graphic_characters[0] =~ m/^\p{MARK}$/) {
            $abstract_character .= shift(@graphic_characters);
        }
        push(@abstract_characters, $abstract_character);
    }
    while (scalar(@abstract_characters)) {
        my ($buffer, $absolute_timestamp);

        foreach my $graphic_character (split(//, $abstract_characters[0])) {
            my $num_bytes_obtained = read($cursor_fh, $buffer, 2);
            if (defined($num_bytes_obtained) && $num_bytes_obtained == 2) {
                $absolute_timestamp = unpack("v", $buffer);
            } else {
                warn "ran out of timing info";
                $absolute_timestamp = $previous_absolute_timestamp;
            }
        }
        
        # FIXME: straight from makekar --- what is this?
        $absolute_timestamp = $absolute_timestamp * ($opus->ticks() / 24);

        if ($absolute_timestamp < $previous_absolute_timestamp) {
            warn sprintf("timestamp %x out of order", $absolute_timestamp / ($opus->ticks() / 24));
            $absolute_timestamp = $previous_absolute_timestamp;
        }
        my $relative_timestamp = $absolute_timestamp - $previous_absolute_timestamp;
        $karaoke_track->new_event('text_event', $relative_timestamp,
                                encode('UTF-8', shift(@abstract_characters)));
        $previous_absolute_timestamp = $absolute_timestamp;
    }
}

my $buffer;
my $num_bytes_obtained = read($cursor_fh, $buffer, 1);
if (!defined($num_bytes_obtained)) {
    warn "error reading timing info: $!";
} elsif ($num_bytes_obtained == 0) {
    warn "EOF without terminator while reading timing info";
} elsif ($buffer !~ /\xFF/ || !eof($cursor_fh)) {
    my $unused_bytes = 0;
    while (read($cursor_fh, $buffer, 1)) {
        $unused_bytes++;
    }
    warn sprintf("%d bytes (%d values) of unused timing info after exhausting the lyrics, or timing info ended without terminator", $unused_bytes, $unused_bytes/2);
}

#close($lyric_fh) or warn "failed to close lyric file $lyric_filename: $!";
#close($lyric_fh) or warn "failed to close cursor file $cursor_filename: $!";

# FIXME: should find a standard way of doing this, but:
# Embed the lyric as one single text item to ease indexing by lyric.
my $lyric_track = MIDI::Track->new;
$lyric_track->new_event('track_name', 0, "Lyric");
$lyric_track->new_event('text_event', 0, encode("UTF-8", $full_lyric));

# FIXME: should find a standard way of doing this, but:
# Embed the artist.
my $artist_name_track = MIDI::Track->new;
$artist_name_track->new_event('track_name', 0, "Artist");
$artist_name_track->new_event('text_event', 0, encode("UTF-8", $artist_name));

# FIXME: should find a standard way of doing this, but:
# Embed the song title.
my $song_title_track = MIDI::Track->new;
$song_title_track->new_event('track_name', 0, "SongTitle");
$song_title_track->new_event('text_event', 0, encode("UTF-8", $song_title));

# Insert karaoke track into MIDI opus as second track (first is timing info).
my $tracks = $opus->tracks_r();
splice(@$tracks, 1, 0, $karaoke_track, $lyric_track, $artist_name_track, $song_title_track);

$opus->write_to_file($kar_filename);

# For pykaraoke: write/append to a titles.txt alongside the .kar.
open(my $titles_fh, ">>", "titles.txt") or die "opening titles.txt for append: $!";
binmode($titles_fh, ":utf8");
print $titles_fh "$kar_filename\t$song_title\t$artist_name\n";
#close titles

exit(0);
