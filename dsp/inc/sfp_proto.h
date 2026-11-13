/**
 * @file    sfp_proto.h
 * @brief   SFP 光纤帧结构（DSP <-> FPGA），与 docs/02 §4 一一对应
 * @note    固定 64 字节，1 字节对齐；使用静态断言保证长度。
 *          DSP 侧小端（C66x LE），FPGA 侧需保持相同字节序。
 */
#ifndef SFP_PROTO_H
#define SFP_PROTO_H

#include <stdint.h>

#define SFP_CMD_MAGIC   0xA55Au
#define SFP_FB_MAGIC    0x5AA5u
#define SFP_TAIL        0x5AA5C33Cu
#define SFP_FRAME_LEN   64

#pragma pack(push, 1)

/* DSP -> FPGA : 64 B */
typedef struct {
    uint16_t magic;        /* 0  */
    uint16_t seq;          /* 2  */
    uint8_t  mode;         /* 4  0=封波 1=预定位 2=I/f 3=闭环 4=故障 */
    uint8_t  enable;       /* 5  */
    uint8_t  reset_fault;  /* 6  */
    uint8_t  flags;        /* 7  bit0 制动 bit1 弱磁 bit2 注入 */
    float    id_ref;       /* 8  A 峰值 */
    float    iq_ref;       /* 12 A 峰值 */
    float    theta_cmd;    /* 16 rad，已含 T_comp */
    float    omega_est;    /* 20 rad/s 电角速度（FPGA 外推用） */
    float    i_limit;      /* 24 A */
    float    vdc_limit;    /* 28 V */
    float    t_comp;       /* 32 s 在线微调 */
    uint8_t  reserved[20]; /* 36 */
    uint32_t crc32;        /* 56 覆盖 0..55 */
    uint32_t tail;         /* 60 */
} SfpCmd;

/* FPGA -> DSP : 64 B */
typedef struct {
    uint16_t magic;        /* 0  */
    uint16_t seq;          /* 2  */
    uint16_t status;       /* 4  bit0 电流环就绪 bit1 PWM 运行 bit2 电压受限 */
    uint16_t fault_code;   /* 6  过流/过压/超温/丢帧/硬件 */
    float    i_alpha;      /* 8  A 200us 平均 */
    float    i_beta;       /* 12 A */
    float    v_alpha;      /* 16 V 实际施加电压 200us 平均 */
    float    v_beta;       /* 20 V */
    float    vdc;          /* 24 V */
    float    temp_power;   /* 28 C */
    float    temp_motor;   /* 32 C */
    uint32_t t_stamp;      /* 36 FPGA 200us 计数 */
    float    theta_applied;/* 40 rad 本窗口实际角度（调试） */
    uint8_t  reserved[12]; /* 44 */
    uint32_t crc32;        /* 56 */
    uint32_t tail;         /* 60 */
} SfpFb;

#pragma pack(pop)

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(SfpCmd) == SFP_FRAME_LEN, "SfpCmd must be 64 bytes");
_Static_assert(sizeof(SfpFb)  == SFP_FRAME_LEN, "SfpFb must be 64 bytes");
#endif

/* CRC32（多项式 0xEDB88320，查表法） */
uint32_t sfp_crc32(const void *data, uint32_t len);
/* 帧校验：magic/tail/crc 全部正确返回 1 */
int sfp_check_cmd(const SfpCmd *f);
int sfp_check_fb(const SfpFb *f);

#endif /* SFP_PROTO_H */
