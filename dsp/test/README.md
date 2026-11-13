# DSP 代码骨架说明与一致性测试

## 1. 文件

| 文件 | 说明 |
|---|---|
| `inc/sensorless.h` | 观测器/速度环/状态机的接口与参数结构 |
| `src/sensorless.c` | 实现，与 `sim/sensorless.py` 逐行对应 |
| `inc/sfp_proto.h` | SFP 64 字节帧结构（含静态断言、CRC 接口） |
| `test/test_sensorless.c` | 离线回放 golden 向量的测试程序 |

## 2. 编译（三种方式任选）

### 2.1 CCS / C66x（目标代码）
新建 CCS 工程，加入 `src/sensorless.c`，包含路径 `inc/`；
编译选项建议：`-O2 -mf5 --fp_mode=relaxed -ml0`（float32，避免 double）。
将 `test/test_sensorless.c` 换成 `control_isr.c` 的调用即可（接口见头文件）。

### 2.2 PC（MinGW / MSVC / clang，验证算法一致性）
```bash
gcc -O2 -I../inc ../src/sensorless.c test_sensorless.c -lm -o test_sensorless
./test_sensorless ../../sim/results/golden_vectors.csv out.csv
python ../../sim/compare_golden.py ../../sim/results/golden_vectors.csv out.csv
```
判据：角度最大偏差 < 1e-4 rad，反电动势相对偏差 < 1e-3 → PASS。

### 2.3 MATLAB MEX
```matlab
mex -I../inc ../src/sensorless.c test_sensorless.c
```
（MEX 需先配置 C 编译器；仅用于回放验证，不用于目标代码。）

## 3. 一致性测试原理

`sim/run_simulation.py` 导出 `golden_vectors.csv`，每行是一次 5 kHz 控制周期的
观测器输入（iα、iβ、vα、vβ，均为 200 µs 平均值）与 Python 参考输出。
C 版本逐行回放，输出 `theta_est,w,emag`，由 `compare_golden.py` 比对。

> 注意：golden 向量包含预定位/I/f 段，此时反电动势不可观测，PLL 处于冻结状态；
> 一致性比对关注的是**逐位复现能力**，不是跟踪精度。

## 4. 移植注意事项

1. **全 float32**：C66x 上 double 慢约 10 倍，所有常量带 `f` 后缀；
2. **无动态内存**：所有状态在结构体里，上电显式初始化；
3. **三角函数**：`sinf/cosf` 在 C66x 上约 20~30 周期，可接受；如需更快用 1024 点查表 + 线性插值；
4. **角度 wrap**：统一 `sl_wrap()` 到 [-π, π)，跨周期比较必须走最短路径；
5. **L2 与 Cache**：控制代码/数据段放 L2 SRAM 并关闭该段 cache，保证确定性；
6. **中断**：ISR 入口到出口关中断，关中断窗口 <1 µs；
7. **参数标定**：`D_comp`、`obs_wc`、`pll_wn` 运行时可改，写入时做 CRC 保护。
