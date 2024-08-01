#!/usr/bin/env perl
use Mojolicious::Lite -signatures;
use IO::Select;
use Scalar::Util qw(openhandle);
use JSON;

# Serve the index.html file
get '/' => sub ($c) {
    $c->res->headers->access_control_allow_origin('*');
    $c->res->headers->cache_control('no-cache');
    $c->render(template => 'index');
};

# Serve JSON data
get '/data' => sub ($c) {
    $c->res->headers->access_control_allow_origin('*');
    $c->res->headers->content_type('application/json; charset=utf-8');

    my ($sec, $min, $hour, $day, $month, $year) = localtime(time());
    my $date = sprintf("%4d-%02d-%02d", $year + 1900, $month + 1, $day);
    my $file = "/var/log/wbox/monitor/monitor-$date.log";

    my $fileh = get_fh($file);
    return $c->render(json => {error => 'file not found'}) unless $fileh;

    my $data = '';
    for my $fh (IO::Select->new($fileh)->can_read(0)) {
        my $bytes = sysread $fh, $data, 65536;
        if (!defined $bytes) {
            close $fh;
            return $c->render(json => {error => 'read error'});
        }
    }

    return $c->render(json => process_data($data));
};

# Process the data file
sub process_data {
    state $content    = {};
    state $updated_at = 0;
    my ($data) = @_;

    my $time = time;
    return $content if $time < $updated_at + 5;

    if ($data =~ /(.*)\n$/) {
        my $line = (split /\n+/, $1)[-1];
        my (
            $datetime,    $rmsLeftIn,   $rmsRightIn,
            $peakLeftIn,  $peakRightIn, $rmsLeftOut,
            $rmsRightOut, $peakLeftOut, $peakRightOut
        ) = split /\t/, $line;

        $content = {
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
        };

        $updated_at = $time;
        $data =~ s/.*\n$//;
    }

    return {"error" => "outdated"} if $time > $updated_at + 10;
    return $content;
}

# Get file handle
sub get_fh {
    state $old_file;
    state $old_fh;
    my ($file) = @_;

    return $old_fh if $old_file && $old_file eq $file && openhandle $old_fh;

    close $old_fh if defined $old_fh;
    open my $fh, '<', $file or return;
    $old_fh   = $fh;
    $old_file = $file;

    return $fh;
}

app->start('daemon', '-l', 'http://*:7654');

__DATA__

@@ index.html.ep
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dynamic Display</title>
    <style>
        @font-face { font-family: 'Roboto'; src: url('fonts/roboto-v18-latin_latin-ext-regular.woff2') format('woff2'); }
        @font-face { font-family: 'DSEG7-Classic'; src: url('fonts/DSEG7Classic-Regular.woff2') format('woff2'); }
        * { color: #fff; font-family: 'Roboto', sans-serif; padding: 0; margin: 0; transition: all 5s; user-select: none; }
        body { background: #000; display: flex; flex-direction: column; justify-content: space-around; align-items: center; width: 100vw; height: 100vh; overflow: hidden; gap: 5vmin; }
        #clock { color: #fff; font-size: 12vw; position: absolute; z-index: 10; text-shadow: 0px 0px 2vmin black; opacity: 0.7; }
        #error { color: red; text-align: center; position: absolute; z-index: 10; }
        #meters { display: flex; background: #002; padding: 1%; }
        .bar { text-align: center; width: 25vmin; height: 100vh; overflow: hidden; position: relative; padding: 1vmin; cursor: pointer; }
        #rms, #peak { font-size: 2vmin; width: 100%; position: absolute; bottom: 0; height: 0%; transition: all 5s linear; }
        #rmsLabel, #peakLabel { font-size: 4vmin; padding: 1vmin; text-shadow: 0px 0px 2vmin black; white-space: nowrap; }
        #peak { color: black; background: #66ff66; }
        #peak.mediumPeak { background: yellow !important; }
        #peak.loudPeak { background: red !important; }
        #rms.loudRms { background: red !important; }
        #rms.silent { color: black; background: yellow; }
        #rms { color: white; background: green; }
        .hidden { display: none; }
        #in-right { margin-left: 0.5vmax; margin-right: 1vmax; }
        #out-right { margin-left: 0.5vmax; }
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
                ["in", "out"].forEach(dir => {
                    ["left", "right"].forEach(channel => {
                        setChannel(`#${dir}-${channel} #peak`, data[dir][`peak-${channel}`], `#${dir}-${channel} #rms`, data[dir][`rms-${channel}`]);
                    });
                });
            } catch (error) {
                console.log(error);
                document.getElementById("meters").classList.add("hidden");
            }
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
