%% AMC1306 功能仿真主脚本
% 内容：
%   1. 模型自检（位流密度、抽取输出直流）
%   2. 三相稳态电流：各相群延时/幅值测量、电流矢量旋转误差
%   3. 阶跃电流：群延时 vs 完全建立时间（含 12.8us 输出网格量化效应）
%   4. 补偿方案 A：Park 域相角前移（V 曲线标定）
%   5. 补偿方案 C：整数化延迟均衡器（2 抽头）+ 整数拍相角前移
%   6. 阶跃工况预测补偿与噪声代价
%
% 运行：matlab -batch "analysis_main" 或 MATLAB 中直接 run

clear; close all; clc;
set(0,'DefaultAxesFontName','Microsoft YaHei');
set(0,'DefaultAxesFontSize',9);

outdir = fullfile(fileparts(mfilename('fullpath')),'results');
if ~exist(outdir,'dir'), mkdir(outdir); end

fclk    = 20e6;      % 调制器时钟
OSR     = 256;       % sinc3 抽取率
fs_out  = fclk/OSR;  % 78.125 kHz
Ts_out  = 1/fs_out;  % 12.8 us
lat_clk = 2;         % 链前延迟（调制器流水线+Manchester，可标定）
A       = 0.6;       % 测试幅值（归一化满量程，留调制器稳定裕量）

tau_g   = lat_clk/fclk + (3*OSR-3)/(2*fclk);   % sinc3 群延时 (L-1)/2, L=3*OSR-2
tau_set = lat_clk/fclk + (3*OSR-2)/fclk;       % 完全建立 = 冲激响应总长

fprintf('=== AMC1306 chain model ===\n');
fprintf('fs_out = %.3f kHz, Ts_out = %.3f us\n', fs_out/1e3, Ts_out*1e6);
fprintf('group delay  tau_g   = %.3f us (%.4f output samples)\n', tau_g*1e6, tau_g/Ts_out);
fprintf('full settle  tau_set = %.3f us (%.4f output samples)\n', tau_set*1e6, tau_set/Ts_out);
fprintf('settle/group ratio   = %.3f\n\n', tau_set/tau_g);

%% ================= 1. 模型自检 =================
n1 = 200000; t1 = (0:n1-1)/fclk;   % 781 个输出 = 10 个 1kHz 整周期
u1 = 0.2 + 0.1*sin(2*pi*1e3*t1);
[y1, d1] = model_amc1306(u1, fclk, OSR, lat_clk);
fprintf('[1 check] bitstream mean  = %.4f (expect ~0.200)\n', mean(d1));
fprintf('[1 check] decimated mean = %.4f (expect ~0.200, 1kHz 均值取整周期)\n', mean(y1));

%% ================= 2. 三相稳态电流 =================
fprintf('\n[2] three-phase steady state\n');
for f = [50 200]
    t_sim = max(0.03, 3/f);
    n = round(fclk*t_sim);
    t = (0:n-1)/fclk;
    t_out = (1:floor(n/OSR))*Ts_out;   % 输出 k 在抽取时刻 (k+1)*Ts_out 才可用
    ph = [0 -2*pi/3 2*pi/3];
    taus = zeros(1,3); gains = zeros(1,3);
    y3 = zeros(3, numel(t_out));
    for k = 1:3
        u = A*sin(2*pi*f*t + ph(k));
        y = model_amc1306(u, fclk, OSR, lat_clk);
        y3(k,:) = y;
        k0 = 40;   % 丢弃滤波器初始建立段
        % 各相用自己的相位基准拟合，滞后量 = -atan2(c2,c1)/w
        X = [sin(2*pi*f*t_out(k0:end) + ph(k))', cos(2*pi*f*t_out(k0:end) + ph(k))'];
        c = X \ y(k0:end)';
        gains(k) = hypot(c(1),c(2))/A;
        taus(k)  = -atan2(c(2),c(1))/(2*pi*f);
    end
    fprintf('[f=%3d Hz] tau = %.3f / %.3f / %.3f us, gain = %.6f\n', ...
            f, taus(1)*1e6, taus(2)*1e6, taus(3)*1e6, mean(gains));
    fprintf('           theory tau_g = %.3f us; vector rotation delta = %.4f deg\n', ...
            tau_g*1e6, rad2deg(2*pi*f*tau_g));

    if f == 200
        y200 = y3; t_out200 = t_out;
        fig = figure('Position',[80 80 1000 620]);
        subplot(2,1,1);
        plot(t*1e3, A*sin(2*pi*f*t), 'b'); hold on;
        stairs(t_out*1e3, y3(1,:), 'r');
        xlim([0 5/f*1e3]); xlabel('t [ms]'); ylabel('归一化电流'); grid on;
        legend('输入 ia','滤波输出 ia','Location','best');
        title(sprintf('三相稳态 f=%dHz：滤波输出滞后输入 %.3f us（=群延时）', f, taus(1)*1e6));
        subplot(2,1,2);
        plot(t_out*1e3, y3(1,:),'b'); hold on;
        plot(t_out*1e3, y3(2,:),'r');
        plot(t_out*1e3, y3(3,:),'g');
        xlim([0 5/f*1e3]); xlabel('t [ms]'); ylabel('归一化电流'); grid on;
        legend('ia','ib','ic','Location','best');
        saveas(fig, fullfile(outdir,'fig_steady_state.png'));
    end
end

%% ================= 3. 阶跃电流：群延时 vs 完全建立 =================
fprintf('\n[3] step response\n');
t_sim = 600e-6; n = round(fclk*t_sim);
t = (0:n-1)/fclk;
t0_list = [100e-6, 106.4e-6];   % 阶跃相对抽取网格的两个相位

% sinc3 理论阶跃响应（fclk 分辨率，含链前延迟，长度 3*OSR-2+lat_clk=768 点）
h = conv(conv(ones(1,OSR),ones(1,OSR)),ones(1,OSR))/OSR^3;
s_fine = A*cumsum([zeros(1,lat_clk), h]);
tf = (0:numel(s_fine)-1)/fclk;
s_end = s_fine(end);
t50  = tf(find(s_fine >= 0.5*s_end, 1));
t90  = tf(find(s_fine >= 0.9*s_end, 1));
t100 = tf(find(s_fine >= s_end - 1e-12, 1));
fprintf('50%%  = %.3f us, 90%% = %.3f us, 100%% = %.3f us\n', t50*1e6, t90*1e6, t100*1e6);
fprintf('100%%/50%% = %.3f  (=完全建立时间/群延时)\n', t100/t50);

fig = figure('Position',[80 80 1000 540]);
plot(tf*1e6 + t0_list(1)*1e6, s_fine, 'k', 'LineWidth',1.3); hold on;
for t0 = t0_list
    u = A*(t >= t0);
    y = model_amc1306(u, fclk, OSR, lat_clk);
    t_out = (1:numel(y))*Ts_out;   % 输出在抽取时刻可用
    plot(t_out*1e6, y, 'o-', 'LineWidth',1.0);
end
xline(t0_list(1)*1e6 + tau_g*1e6,   'g--', '群延时 19.28us', 'LabelVerticalAlignment','bottom');
xline(t0_list(1)*1e6 + tau_set*1e6, 'r--', '完全建立 38.4us', 'LabelVerticalAlignment','bottom');
xlabel('t [us]'); ylabel('归一化输出'); grid on;
legend([{'sinc3 理论阶跃(细)'}, {'抽取输出 t0=100us'}, {'抽取输出 t0=106.4us'}],'Location','southeast');
title('阶跃响应：群延时（50%）≈ 19.28us，完全建立（100%）≈ 38.4us，相差 2 倍');
saveas(fig, fullfile(outdir,'fig_step_response.png'));

%% ================= 4. 补偿方案 A：Park 域相角前移 =================
fprintf('\n[4A] compensation A: Park-domain phase advance\n');
ya = y200(1,:); yb = y200(2,:); yc = y200(3,:);
th = 2*pi*f*t_out200;
id_m = 2/3*(ya.*cos(th) + yb.*cos(th-2*pi/3) + yc.*cos(th+2*pi/3));
iq_m = 2/3*(-ya.*sin(th) - yb.*sin(th-2*pi/3) - yc.*sin(th+2*pi/3));
% 电流取 ia=A*sin(theta) 约定，稳态真值 dq = (0, -A)
id_ref = 0; iq_ref = -A; k0 = 40;

tau_sw = linspace(0, 40e-6, 101);
err = zeros(size(tau_sw));
for m = 1:numel(tau_sw)
    dth = 2*pi*f*tau_sw(m);
    id_c = id_m*cos(dth) - iq_m*sin(dth);
    iq_c = id_m*sin(dth) + iq_m*cos(dth);
    err(m) = sqrt(mean((id_c(k0:end)-id_ref).^2 + (iq_c(k0:end)-iq_ref).^2));
end
[~, mi] = min(err);
fprintf('optimal tau = %.3f us (theory %.3f), residual dq RMS = %.5f\n', ...
        tau_sw(mi)*1e6, tau_g*1e6, err(mi));

fig = figure('Position',[80 80 900 430]);
plot(tau_sw*1e6, err, 'b-', 'LineWidth',1.2); hold on;
xline(tau_g*1e6, 'r--', '理论群延时', 'LabelVerticalAlignment','top');
plot(tau_sw(mi)*1e6, err(mi), 'ro', 'MarkerFaceColor','r');
xlabel('补偿延时 tau [us]'); ylabel('dq 残差 RMS（归一化）'); grid on;
title('方案A：相角前移补偿量 V 曲线——最优值即链群延时，可在线/离线标定');
saveas(fig, fullfile(outdir,'fig_comp_rotation.png'));

%% ================= 5. 补偿方案 C：整数化延迟均衡器 =================
fprintf('\n[4C] compensation C: integer-delay equalizer\n');
D = 2;                          % 目标总时延：整数个输出采样
b_eq = D - tau_g/Ts_out;        % 均衡器需补足的小数延迟（拍）
a_eq = 1 - b_eq;
fprintf('equalizer taps = [%.4f %.4f], total delay -> %d samples (%.3f us)\n', ...
        a_eq, b_eq, D, D*Ts_out*1e6);

% 均衡器相位非线性残差 vs 频率（解析）
fvec = linspace(0, 2e3, 400);
wT = 2*pi*fvec*Ts_out;
H_eq = a_eq + b_eq*exp(-1j*wT);
phi_eq = unwrap(angle(H_eq));
phi_ideal = -wT*b_eq;
resid = rad2deg(phi_eq - phi_ideal);

fig = figure('Position',[80 80 900 400]);
subplot(1,2,1);
plot(fvec, resid, 'b'); grid on;
xlabel('f [Hz]'); ylabel('相位残差 [deg]');
title(sprintf('均衡器相位非线性残差（2kHz 内 <= %.4f deg）', max(abs(resid))));
subplot(1,2,2);
plot(fvec, abs(H_eq), 'b'); grid on;
xlabel('f [Hz]'); ylabel('|H_eq|');
title(sprintf('均衡器幅频（带内偏离 1 不超过 %.6f）', max(abs(abs(H_eq)-1))));
saveas(fig, fullfile(outdir,'fig_comp_equalizer.png'));

% 对三相施加均衡器 + 整数 D 拍补偿：测量侧角度后移（Park 用测量时刻的转子角 θ-δ，
% 等价于对测量 dq 正向旋转 +ωτ；[4A] 的 V 曲线已确认该方向）
ya_eq = filter([a_eq b_eq], 1, ya);
yb_eq = filter([a_eq b_eq], 1, yb);
yc_eq = filter([a_eq b_eq], 1, yc);
th_c = 2*pi*f*(t_out200 - D*Ts_out);
id_c = 2/3*(ya_eq.*cos(th_c) + yb_eq.*cos(th_c-2*pi/3) + yc_eq.*cos(th_c+2*pi/3));
iq_c = 2/3*(-ya_eq.*sin(th_c) - yb_eq.*sin(th_c-2*pi/3) - yc_eq.*sin(th_c+2*pi/3));
e_c = sqrt(mean((id_c(k0:end)-id_ref).^2 + (iq_c(k0:end)-iq_ref).^2));
fprintf('dq residual after equalizer + integer advance = %.5f (uncompensated %.5f)\n', ...
        e_c, sqrt(mean((id_m(k0:end)-id_ref).^2 + (iq_m(k0:end)-iq_ref).^2)));

%% ================= 6. 阶跃工况：预测补偿与噪声代价 =================
fprintf('\n[4D] step + equalizer + prediction\n');
t_sim = 600e-6; n = round(fclk*t_sim);
t = (0:n-1)/fclk;
rng(1);
u = A*(t >= 100e-6) + 0.003*randn(1, n);   % 叠加输入噪声用于噪声代价评估
y = model_amc1306(u, fclk, OSR, lat_clk);
y_eq = filter([a_eq b_eq], 1, y);
dy = [0 diff(y_eq)];
y_pred = y_eq + D*dy;    % 线性外推 D 拍
t_out = (1:numel(y))*Ts_out;   % 输出在抽取时刻可用

% 稳态段噪声代价（t_out 300~500us，已完全建立）
seg = (t_out > 300e-6) & (t_out < 500e-6);
std_eq = std(y_eq(seg)); std_pred = std(y_pred(seg));
fprintf('noise std: equalized = %.6f, predicted = %.6f (ratio %.2f, theory sqrt(1+2*D^2)=%.2f)\n', ...
        std_eq, std_pred, std_pred/std_eq, sqrt(1+2*D^2));

fig = figure('Position',[80 80 1000 540]);
subplot(1,2,1);
plot(tf*1e6 + t0_list(1)*1e6, s_fine, 'k', 'LineWidth',1.2); hold on;
plot(t_out*1e6, y_eq, 'b.-');
plot(t_out*1e6, y_pred, 'r.-');
xline(t0_list(1)*1e6 + D*Ts_out*1e6, 'g--', 'D 拍时延');
xlim([95 160]); xlabel('t [us]'); ylabel('归一化输出'); grid on;
legend('sinc3 理论阶跃','均衡后(时延=D拍)','预测补偿','Location','southeast');
title('阶跃：均衡后仍差 D 拍，预测外推提前恢复（伴随过冲）');
subplot(1,2,2);
plot(t_out*1e6, y_eq, 'b'); hold on;
plot(t_out*1e6, y_pred, 'r');
xlim([300 500]); xlabel('t [us]'); ylabel('归一化输出'); grid on;
legend('均衡后','预测(噪声放大)','Location','best');
title('稳态段噪声对比：预测补偿的代价');
saveas(fig, fullfile(outdir,'fig_comp_prediction.png'));

fprintf('\n=== done, figures in %s ===\n', outdir);
