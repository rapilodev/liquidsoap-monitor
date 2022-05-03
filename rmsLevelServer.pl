#!/usr/bin/perl
package RmsLevelServer {

use HTTP::Server::Simple::CGI;
use base qw(HTTP::Server::Simple::CGI);

my %dispatch = (
	'/'     => \&getIndex,
	'/data' => \&getData,
);

sub handle_request {
	my $self = shift;
	my $cgi  = shift;

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

sub getIndex {
	my $cgi = shift;
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
                setChannel("#leftIn #peak",   data.in.peakLeft,   "#leftIn #rms",   data.in.rmsLeft);
                setChannel("#rightIn #peak",  data.in.peakRight,  "#rightIn #rms",  data.in.rmsRight);
                setChannel("#leftOut #peak",  data.out.peakLeft,  "#leftOut #rms",  data.out.rmsLeft);
                setChannel("#rightOut #peak", data.out.peakRight, "#rightOut #rms", data.out.rmsRight);
            }
        );
    }

    function debug(data){
        var content="";
        content+= " rmsLeft:"+ data.rmsLeft;
        content+= " rmsRight:"+ data.rmsRight;
        content+= " peakLeft:"+ data.peakLeft;
        content+= " peakRight:"+ data.peakRight;
        $('#text').html(content)
    }
    
    function updateClock() {
        var now = new Date();

        var hours = now.getHours();
        var minutes = now.getMinutes();
        var seconds = now.getSeconds();

        if (hours < 10) {
            hours = "0" + hours;
        }
        if (minutes < 10) {
            minutes = "0" + minutes;
        }
        if (seconds < 10) {
            seconds = "0" + seconds;
        }

        $('#clock').html(hours + ':' + minutes + ':' + seconds);
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
    </style>
</head>

<body>
    <div id="buttons">
        <button onclick="$('#leftIn').toggle();$('#rightIn').toggle();">show input</button>
    </div>
        
    <center>
        <div id="clock"></div>
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

sub getData {
	my $cgi = shift;
	return if !ref $cgi;
	my $date = getDate();
	my $file = "/var/log/wbox/monitor/monitor-$date.log";
	my $line = `tail -1 $file`;
	chomp $line;
	my ( $datetime, $rmsLeftIn, $rmsRightIn, $peakLeftIn, $peakRightIn, $rmsLeftOut, $rmsRightOut, $peakLeftOut, $peakRightOut ) = split( /\t/, $line );

	my $content = "Content-type:application/json; charset=utf-8\n";
    $content .=  "Access-Control-Allow-Origin: *\n";
    $content .=  "\n";
	$content .= qq{\{\n};
	$content .= qq{"datetime":"$datetime", \n};
	$content .= qq{"in":  \{"rmsLeft":$rmsLeftIn,  "rmsRight":$rmsRightIn,  "peakLeft":$peakLeftIn,  "peakRight":$peakRightIn\},\n};
	$content .= qq{"out": \{"rmsLeft":$rmsLeftOut, "rmsRight":$rmsRightOut, "peakLeft":$peakLeftOut, "peakRight":$peakRightOut\}\n};
	$content .= qq{\}\n};
	print $content. "\n";
}

sub getDate {
	( my $sec, my $min, my $hour, my $day, my $month, my $year ) = localtime( time() );
	my $datetime = sprintf( "%4d-%02d-%02d", $year + 1900, $month + 1, $day );
	return $datetime;
}
}

# start the server on port 8080
my $pid = RmsLevelServer->new(8080)->run();
print "Use 'kill $pid' to stop server.\n";

