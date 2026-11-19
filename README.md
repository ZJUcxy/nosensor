# 300V/25A 表贴式 PMSM 无位置传感器控制 —— 方案与仿真验证

本工作区用于**无感算法仿真验证与 DDS 部署**：基于 DSP C6678（5 kHz 控制中断）+ FPGA 三相驱动板（FOC/电流环已实现）+ SFP 光纤链路，实现 300 V / 25 A 表贴式旋转 PMSM 的**起动算法与无位置传感器闭环控制**，路线为"仿真 → 代码一致性 → 台架 → 整机"。

---

## 1. 文档

| 文档 | 内容 |
|---|---|
| [01 无感算法设计方案](docs/01_无感算法设计方案.md) | 观测器选型与推导、PLL、起动状态机、无扰切换、参数辨识、仿真结果、风险 |
| [02 硬件部署与 SFP 接口方案](docs/02_硬件部署与SFP接口方案.md) | DSP/FPGA 职责划分、5 kHz 时序预算、SFP 帧格式、FPGA 改造清单、保护与安全 |
| [03 仿真与板级验证计划](docs/03_仿真与板级验证计划.md) | 四级验证、仿真矩阵、PIL 一致性、台架配置、26 步 demo、验收指标、12 周计划 |

## 2. 目录

```
.
├── docs/                  # 方案与计划（本项目的核心交付）
├── sim/                   # Python 仿真（可直接运行）
│   ├── pmsm_params.py     # 电机/控制/链路参数（示例值，待实测替换）
│   ├── pmsm_model.py      # PMSM + 逆变器 + FPGA 电流环模型
│   ├── sensorless.py      # EEMF 观测器 + PLL + 速度环（与 C 代码逐行对应）
│   ├── run_simulation.py  # S1~S5 场景 + 出图 + 导出 golden vectors
│   ├── compare_golden.py  # C 实现与 Python 模型一致性比对
│   └── results/           # 图、npz、golden_vectors.csv、run.log
├── matlab/                # MATLAB 对标脚本（Simulink 工作流对接）
├── amc1306/               # AMC1306 功能仿真（MATLAB）：sinc3 群延时/建立时间与补偿
│   ├── model_amc1306.m    # ΔΣ调制器+Manchester+sinc3(OSR=256) 链模型
│   ├── analysis_main.m    # 三相稳态/阶跃/补偿方案分析主脚本
│   └── 群延时分析与补偿方案.md
├── fpga/                  # FPGA 电角度外推模块（25kHz 触发 + 5kHz 同步装载）
│   ├── rtl/angle_extrapolator.v
│   ├── tb/tb_angle_extrapolator.v
│   └── README.md
└── dsp/                   # DSP C 代码骨架
    ├── inc/sensorless.h
    ├── src/sensorless.c
    └── test/test_sensorless.c
```

## 3. 快速开始

```bash
# Python 仿真（约 70 s，生成 6 张图与 golden 向量）
cd sim
python run_simulation.py

# MATLAB 对标（需本机 MATLAB）
cd matlab
matlab -batch "sensorless_sim"
```

## 4. 方案要点（一页纸）

- **观测器**：估计 dq 系扩展反电动势观测器（EEMF）+ 归一化 PLL，5 kHz 离散。
  不选传统 SMO：5 kHz、Ls=1 mH 时滑模增益须 >130 V，每拍电流抖振 k·Ts/Ls≈26 A，边界层无法收敛。
  不选 αβ 静止系全阶观测器：反电动势状态随转子旋转，离散极点随速退化，高速失锁（仿真已复现）。
- **起动**：预定位（含 5 Hz 抖动脉冲破 180° 死点）→ I/f 强拖至 30 Hz 电频率（450 rpm）→ 观测器确认 → 角度交叉淡入 + 转矩电流无扰交接 → 闭环。
- **切换判据**：|ê|≥10 V、|θf-θ̂|≤25°、ω̂≥0.8ωf，连续 10 拍；超时则继续升速重试。
- **接口**：DSP 5 kHz 下发 `id*/iq*/θ/ω`，FPGA 回传 `iαβ/vαβ/vdc` 的 200 µs 同步平均值；FPGA 做角度外推、死区补偿、逐周期保护与链路看门狗。
- **速域边界**：SPM 无凸极，零速/极低速不闭环；最低可控转速 10%（450 rpm）。>3750 rpm 需把观测器下移 FPGA 或提高中断频率。

## 5. 仿真结论（当前基线）

| 指标 | 结果 |
|---|---|
| 完整起动 0→3000 rpm | 切换 1.25 s，切换后角度 RMS 5.7°，终值误差 0.00% |
| 1000→2000 rpm 阶跃 | 超调 0.4%，90% 上升 82 ms |
| 参数失配 Rs±30%/Ls±30%/ψf±15% | 角度 RMS 3.6°~5.7° |
| 起动蒙特卡洛（12 初始角 × 2 负载） | 100% |

> 仿真参数为**示例值**（铭牌缺失），必须先按 `docs/01 §7` 完成 Rs/Ls/ψf/J 辨识后替换。

## 6. 下一步（建议顺序）

1. 补齐 S6/S7 仿真（电流偏置/噪声、死区/温漂、母线波动、负载突变、带速重投）；
2. 用实测参数替换 `sim/pmsm_params.py` 与 `dsp/test/test_sensorless.c` 中的默认值；
3. 在 CCS 中编译 `dsp/` 并用 `golden_vectors.csv` 做一致性回放（判据见 `docs/03 §3`）；
4. 按 `docs/02 §8` 完成板级 bring-up，重点是**链路延迟实测**与 **T_comp 标定**；
5. 按 `docs/03 §5` 完成 26 步 demo 与验收。

## 7. 待确认输入

1. 电机铭牌与参数（额定功率/转速/电流/反电势/极对数）；
2. 风机负载曲线（额定点转矩、起动阻转矩）；
3. 最高转速要求；
4. SFP 实测延迟与抖动；
5. 驱动板电流采样方式与 ADC 位数、零偏稳定性；
6. FPGA 固件可改动范围（是否可加 200 µs 电压平均、角度外推、死区补偿）。
