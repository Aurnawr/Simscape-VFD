function S = my_fft(t, x, f1, Twin, fs)
%MY_FFT  Single-sided amplitude spectrum of a PWM waveform using fft().
%
%   S = my_fft(t, x, f1, Twin, fs)
%
%   t    : time vector from the simulation (variable step is fine)
%   x    : signal (e.g. line voltage Vab or phase current Ia)
%   f1   : fundamental frequency in Hz (50)
%   Twin : length of the analysis window in s, taken from the END of the
%          signal. Use a whole number of fundamental cycles (e.g. 0.1 s =
%          5 cycles) so every harmonic falls exactly on an FFT bin.
%   fs   : resampling frequency in Hz (default 2 MHz)
%
%   The solver is variable-step, so the signal is first resampled onto a
%   uniform grid. Then:
%       X  = fft(x)/N                  (two-sided spectrum)
%       A  = 2*|X(1:N/2+1)|            (single-sided peak amplitude)
%       A(1) = |X(1)|                  (DC is not doubled)
%
%   Output struct S:
%       S.f, S.A        frequency axis (Hz) and peak amplitude per bin
%       S.fund          fundamental peak amplitude (at f1)
%       S.harm          table: order n, frequency, amplitude, % of fundamental
%       S.THD           total THD (%) = sqrt(Vrms^2 - Vdc^2 - V1rms^2) / V1rms
%       S.THD_low       THD (%) using only harmonics 2..50 (low order)

    if nargin < 5 || isempty(fs), fs = 2e6; end
    t = t(:); x = x(:);

    % --- 1. take an integer number of cycles from the end of the run
    tEnd = t(end);
    tu   = (tEnd - Twin : 1/fs : tEnd - 1/fs).';   % uniform grid, exactly Twin long
    [tq, iu] = unique(t);                          % interp1 needs unique t
    xu   = interp1(tq, x(iu), tu, 'linear');

    % --- 2. FFT
    N  = numel(xu);
    X  = fft(xu) / N;
    A  = 2 * abs(X(1:floor(N/2)+1));
    A(1) = abs(X(1));
    f  = (0:floor(N/2)).' * fs / N;                % resolution df = 1/Twin
    df = fs / N;

    % --- 3. fundamental and harmonics (bins at integer multiples of f1)
    k1    = round(f1/df) + 1;
    fund  = A(k1);
    step  = round(f1/df);                          % bins per harmonic order

    fmaxTHD = f(end);                              % table: all harmonics up to fs/2
    kmax    = numel(f);
    hIdx    = (k1 + step) : step : kmax;           % 2nd, 3rd, ... harmonics

    % total THD from RMS values (no frequency cut-off):
    %   Vrms^2 = Vdc^2 + V1rms^2 + sum(Vh_rms^2)
    xrms2 = mean(xu.^2);
    THD   = 100 * sqrt(max(xrms2 - A(1)^2 - fund^2/2, 0)) / (fund/sqrt(2));

    hLow    = (k1 + step) : step : min(k1 + 49*step, kmax);   % orders 2..50
    THD_low = 100 * sqrt(sum(A(hLow).^2)) / fund;

    % --- 4. table of the largest harmonics (orders 2 and up)
    n   = round(f(hIdx) / f1);
    amp = A(hIdx);
    T   = table(n, f(hIdx), amp, 100*amp/fund, ...
                'VariableNames', {'order', 'freq_Hz', 'amp_peak', 'pct_of_fund'});
    T   = sortrows(T, 'amp_peak', 'descend');

    S = struct('f', f, 'A', A, 'df', df, 'fund', fund, 'dc', A(1), ...
               'harm', T, 'THD', THD, 'THD_low', THD_low);
end
