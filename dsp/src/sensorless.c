/**
 * @file    sensorless.c
 * @brief   无位置传感器观测器、速度环、起动状态机实现
 * @note    与 sim/sensorless.py 逐行对应；可用 dsp/test 回放 golden_vectors.csv 验证一致性。
 */
#include "sensorless.h"
#include <math.h>

#define SL_TWOPI  6.28318530717959f

/* ================================================================== */
/* 观测器                                                              */
/* ================================================================== */
void sl_obs_init(SlObserver *o, const SlMotorParam *mp, const SlCtrlParam *cp,
                 float theta0, float w0)
{
    float wo = cp->obs_wc;

    o->L1 = 2.0f * wo - mp->Rs / mp->Ls;
    o->L2 = -mp->Ls * wo * wo;
    o->i_hat[0] = 0.0f; o->i_hat[1] = 0.0f;
    o->e_hat[0] = 0.0f; o->e_hat[1] = 0.0f;
    o->theta   = sl_wrap(theta0);
    o->w       = w0;
    o->int_w   = w0;
    o->w_f     = w0;
    o->emag    = 0.0f;
    o->alpha_w = 1.0f - expf(-cp->w_lpf_speed * cp->Ts);
}

void sl_obs_update(SlObserver *o, const SlMotorParam *mp, const SlCtrlParam *cp,
                   const float v_ab[2], const float i_ab[2], float out[4])
{
    const float Ts = cp->Ts;
    float c = cosf(o->theta);
    float s = sinf(o->theta);
    float id_m =  c * i_ab[0] + s * i_ab[1];
    float iq_m = -s * i_ab[0] + c * i_ab[1];
    float vd   =  c * v_ab[0] + s * v_ab[1];
    float vq   = -s * v_ab[0] + c * v_ab[1];
    float idh = o->i_hat[0], iqh = o->i_hat[1];
    float edh = o->e_hat[0], eqh = o->e_hat[1];
    float did, diq, ed, eq, emag, eps;

    /* 电流观测器（dq 系，含旋转耦合项） */
    did = (vd - mp->Rs * idh + o->w * mp->Ls * iqh - edh) / mp->Ls;
    diq = (vq - mp->Rs * iqh - o->w * mp->Ls * idh - eqh) / mp->Ls;
    ed  = id_m - idh;
    eq  = iq_m - iqh;
    did += o->L1 * ed;
    diq += o->L1 * eq;
    o->i_hat[0] = idh + Ts * did;
    o->i_hat[1] = iqh + Ts * diq;

    /* 反电动势观测器：dq 系下为直流量，L2 为负 */
    o->e_hat[0] = edh + Ts * o->L2 * ed;
    o->e_hat[1] = eqh + Ts * o->L2 * eq;

    /* 归一化 PLL：ed 反映角度误差 */
    emag = sqrtf(o->e_hat[0] * o->e_hat[0] + o->e_hat[1] * o->e_hat[1]);
    o->emag = emag;
    if (emag > cp->e_pll_min) {
        eps = -o->e_hat[0] / (emag + 1e-9f);
    } else {
        eps = 0.0f;
        o->int_w *= 0.999f;          /* 不可观测区：缓慢复位频率积分 */
    }
    o->int_w += Ts * (cp->pll_wn * cp->pll_wn) * eps;
    if (o->int_w >  cp->w_max) o->int_w =  cp->w_max;
    if (o->int_w < -cp->w_max) o->int_w = -cp->w_max;

    o->w = 2.0f * cp->pll_zeta * cp->pll_wn * eps + o->int_w;
    if (o->w >  cp->w_max) o->w =  cp->w_max;
    if (o->w < -cp->w_max) o->w = -cp->w_max;

    o->theta = sl_wrap(o->theta + Ts * o->w);

    /* 速度反馈低通 */
    o->w_f += o->alpha_w * (o->w - o->w_f);

    out[0] = o->theta;   /* 角度补偿在状态机输出端统一加，便于标定 */
    out[1] = o->w;
    out[2] = o->w_f;
    out[3] = emag;
}

/* ================================================================== */
/* 速度环                                                              */
/* ================================================================== */
void sl_pi_init(SlSpeedPi *s, float integ0)
{
    s->integ = integ0;
}

float sl_pi_step(SlSpeedPi *s, const SlCtrlParam *cp, float ref, float fb,
                 float lim, float dt)
{
    float e = ref - fb;
    float u = cp->Kp_w * e + s->integ;
    float u_sat = u;

    if (u_sat >  lim) u_sat =  lim;
    if (u_sat < -lim) u_sat = -lim;

    /* 条件积分抗饱和 */
    if ((u_sat == u) || (u > lim && e < 0.0f) || (u < -lim && e > 0.0f)) {
        s->integ += dt * cp->Ki_w * e;
    }
    return u_sat;
}

/* ================================================================== */
/* 起动状态机                                                          */
/* ================================================================== */
void sl_fsm_init(SlFsm *f, const SlCtrlParam *cp, float t0)
{
    f->mode     = SL_MODE_ALIGN;
    f->t        = t0;
    f->theta_f  = 0.0f;
    f->we_f     = cp->we_start;
    f->blend    = 0.0f;
    f->iq_init  = 0.0f;
    f->w_start  = 0.0f;
    f->cnt      = 0;
    f->t_settle = 0.0f;
    f->t_tr     = 0.0f;
    f->w_ref    = 0.0f;
    f->fault    = 0u;
}

void sl_fsm_reset(SlFsm *f, const SlCtrlParam *cp)
{
    sl_fsm_init(f, cp, 0.0f);
}

void sl_fsm_step(SlFsm *f, const SlCtrlParam *cp, const SlMotorParam *mp,
                 float dt, float theta_est, float w_est, float w_f,
                 float emag, float w_ref_target, SlSpeedPi *pi, SlCmd *cmd)
{
    float accel = (cp->we_switch - cp->we_start) / cp->t_ramp;

    f->t += dt;

    cmd->id_ref    = 0.0f;
    cmd->iq_ref    = 0.0f;
    cmd->theta_cmd = 0.0f;
    cmd->w_cmd     = 0.0f;

    switch (f->mode) {

    case SL_MODE_ALIGN:
        cmd->id_ref = cp->I_align * (f->t < 0.15f ? (f->t / 0.15f) : 1.0f);
        /* 抖动脉冲：破除 180deg 不稳定平衡 */
        cmd->iq_ref = (f->t < 0.20f) ? 2.0f * sinf(SL_TWOPI * 5.0f * f->t) : 0.0f;
        cmd->theta_cmd = 0.0f;
        cmd->w_cmd = 0.0f;
        if (f->t >= cp->t_align) {
            f->mode    = SL_MODE_IF;
            f->theta_f = 0.0f;
            f->we_f    = cp->we_start;
        }
        break;

    case SL_MODE_IF:
        f->we_f += dt * accel;
        if (f->we_f > cp->we_switch) f->we_f = cp->we_switch;
        f->theta_f = sl_wrap(f->theta_f + dt * f->we_f);
        cmd->id_ref = cp->I_if;
        cmd->iq_ref = 0.0f;
        cmd->theta_cmd = f->theta_f;
        cmd->w_cmd = f->we_f;
        if (f->we_f >= cp->we_switch - 1e-6f) {
            f->mode = SL_MODE_SETTLE;
            f->cnt = 0;
            f->t_settle = f->t;
        }
        break;

    case SL_MODE_SETTLE: {
        float ang;
        int ok;
        f->theta_f = sl_wrap(f->theta_f + dt * f->we_f);
        cmd->id_ref = cp->I_if;
        cmd->iq_ref = 0.0f;
        cmd->theta_cmd = f->theta_f;
        cmd->w_cmd = f->we_f;

        ang = sl_wrap(f->theta_f - theta_est);
        if (ang < 0.0f) ang = -ang;
        ok = (emag > cp->e_min) &&
             (ang < cp->ang_switch) &&
             (w_est > 0.8f * f->we_f);
        f->cnt = ok ? (f->cnt + 1) : 0;

        if (f->cnt >= 10 || (f->t - f->t_settle) > 0.8f) {
            float d0 = sl_wrap(f->theta_f - theta_est);
            f->mode    = SL_MODE_BLEND;
            f->blend   = 0.0f;
            f->iq_init = cp->I_if * sinf(d0);
            f->w_start = (w_f / mp->p > 0.0f) ? (w_f / mp->p) : 0.0f;
            f->t_tr    = f->t;
            sl_pi_init(pi, f->iq_init);
        }
        break;
    }

    case SL_MODE_BLEND: {
        float d;
        f->theta_f = sl_wrap(f->theta_f + dt * f->we_f);
        f->blend += dt / cp->t_blend;
        if (f->blend > 1.0f) f->blend = 1.0f;
        d = sl_wrap(f->theta_f - theta_est);
        cmd->theta_cmd = sl_wrap(theta_est + (1.0f - f->blend) * d);
        cmd->w_cmd = w_est;
        cmd->iq_ref = sl_pi_step(pi, cp, f->w_start, w_f / mp->p, cp->iq_lim, dt);
        cmd->id_ref = 0.0f;
        if (f->blend >= 1.0f) {
            f->mode = SL_MODE_CLOSED;
        }
        break;
    }

    case SL_MODE_CLOSED: {
        float span = w_ref_target - f->w_start;
        float k = (cp->t_speed_ramp > 0.0f) ? (f->t - f->t_tr) / cp->t_speed_ramp : 1.0f;
        if (k > 1.0f) k = 1.0f;
        f->w_ref = f->w_start + span * k;
        cmd->iq_ref = sl_pi_step(pi, cp, f->w_ref, w_f / mp->p, cp->iq_lim, dt);
        cmd->id_ref = 0.0f;
        cmd->theta_cmd = theta_est;
        cmd->w_cmd = w_est;
        break;
    }

    case SL_MODE_FAULT:
    default:
        cmd->id_ref = 0.0f;
        cmd->iq_ref = 0.0f;
        cmd->theta_cmd = 0.0f;
        cmd->w_cmd = 0.0f;
        break;
    }

    /* 角度超前补偿（统一在输出端加，便于在线标定） */
    cmd->theta_cmd = sl_wrap(cmd->theta_cmd + cmd->w_cmd * cp->D_comp);
}
