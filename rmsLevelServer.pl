#!/usr/bin/perl
use strict;
use warnings;
package RmsLevelServer {

use HTTP::Server::Simple::CGI;
use base qw(HTTP::Server::Simple::CGI);
use feature 'state';

use Scalar::Util qw(openhandle);
use JSON ();

my %dispatch = (
    '/'     => \&get_index,
    '/data' => \&get_data,
);

sub handle_request {
    my ($self, $cgi)  = @_;

    my $path    = $cgi->path_info();
    my $handler = $dispatch{$path};

    if ( ref($handler) eq "CODE" ) {
        print "HTTP/1.0 200 OK\r\n";
        $handler->($cgi);

    } else {
        print "HTTP/1.0 404 Not found\r\n";
        print "Content-type:text/plain; charset=utf-8\n";
        print "Access-Control-Allow-Origin: *\n";
        print "\n404 - not found\n";
    }
}

sub get_index {
    my ($cgi) = @_;
    return if !ref $cgi;
    print "Content-type:text/html; charset=utf-8\n";
    print "Access-Control-Allow-Origin: *\n";
    print "\n";
    my $data= q!<\!DOCTYPE html>
<html>
<head>
    <script src="https://ajax.googleapis.com/ajax/libs/jquery/3.2.1/jquery.min.js" type="text/javascript"></script>
    <script>

    function setChannel(peakId, peak, rmsId, rms){
        $(peakId+" #peakLabel").html( Math.round(peak) );
        $(rmsId+" #rmsLabel").html( Math.round(rms) );

        peak *= -1;
        if (peak < 1){
            $(peakId).addClass("loudPeak");
        }else{
            $(peakId).removeClass("loudPeak");
        }

        if (peak < 3){
            $(peakId).addClass("mediumPeak");
        }else{
            $(peakId).removeClass("mediumPeak");
        }
        
        rms *= -1;
        if (rms < 18) {
            $(rmsId).addClass("loudRms");
        }else{
            $(rmsId).removeClass("loudRms");
        }

        if (rms > 30) {
            $(rmsId).addClass("silent");
        }else{
            $(rmsId).removeClass("silent");
        }
        
        var height  = 100 - peak;
        $(peakId).css("height",  height+"%");
        
        var height  = 100 - rms;
        $(rmsId).css("height",  height+"%");

    }
    
    function showLevel(){
        $.getJSON( 'data', 
            function(data) {
                $('#error').html(data.error);
                setChannel("#leftIn #peak",   data.in["peak-left"],   "#leftIn #rms",   data.in["rms-left"]);
                setChannel("#rightIn #peak",  data.in["peak-right"],  "#rightIn #rms",  data.in["rms-right"]);
                setChannel("#leftOut #peak",  data.out["peak-left"],  "#leftOut #rms",  data.out["rms-left"]);
                setChannel("#rightOut #peak", data.out["peak-right"], "#rightOut #rms", data.out["rms-right"]);
            }
        );
    }

    function debug(data){
        var content="";
        content+= " rms-left:"+ data["rms-left"];
        content+= " rms-right:"+ data["rms-right"];
        content+= " peak-left:"+ data["peak-left"];
        content+= " peak-right:"+ data["peak-right"];
        $('#text').html(content)
    }

    function format_digits(i) {
        return (i < 10) ? "0" + i : i;
    }
    
    function updateClock() {
        var now = new Date();
        $('#clock').html([
            format_digits(now.getHours()),
            format_digits(now.getMinutes()),
            format_digits(now.getSeconds())
        ].join(":"));
    }    

    $( document ).ready(
        function() {
            $('#leftIn').hide();
            $('#rightIn').hide();
            showLevel();
            updateClock();
            var id = setInterval(
                function(){
                    showLevel();
                }, 5000
            );
            var id = setInterval(
                function(){
                    updateClock();
                }, 1000
            );
        }
    );
    </script>

    <style>
    html,body{
        background:black;
        font-family:sans;
    }
    
    #content{
        display: flex;
        align-items: center;
        justify-content: center;
    }

    .bar{
        background:black;
        margin:0.5em;
        text-align:center;
        width: 150px;
        height: 700px;
        border: 6px solid #999;
        overflow: hidden;
        position: relative;
    }

    #rms, #peak {
        color:white;
        background:green;
        font-size:3rem;
        width: 100%;
        overflow: hidden;
        position: absolute;
        left: -6px;

        border-top: 0;
        border: 6px solid #999;
        bottom: 0;
        height: 0%;
        transition: all 1s linear;
        vertical-align:bottom;
    }
    
    #peak{
        color:black;
        background:#66ff66;
        bottom-border:0;
    }
    
    #peak.mediumPeak{
        color:black;
        background:yellow\!important;
        transition: all 1s linear;
    }

    #peak.loudPeak{
        color:white;
        background:red\!important;
        transition: all 1s linear;
    }

    #rms.loudRms{
        color:white;
        background:red\!important;
        transition: all 1s linear;
    }
  
    #rms.silent{
        color:black;
        background:yellow;
        transition: all 1s linear;
    }
   
    #rightIn{
        margin-right:3em;
    }
   
    button{
        position:absolute;
        top:0;
        right:0;
        padding:1em;
        background:#666;
        color:white;
        border:0;
    }
    
    #clock{
        color:white;
        font-size:3em;
    }

    #error{
        color:red;
    }

    </style>
</head>

<body>
    <div id="buttons">
        <button onclick="$('#leftIn').toggle();$('#rightIn').toggle();">show input</button>
    </div>
        
    <center>
        <div id="clock"></div>
        <div id="error"></div>
    </center>
    
    <div id="content" >
        <div id="leftIn" class="bar">
            <div id="peak">
                <div id="peakLabel"></div>
                <div id="rms">            
                    <div id="rmsLabel"></div>
                </div>
            </div>
        </div>
        <div id="rightIn" class="bar">
            <div id="peak">
                <div id="peakLabel"></div>
                <div id="rms">
                    <div id="rmsLabel"></div>
                </div>
            </div>
        </div>

        <div id="leftOut" class="bar">
            <div id="peak">
                <div id="peakLabel"></div>
                <div id="rms">            
                    <div id="rmsLabel"></div>
                </div>
            </div>
        </div>
        <div id="rightOut" class="bar">
            <div id="peak">
                <div id="peakLabel"></div>
                <div id="rms">
                    <div id="rmsLabel"></div>
                </div>
            </div>
        </div>

    </div>
</body>
</html>
    !;
    print $data;
}

my $json_header = "Content-type:application/json; charset=utf-8\n";
$json_header .=  "Access-Control-Allow-Origin: *\n";
$json_header .=  "\n";

sub get_fh {
    my ($file) = @_;
    state $old_file;
    state $old_fh;
    return $old_fh if $old_file and $old_file eq $file and openhandle $old_fh;
    open my $fh, '<', $file or return undef;
    $old_fh = $fh;
    $old_file = $file;
    return $fh;
}

sub get_data {
    my ($cgi) = @_;

    ( my $sec, my $min, my $hour, my $day, my $month, my $year ) = localtime( time() );
    my $date = sprintf( "%4d-%02d-%02d", $year + 1900, $month + 1, $day );
    my $file = "/var/log/wbox/monitor/monitor-$date.log";
    state $data = '';
    while (my $fileh = get_fh($file)){
        my $bytes = sysread $fileh, $data, 65535, length $data;
        if (!defined $bytes) {
            close $fileh;
            return print $json_header, qq!{"error":"read error"}\n!;
        }
        last if $bytes == 0;
        if ($bytes) {
            my $pos = rindex $data, "\n";
            next if $pos == -1;
            if ($pos == length($data)-1) {
                $pos = rindex $data, "\n", $pos-1;
                $data = substr($data, $pos) if $pos != -1;
            }
        }
    }
    state $content = '{}';
    state $updated_at = 0;
    if ($data =~ /(.+)\n$/) {
        my $line = $1;
        my ( $datetime, $rmsLeftIn, $rmsRightIn, $peakLeftIn, $peakRightIn, $rmsLeftOut, $rmsRightOut, $peakLeftOut, $peakRightOut ) = split /\t/, $line;
        $content = JSON->new->utf8->canonical->encode({
            datetime => $datetime,
            in  => {"rms-left" => $rmsLeftIn,  "rms-right" => $rmsRightIn,   "peak-left" => $peakLeftIn,   "peak-right" => $peakRightIn},
            out => {"rms-left" => $rmsLeftOut, "rms-right" => $rmsRightOut,  "peak-left" => $peakLeftOut,  "peak-right" => $peakRightOut},
            error =>  defined $peakRightOut ? '' : 'parse error'
        });
        $updated_at = time;
        $data =~ s/.*\n$//;
    }
    print $json_header, (time < $updated_at + 10) ? $content : qq!{"error":"outdated"}\n!;
}

} # package RmsLevelServer

# start the server on port 8080
my $pid = RmsLevelServer->new(8080)->run();
print "Use 'kill $pid' to stop the server.\n";
