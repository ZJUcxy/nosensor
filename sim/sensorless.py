# -*- coding: utf-8 -*-
"""
无位置传感器观测器 + 调节器（与 dsp/src/sensorless.c 逐行对应）
================================================================
采用**估计 dq 坐标系下的扩展反电动势观测器**，而不是 alpha-beta 静止系
全阶观测器，原因：
    5kHz 采样下，静止系观测器的反电动势状态必须随转子旋转，离散误差
    极点随电角速度升高而向单位圆靠近（3000rpm 时 0.977），相位滞后
    累积导致高速失锁。放到估计 dq 系后，反电动势是直流量，观测器成为
    定常线性系统，全速域极点不变，5kHz 下数值稳定。

模型（估计 dq 系，w = 电角速度估计）：
    vd = Rs*id + L*did/dt - w*L*iq + ed
    vq = Rs*iq + L*diq/dt + w*L*id + eq
观测器：
    i_hat' = (v - Rs*i_hat + w*L*J*i_hat - e_hat)/L + L1*(i - i_hat)
    e_hat' = L2*(i - i_hat)
    （J = [[0,-1],[1,0]]，叉乘项按 dq 系耦合展开）

稳定性：误差特征方程 s^2 + (Rs/L+L1)s - L2/L = 0，
    L1 = 2*wo - Rs/L,  L2 = -L*wo^2   （wo 为期望观测带宽）
"""
import numpy as np

TWOPI = 2.0 * np.pi


def wrap(x):
    return (x + np.pi) % TWOPI - np.pi


class DQObserver:
    def __init__(self, mp, cp):
        self.mp = mp
        self.cp = cp
        Ts = 1.0 / cp.f_ctrl
        self.Ts = Ts
        wo = cp.obs_wc
        self.L1 = 2.0 * wo - mp.Rs / mp.Ls
        self.L2 = -mp.Ls * wo * wo
        self.i_hat = np.zeros(2)     # [id, iq]
        self.e_hat = np.zeros(2)     # [ed, eq]
        self.theta = 0.0
        self.w = 0.0
        self.int_w = 0.0
        self.w_f = 0.0
        wn, z = cp.w_pll, cp.zeta
        self.Kp = 2.0 * z * wn
        self.Ki = wn * wn
        self.alpha_w = 1.0 - np.exp(-cp.w_lpf_speed * Ts)
        self.dbg_emag = 0.0

    def reset(self, theta0=0.0, w0=0.0):
        self.i_hat[:] = 0.0
        self.e_hat[:] = 0.0
        self.theta = wrap(theta0)
        self.w = w0
        self.int_w = w0
        self.w_f = w0

    def update(self, vab, iab):
        mp, cp, Ts = self.mp, self.cp, self.Ts
        c, s = np.cos(self.theta), np.sin(self.theta)
        # Park: alpha-beta -> 估计 dq
        id_m = c * iab[0] + s * iab[1]
        iq_m = -s * iab[0] + c * iab[1]
        vd = c * vab[0] + s * vab[1]
        vq = -s * vab[0] + c * vab[1]
        idh, iqh = self.i_hat
        edh, eqh = self.e_hat
        # 电流观测器（含旋转耦合项）
        did = (vd - mp.Rs * idh + self.w * mp.Ls * iqh - edh) / mp.Ls
        diq = (vq - mp.Rs * iqh - self.w * mp.Ls * idh - eqh) / mp.Ls
        ed = id_m - idh
        eq = iq_m - iqh
        did += self.L1 * ed
        diq += self.L1 * eq
        self.i_hat = np.array([idh + Ts * did, iqh + Ts * diq])
        # 反电动势观测器（dq 系为直流量）
        self.e_hat = np.array([edh + Ts * self.L2 * ed, eqh + Ts * self.L2 * eq])
        # 锁相环：ed 反映角度误差
        emag = np.hypot(self.e_hat[0], self.e_hat[1])
        self.dbg_emag = emag
        if emag > cp.e_pll_min:
            eps = -self.e_hat[0] / (emag + 1e-9)
        else:
            eps = 0.0
            self.int_w *= 0.999
        self.int_w += Ts * self.Ki * eps
        self.int_w = float(np.clip(self.int_w, -cp.w_max, cp.w_max))
        self.w = float(np.clip(self.Kp * eps + self.int_w, -cp.w_max, cp.w_max))
        self.theta = wrap(self.theta + Ts * self.w)
        self.w_f += self.alpha_w * (self.w - self.w_f)
        return self.theta, self.w, self.w_f, emag


class SpeedPI:
    """转速 PI（输出 iq*），带条件积分抗饱和"""

    def __init__(self, cp):
        self.cp = cp
        self.integ = 0.0

    def reset(self, val=0.0):
        self.integ = float(val)

    def step(self, ref, fb, limit, dt):
        e = ref - fb
        u = self.cp.Kp_w * e + self.integ
        u_sat = float(np.clip(u, -limit, limit))
        if u_sat == u or (u > limit and e < 0.0) or (u < -limit and e > 0.0):
            self.integ += dt * self.cp.Ki_w * e
        return u_sat


def estimate_error(theta_est, theta_true):
    return np.rad2deg(wrap(theta_est - theta_true))
