%% build_six_switch_model.m
% Builds vfd_six_switch.slx from single_phase_to_three_phase.slx.
%
% The original model uses one "Converter (Three-Phase)" block as the inverter.
% Here that block (and its Six-Pulse Gate Multiplexer + Phase Splitter) is
% replaced by SIX separate switches, so every device of the two-level
% inverter is visible:
%
%        DC+ ───────┬──────────────┬──────────────┐
%                 Q_aH ‖ D_aH    Q_bH ‖ D_bH    Q_cH ‖ D_cH
%                   ├── a          ├── b          ├── c      -> RL load
%                 Q_aL ‖ D_aL    Q_bL ‖ D_bL    Q_cL ‖ D_cL
%        DC- ───────┴──────────────┴──────────────┘
%
%   Q = IGBT (Ideal, Switching), D = anti-parallel (freewheeling) diode.
%   Upper and lower switch of a leg get complementary gate pulses from the
%   same PWM Generator as before (15 V gate, 6 V threshold).
%
% Run from the repository root:
%   run(fullfile('scripts','build_six_switch_model.m'))

root = fileparts(fileparts(mfilename('fullpath')));   % repo root
cd(root);
src = 'single_phase_to_three_phase';
mdl = 'vfd_six_switch';

if bdIsLoaded(mdl), close_system(mdl, 0); end
if bdIsLoaded(src), close_system(src, 0); end
copyfile([src '.slx'], [mdl '.slx'], 'f');
load_system(mdl);
load_system('ee_lib');

B = @(name) [mdl '/' name];
P = @(name) get_param(B(name), 'PortHandles');

%% 1. remove the integrated converter and everything wired to it
for name = {'Inverter', 'Gate Mux', 'Phase Splitter'}
    lh = get_param(B(name{1}), 'LineHandles');
    hs = [lh.LConn(:); lh.RConn(:)];
    for h = hs(hs > 0).'
        if ishandle(h), delete_line(h); end
    end
    delete_block(B(name{1}));
end
% Deleting those lines also removes the branches that tied the DC bus and
% the phase sensors together, so all of them are re-wired below.

%% 2. find the library blocks
igbtLib  = find_system('ee_lib', 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
                       'Name', sprintf('IGBT (Ideal,\nSwitching)'));
if isempty(igbtLib)
    igbtLib = find_system('ee_lib', 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
                          'Name', 'IGBT (Ideal, Switching)');
end
assert(~isempty(igbtLib), 'IGBT (Ideal, Switching) not found in ee_lib');
igbtLib  = igbtLib{1};
diodeLib = 'fl_lib/Electrical/Electrical Elements/Diode';

%% 3. add 6 IGBTs + 6 anti-parallel diodes
legs = 'abc';
x0 = 1500; dx = 260; yH = 80; yL = 330;          % layout (right of the old blocks)
for k = 1:3
    for sw = {'H', 'L'}
        s  = sw{1};
        y  = yH; if s == 'L', y = yL; end
        q  = sprintf('Q_%c%s', legs(k), s);
        d  = sprintf('D_%c%s', legs(k), s);
        add_block(igbtLib, B(q), 'Position', [x0+(k-1)*dx, y, x0+(k-1)*dx+60, y+70]);
        add_block(diodeLib, B(d), 'Position', [x0+(k-1)*dx+110, y+15, x0+(k-1)*dx+150, y+55], ...
                  'Orientation', 'up');
        set_param(B(q), 'port_option', 'ee.enum.controlport.ps');   % gate = physical signal
        set_param(B(q), 'Vth', '6', 'Ron', '1e-3', 'Goff', '1e-6');
        set_param(B(d), 'Vf', '0.8', 'Ron', '1e-3', 'Goff', '1e-6');
    end
end

% Port map (checked with print_ports below, R2026b):
%   IGBT : LConn(1) = G (gate, physical signal), RConn(1) = C, RConn(2) = E
%   Diode: LConn(1) = + (anode),                 RConn(1) = - (cathode)
G = @(q) P(q).LConn(1);  C = @(q) P(q).RConn(1);  E = @(q) P(q).RConn(2);
A = @(d) P(d).LConn(1);  K = @(d) P(d).RConn(1);
link = @(h1, h2) connect_ports(mdl, h1, h2);

%% 4. DC bus  (DC+ = D2 cathode side / Load R top, DC- = D4 side / Load R bottom)
dcp = P('Load R').LConn(1);
dcn = P('Load R').RConn(1);
link(P('D2').RConn(1), dcp);
link(P('Vout Sensor').LConn(1), dcp);
link(P('D4').LConn(1), dcn);
link(P('Vout Sensor').RConn(2), dcn);

%% 5. legs
sensor = {'Ia Sensor', 'Ib Sensor', 'Ic Sensor'};
gateIn = {'S-PS aH', 'S-PS aL'; 'S-PS bH', 'S-PS bL'; 'S-PS cH', 'S-PS cL'};
for k = 1:3
    qH = sprintf('Q_%cH', legs(k)); qL = sprintf('Q_%cL', legs(k));
    dH = sprintf('D_%cH', legs(k)); dL = sprintf('D_%cL', legs(k));
    mid = P(sensor{k}).LConn(1);                  % phase output node
    link(C(qH), dcp);  link(E(qH), mid);           % upper switch: DC+ -> phase
    link(C(qL), mid);  link(E(qL), dcn);           % lower switch: phase -> DC-
    link(A(dH), mid);  link(K(dH), dcp);           % freewheel diodes
    link(A(dL), dcn);  link(K(dL), mid);
    link(P(gateIn{k,1}).RConn(1), G(qH));          % gate pulses
    link(P(gateIn{k,2}).RConn(1), G(qL));
end
% line-voltage sensor Vab across phase a and phase b
link(P('Vab Sensor').LConn(1),  P('Ia Sensor').LConn(1));
link(P('Vab Sensor').RConn(2),  P('Ib Sensor').LConn(1));

%% 6. save and check it compiles
set_param(mdl, 'StopTime', '0.1');
save_system(mdl);
fprintf('Built %s.slx - updating diagram to check connections...\n', mdl);
set_param(mdl, 'SimulationCommand', 'update');
fprintf('OK: model compiles. Open it with  open_system(''%s'')\n', mdl);

%% connect two physical ports. Simulink refuses a line whose SECOND port is
% already wired, so the free port always goes second. If both ports are
% already wired they are on the same net from the original model -> skip.
function connect_ports(mdl, h1, h2)
    l1 = get_param(h1, 'Line') ~= -1;
    l2 = get_param(h2, 'Line') ~= -1;
    if l1 && l2, return; end
    if l2, [h1, h2] = deal(h2, h1); end
    add_line(mdl, h1, h2, 'autorouting', 'smart');
end

%% helper you can call from the command window to see a block's ports:
%   print_ports('vfd_six_switch/Q_aH')
function print_ports(blk) %#ok<DEFNU>
    ph = get_param(blk, 'PortHandles');
    for f = {'LConn', 'RConn'}
        for i = 1:numel(ph.(f{1}))
            pos = get_param(ph.(f{1})(i), 'Position');
            fprintf('%s(%d) at [%d %d]\n', f{1}, i, pos(1), pos(2));
        end
    end
end
