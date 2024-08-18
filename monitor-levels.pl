#!/usr/bin/env perl
use strict;
use warnings;

use File::Basename;
use Time::HiRes qw(time sleep);
use Scalar::Util qw(looks_like_number);
use DateTime;
use File::Slurp;
use Getopt::Long;

use Fcntl qw(:flock);
flock DATA, LOCK_EX | LOCK_NB or die "Unable to lock file $!";
my $template='';
while(<DATA>){$template.=$_};

my $log_dir;
my $plot_dir;
my $help;
my $gnuplot = '/usr/bin/gnuplot';
my $min_rms = -36;
my $run_duration = 10 * 60;
my $sleep = 60;

Getopt::Long::GetOptions(
    'log_dir=s' => \$log_dir,
    'plot_dir=s' => \$plot_dir,
    'gnuplot=s' => \$gnuplot,
    'min_rms=f' => \$min_rms,
    'run_duration=i' => \$run_duration,
    'sleep=i' => \$sleep,
    'help' => \$help,
) or die "Error in command line arguments\n";

if ($help || !$log_dir || !$plot_dir) {
    print "Usage: $0 --log_dir=<log_directory> --plot_dir=<plot_directory> [--gnuplot=<path_to_gnuplot>] [--min_rms=<minimum_rms>] [--run_duration=<seconds>] [--sleep=<seconds>]\n";
    exit;
}
$min_rms = abs($min_rms);

sub time_to_datetime {
    my $time = shift || time();
    my ($sec, $min, $hour, $day, $month, $year) = localtime($time);
    return sprintf("%4d-%02d-%02d %02d:%02d:%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec);
}

sub time_to_date {
    my $time = shift || time();
    my ($sec, $min, $hour, $day, $month, $year) = localtime($time);
    return sprintf("%4d-%02d-%02d", $year + 1900, $month + 1, $day);
}

sub info {
    print time_to_datetime() . " ". join (" ", @_) . "\n";
}

sub warning {
    print time_to_datetime() . " ". join (" ", @_) . "\n";
}

sub build_data_file {
    my ($source, $target) = @_;

    info("plot $target");
    my $content = '';
    unlink $target or warn "unlink $target: $!" if -e $target;
    open my $in, "<", $source or warn "open: $source";
    open my $out, ">", $target or warn "open: $target";
    while (<$in>) {
        chomp(my $line = $_);
        if ($line =~ /^#/) {
            print $out $line . "\n";
        } else {
			my @vals = split /\t/, $line;
			print $out join("\t", $vals[0], map {
				if ($_ <= -100) {
					'-';
				} elsif ($_ < -$min_rms) {
					0;
				} else {
					$min_rms - abs($_);
				}
			} @vals[1..$#vals]), "\n";		}
    }
    close $in;
    close $out or warn "close:$!";
}

sub plot {
    my ($date, $filename1, $filename2) = @_;

    my $plot_dir = $log_dir . '/plot/';
    return warning("plot dir $plot_dir does not exist") unless -d $plot_dir;
    return warning("skip plot, $filename1 does not exist") unless -e $filename1;
    return warning("skip plot, $filename2 does not exist") unless -e $filename2;

    my $data_file1 = '/tmp/monitor-level1.plot';
    build_data_file($filename1, $data_file1);
    return warning("skip plot, $data_file1 does not exist") unless -e $data_file1;

    my $data_file2 = '/tmp/monitor-level2.plot';
    build_data_file($filename1, $data_file2);
    return warning("skip plot, $data_file2 does not exist") unless -e $data_file2;

    my $ytics = join(", ", map { sprintf '"%s" %s', $min_rms - $_, $_; } $min_rms .. -$min_rms); 

    my $plot = $template;
    $plot =~ s/DATE/$date/g;
    $plot =~ s/YTICS/$ytics/g;
    $plot =~ s/MIN_RMS/$min_rms/g;
    $plot =~ s/FILENAME1/$data_file1/g;
    $plot =~ s/FILENAME2/$data_file2/g;
    my $plot_file = "/tmp/monitor.plot";
	write_file($plot_file, $plot);

    my $image_file = "$plot_dir/monitor-$date.svg";
    my $command = "$gnuplot '$plot_file' > '$image_file'";
    info($command);
    !system $command or warning "$command failed: $?";
    chmod 0775, $image_file or warning "chmod failed: $?";
    unlink $plot_file or warning "cannot unlink $?";
}

my $start_time = time();
while (time() < $start_time + $run_duration) {
	my $date = time_to_date();
    plot($date, "$log_dir/$date-pre.log", "$log_dir/$date-post.log");
    sleep $sleep;
}

__DATA__
set terminal svg size 2000,600 linewidth 1 background rgb 'black'
set multiplot layout 3, 1        
set xdata time
set timefmt "%Y-%m-%d %H:%M:%S"
set datafile separator "\t"
set format x "%H-%M"

set border lc rgb '#f0f0f0f0'
set style fill transparent solid 0.3
set style data lines

unset border
set grid
set tmargin 1
set bmargin 1
set lmargin 10
set rmargin 3

set xrange ["DATE 00:00:00Z":"DATE 23:59:59Z"]
set ylabel "input in dB" tc rgb "#f0f0f0"
set ytics (YTICS)
set yrange [-MIN_RMS:MIN_RMS]
    
plot \
MIN_RMS-20  notitle lc rgb "#50999999", \
-MIN_RMS+20 notitle lc rgb "#50999999", \
MIN_RMS-1   notitle lc rgb "#50999999", \
-MIN_RMS+1  notitle lc rgb "#50999999", \
"FILENAME1" using 1:( $4) notitle lc rgb "#50eecccc" w filledcurves y1=0, \
"FILENAME1" using 1:(-$5) notitle lc rgb "#50cceecc" w filledcurves y1=0, \
"FILENAME1" using 1:( $2) notitle lc rgb "#50ff0000" w filledcurves y1=0, \
"FILENAME1" using 1:(-$3) notitle lc rgb "#5000ff00" w filledcurves y1=0

set ylabel "gain in dB" tc rgb "#f0f0f0"
set yrange [-24:24]
set ytics border mirror norotate autofreq

plot \
0 notitle lc rgb "#50999999", \
"< paste FILENAME1 FILENAME2" using 1:(.0+($7)-($2)) notitle lc rgb "#50ff0000" smooth freq, \
"< paste FILENAME1 FILENAME2" using 1:(.0+($8)-($3)) notitle lc rgb "#5000ff00" smooth freq 

set ylabel "output in dB" tc rgb "#f0f0f0"
set ytics (YTICS)
set yrange [-MIN_RMS:MIN_RMS]

plot \
MIN_RMS-20  notitle lc rgb "#00999999", \
-MIN_RMS+20 notitle lc rgb "#00999999", \
MIN_RMS-1   notitle lc rgb "#00999999", \
-MIN_RMS+1  notitle lc rgb "#00999999", \
"FILENAME2" using 1:( $4) notitle lc rgb "#50eecccc" w filledcurves y1=0, \
"FILENAME2" using 1:(-$5) notitle lc rgb "#50cceecc" w filledcurves y1=0, \
"FILENAME2" using 1:( $2) notitle lc rgb "#50ff0000" w filledcurves y1=0, \
"FILENAME2" using 1:(-$3) notitle lc rgb "#5000ff00" w filledcurves y1=0


