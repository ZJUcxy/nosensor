# -*- coding: utf-8 -*-
"""
被控对象模型：PMSM + 三相逆变器 + FPGA 电流环
================================================
坐标：alpha-beta 静止坐标系，电角度 theta 为转子 d 轴相对 alpha 轴角度。
符号约定：
    e_alpha = -we*psif*sin(theta)
    e_beta  = +we*psif*cos(theta)
    Te = 1.5*p*psif*(i_beta*cos(theta) - i_alpha*sin(theta))
"""
import numpy as np


class PMSM:
    def __init__(self, mp):
        self.mp = mp
        self.ia = 0.0
        self.ib = 0.0
        self.theta = 0.0     # 电角度 [rad]
        self.wm = 0.0        # 机械角速度 [rad/s]

    def load_torque(self, wm):
        mp = self.mp
        return mp.k_load * wm * wm + mp.T_c * np.tanh(wm / 0.05)

    def deriv(self, s, vab):
        ia, ib, th, wm = s
        mp = self.mp
        we = mp.p * wm
        ea = -we * mp.psif * np.sin(th)
        eb = we * mp.psif * np.cos(th)
        dia = (vab[0] - mp.Rs * ia - ea) / mp.Ls
        dib = (vab[1] - mp.Rs * ib - eb) / mp.Ls
        te = 1.5 * mp.p * mp.psif * (ib * np.cos(th) - ia * np.sin(th))
        dwm = (te - self.load_torque(wm) - mp.B * wm) / mp.J
        return np.array([dia, dib, mp.p * wm, dwm])

    def step(self, vab, dt):
        s = np.array([self.ia, self.ib, self.theta, self.wm])
        k1 = self.deriv(s, vab)
        k2 = self.deriv(s + 0.5 * dt * k1, vab)
        k3 = self.deriv(s + 0.5 * dt * k2, vab)
        k4 = self.deriv(s + dt * k3, vab)
        s = s + dt / 6.0 * (k1 + 2.0 * k2 + 2.0 * k3 + k4)
        self.ia, self.ib = s[0], s[1]
        self.theta = (s[2] + np.pi) % (2.0 * np.pi) - np.pi
        self.wm = s[3]

    def idq_rotor(self):
        c, s = np.cos(self.theta), np.sin(self.theta)
        return c * self.ia + s * self.ib, -s * self.ia + c * self.ib


class CurrentLoop:
    """FPGA 侧电流环（dq PI + 反电动势/解耦前馈 + SVPWM 线性区限幅）"""

    def __init__(self, mp, cp):
        self.mp = mp
        self.cp = cp
        self.Kp = mp.Ls * cp.w_cc
        self.Ki = mp.Rs * cp.w_cc
        self.int_d = 0.0
        self.int_q = 0.0
        self.vmax = mp.Vdc / np.sqrt(3.0)
        self.vab = np.zeros(2)

    def step(self, ia, ib, id_ref, iq_ref, th, we, dt):
        mp = self.mp
        c, s = np.cos(th), np.sin(th)
        idm = c * ia + s * ib
        iqm = -s * ia + c * ib
        ed = id_ref - idm
        eq = iq_ref - iqm

        vd_ff = -we * mp.Ls * iqm
        vq_ff = we * (mp.Ls * idm + mp.psif)
        vd = self.Kp * ed + self.int_d + vd_ff
        vq = self.Kp * eq + self.int_q + vq_ff

        vm = np.hypot(vd, vq)
        vd_sat, vq_sat = vd, vq
        if vm > self.vmax:
            k = self.vmax / vm
            vd_sat, vq_sat = vd * k, vq * k
        # 反算抗饱和
        self.int_d += dt * (self.Ki * ed + (vd_sat - vd) / 0.01)
        self.int_q += dt * (self.Ki * eq + (vq_sat - vq) / 0.01)

        va = c * vd_sat - s * vq_sat
        vb = s * vd_sat + c * vq_sat
        self.vab = np.array([va, vb])
        return self.vab


def dead_time_distortion(vab, iab, mp, cp):
    """死区电压畸变近似：dv = Vdc*(Td/Tpwm)*sign(i)，按相叠加（alpha-beta 等效）"""
    if cp.dead_time <= 0.0:
        return vab
    dv = mp.Vdc * (cp.dead_time / cp.t_pwm)
    # 由 alpha-beta 电流反推三相电流符号，再投影回 alpha-beta
    ia = iab[0]
    ib = (-iab[0] + np.sqrt(3.0) * iab[1]) / 2.0
    ic = -ia - ib
    sa = np.tanh(ia / 0.3)
    sb = np.tanh(ib / 0.3)
    sc = np.tanh(ic / 0.3)
    # Clarke: alpha = sa, beta = (sa + 2*sb)/sqrt(3)  (sa+sb+sc=0)
    da = sa
    db = (sa + 2.0 * sb) / np.sqrt(3.0)
    return vab - dv * np.array([da, db])
