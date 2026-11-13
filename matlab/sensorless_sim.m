%% 无感控制完整起动仿真（MATLAB 版本，与 sim/run_simulation.py 等价）
%  用途：团队 Simulink 工作流的对标脚本；参数/结构与 Python 版一一对应。
%  运行：sensorless_sim
%  输出：matlab/results/S1_startup_matlab.png
%
%  说明：本脚本用纯 MATLAB 实现"电压源逆变器 + 20kHz 电流环 + 5kHz DSP 控制"，
%        不含 Simulink 模型；如需 Simulink，可按本文件的模块划分搭建：
%        [PMSM Plant] [Current Loop] [SFP Delay] [Observer] [Speed PI] [Startup FSM]

function sensorless_sim()
clc; close all;

%% ---------------- 参数 ----------------
mp.p    = 4;
mp.Rs   = 0.18;
mp.Ls   = 1.0e-3;
mp.psif = 0.105;
mp.Vdc  = 300;
mp.J    = 0.01;
mp.B    = 8e-4;
mp.Tc   = 0.40;
mp.kl   = 1.42e-4;
mp.wm_rated = 3000/60*2*pi;

cp.Ts       = 2e-4;
cp.Tpwm     = 5e-5;
cp.wcc      = 2*pi*400;
cp.obswc    = 2*pi*250;
cp.wn       = 2*pi*30;
cp.zeta     = 1.0;
cp.epllmin  = 4;
cp.wmax     = 2*pi*300;
cp.wlpfs    = 1/3e-3;
cp.Kp       = 2.5;
cp.Ki       = 120;
cp.iqlim    = 25;
cp.Dcomp    = 0;
cp.Ialign   = 15;
cp.talign   = 0.35;
cp.westart  = 2*pi*2;
cp.weswitch = 2*pi*30;
cp.tramp    = 0.9;
cp.Iif      = 10;
cp.angsw    = 25*pi/180;
cp.emin     = 10;
cp.tblend   = 0.1;
cp.tsramp   = 1.8;
cp.Dlink    = 100e-6;

%% ---------------- 观测器增益 ----------------
L1 = 2*cp.obswc - mp.Rs/mp.Ls;
L2 = -mp.Ls*cp.obswc^2;
alpha_w = 1 - exp(-cp.wlpfs*cp.Ts);

%% ---------------- 初值 ----------------
Tend  = 4.5;
N     = round(Tend/cp.Ts);
nsub  = round(cp.Ts/cp.Tpwm);
accel = (cp.weswitch - cp.westart)/cp.tramp;

p.ia = 0; p.ib = 0; p.theta = 0; p.wm = 0;
cl.intd = 0; cl.intq = 0;
ob.ih = [0;0]; ob.eh = [0;0]; ob.theta = 0; ob.w = 0; ob.intw = 0; ob.wf = 0;
pi_i = 0;                        % 速度环积分
id_ref = 0; iq_ref = 0;

theta_f = 0; we_f = cp.westart;
mode = 1;                        % 1=ALIGN 2=IF 3=SETTLE 4=BLEND 5=CLOSED
blend = 0; cnt = 0; iq_init = 0; w_start = 0; t_tr = 0; t_settle = 0;
w_ref = 0;
last = struct('t',0,'theta',0,'w',0,'id',0,'iq',0);
cmds = zeros(0,5);               % [t_ready theta w id iq]

% 记录
rec = zeros(N,10);               % t wm wref west therr iq id iqr mode emag
acc_i = [0;0]; acc_v = [0;0]; acc_n = 0;
th_est = 0; w_est = 0; w_f = 0; emag = 0;

%% ---------------- 主循环 ----------------
for n = 1:N
    t = (n-1)*cp.Ts;

    % ---- 5kHz 控制 ----
    if n > 1 && acc_n > 0
        ifb = acc_i/acc_n;
        vfb = acc_v/acc_n;

        % Park + 观测器
        c = cos(ob.theta); s = sin(ob.theta);
        idm =  c*ifb(1) + s*ifb(2);
        iqm = -s*ifb(1) + c*ifb(2);
        vd  =  c*vfb(1) + s*vfb(2);
        vq  = -s*vfb(1) + c*vfb(2);
        ed_ = idm - ob.ih(1);
        eq_ = iqm - ob.ih(2);
        did = (vd - mp.Rs*ob.ih(1) + ob.w*mp.Ls*ob.ih(2) - ob.eh(1))/mp.Ls + L1*ed_;
        diq = (vq - mp.Rs*ob.ih(2) - ob.w*mp.Ls*ob.ih(1) - ob.eh(2))/mp.Ls + L1*eq_;
        ob.ih = ob.ih + cp.Ts*[did; diq];
        ob.eh = ob.eh + cp.Ts*L2*[ed_; eq_];
        emag = norm(ob.eh);
        if emag > cp.epllmin
            eps_ = -ob.eh(1)/(emag+1e-9);
        else
            eps_ = 0;
            ob.intw = ob.intw*0.999;
        end
        ob.intw = max(min(ob.intw + cp.Ts*cp.wn^2*eps_, cp.wmax), -cp.wmax);
        ob.w = max(min(2*cp.zeta*cp.wn*eps_ + ob.intw, cp.wmax), -cp.wmax);
        ob.theta = wrap_pi(ob.theta + cp.Ts*ob.w);
        ob.wf = ob.wf + alpha_w*(ob.w - ob.wf);

        th_est = ob.theta; w_est = ob.w; w_f = ob.wf;

        % 状态机
        id_ref = 0; iq_ref = 0; theta_base = 0; w_cmd = 0;
        switch mode
            case 1  % ALIGN
                id_ref = cp.Ialign*min(1, t/0.15);
                iq_ref = 2*sin(2*pi*5*t)*(t < 0.2);
                theta_base = 0; w_cmd = 0;
                if t >= cp.talign
                    mode = 2; theta_f = 0; we_f = cp.westart;
                end
            case 2  % IF
                we_f = min(we_f + cp.Ts*accel, cp.weswitch);
                theta_f = wrap_pi(theta_f + cp.Ts*we_f);
                id_ref = cp.Iif; iq_ref = 0;
                theta_base = theta_f; w_cmd = we_f;
                if we_f >= cp.weswitch - 1e-9
                    mode = 3; cnt = 0; t_settle = t;
                end
            case 3  % SETTLE
                theta_f = wrap_pi(theta_f + cp.Ts*we_f);
                id_ref = cp.Iif; iq_ref = 0;
                theta_base = theta_f; w_cmd = we_f;
                ang = abs(wrap_pi(theta_f - th_est));
                ok = (emag > cp.emin) && (ang < cp.angsw) && (w_est > 0.8*we_f);
                if ok, cnt = cnt + 1; else, cnt = 0; end
                if cnt >= 10 || (t - t_settle) > 0.8
                    mode = 4; blend = 0;
                    d0 = wrap_pi(theta_f - th_est);
                    iq_init = cp.Iif*sin(d0);
                    w_start = max(w_f/mp.p, 0);
                    pi_i = iq_init; t_tr = t;
                end
            case 4  % BLEND
                theta_f = wrap_pi(theta_f + cp.Ts*we_f);
                blend = min(blend + cp.Ts/cp.tblend, 1);
                d = wrap_pi(theta_f - th_est);
                theta_base = wrap_pi(th_est + (1-blend)*d);
                w_cmd = w_est;
                [iq_ref, pi_i] = sp_pi(pi_i, cp, w_start, w_f/mp.p, cp.iqlim, cp.Ts);
                if blend >= 1, mode = 5; end
            case 5  % CLOSED
                k = min((t - t_tr)/cp.tsramp, 1);
                w_ref = w_start + (mp.wm_rated - w_start)*k;
                [iq_ref, pi_i] = sp_pi(pi_i, cp, w_ref, w_f/mp.p, cp.iqlim, cp.Ts);
                theta_base = th_est; w_cmd = w_est;
        end
        % 注意：sp_pi 内部更新积分，MATLAB 用嵌套函数实现
        theta_sent = wrap_pi(theta_base + w_cmd*cp.Dcomp);
        cmds(end+1,:) = [t + cp.Dlink, theta_sent, w_cmd, id_ref, iq_ref];
    end

    % 记录
    idq = [ cos(p.theta) sin(p.theta); -sin(p.theta) cos(p.theta)]*[p.ia; p.ib];
    rec(n,:) = [t, p.wm, w_ref, w_f/mp.p, wrap_pi(th_est-p.theta)*180/pi, ...
                idq(2), idq(1), iq_ref, mode, emag];

    % ---- 20kHz 子步 ----
    acc_i = [0;0]; acc_v = [0;0]; acc_n = 0;
    for k = 1:nsub
        tk = t + (k-1)*cp.Tpwm;
        while ~isempty(cmds) && cmds(1,1) <= tk
            last.t = tk; last.theta = cmds(1,2); last.w = cmds(1,3);
            last.id = cmds(1,4); last.iq = cmds(1,5);
            cmds(1,:) = [];
        end
        thg = last.theta + last.w*(tk - last.t);
        [vab, cl] = current_loop(cl, mp, cp, p, last, thg);
        p = plant_step(p, mp, vab, cp.Tpwm);
        acc_i = acc_i + [p.ia; p.ib];
        acc_v = acc_v + vab;
        acc_n = acc_n + 1;
    end
end

%% ---------------- 画图 ----------------
rpm = 60/(2*pi);
f = figure('Position',[100 100 1100 700]);
subplot(3,1,1);
plot(rec(:,1), rec(:,2)*rpm, 'b', 'LineWidth',1.4); hold on;
plot(rec(:,1), rec(:,3)*rpm, 'k--');
plot(rec(:,1), rec(:,4)*rpm, 'r');
xline(t_tr,'g:');
ylabel('转速 [rpm]'); legend('实际','给定','观测','切换'); grid on;
title('MATLAB 对标：预定位 -> I/f -> 观测器切换 -> 闭环升速');

subplot(3,1,2);
plot(rec(:,1), rec(:,5), 'b'); ylabel('角度误差 [deg]'); grid on; ylim([-60 60]);

subplot(3,1,3);
plot(rec(:,1), rec(:,6), 'b'); hold on;
plot(rec(:,1), rec(:,8), 'r--');
plot(rec(:,1), rec(:,7), 'g');
ylabel('电流 [A]'); xlabel('t [s]'); legend('iq','iq*','id'); grid on;

outdir = fullfile(fileparts(mfilename('fullpath')), 'results');
if ~exist(outdir,'dir'), mkdir(outdir); end
saveas(f, fullfile(outdir,'S1_startup_matlab.png'));
fprintf('done: final speed %.1f rpm, mode %d\n', rec(end,2)*rpm, rec(end,9));
end

%% ================= 子函数 =================
function y = wrap_pi(x)
y = mod(x + pi, 2*pi) - pi;
end

function [u, integ] = sp_pi(integ, cp, ref, fb, lim, dt)
e = ref - fb;
u = cp.Kp*e + integ;
u_sat = max(min(u, lim), -lim);
if (u_sat == u) || (u > lim && e < 0) || (u < -lim && e > 0)
    integ = integ + dt*cp.Ki*e;
end
u = u_sat;
end

function [vab, cl] = current_loop(cl, mp, cp, p, last, th)
c = cos(th); s = sin(th);
idm =  c*p.ia + s*p.ib;
iqm = -s*p.ia + c*p.ib;
ed = last.id - idm;
eq = last.iq - iqm;
Kp = mp.Ls*cp.wcc; Ki = mp.Rs*cp.wcc;
vd = Kp*ed + cl.intd - last.w*mp.Ls*iqm;
vq = Kp*eq + cl.intq + last.w*(mp.Ls*idm + mp.psif);
vm = hypot(vd, vq);
vmax = mp.Vdc/sqrt(3);
if vm > vmax
    vd = vd*vmax/vm; vq = vq*vmax/vm;
end
cl.intd = cl.intd + cp.Tpwm*Ki*ed;
cl.intq = cl.intq + cp.Tpwm*Ki*eq;
vab = [c*vd - s*vq; s*vd + c*vq];
end

function p = plant_step(p, mp, vab, dt)
% RK4
s0 = [p.ia; p.ib; p.theta; p.wm];
k1 = deriv(s0, vab, mp);
k2 = deriv(s0 + 0.5*dt*k1, vab, mp);
k3 = deriv(s0 + 0.5*dt*k2, vab, mp);
k4 = deriv(s0 + dt*k3, vab, mp);
s0 = s0 + dt/6*(k1 + 2*k2 + 2*k3 + k4);
p.ia = s0(1); p.ib = s0(2);
p.theta = wrap_pi(s0(3)); p.wm = s0(4);
end

function d = deriv(s, vab, mp)
ia = s(1); ib = s(2); th = s(3); wm = s(4);
we = mp.p*wm;
ea = -we*mp.psif*sin(th);
eb =  we*mp.psif*cos(th);
dia = (vab(1) - mp.Rs*ia - ea)/mp.Ls;
dib = (vab(2) - mp.Rs*ib - eb)/mp.Ls;
Te = 1.5*mp.p*mp.psif*(ib*cos(th) - ia*sin(th));
TL = mp.kl*wm*wm + mp.Tc*tanh(wm/0.05);
dwm = (Te - TL - mp.B*wm)/mp.J;
d = [dia; dib; mp.p*wm; dwm];
end
