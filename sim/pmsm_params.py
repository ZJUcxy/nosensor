# -*- coding: utf-8 -*-
"""
无感控制仿真参数集
==================
说明：以下为 300V/25A 级表贴式（SPM）风机/泵类负载的**示例参数**，
用于算法与代码链路验证；正式验证前必须用第 docs/01 章参数辨识流程
实测替换（Rs/Ls/psi_f/J 四组参数）。

单位约定：SI（V, A, H, Wb, N·m, rad/s）
电角度 theta_e = p * theta_mech
"""


class MotorParams:
    def __init__(self, **kw):
        # ---------- 电气 ----------
        self.p = 4                     # 极对数
        self.Rs = 0.18                 # 定子相电阻 [Ohm] @25C
        self.Ls = 1.0e-3               # 定子电感, SPM: Ld=Lq [H]
        self.psif = 0.105              # 永磁体磁链 [Wb]
        self.Vdc = 300.0               # 直流母线电压 [V]
        self.I_rated = 25.0            # 额定相电流(峰值) [A]
        self.I_limit = 32.0            # 瞬态电流限幅(峰值) [A]

        # ---------- 机械 ----------
        self.J = 0.01                  # 折算转动惯量 [kg·m^2]
        self.B = 8.0e-4                # 粘滞摩擦系数 [N·m·s/rad]
        self.T_c = 0.40                # 库仑摩擦 [N·m]（用于预定位收敛）
        self.k_load = 1.42e-4          # 风机/泵类负载: TL = k_load * wm^2
        self.n_rated = 3000.0          # 额定转速 [rpm]

        # ---------- 派生 ----------
        self.kt = 1.5 * self.p * self.psif      # 转矩常数 [N·m/A]
        self.wm_rated = self.n_rated / 60.0 * 2.0 * 3.141592653589793
        self.we_rated = self.wm_rated * self.p
        for k, v in kw.items():
            setattr(self, k, v)


class CtrlParams:
    def __init__(self, **kw):
        # ---------- 时间基 ----------
        self.f_ctrl = 5000.0           # DSP 中断频率 [Hz]  (Ts = 200us)
        self.f_pwm = 20000.0           # FPGA 电流环 / PWM 频率 [Hz] (50us)

        # ---------- FPGA 电流环 ----------
        self.w_cc = 2.0 * 3.141592653589793 * 400.0   # 电流环带宽 [rad/s]

        # ---------- 全阶 EMF 观测器 ----------
        self.obs_wc = 2.0 * 3.141592653589793 * 250.0   # 观测器带宽 [rad/s]
        self.w_lpf_speed = 1.0 / 3.0e-3  # 速度反馈滤波 [rad/s]

        # ---------- PLL ----------
        self.w_pll = 2.0 * 3.141592653589793 * 30.0   # 自然频率 [rad/s]
        self.zeta = 1.0                # 阻尼比
        self.e_pll_min = 4.0           # PLL 起作用的反电动势门限 [V]
        self.w_max = 2.0 * 3.141592653589793 * 300.0  # 最大电角速度(1.5倍额定)

        # ---------- 速度环 ----------
        self.Kp_w = 2.5                # [A/(rad/s)]
        self.Ki_w = 120.0              # [A/(rad/s)]

        # ---------- 起动时序 ----------
        self.I_align = 15.0            # 预定位电流(峰值) [A]
        self.t_align = 0.35            # 预定位时间 [s]
        self.we_start = 2.0 * 3.141592653589793 * 2.0    # I/f 起始电频率 2Hz
        self.we_switch = 2.0 * 3.141592653589793 * 30.0  # 切换电频率 30Hz (=450rpm)
        self.t_ramp = 0.9              # I/f 升速时间 [s]
        self.I_if = 10.0               # I/f 电流幅值(峰值) [A]
        self.ang_switch = 0.4363       # 允许切换角度差 25deg [rad]
        self.confirm_n = 10            # 连续满足次数
        self.e_min = 10.0              # 反电动势幅值门限 [V]
        self.t_blend = 0.1             # 角度交叉淡入时间 [s]
        self.iq_lim = 25.0             # 速度环输出限幅 [A]

        # ---------- 通信链路 ----------
        self.D_link = 100e-6           # SFP+FPGA 前向延迟 [s]
        self.D_comp = 0e-6             # DSP 侧角度超前补偿（台架标定）[s]

        # ---------- 传感器/逆变器非理想 ----------
        self.i_offset = 0.0            # 电流采样直流偏置 [A]
        self.i_noise = 0.0             # 电流采样噪声 RMS [A]
        self.dead_time = 0.0           # 死区时间 [s]
        self.t_pwm = 1.0 / 20000.0     # PWM 周期

        for k, v in kw.items():
            setattr(self, k, v)
