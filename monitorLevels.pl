#!/usr/bin/perl

use strict;
use warnings;

use Net::Telnet;
use File::Basename;
use Time::HiRes qw(time sleep alarm);
use POSIX qw(strftime);
use Scalar::Util qw(looks_like_number);

our $log_dir='/var/log/wbox/monitor/';
my $liquidsoap_host='localhost';
my $liquidsoap_port='9876';
my $gnuplot='/usr/bin/gnuplot';

my $minRms = -36;
$minRms *= -1 if $minRms < 0;

#set 
my $debug = 1;
my $runDuration = 10*60;
my $plot_frequency = 1*60;
my $rmsInterval = 10;
my $sleep = 5;

my $time=time();
my $start_time=$time;
my $plot_time=$time;

my $remote_duration=liquidsoap_cmd('var.get duration')||0;
$remote_duration=0.0 unless(looks_like_number($remote_duration));
liquidsoap_cmd('var.set duration='.$rmsInterval) if($remote_duration != $rmsInterval);

while ($time < $start_time +$runDuration){
	my @localtime=localtime($time);

	#get data
	my $line=liquidsoap_cmd('measure');

    my @data = split( /\s+/, $line );
    for my $i ( 0 .. 7 ) {
        $data[$i] = rmsToDb( $data[$i] );
    }
	
	my @line=(		timeToDatetime(), 		    @data );
	$line=join("\t", @line)."\n";

	#print data to file
	my $filename=$log_dir.'monitor-'.timeToDate().'.log';
	if (-e $filename){
		open FILE, ">>",$filename;
		print FILE $line;
		close FILE;
	}else{
		open FILE, ">",$filename;
		print FILE $line;
		close FILE;
	}

	#plot file
	#if($time > $plot_time+$plot_frequency){
		$plot_time=$time;
		my $date=strftime("%F",@localtime);
		plot($filename, $date);
	#}
	sleep $sleep;
	$time=time();
}
exit;

sub buildDataFile {
    my $rmsFile  = shift;
    my $dataFile = shift;

    unlink $dataFile if -e $dataFile;

    open my $file, "<", $rmsFile or warn("cannot read from $rmsFile");

    my $content = '';
    while (<$file>) {
        my $line = $_;
        $line =~ s/\n//g;
        my @vals = split( /\t/, $line );
        if ( $line =~ /^#/ ) {
            $content .= $line . "\n";
            next;
        }
        next if scalar(@vals) < 5;

        for my $i ( 1 .. scalar(@vals) - 1 ) {
            my $val = $vals[$i];

            # silence detection
            if ( $val <= -100 ) {
                $vals[$i] = '-';
                next;
            }

            # cut off signal lower than minRMS
            $val = -$minRms if $val < -$minRms;

            # get absolute value
            $val = abs($val);

            # inverse value for plot (minRMS-val= plotVal)
            $val = $minRms - $val;
            $vals[$i] = $val;
        }
        $content .= join( "\t", @vals ) . "\n";
    }
    close $file;

    info("plot $dataFile");
    open my $outFile, ">", $dataFile or warn("cannot write to $dataFile");
    print $outFile $content;
    close $outFile;
}

sub plot {
    my $filename = shift;
    my $date     = shift;

    #my $plotDir = $config->{scheduler}->{plotDir};
    my $plotDir='/var/log/wbox/monitor/';
    return unless -e $plotDir;
    return unless -d $plotDir;

    #my $gnuplot = $config->{scheduler}->{gnuplot};
    #return unless -e $gnuplot;
    my $gnuplot='/usr/bin/gnuplot';

    unless ( -e $filename ) {
        warning("skip plot, $filename does not exist");
        return;
    }

    my $dataFile = '/tmp/' . File::Basename::basename($filename) . '.plot';
    buildDataFile( $filename, $dataFile );
    $filename = $dataFile;

    unless ( -e $filename ) {
        warning("skip plot, $filename does not exist");
        return;
    }

    #info("") if $isVerboseEnabled2;

    my @ytics = ();
    for ( my $i = 0 ; $i <= $minRms ; $i += 8 ) {
        unshift @ytics, '"-' . ( $minRms - abs(-$i) ) . '" ' . (-$i);
        push @ytics, '"-' . ( $minRms - abs($i) ) . '" ' . ($i);
    }
    my $ytics = join( ", ", @ytics );

    my $plot = qq{
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

set xrange ["} . $date . q{ 00:00:00Z":"} . $date . qq{ 23:59:59Z"]
      
}.qq{
set ylabel "input in dB" tc rgb "#f0f0f0"
set ytics ($ytics)
set yrange [-$minRms:$minRms]
    
plot \\
$minRms-20  notitle lc rgb "#50999999", \\
-$minRms+20 notitle lc rgb "#50999999", \\
$minRms-1   notitle lc rgb "#50999999", \\
-$minRms+1  notitle lc rgb "#50999999", \\
"} . $filename . q{" using 1:( $4) notitle lc rgb "#50eecccc" w filledcurves y1=0, \
"} . $filename . q{" using 1:(-$5) notitle lc rgb "#50cceecc" w filledcurves y1=0, \
"} . $filename . q{" using 1:( $2) notitle lc rgb "#50ff0000" w filledcurves y1=0, \
"} . $filename . q{" using 1:(-$3) notitle lc rgb "#5000ff00" w filledcurves y1=0

set ylabel "gain in dB" tc rgb "#f0f0f0"
set yrange [-24:24]
set ytics border mirror norotate autofreq
}.qq{
plot \\
0 notitle lc rgb "#50999999", \\
"} . $filename . qq{" using 1:(.0+(\$6)-(\$2)) notitle lc rgb "#50ff0000" smooth freq, \\
"} . $filename . qq{" using 1:(.0+(\$7)-(\$3)) notitle lc rgb "#5000ff00" smooth freq\\

}.qq{
set ylabel "output in dB" tc rgb "#f0f0f0"
set ytics ($ytics)
set yrange [-$minRms:$minRms]

plot \\
$minRms-20  notitle lc rgb "#00999999", \\
-$minRms+20 notitle lc rgb "#00999999", \\
$minRms-1   notitle lc rgb "#00999999", \\
-$minRms+1  notitle lc rgb "#00999999", \\
"} . $filename . q{" using 1:( $8) notitle lc rgb "#50eecccc" w filledcurves y1=0, \
"} . $filename . q{" using 1:(-$9) notitle lc rgb "#50cceecc" w filledcurves y1=0, \
"} . $filename . q{" using 1:( $6) notitle lc rgb "#50ff0000" w filledcurves y1=0, \
"} . $filename . q{" using 1:(-$7) notitle lc rgb "#5000ff00" w filledcurves y1=0

};
    my $plotFile = "/tmp/monitor.plot";
    open my $file, '>', $plotFile;
    print $file $plot;
    close $file;

    my $imageFile = "$plotDir/monitor-$date.svg";
    my $command   = "$gnuplot '$plotFile' > '$imageFile'";
    info($command);
    `$command`;
    my $exitCode = $? >> 8;
    if ( $exitCode > 0 ) {
        warning("plot finished with $exitCode");
    } else {
        info("plot finished with $exitCode");# if $isVerboseEnabled2;
    }

    unlink $plotFile;

    setFilePermissions($imageFile);
}

#full scale to DB
sub rmsToDb{
	my $val=$_[0];
	if((looks_like_number($val)) && ($val>0.0)){
		return sprintf("%.05f", 20.0*log($val)/log(10.0) );
	}else{
		return -100.0;
	}
}

sub liquidsoap_cmd{
	my $liquidsoap_cmd=shift;
	#print "liquidsoap_cmd\t'$liquidsoap_cmd'\n";
#	eval{
		my $telnet = new Net::Telnet ( 
			Timeout=>10, 
			Prompt => '/END$/',
			Errmode => \&telnet_error,
		);
		$telnet->open(
			Host=>$liquidsoap_host, 
			Port=>$liquidsoap_port,
			Errmode => \&telnet_error,
		);
		my @lines= $telnet->cmd($liquidsoap_cmd);
		$telnet->print("quit");
		$telnet->close();
		my $result=join("",@lines);
		$result=~s/BEGIN\n//;
		$result=~s/\n$//;
		return $result;
#	};
}


sub telnet_error{
	my $result=shift;
	my $message="ERROR\t$result\n";
	debug(0, $message);
	return 1;
}

sub info {
    my $message = shift;

    my $caller = getCaller();
    my $date   = timeToDatetime();
    my $line   = "$date\tINFO";
    $line .= sprintf( "\t%-16s", $caller ) if defined $caller;
    $message =~ s/\n/\\n/g;
    $message =~ s/\r/\\r/g;
    $line .= "\t$message";
    print $line. "\n";
}

sub warning {
    my $message    = shift;
    my $onlyToFile = shift;

    my $now  = time();
    my $date = timeToDatetime($now);
    $message =~ s/\n/\\n/g;
    $message =~ s/\r/\\r/g;
    print "$date\tWARN\t$message\n";
}

sub error {
    my $message = shift;

    my $now  = time();
    my $date = timeToDatetime($now);
    print "$date\tERROR\t$message\n";
}

sub exitOnError {
    my $message = shift;
    my $caller  = getCaller();

    my $now  = time();
    my $date = timeToDatetime($now);
    print STDERR "$date\tERROR\t$caller\t$message\n";
    exit;
}

sub debug{
	my $level=shift;
	my $message=shift;
	print $message."\n" if ($debug>$level);
}

sub timeToDatetime {
    my $time = shift;

    $time = time() unless ( ( defined $time ) && ( $time ne '' ) );
    ( my $sec, my $min, my $hour, my $day, my $month, my $year ) = localtime($time);
    my $datetime = sprintf( "%4d-%02d-%02d %02d:%02d:%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
    return $datetime;
}

sub timeToDate {
    my $time = shift;

    $time = time() unless ( ( defined $time ) && ( $time ne '' ) );
    ( my $sec, my $min, my $hour, my $day, my $month, my $year ) = localtime($time);
    my $datetime = sprintf( "%4d-%02d-%02d", $year + 1900, $month + 1, $day);
    return $datetime;
}

sub getCaller() {
    my ( $package, $filename, $line, $subroutine ) = caller(2);
    return undef unless defined $subroutine;
    $subroutine =~ s/main\:\://;
    return "$subroutine()";
}

sub getUserId {
    my $userName = shift;
    my $userId   = getpwnam($userName);
    return $userId;
}

sub getGroupId {
    my $groupName = shift;
    my $groupId   = getgrnam($groupName);
    return $groupId;
}

sub setFilePermissions {
    my $path    = shift;
    my $userId  = getUserId('audiostream');
    my $groupId = getGroupId('www-data');
    return unless defined $userId;
    return unless defined $groupId;
    chown( $userId, $groupId, $path );
}


