#!/usr/bin/env perl

use Math::Trig;
use Getopt::Long;
use autodie;
use feature 'say';
use Carp;
use strict;
use warnings;

my $help;
my $in;
my $out;
if (!GetOptions('help', \$help, 'in=s', \$in, 'out=s', \$out) || $help || !defined($in) ) {
    print "usage $0: [--help] -in input_wav_file -out output_file\n";
    exit 9;
}


sub read_bytes {
    my $fd = shift;
    my $len = shift;

    my $buf;
    if ( read($fd, $buf, $len) != $len ) {
        die "read $len bytes failed";
    }
    return $buf;
    
}

sub check_eq {
    if ( $_[0] ne $_[1] ) {
        croak "expected '$_[0]' got '$_[1]" . ( @_ > 2 ? " $_[2]": '');
    }
    return 1;
}
sub check_num_eq {
    if ( $_[0] != $_[1] ) {
        croak "expected '$_[0]' got '$_[1]" . ( @_ > 2 ? " $_[2]": '');
    }
    return 1;
}

sub dump_around {
    my $ar = shift;
    my $i_start = shift;
    my $window = shift;

#   for ( my $i = $i_start - $window ; $i <= $i_start + $window ; $i++ ) {
#   }
    say "window around $i_start";
    say join(' ', @$ar[($i_start - $window) .. ($i_start - 1)]);
    say join(' ', @$ar[($i_start) .. ($i_start + $window)]);
}

sub adjust_sync {
    my $sig_hr = shift;
    my $ar = shift;
    my $i_start = shift;

#   dump_around( $ar, $i_start, 20 );

    my @b;
    my $r_sum = 0;
    my $max_run_sum = 0;
    my $i_max_run_sum = 0;
    for ( my $i = -20; $i <=30; $i++ ) {
        if ( $i >= 0 ) {
            my $old = shift @b;
            $r_sum -= $old;
        }
        my $val = $ar->[$i+$i_start]; 
        if ( $val > 2 ) {
            $r_sum += $val; 
            push @b, $val;
        }
        elsif ( $val < -2 ) {
            $r_sum -= $val; 
            push @b, -$val;
        } else {
            push @b, 0;
        }
        if ( $r_sum > $max_run_sum ) {
            $max_run_sum = $r_sum;
            $i_max_run_sum = $i;
        }
    }
    my $correction = $i_max_run_sum - 20;
    if ( abs($correction) > 2 ) {
        say "at $i_start correction $correction";
        $sig_hr->{correction} += $correction;
        $sig_hr->{start} += $correction;
    }
    $sig_hr->{next_correction} = $i_start + 80*8*20;
    
}

sub check_signal_start {
    my $i_begin = shift;
    my $ar = shift;

    my $r_sum = 0;
    my @b;
    my $s_len = 0;
    my @s_off;
    my $max_run_sum = 0;
    my $i_max_run_sum = 0;
    for ( my $i = 0; $i < 80; $i++ ) {
        if ( $i >= 20 ) {
            my $old = shift @b;
            $r_sum -= $old;
        }
        my $val = $ar->[$i+$i_begin]; 
        if ( $val > 2 ) {
            $r_sum += $val; 
            push @b, $val;
        }
        elsif ( $val < -2 ) {
            $r_sum -= $val; 
            push @b, -$val;
        } else {
            push @b, 0;
        }
        if ( $r_sum > $max_run_sum ) {
            $max_run_sum = $r_sum;
            $i_max_run_sum = $i + $i_begin;
        }
    }
    say "$i_max_run_sum max $max_run_sum";
    my $thresh = int($max_run_sum * 7 / 10);
    my $hold = int($max_run_sum / 4);
    say "thresh $thresh";
    my $i_start = $i_max_run_sum - 20;
    my $result = '';
    for ( my $i = 0 ; $i < 32 ; $i++ ) {
        my $s = 0;
        for ( my $j = 0; $j < 20 ; $j++ ) {
            $s += abs($ar->[$i_start + 20*$i + $j ]);
        }
        #say "s $s";
        if ( $s > $thresh ) {
            $result .=  '1';
        }
        elsif ( $s < $hold ) {
            $result .=  '0';
        }
        else {
            $result .=  '-';
        }

    }
    print "$result\n";
    if ( $result eq '10001000100010001000100010001000' ) {
        for ( my $k = 0 ; $k < 800 ; $k ++) {
            
            print $ar->[$i_start + $k], ' ';
            print "\n" if $k %80 == 79;
        }
        say "YES ****";
        return {
            start => $i_start + 20*32,
            thresh1 => $thresh,
            thresh0 => $hold,
            correction => 0,
            next_correction => $i_start + + 20*32 + 80*20*8,
        }           
            
    } else {
        return 0;
    }
}

sub read_signal_bit {
    my $ar = shift;
    my $sig_hr = shift;
    my $i_byte = shift;
    my $i_bit = shift;

    my $i_start = $sig_hr->{start} + $i_byte*80*8 + $i_bit*80;

    my $thresh = $sig_hr->{thresh1};
    my $hold =  $sig_hr->{thresh0};
    my $result;

    my $s;
    for ( my $j = 0; $j < 20 ; $j++ ) {         
        $s += abs($ar->[$i_start + $j ]);
    }
    if ( $s > $thresh ) {
        $result =  1;
        if ( $i_start > $sig_hr->{next_correction} ) {
            adjust_sync($sig_hr, $ar, $i_start);
        }
    }
    elsif ( $s < $hold ) {
        $result =  0;
    }
    else {
        for ( my $h = 0; $h < 80 ; $h++ ) {
            print $ar->[$i_start + $h], ' ';
        }
        print "\n";
        croak "bad bit $hold < $s < $thresh byte $i_byte";
        return '';
    }
    for ( my $k = 1 ; $k < 4; $k++ ) {
        my $s0 = 0;
        for ( my $j = 0; $j < 20 ; $j++ ) {
            $s0 += abs($ar->[$i_start + 20*$k + $j ]);
        }
        if ( $s0 > $hold ) {
            for ( my $h = 0; $h < 80 ; $h++ ) {
                print $ar->[$i_start + $h], ' ';
            }
            print "\n";
            croak "bad pad $s0 > $hold byte $i_byte";
            return '';
        }
    }
    return $result;
}

sub read_signal_len {
    my $ar = shift;
    my $sig_hr = shift;
    my $i_byte = shift;

    my $len_str = '';
    for( my $j = 0; $j < 4 ; $j++ ) {
        my $val = 0;
        for ( my $i = $j*8; $i < ($j+1)*8 ; $i++ ) {
            $val = $val * 2;
            my $bit= read_signal_bit( $ar, $sig_hr, $i_byte, $i);
            $val++ if $bit == 1; 
        }
#   say "val $val";
#       say  chr($val);
        $len_str .= chr($val);
    }
    my $mlen = unpack( 'V', $len_str ); 
    say "message length ", $mlen;   
    return $mlen;
}

sub read_signal_byte {
    my $ar = shift;
    my $sig_hr = shift;
    my $i_byte = shift;
    my $fd = shift;

    my $val = 0;
    for ( my $i = 0; $i < 8 ; $i++ ) {
        $val = $val * 2;
        my $bit= read_signal_bit( $ar, $sig_hr, $i_byte, $i);
        $val++ if $bit == 1; 
    }
#   say "val $val";
    print $fd chr($val);
}

open my $fin, '<:raw', $in;
my $header = read_bytes( $fin, 44 );

my($riff,
 $rlen,
 $wav,
 $fmt,
 $fmt_len,
 $type,
 $nchannels,
 $samp_per_sec,
 $avg_bytes_per_sec,
 $bytes_per_samp,
 $nbits,
 $data,
 $dlen) =
unpack('a4 V a4 a4 V v v V V v v a4 V', $header);

say "riff $riff";
say "rlen $rlen";
say "wav $wav";
say "fmt $fmt";
say "fmt_len $fmt_len";
say "type $type";
say "nchannels $nchannels";
say "samp_per_sec $samp_per_sec";
say "avg_bytes_per_sec $avg_bytes_per_sec";
say "bytes_per_samp $bytes_per_samp";
say "nbits $nbits";
say "data $data";
say "dlen $dlen";

check_eq( 'RIFF', $riff );
check_eq( 'WAVE', $wav );
check_eq( 'fmt ', $fmt );
check_num_eq( 16, $fmt_len, "fmt length" );
check_num_eq( 1, $type, 'WAVE_FMT_PCM' );
check_num_eq( 1, $nchannels, 'channels');
check_num_eq( 8000, $samp_per_sec, 'samples per second');
check_num_eq( 8000, $avg_bytes_per_sec, 'avg bytes per second');
check_num_eq( 1, $bytes_per_samp, 'avg bytes per second');
check_num_eq( 8, $nbits, 'bits');
check_eq( 'data', $data );

say time();


my $byte;
my @bytes;
#$bytes[2960044] = undef;
my $max = 20;
my $index = 0;
while ( read( $fin, $byte, 1024) > 0 ) {
    push @bytes, map { $_ - 128 } unpack( 'C*', $byte );
}
say time();

say 'bytes of data: ' . scalar(@bytes);

# scan for signal
my $running_sum = 0;
my @buffer;
my $sig_len = 0;
my @sig_off;
my $sig_data_hr;
for ( my $i = 0; $i < @bytes; $i++ ) {
    if ( $i >= 20 ) {
        my $old = shift @buffer;
        $running_sum -= abs( $old );
    }
    my $val = $bytes[$i]; 
    if ( $val > 2 ) {
        $running_sum += $val; 
        push @buffer, $val;
    }
    elsif ( $val < -2 ) {
        $running_sum -= $val; 
        push @buffer, -$val;
    } else {
        push @buffer, 0;
    }
    if ( $running_sum > 32 ) {
        $sig_len++;
    }
    elsif ( $running_sum < 32 ) {
        if ( $sig_len > 20 ) {
            $sig_data_hr = check_signal_start( $i - 40, \@bytes );
            if ( $sig_data_hr ) {
                last;
            }
            $sig_off[ $i % 80 ]++;
            say "sig end $i len $sig_len mod " . ($i % 80 );
        }
        $sig_len = 0;
    }
#   say "$i rs $running_sum";
}

say time();

for( my $i = 0; $i < 80 ; $i++ ) {
    if ( $sig_off[$i] ) {
        say "$i $sig_off[$i]";
    }
}


die 'cannot find signal start header' if ! $sig_data_hr;

my $max_bytes = int(( $#bytes - $sig_data_hr->{start} ) / (80*8));
my $len = read_signal_len( \@bytes, $sig_data_hr, 0);
if ( $max_bytes - 4 < $len ) {
    die "truncated: max bytes $max_bytes len $len";
}
open my $fd_out, '>:raw', $out;
for ( my $i = 4; $i < $max_bytes; $i++ ) {
    if ( $i < $len + 4) {
        read_signal_byte( \@bytes, $sig_data_hr, $i, $fd_out);
        say $i if $i % 1000 == 0;
    }
}

say time();

close $fd_out;
say "total correction $sig_data_hr->{correction}";

__END__


