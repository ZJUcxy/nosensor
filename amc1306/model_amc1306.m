function [y, d] = model_amc1306(u, fclk, OSR, lat_clk)
%MODEL_AMC1306  AMC1306 功能模型：二阶ΔΣ调制器 -> Manchester解码 -> sinc3(CIC)抽取
%
%   [y, d] = model_amc1306(u, fclk, OSR, lat_clk)
%
% 输入：
%   u       : 输入信号（按 fclk 采样），归一化满量程 |u|<=1
%   fclk    : 调制器时钟 [Hz]，如 20e6
%   OSR     : sinc3 抽取率，如 256
%   lat_clk : 滤波器前的固定延迟 [时钟周期数]
%             = 调制器流水线 + Manchester 解码延迟，默认 2，需在硬件上标定
% 输出：
%   y       : 抽取后输出（速率 fclk/OSR），与输入同归一化
%   d       : 解码后的单比特流（+1/-1），调试用
%
% 延迟组成（20 MHz 时钟、OSR=256 时的数值）：
%   链前固定延迟      lat_clk / fclk                  =  0.100 us
%   sinc3 群延时      (3*OSR-3)/2 / fclk = 382.5 clk  = 19.125 us
%   sinc3 完全建立    (3*OSR-2)   / fclk = 766   clk  = 38.300 us
%   总群延时          19.225 us；总完全建立 38.400 us
%
% 注意：本模型为行为级功能模型；调制器系数 a1=a2=0.5，输入幅值建议
%       |u| <= 0.7 以保证二阶结构不饱和（真实芯片另有 ±320mV/±50mV 的
%       模拟前级限幅，此处不做建模）。

if nargin < 2, fclk = 20e6; end
if nargin < 3, OSR = 256; end
if nargin < 4, lat_clk = 2; end

u = u(:).';
n = numel(u);

% ---- 1) 二阶 ΔΣ 调制器（CIFB：反馈上一拍量化值，固有 1 拍环路延迟）----
a1 = 0.5; a2 = 0.5;
x1 = 0; x2 = 0; vp = 0;
v = zeros(1, n);
for k = 1:n
    x1 = x1 + a1*(u(k) - vp);
    x2 = x2 + a2*(x1 - vp);
    vp = sign(x2);
    v(k) = vp;
end

% ---- 2) 链前固定延迟（调制器流水线 + Manchester 解码）----
d = [zeros(1, lat_clk), v(1:end-lat_clk)];

% ---- 3) sinc3 CIC 抽取（Hogenauer：3 级积分 + 256 抽取 + 3 级梳状）----
nout = floor(n / OSR);
i1 = 0; i2 = 0; i3 = 0;
acc = zeros(1, nout);
idx = 0;
for k = 1:(OSR*nout)
    i1 = i1 + d(k);
    i2 = i2 + i1;
    i3 = i3 + i2;
    if mod(k, OSR) == 0
        idx = idx + 1;
        acc(idx) = i3;
    end
end
c1 = diff([0 acc]);
c2 = diff([0 c1]);
c3 = diff([0 c2]);
y = c3 / OSR^3;    % 增益 N^3 归一化
end
