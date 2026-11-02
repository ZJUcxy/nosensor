#include <stdint.h>
#include "xil_io.h"
#include "xil_printf.h"
#include "../reg_map.h"

#ifndef FOC_BASE
#define FOC_BASE 0x44A00000u
#endif
#ifndef UART_BASE
#define UART_BASE 0x40600000u
#endif

static uint32_t rd(uint32_t off) { return Xil_In32(FOC_BASE + off); }
static void wr(uint32_t off, uint32_t v) { Xil_Out32(FOC_BASE + off, v); }

static int uart_get(void) {
    if (Xil_In32(UART_BASE + 0x08) & 0x01u)
        return (int)(Xil_In32(UART_BASE + 0x00) & 0xFFu);
    return -1;
}

static uint32_t parse_hex(const char *s, int *ok) {
    uint32_t v = 0;
    int n = 0;
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) s += 2;
    while (*s) {
        char c = *s++;
        uint32_t d;
        if (c >= '0' && c <= '9') d = (uint32_t)(c - '0');
        else if (c >= 'a' && c <= 'f') d = (uint32_t)(c - 'a' + 10);
        else if (c >= 'A' && c <= 'F') d = (uint32_t)(c - 'A' + 10);
        else break;
        v = (v << 4) | d;
        n++;
    }
    *ok = n > 0;
    return v;
}

static void do_start(void) {
    uint32_t fault = rd(FOC_FAULT);
    uint32_t st = rd(FOC_STATUS);
    if (fault != 0) { xil_printf("reject fault %08x\r\n", fault); return; }
    if ((st & FOC_STAT_PARAM) == 0) { xil_printf("reject param_ok=0\r\n"); return; }
    wr(FOC_CTRL, rd(FOC_CTRL) | FOC_CTRL_ENABLE);
    xil_printf("start\r\n");
}

static void do_dump(void) {
    xil_printf("STATUS %08x FAULT %08x\r\n", rd(FOC_STATUS), rd(FOC_FAULT));
    xil_printf("IA %08x IB %08x IC %08x\r\n", rd(FOC_IA), rd(FOC_IB), rd(FOC_IC));
    xil_printf("ID %08x IQ %08x TH %08x W %08x\r\n",
               rd(FOC_ID_MEAS), rd(FOC_IQ_MEAS), rd(FOC_THETA_PARK), rd(FOC_OMEGA_STEP));
    xil_printf("AGE %08x SEQ %08x\r\n", rd(FOC_OBS_AGE), rd(FOC_SNAP_SEQ));
}

static int starts(const char *s, const char *p) {
    while (*p) {
        if (*s++ != *p++) return 0;
    }
    return 1;
}

static void handle(char *line) {
    int ok = 0;
    if (starts(line, "r ")) {
        uint32_t a = parse_hex(line + 2, &ok);
        if (ok) xil_printf("%08x\r\n", rd(a));
    } else if (starts(line, "w ")) {
        char *sp = line + 2;
        while (*sp && *sp != ' ') sp++;
        if (*sp == ' ') {
            *sp = 0;
            uint32_t a = parse_hex(line + 2, &ok);
            int ok2 = 0;
            uint32_t d = parse_hex(sp + 1, &ok2);
            if (ok && ok2) wr(a, d);
        }
    } else if (starts(line, "start")) do_start();
    else if (starts(line, "stop")) {
        wr(FOC_CTRL, rd(FOC_CTRL) & ~FOC_CTRL_ENABLE);
        xil_printf("stop\r\n");
    } else if (starts(line, "clear")) {
        if (rd(FOC_CTRL) & FOC_CTRL_ENABLE) xil_printf("reject enable=1\r\n");
        else {
            wr(FOC_CTRL, rd(FOC_CTRL) | FOC_CTRL_FAULT_CLR);
            xil_printf("clear\r\n");
        }
    } else if (starts(line, "dump")) do_dump();
    else xil_printf("r|w|start|stop|clear|dump\r\n");
}

int main(void) {
    char line[64];
    int n = 0;
    xil_printf("foc shell\r\n");
    for (;;) {
        int c = uart_get();
        if (c < 0) continue;
        if (c == '\r' || c == '\n') {
            line[n] = 0;
            if (n) handle(line);
            n = 0;
        } else if (n < 63) line[n++] = (char)c;
    }
}
