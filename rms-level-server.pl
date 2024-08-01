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

@font-face {
    font-family: 'Roboto';
    font-style: normal;
    font-weight: 400;
    src: local('Roboto'), local('Roboto-Regular'),
         url('fonts/roboto-v18-latin_latin-ext-regular.woff2') format('woff2');
}

@font-face {
  font-family: 'DSEG7-Classic';
  src: url('fonts/DSEG7Classic-Regular.woff2') format('woff2');
  font-weight: normal;
  font-style: normal;
}

* {
    color: #fff;
    font-family: 'Roboto', sans-serif;
    padding: 0;
    margin: 0;
    transition: all 5s;
    user-select: none;
}

body {
    background: #000;
    display: flex;
    flex-direction: column;
    justify-content: space-around;
    align-items: center;
    width: 100vw;
    height: 100vh;
    overflow: hidden;
    gap: 5vmin;
}

#clock {
    color: #fff;
    font-size: 12vw;
    position:absolute;
    z-index:10;
    text-shadow: 0px 0px 2vmin black;
    opacity:0.7;
}

#error {
    color: red;
    text-align: center;
    position:absolute;
    z-index:10;
}

#meters {
    display: flex;
    background: #002;
    padding: 1%;
}

.bar {
    text-align: center;
    width: 25vmin;
    height: 100vh;
    overflow: hidden;
    position: relative;
    padding: 1vmin;
    cursor: pointer;
}

#rms, #peak {
    font-size: 2vmin;
    width: 100%;
    position: absolute;
    bottom: 0;
    height: 0%;
    transition: all 5s linear;
}

#rmsLabel, #peakLabel {
    font-size:4vmin;
    padding:1vmin;
    text-shadow: 0px 0px 2vmin black;
    white-space: nowrap;
}

#peak {
    color: black;
    background: #66ff66;
}

#peak.mediumPeak {
    background: yellow !important;
}

#peak.loudPeak {
    background: red !important;
}

#rms.loudRms {
    background: red !important;
}

#rms.silent {
    color: black;
    background: yellow;
}

#rms {
    color: white;
    background: green;
}

.hidden{
    display: none;
}

#in-right {
    margin-left: 0.5vmax;
    margin-right: 1vmax;
}

#out-right {
    margin-left: 0.5vmax;
}

    </style>
    <script>
        const levelUrl = 'data';

         const setChannel = (peakId, peak, rmsId, rms) => {
            document.querySelector(`${peakId} #peakLabel`).innerText = Math.round(peak);
            document.querySelector(`${rmsId} #rmsLabel`).innerText = Math.round(rms);

            peak *= -1;
            const peakElem = document.querySelector(peakId);
            peakElem.classList.toggle("loudPeak", peak < 1);
            peakElem.classList.toggle("mediumPeak", peak < 3);

            rms *= -1;
            const rmsElem = document.querySelector(rmsId);
            rmsElem.classList.toggle("loudRms", rms < 18);
            rmsElem.classList.toggle("silent", rms > 30);

            peakElem.style.height = `${100 - peak}%`;
            rmsElem.style.height = `${100 - rms}%`;
        };

        const showLevel = async () => {
            try {
                const response = await fetch(levelUrl);
                const data = await response.json();
                document.getElementById("meters").classList.remove("hidden");
                ["in","out"].forEach(dir => {
                    ["left", "right"].forEach(channel => {
                        setChannel(
                            `#${dir}-${channel} #peak`, data[dir][`peak-${channel}`],
                            `#${dir}-${channel} #rms`, data[dir][`rms-${channel}`]
                        );
                    });
                });
            } catch(error) {
                console.log(error)
                document.getElementById("meters").classList.add("hidden");
            };
        };

        const updateClock = () => {
            const now = new Date();
            document.getElementById('clock').textContent = now.toTimeString().split(' ')[0];
        };

        document.addEventListener('DOMContentLoaded', () => {

            document.getElementById('meters').addEventListener('click', () => {
                document.getElementById('in-left').classList.toggle('hidden');
                document.getElementById('in-right').classList.toggle('hidden');
            });

            updateClock();
            setInterval(showLevel, 5000);
            setInterval(updateClock, 1000);
        });
    </script>
</head>
<body>
    <div id="clock"></div>
    <div id="error"></div>
    <div id="meters">
        <div id="in-left" class="bar card hidden">
            <div id="peak">
                <div id="peakLabel"></div>
                <div id="rms">
                    <div id="rmsLabel"></div>
                    In L
                </div>
            </div>
        </div>
        <div id="in-right" class="bar card hidden">
            <div id="peak">
                <div id="peakLabel"></div>
                <div id="rms">
                    <div id="rmsLabel"></div>
                    In R
                </div>
            </div>
        </div>

        <div id="out-left" class="bar card">
            <div id="peak">
                <div id="peakLabel"></div>
                <div id="rms">
                    <div id="rmsLabel"></div>
                    Main L
                </div>
            </div>
        </div>
        <div id="out-right" class="bar card">
            <div id="peak">
                <div id="peakLabel"></div>
                <div id="rms">
                    <div id="rmsLabel"></div>
                    Main R
                </div>
            </div>
        </div>
    </div>
</body>
</html>
