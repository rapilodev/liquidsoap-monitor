#!/usr/bin/env perl
use strict;
use warnings;
use feature 'state';
use LWP::UserAgent;
my $port = 7654;
use Fcntl qw(:flock);
flock DATA, LOCK_EX | LOCK_NB or die "Unable to lock file $!\n";
my $index = join '', map {"$_\n"} (
    "HTTP/1.0 200 OK\r",
    "Content-type: text/html; charset=utf-8",
    "Access-Control-Allow-Origin: *",
    "Cache-Control: no-cache",
    "",
    do {local $/; <DATA>}
);

package RmsLevelServer {
    use HTTP::Server::Simple::CGI;
    use base qw(HTTP::Server::Simple::CGI);
    use IO::Select();
    use Scalar::Util qw(openhandle);
    use JSON();

    sub handle_request {
        my ($self, $cgi) = @_;
        my $endpoint = {
            '/'     => \&get_index,
            '/data' => \&get_data,
        }->{$cgi->path_info()};
        return join '',
            map {"$_\n"} (
            "HTTP/1.0 404 Not Found\r",
            "Content-type: text/plain; charset=utf-8",
            "Access-Control-Allow-Origin: *",
            "", "404 - Not Found"
            ) unless $endpoint;
        print $endpoint->($cgi);
    }

    sub get_index {
        my ($cgi) = @_;
        return unless ref $cgi;
        return $index;
    }

    sub process_data {
        my ($data) = @_;
        state $content    = '{}';
        state $updated_at = 0;
        state $json       = JSON->new->utf8->canonical;
        my $time = time;
        return $content if $time < $updated_at + 5;

        if ($data =~ /(.*)\n$/) {
            my $line = (split /\n+/, $1)[-1];
            my (
                $datetime,    $rmsLeftIn,   $rmsRightIn,
                $peakLeftIn,  $peakRightIn, $rmsLeftOut,
                $rmsRightOut, $peakLeftOut, $peakRightOut
            ) = split /\t/, $line;
            $content = $json->encode(
                {
                    datetime => $datetime,
                    in       => {
                        "rms-left"   => $rmsLeftIn,
                        "rms-right"  => $rmsRightIn,
                        "peak-left"  => $peakLeftIn,
                        "peak-right" => $peakRightIn
                    },
                    out => {
                        "rms-left"   => $rmsLeftOut,
                        "rms-right"  => $rmsRightOut,
                        "peak-left"  => $peakLeftOut,
                        "peak-right" => $peakRightOut
                    },
                    error => defined $peakRightOut ? '' : 'parse error'
                }
            );
            $updated_at = $time;
            $data =~ s/.*\n$//;
        }
        return qq!{"error":"outdated"}! if $time > $updated_at + 10;
        return $content;
    }

    sub get_fh {
        my ($file) = @_;
        state $old_file;
        state $old_fh;
        return $old_fh if $old_file && $old_file eq $file && openhandle $old_fh;
        close $old_fh  if defined $old_fh;
        open my $fh, '<', $file or return;
        $old_fh   = $fh;
        $old_file = $file;
        return $fh;
    }

    sub get_data {
        my ($cgi) = @_;
        state $json_header = join '',
            map {"$_\n"} (
            "HTTP/1.0 200 OK\r",
            "Content-type: application/json; charset=utf-8",
            "Access-Control-Allow-Origin: *", ""
            );
        state $data = '';
        my ($sec, $min, $hour, $day, $month, $year) = localtime(time());
        my $date  = sprintf("%4d-%02d-%02d", $year + 1900, $month + 1, $day);
        my $file  = "/var/log/wbox/monitor/monitor-$date.log";
        my $fileh = get_fh($file);
        return $json_header, qq!{"error":"file not found"}\n!
            unless $fileh;

        for my $fh (IO::Select->new($fileh)->can_read(0)) {
            my $bytes = sysread $fh, $data, 65536;
            if (!defined $bytes) {
                close $fh;
                return $json_header, qq!{"error":"read error"}\n!;
            }
        }
        return $json_header, process_data($data);
    }
};

my $ua = LWP::UserAgent->new;
$ua->timeout(10);
RmsLevelServer->new($port)->run();
while (1) {
    RmsLevelServer->new($port)->run()
        unless $ua->get("http://localhost:$port/")->is_success;
    sleep 60;
}

__DATA__
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dynamic Display</title>
    <style>
        html, body { background: black; font-family: sans-serif; margin: 0; padding: 0; }
        #content { display: flex; align-items: center; justify-content: center; flex-wrap: wrap; }
        .bar { background: black; margin: 0.5em; text-align: center; width: 150px; height: 700px; border: 6px solid #999; position: relative; }
        #peak, #rms { color: white; font-size: 3rem; width: 100%; position: absolute; left: -6px; border-top: 0; border: 6px solid #999; bottom: 0; height: 0; transition: height 1s linear; }
        #peak { background: #66ff66; }
        #peak.mediumPeak { background: yellow !important; }
        #peak.loudPeak { color: white; background: red !important; }
        #rms { background: green; }
        #rms.loudRms { color: white; background: red !important; }
        #rms.silent { color: black; background: yellow; }
        #rightIn { margin-right: 3em; }
        button { position: absolute; top: 0; right: 0; padding: 1em; background: #666; color: white; border: none; cursor: pointer; }
        #clock { color: white; font-size: 3em; text-align: center; }
        #error { color: red; text-align: center; }
    </style>
    <script>
        document.addEventListener('DOMContentLoaded', () => {
            const fetchData = async () => {
                try {
                    const response = await fetch('data');
                    const data = await response.json();
                    document.getElementById('error').textContent = data.error;
                    updateChannel('#leftIn', data.in["peak-left"], data.in["rms-left"]);
                    updateChannel('#rightIn', data.in["peak-right"], data.in["rms-right"]);
                    updateChannel('#leftOut', data.out["peak-left"], data.out["rms-left"]);
                    updateChannel('#rightOut', data.out["peak-right"], data.out["rms-right"]);
                } catch (error) {
                    console.error('Error fetching data:', error);
                }
            };

            const updateClock = () => {
                const now = new Date();
                document.getElementById('clock').textContent = now.toTimeString().split(' ')[0];
            };

            const updateChannel = (selector, peak, rms) => {
                const peakEl = document.querySelector(`${selector} #peak`);
                const rmsEl = document.querySelector(`${selector} #rms`);
                const peakLabel = document.querySelector(`${selector} #peakLabel`);
                const rmsLabel = document.querySelector(`${selector} #rmsLabel`);

                peakLabel.textContent = Math.round(peak);
                rmsLabel.textContent = Math.round(rms);

                peak *= -1;
                rms *= -1;

                peakEl.className = peak < 1 ? 'loudPeak' : peak < 3 ? 'mediumPeak' : '';
                rmsEl.className = rms < 18 ? 'loudRms' : rms > 30 ? 'silent' : '';

                peakEl.style.height = `${100 - peak}%`;
                rmsEl.style.height = `${100 - rms}%`;
            };

            document.getElementById('leftIn').style.display = 'none';
            document.getElementById('rightIn').style.display = 'none';

            fetchData();
            updateClock();
            setInterval(fetchData, 5000);
            setInterval(updateClock, 1000);
        });
    </script>
</head>
<body>
    <div id="buttons">
        <button onclick="['leftIn', 'rightIn'].forEach(id => {
            const el = document.getElementById(id);
            el.style.display = el.style.display === 'none' ? 'block' : 'none';
        })">Show Input</button>
    </div>
    <div id="clock"></div>
    <div id="error"></div>
    <div id="content">
        <div id="leftIn" class="bar">
            <div id="peak"><div id="peakLabel"></div></div>
            <div id="rms"><div id="rmsLabel"></div></div>
        </div>
        <div id="rightIn" class="bar">
            <div id="peak"><div id="peakLabel"></div></div>
            <div id="rms"><div id="rmsLabel"></div></div>
        </div>
        <div id="leftOut" class="bar">
            <div id="peak"><div id="peakLabel"></div></div>
            <div id="rms"><div id="rmsLabel"></div></div>
        </div>
        <div id="rightOut" class="bar">
            <div id="peak"><div id="peakLabel"></div></div>
            <div id="rms"><div id="rmsLabel"></div></div>
        </div>
    </div>
</body>
</html>
