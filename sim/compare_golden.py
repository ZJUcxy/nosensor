# -*- coding: utf-8 -*-
"""
C 代码与 Python 参考模型一致性比对
====================================
用法：
    python compare_golden.py golden_vectors.csv out_c.csv

golden_vectors.csv: t,ia,ib,va,vb,theta_est,err_deg,emag   （sim 导出）
out_c.csv:          theta_est,w,emag                         （dsp/test 输出）
判据：角度最大偏差 < 1e-4 rad，反电动势幅值相对偏差 < 1e-3。
"""
import sys
import numpy as np


def wrap(x):
    return (x + np.pi) % (2 * np.pi) - np.pi


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    g = np.loadtxt(sys.argv[1], delimiter=",", skiprows=1)
    o = np.loadtxt(sys.argv[2], delimiter=",", skiprows=1)
    n = min(len(g), len(o))
    g, o = g[:n], o[:n]

    dth = wrap(g[:, 5] - o[:, 0])
    dem = np.abs(g[:, 7] - o[:, 2]) / np.maximum(np.abs(g[:, 7]), 1.0)

    print("点数           : %d" % n)
    print("角度最大偏差   : %.3e rad (%.4f deg)" % (np.max(np.abs(dth)), np.rad2deg(np.max(np.abs(dth)))))
    print("角度 RMS 偏差  : %.3e rad" % np.sqrt(np.mean(dth ** 2)))
    print("反电动势相对偏差: %.3e" % np.max(dem))

    ok = (np.max(np.abs(dth)) < 1e-4) and (np.max(dem) < 1e-3)
    print("结论           :", "PASS" if ok else "FAIL")
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main())
