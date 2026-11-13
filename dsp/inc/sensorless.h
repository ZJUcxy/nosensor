/**
 * @file    sensorless.h
 * @brief   无位置传感器控制：观测器 / 速度环 / 起动状态机
 * @note    与 sim/sensorless.py、sim/run_simulation.py 逐行对应。
 *          目标平台 TI C6678（C66x），全部 float32，无动态内存。
 *          角度单位 rad，速度单位 rad/s（电角速度），电流 A（峰值）。
 */
#ifndef SENSORLESS_H
#define SENSORLESS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SL_PI       3.14159265358979f
#define SL_2PI      6.28318530717959f
#define SL_DEG2RAD  0.01745329251994f

/* ------------------------------------------------------------------ */
/* 参数                                                                */
/* ------------------------------------------------------------------ */
typedef struct {
    float p;        /**< 极对数 */
    float Rs;       /**< 定子电阻 Ohm */
    float Ls;       /**< 定子电感 H (SPM: Ld=Lq) */
    float psif;     /**< 永磁磁链 Wb */
    float Vdc;      /**< 母线电压 V */
} SlMotorParam;

typedef struct {
    float Ts;          /**< 控制周期 s (5kHz -> 2e-4) */
    float obs_wc;      /**< 观测器带宽 rad/s (2*pi*250) */
    float pll_wn;      /**< PLL 自然频率 rad/s (2*pi*30) */
    float pll_zeta;    /**< PLL 阻尼 */
    float e_pll_min;   /**< PLL 使能的反电动势门限 V */
    float w_max;       /**< 电角速度限幅 rad/s */
    float w_lpf_speed; /**< 速度反馈滤波 rad/s */
    float Kp_w;        /**< 速度环 P */
    float Ki_w;        /**< 速度环 I */
    float iq_lim;      /**< 速度环输出限幅 A */
    float D_comp;      /**< 角度超前补偿 s（台架标定） */
    /* 起动 */
    float I_align;     /**< 预定位电流 A */
    float t_align;     /**< 预定位时间 s */
    float we_start;    /**< I/f 起始电角速度 rad/s */
    float we_switch;   /**< 切换电角速度 rad/s */
    float t_ramp;      /**< I/f 升速时间 s */
    float I_if;        /**< I/f 电流 A */
    float ang_switch;  /**< 允许切换角度差 rad */
    float e_min;       /**< 切换判据：反电动势门限 V */
    float t_blend;     /**< 角度淡入时间 s */
    float t_speed_ramp;/**< 切换到目标转速的升速时间 s */
    float w_lpf_pll;   /**< 预留 */
} SlCtrlParam;

/* ------------------------------------------------------------------ */
/* 观测器：估计 dq 系扩展反电动势观测器 + PLL                          */
/* ------------------------------------------------------------------ */
typedef struct {
    float i_hat[2];   /**< 估计电流 [id, iq] */
    float e_hat[2];   /**< 估计反电动势 [ed, eq] */
    float theta;      /**< 估计电角度 rad */
    float w;          /**< 估计电角速度 rad/s */
    float int_w;      /**< PLL 积分器 */
    float w_f;        /**< 滤波后电角速度 */
    float emag;       /**< |e| */
    float L1, L2;     /**< 观测器增益 */
    float alpha_w;    /**< 速度滤波系数 */
} SlObserver;

void sl_obs_init(SlObserver *o, const SlMotorParam *mp, const SlCtrlParam *cp,
                 float theta0, float w0);

/**
 * @brief 观测器单步
 * @param v_ab  [v_alpha, v_beta]  实际施加电压（200us 平均值）
 * @param i_ab  [i_alpha, i_beta]  相电流（200us 平均值）
 * @param out   [0]=theta_comp(含补偿) [1]=w [2]=w_f [3]=emag
 */
void sl_obs_update(SlObserver *o, const SlMotorParam *mp, const SlCtrlParam *cp,
                   const float v_ab[2], const float i_ab[2], float out[4]);

/* ------------------------------------------------------------------ */
/* 速度环                                                              */
/* ------------------------------------------------------------------ */
typedef struct {
    float integ;
} SlSpeedPi;

void  sl_pi_init(SlSpeedPi *s, float integ0);
float sl_pi_step(SlSpeedPi *s, const SlCtrlParam *cp, float ref, float fb,
                 float lim, float dt);

/* ------------------------------------------------------------------ */
/* 起动状态机                                                          */
/* ------------------------------------------------------------------ */
typedef enum {
    SL_MODE_INIT    = 0,
    SL_MODE_ALIGN   = 1,
    SL_MODE_IF      = 2,
    SL_MODE_SETTLE  = 3,
    SL_MODE_BLEND   = 4,
    SL_MODE_CLOSED  = 5,
    SL_MODE_FAULT   = 6
} SlMode;

typedef struct {
    SlMode mode;
    float  t;          /**< 状态内计时 */
    float  theta_f;    /**< I/f 强制角 */
    float  we_f;       /**< I/f 频率 */
    float  blend;      /**< 淡入系数 0..1 */
    float  iq_init;    /**< 交接时刻 iq */
    float  w_start;    /**< 交接时刻机械速度 */
    int    cnt;        /**< 切换确认计数 */
    float  t_settle;   /**< SETTLE 开始时间 */
    float  t_tr;       /**< 切换时刻 */
    float  w_ref;      /**< 速度给定（机械 rad/s） */
    uint8_t fault;     /**< 故障码 */
} SlFsm;

typedef struct {
    float id_ref;      /**< 输出 d 轴电流给定 */
    float iq_ref;      /**< 输出 q 轴电流给定 */
    float theta_cmd;   /**< 输出角度（已含 T_comp） */
    float w_cmd;       /**< 输出电角速度（FPGA 外推用） */
} SlCmd;

void sl_fsm_init(SlFsm *f, const SlCtrlParam *cp, float t0);
void sl_fsm_reset(SlFsm *f, const SlCtrlParam *cp);

/**
 * @brief 状态机单步
 * @param dt        控制周期
 * @param theta_est 观测角（未加补偿）
 * @param w_est     观测电角速度
 * @param w_f       滤波后电角速度
 * @param emag      反电动势幅值
 * @param w_ref     目标转速（机械 rad/s）
 * @param cmd       输出
 */
void sl_fsm_step(SlFsm *f, const SlCtrlParam *cp, const SlMotorParam *mp,
                 float dt, float theta_est, float w_est, float w_f,
                 float emag, float w_ref, SlSpeedPi *pi, SlCmd *cmd);

/* 工具 */
static inline float sl_wrap(float x)
{
    while (x >  SL_PI) x -= SL_2PI;
    while (x < -SL_PI) x += SL_2PI;
    return x;
}

#ifdef __cplusplus
}
#endif

#endif /* SENSORLESS_H */
