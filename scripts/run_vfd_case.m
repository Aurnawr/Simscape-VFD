function r = run_vfd_case(mdl, varargin)
%RUN_VFD_CASE  Run the VFD model once with chosen settings and do the FFT.
%
%   r = run_vfd_case(mdl, 'm', 0.8, 'fsw', 5e3, 'Vs_peak', 325, 'C', 2200e-6)
%
%   Settings (name/value, all optional; defaults = the original model):
%     m        modulation index. Reference amplitude = m * Vdc_nom/2
%     fsw      PWM switching (carrier) frequency, Hz
%     Vs_peak  peak of the single-phase AC supply, V  -> sets the DC link
%     C        DC-link capacitance, F                 -> sets the DC ripple
%     Vdc_nom  DC voltage the PWM block assumes, V (default 300)
%     Tstop    simulation stop time, s (default 0.2)
%     Twin     FFT window at the end of the run, s (default 0.1 = 5 cycles)
%
%   Output r has the settings, waveforms (t, vab, van, ia, vdc) and the
%   FFT results r.Vab, r.Van, r.Ia (see my_fft).

    p = inputParser;
    p.addParameter('m', 0.8);
    p.addParameter('fsw', 5e3);
    p.addParameter('Vs_peak', 325);
    p.addParameter('C', 2200e-6);
    p.addParameter('Vdc_nom', 300);
    p.addParameter('Tstop', 0.2);
    p.addParameter('Twin', 0.1);
    p.parse(varargin{:});
    o = p.Results;
    f1 = 50;

    load_system(mdl);
    in = Simulink.SimulationInput(mdl);
    in = in.setBlockParameter([mdl '/Vref abc'],          'Amplitude', num2str(o.m * o.Vdc_nom/2));
    in = in.setBlockParameter([mdl '/Vdc nominal'],       'Value',     num2str(o.Vdc_nom));
    in = in.setBlockParameter([mdl '/PWM Generator'],     'fsw',       num2str(o.fsw));
    in = in.setBlockParameter([mdl '/AC Voltage Source'], 'amp',       num2str(o.Vs_peak));
    in = in.setBlockParameter([mdl '/Capacitor'],         'c',         num2str(o.C));
    % PWM sample time / solver max step: at least 200 points per carrier
    % period, never coarser than the original 2 us (keeps pulse widths exact)
    Ts = min(2e-6, 1/(200*o.fsw));
    in = in.setBlockParameter([mdl '/PWM Generator'],     'Ts',        num2str(Ts));
    in = in.setModelParameter('StopTime', num2str(o.Tstop), ...
                              'MaxStep', num2str(Ts), ...
                              'SimscapeLogType', 'all', ...
                              'SimscapeLogLimitData', 'off');

    fprintf('  sim: m=%.2f  fsw=%5.0f Hz  Vs=%3.0f V  C=%5.0f uF ... ', ...
            o.m, o.fsw, o.Vs_peak, o.C*1e6);
    tic; out = sim(in); fprintf('%.1f s\n', toc);

    sl  = out.simlog;
    t   = sl.Ra.i.series.time;
    r   = o;
    r.t   = t;
    r.vab = sl.Vab_Sensor.V.series.values;                          % line-line
    r.van = sl.Ra.v.series.values + sl.La.v.series.values;          % phase (to load neutral)
    r.ia  = sl.Ra.i.series.values;
    r.vdc = sl.Capacitor.v.series.values;

    w = t >= t(end) - o.Twin;
    r.Vdc_avg    = mean(r.vdc(w));
    r.Vdc_ripple = max(r.vdc(w)) - min(r.vdc(w));

    r.Vab = my_fft(t, r.vab, f1, o.Twin);
    r.Van = my_fft(t, r.van, f1, o.Twin);
    r.Ia  = my_fft(t, r.ia,  f1, o.Twin);

    % theory (linear SPWM, m <= 1): fundamental line voltage peak = sqrt(3)/2 * m * Vdc
    % Note: PWM block normalises with Vdc_nom, actual bridge sees Vdc_avg
    r.Vab_theory = sqrt(3)/2 * o.m * r.Vdc_avg;
end
