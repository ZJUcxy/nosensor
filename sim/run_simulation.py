# -*- coding: utf-8 -*-
"""
无感算法仿真主程序
==================
场景：
  S1  完整起动：预定位 -> I/f 强拖 -> 观测器确认 -> 角度/转矩无缝切换 -> 闭环升速
  S2  闭环转速阶跃响应
  S3  观测器参数失配（Rs / Ls / psi_f）
  S4  链路延迟补偿扫描
  S5  起动蒙特卡洛（初始角 x 负载）

运行：  python run_simulation.py
输出：  sim/results/*.png  +  sim/results/golden_vectors.csv（供 C 代码回放比对）
"""
import os
import copy
import csv
import collections

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

from pmsm_params import MotorParams, CtrlParams
from pmsm_model import PMSM, CurrentLoop, dead_time_distortion
from sensorless import DQObserver, SpeedPI, wrap, estimate_error

TWOPI = 2.0 * np.pi
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "results")
os.makedirs(OUT, exist_ok=True)

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei"]
plt.rcParams["axes.unicode_minus"] = False
plt.rcParams["figure.dpi"] = 130
plt.rcParams["axes.grid"] = True
plt.rcParams["grid.alpha"] = 0.3

MODES = {"ALIGN": 0, "IF": 1, "SETTLE": 2, "BLEND": 3, "CLOSED": 4}
MODE_NAMES = {v: k for k, v in MODES.items()}


# ----------------------------------------------------------------------------
def run_case(mp=None, cp=None, t_end=4.5, theta0=0.0, load_scale=1.0,
             mismatch=None, D_comp=None, vdc=None, start_closed=False,
             w_init=0.0, w_target=None, ramp_time=1.8,
             step_time=None, w_target2=None, seed=0):
    """单次仿真。返回记录字典。"""
    np.random.seed(seed)
    mp = copy.deepcopy(mp) if mp is not None else MotorParams()
    cp = copy.deepcopy(cp) if cp is not None else CtrlParams()
    if vdc is not None:
        mp.Vdc = vdc
    mp.k_load *= load_scale
    d_comp = cp.D_comp if D_comp is None else D_comp
    if w_target is None:
        w_target = mp.wm_rated

    # 观测器内部模型（可注入参数失配）
    mp_obs = copy.deepcopy(mp)
    if mismatch:
        mp_obs.Rs *= mismatch.get("Rs", 1.0)
        mp_obs.Ls *= mismatch.get("Ls", 1.0)
        mp_obs.psif *= mismatch.get("psif", 1.0)

    Ts = 1.0 / cp.f_ctrl
    Ts_pwm = 1.0 / cp.f_pwm
    n_sub = int(round(Ts / Ts_pwm))
    N = int(round(t_end / Ts))
    accel = (cp.we_switch - cp.we_start) / cp.t_ramp

    p = PMSM(mp)
    p.theta = wrap(theta0)
    cl = CurrentLoop(mp, cp)
    smo = DQObserver(mp_obs, cp)
    sp = SpeedPI(cp)

    # 记录
    rec = {k: np.zeros(N) for k in (
        "t", "wm", "wref", "west", "th_err", "iq", "id", "iq_ref", "id_ref",
        "emag", "th_f", "ia", "ib", "va", "vb", "theta_true", "theta_est")}
    rec["mode"] = np.zeros(N, dtype=int)

    cmds = collections.deque()
    last = {"t": 0.0, "theta": wrap(theta0), "w": 0.0, "id": 0.0, "iq": 0.0}
    acc_i = np.zeros(2)
    acc_v = np.zeros(2)
    acc_n = 0

    if start_closed:
        mode = "CLOSED"
        p.wm = w_init                    # w_init 为机械角速度
        theta0 = wrap(theta0)
        p.theta = theta0
        smo.reset(theta0, w_init * mp.p)  # 观测器内部为电角速度
        iq0 = (mp.k_load * p.wm ** 2 + mp.T_c) / mp.kt
        sp.reset(iq0)
        th_est, w_est, w_f, emag = theta0, w_init * mp.p, w_init * mp.p, 0.0
        last.update(theta=wrap(theta0 + w_init * mp.p * d_comp), w=w_init * mp.p,
                    id=0.0, iq=float(np.clip(iq0, -cp.iq_lim, cp.iq_lim)))
        w_ref = w_init
        theta_base = th_est
        w_cmd = w_est
        id_ref, iq_ref = 0.0, last["iq"]
        theta_f, we_f = 0.0, 0.0
        blend, cnt, t_tr, iq_init, w_start = 0.0, 0, 0.0, 0.0, w_init
    else:
        mode = "ALIGN"
        th_est, w_est, w_f, emag = wrap(theta0), 0.0, 0.0, 0.0
        w_ref = 0.0
        theta_base, w_cmd = 0.0, 0.0
        id_ref, iq_ref = 0.0, 0.0
        theta_f, we_f = 0.0, cp.we_start
        blend, cnt, t_tr, iq_init, w_start = 0.0, 0, 0.0, 0.0, 0.0

    for n in range(N):
        t = n * Ts

        # ---------------- 5kHz 控制周期 ----------------
        if n > 0 and acc_n > 0:
            i_fb = acc_i / acc_n
            v_fb = acc_v / acc_n
            th_est, w_est, w_f, emag = smo.update(v_fb, i_fb)

            if mode == "ALIGN":
                id_ref = cp.I_align * min(1.0, t / 0.15)
                # 抖动脉冲：打破 180deg 不稳定平衡，保证任意初始角都能定位
                iq_ref = 2.0 * np.sin(TWOPI * 5.0 * t) if t < 0.20 else 0.0
                theta_base = 0.0
                w_cmd = 0.0
                if t >= cp.t_align:
                    mode = "IF"
                    theta_f = 0.0
                    we_f = cp.we_start

            elif mode == "IF":
                we_f = min(we_f + Ts * accel, cp.we_switch)
                theta_f = wrap(theta_f + Ts * we_f)
                id_ref, iq_ref = cp.I_if, 0.0
                theta_base, w_cmd = theta_f, we_f
                if we_f >= cp.we_switch - 1e-9:
                    mode = "SETTLE"
                    cnt = 0
                    t_settle = t

            elif mode == "SETTLE":
                theta_f = wrap(theta_f + Ts * we_f)
                id_ref, iq_ref = cp.I_if, 0.0
                theta_base, w_cmd = theta_f, we_f
                ang = abs(wrap(theta_f - th_est))
                ok = (emag > cp.e_min) and (ang < cp.ang_switch) and (w_est > 0.8 * we_f)
                cnt = (cnt + 1) if ok else 0
                if cnt >= cp.confirm_n or (t - t_settle) > 0.8:
                    mode = "BLEND"
                    blend = 0.0
                    d0 = wrap(theta_f - th_est)
                    iq_init = cp.I_if * np.sin(d0)
                    w_start = max(w_f / mp.p, 0.0)
                    sp.reset(iq_init)
                    t_tr = t

            elif mode == "BLEND":
                theta_f = wrap(theta_f + Ts * we_f)
                blend = min(blend + Ts / cp.t_blend, 1.0)
                d = wrap(theta_f - th_est)
                theta_base = wrap(th_est + (1.0 - blend) * d)
                w_cmd = w_est
                id_ref = 0.0
                iq_ref = sp.step(w_start, w_f / mp.p, cp.iq_lim, Ts)
                if blend >= 1.0:
                    mode = "CLOSED"

            elif mode == "CLOSED":
                if step_time is not None and t >= step_time:
                    w_ref = w_target2
                elif start_closed:
                    w_ref = min(w_init + (w_target - w_init)
                                * min(1.0, t / ramp_time), w_target)
                else:
                    w_ref = min(w_start + (w_target - w_start)
                                * min(1.0, (t - t_tr) / ramp_time), w_target)
                iq_ref = sp.step(w_ref, w_f / mp.p, cp.iq_lim, Ts)
                id_ref = 0.0
                theta_base, w_cmd = th_est, w_est

            theta_sent = wrap(theta_base + w_cmd * d_comp)
            cmds.append((t + cp.D_link, theta_sent, w_cmd, id_ref, iq_ref))

        # ---------------- 记录（当前时刻真实值与估计值） ----------------
        idq = p.idq_rotor()
        rec["t"][n] = t
        rec["wm"][n] = p.wm
        rec["wref"][n] = w_ref
        rec["west"][n] = w_f / mp.p
        rec["th_err"][n] = estimate_error(th_est, p.theta)
        rec["iq"][n], rec["id"][n] = idq[1], idq[0]
        rec["iq_ref"][n], rec["id_ref"][n] = iq_ref, id_ref
        rec["emag"][n] = emag
        rec["th_f"][n] = theta_f
        rec["theta_true"][n] = p.theta
        rec["theta_est"][n] = th_est
        rec["mode"][n] = MODES[mode]
        if acc_n > 0:
            rec["ia"][n], rec["ib"][n] = acc_i[0] / acc_n, acc_i[1] / acc_n
            rec["va"][n], rec["vb"][n] = acc_v[0] / acc_n, acc_v[1] / acc_n

        # ---------------- 20kHz 子步：FPGA 电流环 + 电机 ----------------
        acc_i[:] = 0.0
        acc_v[:] = 0.0
        acc_n = 0
        for k in range(n_sub):
            tk = t + k * Ts_pwm
            while cmds and cmds[0][0] <= tk:
                _, th, w, idr, iqr = cmds.popleft()
                last.update(t=tk, theta=th, w=w, id=idr, iq=iqr)
            th_fpga = last["theta"] + last["w"] * (tk - last["t"])
            vab = cl.step(p.ia, p.ib, last["id"], last["iq"], th_fpga, last["w"], Ts_pwm)
            vab = dead_time_distortion(vab, (p.ia, p.ib), mp, cp)
            p.step(vab, Ts_pwm)
            meas = np.array([p.ia, p.ib]) + cp.i_offset
            if cp.i_noise > 0.0:
                meas = meas + cp.i_noise * np.random.randn(2)
            acc_i += meas
            acc_v += vab
            acc_n += 1

    rec["t_tr"] = t_tr
    rec["mode_final"] = mode
    rec["mp"] = mp
    return rec


# ----------------------------------------------------------------------------
def metrics(rec, t_from=None):
    t = rec["t"]
    t_tr = rec["t_tr"]
    m = {}
    i0 = int(np.searchsorted(t, (t_tr + 0.25) if t_from is None else t_from))
    err = rec["th_err"][i0:]
    m["ang_rms"] = float(np.sqrt(np.mean(err ** 2)))
    m["ang_max"] = float(np.max(np.abs(err)))
    m["spd_rpm"] = float(rec["wm"][-1] * 60 / TWOPI)
    m["spd_ref_rpm"] = float(rec["wref"][-1] * 60 / TWOPI)
    m["spd_err_pct"] = 100.0 * (m["spd_rpm"] - m["spd_ref_rpm"]) / max(m["spd_ref_rpm"], 1e-9)
    m["tr_ms"] = 1000.0 * (t_tr - 0.35)
    return m


def save(rec, name):
    np.savez(os.path.join(OUT, name + ".npz"), **{k: v for k, v in rec.items()
                                                  if isinstance(v, np.ndarray)})


# ----------------------------------------------------------------------------
def plot_main(rec, fname="S1_startup.png"):
    t = rec["t"]
    rpm = 60 / TWOPI
    fig, ax = plt.subplots(2, 2, figsize=(13, 8))
    fig.suptitle("S1  预定位 -> I/f 强拖 -> 观测器切换 -> 闭环升速", fontsize=13)

    a = ax[0, 0]
    a.plot(t, rec["wm"] * rpm, "b", lw=1.6, label="实际转速")
    a.plot(t, rec["wref"] * rpm, "k--", lw=1.2, label="转速给定")
    a.plot(t, rec["west"] * rpm, "r", lw=1.0, alpha=0.8, label="观测转速")
    a.axvline(rec["t_tr"], color="g", ls=":", label="切换时刻")
    a.set_ylabel("转速 [rpm]"); a.legend(loc="lower right", fontsize=8); a.set_xlabel("t [s]")

    a = ax[0, 1]
    a.plot(t, rec["th_err"], "b", lw=0.9, label="角度误差")
    a.set_ylabel("角度误差 [deg]"); a.set_xlabel("t [s]"); a.set_ylim(-60, 60)
    a2 = a.twinx()
    a2.plot(t, rec["emag"], "orange", lw=0.9, alpha=0.7, label="反电动势幅值")
    a2.set_ylabel("|e| [V]")
    a.axvline(rec["t_tr"], color="g", ls=":")
    h1, l1 = a.get_legend_handles_labels(); h2, l2 = a2.get_legend_handles_labels()
    a.legend(h1 + h2, l1 + l2, loc="upper left", fontsize=8)

    a = ax[1, 0]
    a.plot(t, rec["iq"], "b", lw=1.0, label="iq 实际")
    a.plot(t, rec["iq_ref"], "r--", lw=1.0, label="iq 给定")
    a.plot(t, rec["id"], "g", lw=1.0, label="id 实际")
    a.axvline(rec["t_tr"], color="g", ls=":")
    a.set_ylabel("电流 [A]"); a.set_xlabel("t [s]"); a.legend(fontsize=8)

    a = ax[1, 1]
    a.step(t, rec["mode"], where="post", color="purple")
    a.set_yticks([0, 1, 2, 3, 4])
    a.set_yticklabels([MODE_NAMES[i] for i in range(5)], fontsize=8)
    a.set_xlabel("t [s]"); a.set_title("运行状态机", fontsize=10)

    fig.tight_layout(rect=(0, 0, 1, 0.96))
    fig.savefig(os.path.join(OUT, fname), bbox_inches="tight")
    plt.close(fig)


def plot_zoom(rec, fname="S1_transition_zoom.png"):
    t = rec["t"]
    t_tr = rec["t_tr"]
    m = (t > t_tr - 0.6) & (t < t_tr + 0.5)
    fig, ax = plt.subplots(3, 1, figsize=(11, 8), sharex=True)
    fig.suptitle("切换过程放大：角度、转矩电流与转速的连续性", fontsize=12)

    ax[0].plot(t[m], rec["th_err"][m], "b", lw=1.2)
    ax[0].plot(t[m], np.rad2deg(wrap(rec["th_f"][m] - rec["theta_true"][m])), "g--",
               lw=1.0, label="I/f 强制角 - 真实角")
    ax[0].set_ylabel("角度误差 [deg]"); ax[0].legend(fontsize=8)
    ax[0].axvline(t_tr, color="g", ls=":")

    ax[1].plot(t[m], rec["iq"][m], "b", lw=1.3, label="iq 实际")
    ax[1].plot(t[m], rec["iq_ref"][m], "r--", lw=1.2, label="iq 给定")
    ax[1].plot(t[m], rec["id"][m], "g", lw=1.0, label="id 实际")
    ax[1].set_ylabel("电流 [A]"); ax[1].legend(fontsize=8); ax[1].axvline(t_tr, color="g", ls=":")

    ax[2].plot(t[m], rec["wm"][m] * 60 / TWOPI, "b", lw=1.4, label="实际转速")
    ax[2].plot(t[m], rec["west"][m] * 60 / TWOPI, "r", lw=1.0, label="观测转速")
    ax[2].plot(t[m], rec["wref"][m] * 60 / TWOPI, "k--", lw=1.0, label="给定")
    ax[2].set_ylabel("转速 [rpm]"); ax[2].set_xlabel("t [s]"); ax[2].legend(fontsize=8)
    ax[2].axvline(t_tr, color="g", ls=":")

    fig.tight_layout(rect=(0, 0, 1, 0.95))
    fig.savefig(os.path.join(OUT, fname), bbox_inches="tight")
    plt.close(fig)


def export_golden(rec, fname="golden_vectors.csv"):
    """导出观测器输入/输出，供 dsp/test 回放比对"""
    path = os.path.join(OUT, fname)
    cols = ["t", "ia", "ib", "va", "vb", "theta_est", "th_err", "emag"]
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["t", "i_alpha", "i_beta", "v_alpha", "v_beta",
                    "theta_est", "err_deg", "emag"])
        for i in range(len(rec["t"])):
            w.writerow(["%.9g" % rec[c][i] for c in cols])
    return path


# ----------------------------------------------------------------------------
def main():
    mp = MotorParams()
    cp = CtrlParams()

    # ---------- S1 完整起动 ----------
    print("[S1] 完整起动 ...")
    rec = run_case(mp, cp, t_end=4.5, w_target=mp.wm_rated)
    m = metrics(rec)
    print("     切换时刻 t=%.3fs (I/f 升速 %.0fms), 切换后角度 RMS=%.2fdeg, "
          "最大=%.2fdeg, 终值 %.1f/%.1frpm (%.2f%%)"
          % (rec["t_tr"], m["tr_ms"], m["ang_rms"], m["ang_max"],
             m["spd_rpm"], m["spd_ref_rpm"], m["spd_err_pct"]))
    plot_main(rec)
    plot_zoom(rec)
    save(rec, "S1")
    print("     golden:", export_golden(rec))

    # ---------- S2 转速阶跃 ----------
    print("[S2] 转速阶跃 1000->2000rpm ...")
    rec2 = run_case(mp, cp, t_end=2.4, start_closed=True, w_init=1000 / 60 * TWOPI,
                    w_target=1000 / 60 * TWOPI, step_time=1.0,
                    w_target2=2000 / 60 * TWOPI)
    t = rec2["t"]; rpm = 60 / TWOPI
    i_step = np.searchsorted(t, 1.0)
    seg = rec2["wm"][i_step:]
    # 阶跃响应指标
    w0 = rec2["wm"][i_step - 1] * rpm
    wss = 2000.0
    peak = seg.max() * rpm
    t90 = t[i_step + int(np.argmax(seg * rpm >= w0 + 0.9 * (wss - w0)))]
    fig, ax = plt.subplots(2, 1, figsize=(10, 6), sharex=True)
    ax[0].plot(t, rec2["wm"] * rpm, "b", label="实际转速")
    ax[0].plot(t, rec2["wref"] * rpm, "k--", lw=1.0, label="给定")
    ax[0].set_ylabel("转速 [rpm]"); ax[0].legend()
    ax[0].set_title("S2  转速阶跃响应（闭环无感）", fontsize=12)
    ax[1].plot(t, rec2["th_err"], "b", lw=0.9)
    ax[1].set_ylabel("角度误差 [deg]"); ax[1].set_xlabel("t [s]")
    fig.tight_layout(); fig.savefig(os.path.join(OUT, "S2_speed_step.png"), bbox_inches="tight")
    plt.close(fig)
    print("     峰值 %.1frpm (超调 %.1f%%), 90%%上升时间 %.0fms, 稳态误差 %.2f%%"
          % (peak, 100 * (peak - wss) / (wss - w0), 1000 * (t90 - 1.0),
             100 * (rec2["wm"][-1] * rpm - wss) / wss))

    # ---------- S3 参数失配 ----------
    print("[S3] 观测器参数失配扫描 (1500rpm) ...")
    cases = [(1.0, 1.0, 1.0), (1.3, 1.0, 1.0), (0.7, 1.0, 1.0),
             (1.0, 1.3, 1.0), (1.0, 0.7, 1.0), (1.0, 1.0, 1.15), (1.0, 1.0, 0.85),
             (1.3, 1.3, 1.15), (0.7, 0.7, 0.85)]
    labels, errs, spd_err = [], [], []
    for (kr, kl, kp) in cases:
        r = run_case(mp, cp, t_end=1.6, start_closed=True,
                     w_init=1500 / 60 * TWOPI, w_target=1500 / 60 * TWOPI,
                     mismatch={"Rs": kr, "Ls": kl, "psif": kp})
        mm = metrics(r, t_from=1.0)
        labels.append("Rs%.0f%% Ls%.0f%% psi%.0f%%" % (100 * (kr - 1), 100 * (kl - 1), 100 * (kp - 1)))
        errs.append(mm["ang_rms"]); spd_err.append(mm["spd_err_pct"])
    fig, ax = plt.subplots(figsize=(9, 4.5))
    ax.bar(range(len(labels)), errs, color="steelblue")
    ax.set_xticks(range(len(labels)))
    ax.set_xticklabels(labels, rotation=30, ha="right", fontsize=8)
    ax.set_ylabel("切换后角度误差 RMS [deg]")
    ax.set_title("S3  观测器参数失配敏感性（1500rpm）", fontsize=12)
    fig.tight_layout(); fig.savefig(os.path.join(OUT, "S3_mismatch.png"), bbox_inches="tight")
    plt.close(fig)
    print("     " + ", ".join("%s:%.1f" % (l, e) for l, e in zip(labels, errs)))

    # ---------- S4 延迟补偿扫描 ----------
    print("[S4] 角度超前补偿扫描 (3000rpm) ...")
    ds = np.array([0, 50, 100, 150, 200, 250, 300, 350, 400, 500]) * 1e-6
    res = []
    for d in ds:
        r = run_case(mp, cp, t_end=1.4, start_closed=True, w_init=3000 / 60 * TWOPI,
                     w_target=3000 / 60 * TWOPI, D_comp=float(d), load_scale=0.6)
        res.append(float(np.mean(np.abs(r["id"][-1000:]))))
    fig, ax = plt.subplots(figsize=(8, 4.5))
    ax.plot(ds * 1e6, res, "o-", color="darkorange")
    ax.set_xlabel("角度超前补偿 D_comp [us]")
    ax.set_ylabel("d 轴电流 |id| 均值 [A]（= 角度失配）")
    ax.set_title("S4  角度超前补偿标定（3000rpm，id 最小即最优）", fontsize=12)
    ax.legend(["|id| 均值"])
    fig.tight_layout(); fig.savefig(os.path.join(OUT, "S4_delay_comp.png"), bbox_inches="tight")
    plt.close(fig)
    print("     最优 D_comp = %.0fus, 残余 |id| = %.2fA"
          % (ds[int(np.argmin(res))] * 1e6, min(res)))

    # ---------- S5 起动蒙特卡洛 ----------
    print("[S5] 起动蒙特卡洛 ...")
    thetas = np.arange(0, 360, 30)
    loads = [0.2, 1.0]
    succ = np.zeros((len(loads), len(thetas)))
    for i, ls in enumerate(loads):
        for j, th0 in enumerate(thetas):
            r = run_case(mp, cp, t_end=2.6, theta0=np.deg2rad(th0),
                         load_scale=ls, w_target=800 / 60 * TWOPI)
            mm = metrics(r, t_from=2.2)
            ok = (abs(mm["ang_rms"]) < 20) and (abs(mm["spd_err_pct"]) < 3.0) \
                 and (r["mode_final"] == "CLOSED")
            succ[i, j] = 1.0 if ok else 0.0
    fig, ax = plt.subplots(figsize=(9, 3.2))
    im = ax.imshow(succ, cmap="RdYlGn", vmin=0, vmax=1, aspect="auto")
    ax.set_xticks(range(len(thetas))); ax.set_xticklabels(thetas)
    ax.set_yticks(range(len(loads))); ax.set_yticklabels(["20% 负载", "100% 负载"])
    ax.set_xlabel("初始转子位置 [deg]")
    ax.set_title("S5  起动成功率（1=成功）  总成功率 %.0f%%"
                 % (100 * succ.mean()), fontsize=12)
    for i in range(len(loads)):
        for j in range(len(thetas)):
            ax.text(j, i, "O" if succ[i, j] else "X", ha="center", va="center", fontsize=9)
    fig.tight_layout(); fig.savefig(os.path.join(OUT, "S5_startup_mc.png"), bbox_inches="tight")
    plt.close(fig)
    print("     成功率 %.0f%%" % (100 * succ.mean()))

    print("\n全部结果输出目录:", OUT)


if __name__ == "__main__":
    main()
