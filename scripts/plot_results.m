%% plot_results.m
% Re-runs the single-phase -> three-phase converter model and regenerates
% the output figures in ../images.
%
% Requires: MATLAB, Simulink, Simscape, Simscape Electrical (tested on R2026b).
% Run from the repository root:  run(fullfile('scripts','plot_results.m'))

mdl = 'single_phase_to_three_phase';
load_system(mdl);

% Simscape keeps only the last 10,000 logged points by default (~20 ms here),
% so turn the limit off for this run to get the full 0.1 s.
out = sim(mdl, 'SimscapeLogLimitData', 'off');
sl  = out.simlog;

t   = sl.Ra.i.series.time;                    % s
vin = sl.AC_Voltage_Source.v.series.values;   % V, single-phase AC input
vdc = sl.Capacitor.v.series.values;           % V, DC link
vab = sl.Vab_Sensor.V.series.values;          % V, inverter line-to-line voltage
ia  = sl.Ra.i.series.values;                  % A, phase currents
ib  = sl.Rb.i.series.values;
ic  = sl.Rc.i.series.values;

outDir = 'images';
if ~exist(outDir, 'dir'), mkdir(outDir); end

%% Figure 1 - rectifier + DC link
f1 = figure('Color', 'w', 'Position', [100 100 1100 650]);
try, theme(f1, 'light'); catch, end
tiledlayout(f1, 2, 1, 'TileSpacing', 'compact');
nexttile;
plot(t*1e3, vin, 'LineWidth', 1.1); grid on;
ylabel('V_{in} (V)');
title('Single-phase AC input: 325 V peak (230 V rms), 50 Hz');
nexttile;
plot(t*1e3, vdc, 'LineWidth', 1.3); grid on; ylim([0 350]);
ylabel('V_{dc} (V)'); xlabel('Time (ms)');
title('DC link after diode bridge + 2200 \muF capacitor');
exportgraphics(f1, fullfile(outDir, 'rectifier_dc_link.png'), 'Resolution', 110);

%% Figure 2 - inverter output
f2 = figure('Color', 'w', 'Position', [100 100 1100 900]);
try, theme(f2, 'light'); catch, end
tiledlayout(f2, 3, 1, 'TileSpacing', 'compact');
nexttile;
plot(t*1e3, vab, 'LineWidth', 0.5); grid on; ylim([-400 400]);
ylabel('V_{ab} (V)');
title('Inverter line-to-line voltage V_{ab} (5 kHz sinusoidal PWM)');
nexttile;
w = t >= 0.08;
plot(t(w)*1e3, vab(w), 'LineWidth', 0.6); grid on;
xlim([80 100]); ylim([-400 400]);
ylabel('V_{ab} (V)');
title('V_{ab} zoomed: one 50 Hz cycle (80-100 ms)');
nexttile;
plot(t*1e3, [ia ib ic], 'LineWidth', 1.2); grid on;
ylabel('Current (A)'); xlabel('Time (ms)');
legend('i_a', 'i_b', 'i_c', 'Location', 'north', 'Orientation', 'horizontal');
title('Three-phase load currents (20 \Omega + 20 mH per phase, star-connected)');
exportgraphics(f2, fullfile(outDir, 'inverter_output.png'), 'Resolution', 110);

%% Steady-state numbers (last 20 ms = one 50 Hz cycle)
ws = t >= 0.08;
tw = t(ws);  T = tw(end) - tw(1);
phasor = @(x) trapz(tw, x(ws) .* exp(-1j*2*pi*50*tw)) * 2 / T;   % 50 Hz component
Pa = phasor(ia); Pb = phasor(ib); Pc = phasor(ic);
fprintf('DC link: avg %.1f V (min %.1f, max %.1f)\n', ...
    trapz(tw, vdc(ws))/T, min(vdc(ws)), max(vdc(ws)));
fprintf('50 Hz phase currents (peak): Ia %.2f A, Ib %.2f A, Ic %.2f A\n', ...
    abs(Pa), abs(Pb), abs(Pc));
fprintf('Phase of Ib / Ic relative to Ia: %.0f deg / %.0f deg\n', ...
    rad2deg(angle(Pb/Pa)), rad2deg(angle(Pc/Pa)));
