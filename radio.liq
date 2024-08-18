#!/usr/bin/env liquidsoap

measure_duration = 10.

def dbround(x)
  result = -100
  if x != 0. then
    result = float(int(10.0 * dB_of_lin(x) + 0.5)) / 10.;
  end
  result
end

def save_metrics(label, path, peak, rms)
    #datetime = string.trim(process.read("date '+%Y-%m-%d %H:%M:%S'"));
    #date = string.trim(process.read("date '+%Y-%m-%d'"));
    
    datetime = time.string("%Y-%m-%d %H:%M:%S");
    date = time.string("%Y-%m-%d")
    a = "#{dbround(fst(peak))}\t#{dbround(snd(peak))}";
    b = "#{dbround(fst(rms))}\t#{dbround(snd(rms))}";
    log("#{path} #{label} #{datetime} #{a} #{b}");
    file.write(append=true, data="#{datetime}\t#{a}\t#{b}\n", 
        string.concat([path, date, "-", label, ".log"])
    );
end

def measure_input(radio)
	# measure input RMS and max for log and plot
	p1 = peak.stereo(duration=measure_duration, radio)
	output.dummy(p1)
	r1 = rms.stereo(duration=measure_duration, radio)
	output.dummy(r1)
	thread.run(every=measure_duration, {
		save_metrics("pre", "/srv/audio/levels/piradio/", p1.peak(), r1.rms())
	})
end

def measure_output(radio)
	p2 = peak.stereo(duration=measure_duration, radio)
	output.dummy(p2)
	r2 = rms.stereo(duration=measure_duration, radio)
	output.dummy(r2)
	thread.run(every=measure_duration, {
		save_metrics("post", "/srv/audio/levels/piradio/", p2.peak(), r2.rms())
	})
end

radio = http.input("stream.example/mount")
measure_intput(radio)
radio= ladspa.fastlookaheadlimiter(input_gain=13.5, limit=-1.0, release_time=0.08, radio)
measure_output(radio)
out(radio)


