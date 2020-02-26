#!/usr/bin/env perl

use Math::Trig;
use Getopt::Long;
use autodie;
use strict;
use warnings;

my $help;
my $in;
my $out;
if (!GetOptions('help', \$help, 'in=s', \$in, 'out=s', \$out) || $help ) {
	print "usage: $0 -in infile -out outfile\n";
	exit 9;
}

sub wave_head {
	my $fd = shift;
	my $bytes_per_pulse = shift;
	my $nbytes = shift;
	print $fd 
		'RIFF',
		pack('V', $bytes_per_pulse * $nbytes * 8 + 36 ),
		"WAVE",
		"fmt ",
		pack('V', 16 ), # there are 16 bytes in format chunk
		pack('v', 1 ), # WAVE_FORMAT_PCM
		pack('v', 1 ), # 1 channel
		pack('V', 8000 ), # samples per second
		pack('V', 8000 ), # avg bytes per second
		pack('v', 1 ), # 1 channel 8bit is 1 byte for block of sample
		pack('v', 8 ), # 8bit
		"data",
		pack('V', $bytes_per_pulse * $nbytes * 8 );
}

sub encode_bytes {
	my $fd = shift;
	my $pulse1 = shift;
	my $pulse0 = shift;
	my $data = shift;

	for my $c ( split '', $data )
	{
		print $fd  map { $_ ? $pulse1 : $pulse0 }  split '', unpack('B8', $c);
	}
}

sub func
{
	my $i = shift;
	
	return 128 if $i > 20;
	
	my $x = sin( 2 * 1000 * pi * $i / 8000 ) * 71;
	my $f = 0.5 ** ( ( (10.0 - $i) / 8.0 ) ** 2 );

	return int($x * $f) + 128;
}

my $N_SAMPLE = 80;
my @a = map { func($_) } 0..($N_SAMPLE-1);

my $pulse_len = @a;
my $bytes = pack('C*', @a); # bytes for bit=1
my $ebytes = pack('C*', (128) x $N_SAMPLE); # bytes for bit=0
my $n_zero_pad = 4;

my $file_len = -s $in;
open my $fd_in, '<:raw', $in;
read($fd_in, my $content, $file_len) == $file_len or die "read bytes not as expected";
close $fd_in;

open my $fd_out, '>:raw', $out;
wave_head( $fd_out, $pulse_len, 4 + 1 + $file_len + $n_zero_pad );
for my $s ( "\x{ff}", pack('V',  $file_len ), $content, "\x00" x $n_zero_pad ) {
	encode_bytes( $fd_out, $bytes, $ebytes, $s);
}
close( $fd_out );

__END__

