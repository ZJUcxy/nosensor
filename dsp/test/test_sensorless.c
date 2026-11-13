/**
 * @file    test_sensorless.c
 * @brief   观测器离线回放测试（PC / CCS host 均可编译）
 *
 * 用法：
 *   test_sensorless golden_vectors.csv out.csv
 *
 * golden_vectors.csv 列：t,ia,ib,va,vb,theta_est,err_deg,emag
 * 本程序只用前 5 列作为输入，输出 theta_est/err_deg/emag 三列。
 * 与 Python 参考实现的误差应 < 1e-5（float32 累积误差）。
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "sensorless.h"

static void default_params(SlMotorParam *mp, SlCtrlParam *cp)
{
    memset(mp, 0, sizeof(*mp));
    memset(cp, 0, sizeof(*cp));

    mp->p    = 4.0f;
    mp->Rs   = 0.18f;
    mp->Ls   = 1.0e-3f;
    mp->psif = 0.105f;
    mp->Vdc  = 300.0f;

    cp->Ts          = 2.0e-4f;
    cp->obs_wc      = 6.2831853f * 250.0f;
    cp->pll_wn      = 6.2831853f * 30.0f;
    cp->pll_zeta    = 1.0f;
    cp->e_pll_min   = 4.0f;
    cp->w_max       = 6.2831853f * 300.0f;
    cp->w_lpf_speed = 1.0f / 3.0e-3f;
    cp->Kp_w        = 2.5f;
    cp->Ki_w        = 120.0f;
    cp->iq_lim      = 25.0f;
    cp->D_comp      = 0.0f;

    cp->I_align     = 15.0f;
    cp->t_align     = 0.35f;
    cp->we_start    = 6.2831853f * 2.0f;
    cp->we_switch   = 6.2831853f * 30.0f;
    cp->t_ramp      = 0.9f;
    cp->I_if        = 10.0f;
    cp->ang_switch  = 25.0f * 0.0174532925f;
    cp->e_min       = 10.0f;
    cp->t_blend     = 0.1f;
    cp->t_speed_ramp= 1.8f;
}

int main(int argc, char **argv)
{
    FILE *fin, *fout;
    char line[512];
    SlMotorParam mp;
    SlCtrlParam  cp;
    SlObserver   obs;
    float out[4];

    if (argc < 3) {
        printf("usage: %s golden.csv out.csv\n", argv[0]);
        return 1;
    }
    fin = fopen(argv[1], "r");
    if (!fin) { printf("cannot open %s\n", argv[1]); return 2; }
    fout = fopen(argv[2], "w");
    if (!fout) { printf("cannot write %s\n", argv[2]); fclose(fin); return 2; }

    default_params(&mp, &cp);
    sl_obs_init(&obs, &mp, &cp, 0.0f, 0.0f);

    /* 跳过表头 */
    if (!fgets(line, sizeof(line), fin)) { fclose(fin); fclose(fout); return 3; }
    fprintf(fout, "theta_est,w,emag\n");

    while (fgets(line, sizeof(line), fin)) {
        float t, ia, ib, va, vb, th_ref, err_ref, em_ref;
        float v_ab[2], i_ab[2];
        int n = sscanf(line, "%f,%f,%f,%f,%f,%f,%f,%f",
                       &t, &ia, &ib, &va, &vb, &th_ref, &err_ref, &em_ref);
        if (n < 5) continue;

        v_ab[0] = va; v_ab[1] = vb;
        i_ab[0] = ia; i_ab[1] = ib;
        sl_obs_update(&obs, &mp, &cp, v_ab, i_ab, out);

        fprintf(fout, "%.9g,%.9g,%.9g\n",
                (double)out[0], (double)out[1], (double)out[3]);
    }

    fclose(fin);
    fclose(fout);
    printf("done. observer theta=%.6f w=%.3f\n",
           (double)obs.theta, (double)obs.w);
    return 0;
}
