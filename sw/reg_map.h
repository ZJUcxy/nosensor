#ifndef FOC_REG_MAP_H
#define FOC_REG_MAP_H
#include <stdint.h>
#define FOC_ID            0x000u
#define FOC_VERSION       0x004u
#define FOC_CTRL          0x008u
#define FOC_STATUS        0x00Cu
#define FOC_FAULT         0x010u
#define FOC_FAULT_MASK    0x014u
#define FOC_PWM_CFG       0x018u
#define FOC_PWM_PEAK      0x01Cu
#define FOC_DEADTIME_NS   0x020u
#define FOC_ID_REF        0x024u
#define FOC_IQ_REF        0x028u
#define FOC_KP_D          0x02Cu
#define FOC_KI_D          0x030u
#define FOC_KP_Q          0x034u
#define FOC_KI_Q          0x038u
#define FOC_U_MAX         0x03Cu
#define FOC_I_CMD_MAX     0x040u
#define FOC_SCALE_I       0x044u
#define FOC_DATA_INV      0x048u
#define FOC_DEC_PHASE     0x04Cu
#define FOC_OC_TH         0x050u
#define FOC_OC_N          0x054u
#define FOC_PH_TH         0x058u
#define FOC_PH_N          0x05Cu
#define FOC_I_START       0x060u
#define FOC_I_SLEW_N      0x064u
#define FOC_DFDT          0x068u
#define FOC_T_ALIGN       0x06Cu
#define FOC_W_SWITCH      0x070u
#define FOC_THETA_WIN     0x074u
#define FOC_SWITCH_N      0x078u
#define FOC_BLEND_N       0x07Cu
#define FOC_THETA_ABORT   0x080u
#define FOC_STALL_T_IF    0x084u
#define FOC_STALL_T_RUN   0x088u
#define FOC_W_STALL       0x08Cu
#define FOC_I_STALL       0x090u
#define FOC_LINK_TO       0x094u
#define FOC_ANGLE_LEAD    0x098u
#define FOC_VDC_NOM       0x09Cu
#define FOC_I_BASE        0x0A0u
#define FOC_OBS_CFG       0x0B0u
#define FOC_OBS_AGE       0x0B4u
#define FOC_IA            0x0C0u
#define FOC_IB            0x0C4u
#define FOC_IC            0x0C8u
#define FOC_ID_MEAS       0x0D4u
#define FOC_IQ_MEAS       0x0D8u
#define FOC_THETA_PARK    0x0E4u
#define FOC_OMEGA_STEP    0x0ECu
#define FOC_SNAP_SEQ      0x100u
#define FOC_SNAP_UALPHA   0x104u
#define FOC_SNAP_UBETA    0x108u
#define FOC_SNAP_IALPHA   0x10Cu
#define FOC_SNAP_IBETA    0x110u
#define FOC_THETA_IN      0x114u
#define FOC_SPEED_IN      0x118u
#define FOC_SEQ_ECHO      0x11Cu
#define FOC_OBS_COMMIT    0x120u
#define FOC_OBS_DROP_CNT  0x124u
#define FOC_CTRL_ENABLE   (1u << 0)
#define FOC_CTRL_SOFT_RST (1u << 2)
#define FOC_CTRL_FAULT_CLR (1u << 3)
#define FOC_CTRL_DIR      (1u << 4)
#define FOC_STAT_STATE    0x000Fu
#define FOC_STAT_PWM      (1u << 4)
#define FOC_STAT_LINK     (1u << 5)
#define FOC_STAT_PARAM    (1u << 6)
#endif
