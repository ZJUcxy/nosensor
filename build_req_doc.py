# -*- coding: utf-8 -*-
"""生成《FPGA 无传感器永磁同步电机控制需求规格说明书》V0.6。

V0.5 冻结 MCU 200 µs 寄存器事务。
V0.6 按该接口划分模块职责，并规定端口、内部信号和谷点更新顺序。
"""
from docx import Document
from docx.shared import Pt, RGBColor, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

EAST_HEAD = "微软雅黑"
EAST_BODY = "宋体"
LATIN = "Calibri"

doc = Document()

sec = doc.sections[0]
sec.left_margin = Cm(1.8)
sec.right_margin = Cm(1.8)
sec.top_margin = Cm(1.8)
sec.bottom_margin = Cm(1.8)

normal = doc.styles["Normal"]
normal.font.name = LATIN
normal.font.size = Pt(10.5)
normal._element.rPr.rFonts.set(qn("w:eastAsia"), EAST_BODY)


def _set_run_font(run, east=EAST_BODY, size=None, bold=None, color=None, mono=False):
    run.font.name = "Consolas" if mono else LATIN
    rpr = run._element.get_or_add_rPr()
    rfonts = rpr.get_or_add_rFonts()
    rfonts.set(qn("w:eastAsia"), east)
    if size is not None:
        run.font.size = Pt(size)
    if bold is not None:
        run.bold = bold
    if color is not None:
        run.font.color.rgb = RGBColor(*color)


def add_heading(text, level):
    h = doc.add_heading(level=level)
    run = h.add_run(text)
    _set_run_font(run, east=EAST_HEAD, size=None, bold=True,
                  color=(0x1F, 0x3B, 0x63) if level <= 1 else (0x2E, 0x4A, 0x7A))
    return h


def add_para(text, size=10.5, bold=False, align=None, space_after=4):
    p = doc.add_paragraph()
    run = p.add_run(text)
    _set_run_font(run, east=EAST_BODY, size=size, bold=bold)
    p.paragraph_format.space_after = Pt(space_after)
    if align is not None:
        p.alignment = align
    return p


def add_mono(text):
    p = doc.add_paragraph()
    run = p.add_run(text)
    _set_run_font(run, east=EAST_BODY, size=8, mono=True)
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.space_before = Pt(2)
    return p


def add_bullet(text):
    p = doc.add_paragraph(style="List Bullet")
    run = p.add_run(text)
    _set_run_font(run, east=EAST_BODY, size=10.5)
    p.paragraph_format.space_after = Pt(2)
    return p


def _shade(cell, hexcolor):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:fill"), hexcolor)
    tcPr.append(shd)


def make_table(headers, rows, widths=None, header_fill="1F3B63", font_size=8):
    t = doc.add_table(rows=1, cols=len(headers))
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    hdr = t.rows[0].cells
    for i, htext in enumerate(headers):
        hdr[i].text = ""
        run = hdr[i].paragraphs[0].add_run(htext)
        _set_run_font(run, east=EAST_HEAD, size=font_size, bold=True, color=(0xFF, 0xFF, 0xFF))
        _shade(hdr[i], header_fill)
    for row in rows:
        cells = t.add_row().cells
        for i, val in enumerate(row):
            cells[i].text = ""
            run = cells[i].paragraphs[0].add_run(str(val))
            _set_run_font(run, east=EAST_BODY, size=font_size)
    if widths:
        for i, w in enumerate(widths):
            for row in t.rows:
                row.cells[i].width = Cm(w)
    doc.add_paragraph().paragraph_format.space_after = Pt(2)
    return t


def add_sig_table(rows):
    return make_table(["信号", "位宽", "方向", "说明"], rows,
                      widths=[4.8, 1.6, 1.5, 8.3], font_size=8)


def add_module(heading, func, sig_rows, internal_rows=None):
    add_heading(heading, 3)
    add_para(func, space_after=3)
    add_para("端口", size=10.5, bold=True, space_after=2)
    add_sig_table(sig_rows)
    if internal_rows:
        add_para("内部信号", size=10.5, bold=True, space_after=2)
        add_sig_table(internal_rows)


# ================= 封面 =================
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run("FPGA 无传感器永磁同步电机控制")
_set_run_font(run, east=EAST_HEAD, size=22, bold=True, color=(0x1F, 0x3B, 0x63))
p.paragraph_format.space_before = Pt(90)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run("需求规格说明书")
_set_run_font(run, east=EAST_HEAD, size=22, bold=True, color=(0x1F, 0x3B, 0x63))

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run("—— XC7K325T 电流环、I-F 启动与外部 SMO 观测器接口 ——")
_set_run_font(run, east=EAST_BODY, size=12, color=(0x55, 0x55, 0x55))
p.paragraph_format.space_after = Pt(36)

make_table(
    ["项目", "内容"],
    [
        ["文档名称", "FPGA 无传感器永磁同步电机控制需求规格说明书"],
        ["文档版本", "V0.6"],
        ["文档状态", "C1–C6 已确认。第 4 章为模块端口与内部信号基线"],
        ["密级", "内部"],
        ["前版", "V0.2 草案（2025-07），状态为待评审"],
        ["修订日期", "2026-11-02"],
        ["适用对象", "FPGA 逻辑、控制算法、系统集成与测试"],
    ],
    widths=[3.6, 12.6],
    font_size=9,
)
add_para("V0.3 修正了 V0.2 中不能同时成立的指标。V0.4 写入采样、算法范围和 IPM 极性。"
         "V0.5 把观测器定为 MCU 的 200 µs 中断。V0.6 按该接口规定每个模块的职责、端口、内部信号和谷点更新顺序。",
         space_after=6)
doc.add_page_break()

# ================= 1 =================
add_heading("1 文档信息", 1)
add_para("本文件定义基于 Xilinx Kintex-7 XC7K325T、IPM 与 TI AMC1306 的表贴式永磁同步电机（SPMSM）"
         "无位置传感器矢量控制需求。FPGA 实现 25 kHz 电流闭环、SVPWM、I-F 启动、保护，以及与外部观测器的数据端口。"
         "滑模观测器与锁相环运行在外部 MCU/DSP，不在本 FPGA 工程内实现。", space_after=6)

add_heading("1.1 修订记录", 2)
make_table(
    ["版本", "日期", "说明"],
    [
        ["V0.2", "2025-07", "草案。给出模块划分、功能清单和寄存器草稿。"],
        ["V0.3", "2026-11-02",
         "澄清定标、载波时基、采样延迟与带宽、状态机、保护、寄存器和范围。新增工程计划与验收。"],
        ["V0.4", "2026-11-02",
         "确认 OSR=256 与 19.2 MHz、1.5 kHz 带宽、线性区电流环、不采母线温度、裸机例程、IPM 高有效。"],
        ["V0.5", "2026-11-03",
         "观测器改为 MCU 每 200 µs 经 SFP 读写寄存器：上行 u、i，下行电角度与电角速度。"],
        ["V0.6", "2026-11-03",
         "按 V0.5 重划模块边界，补齐端口、内部信号、谷点更新顺序和模块互联。"],
    ],
    widths=[2.2, 3.0, 11.0],
    font_size=8,
)

add_heading("1.2 需求优先级与追溯", 2)
add_para("P0 不满足则本阶段不能验收。P1 在 P0 闭环仿真通过后实现，缺少时不影响电流环主路径。P2 只预留，不编码。"
         "每条功能需求在第 5 章给出验收准则，并在第 14.4 节追溯到模块和测试。", space_after=4)

add_heading("1.3 术语与缩写", 2)
make_table(
    ["缩写", "含义", "本文件中的用法"],
    [
        ["FOC", "磁场定向控制", "本阶段只做电流环，不做速度环"],
        ["I-F", "电流闭环、角度开环启动", "PI 始终闭合；开环量只是电角度和电流指令"],
        ["SMO+PLL", "滑模观测器 + 锁相环", "外部器件，本工程只交换数据"],
        ["Q31", "有符号 32 位小数", "数值 = 寄存器 / 2^31，范围 [-1, 1)"],
        ["UQ32", "无符号圆周小数", "数值 = 寄存器 / 2^32，模 1 对应 2π 电角度"],
        ["Q16.16", "有符号 16 位整数 + 16 位小数", "数值 = 寄存器 / 2^16"],
        ["ω_step", "每载波周期的电角度增量", "与 UQ32 同一 LSB，不是 rad/s"],
        ["pu", "标幺", "电流基值 I_BASE，电压基值 Vdc/√3"],
        ["谷点", "三角载波计数回到 0 的时刻", "采样锁存、比较值装载、序号加 1 都在谷点"],
    ],
    widths=[2.6, 5.4, 8.2],
    font_size=8,
)

add_heading("1.4 参考文档", 2)
for t in [
    "Xilinx Kintex-7 FPGA 数据手册，器件 XC7K325T-2FFG900。",
    "TI AMC1306x25 / AMC1306x05 数据手册。调制时钟最高 21 MHz，时钟占空比 40%～60%。",
    "Xilinx Aurora 8B/10B LogiCORE IP 产品指南。仅在适配已有链路时引用。",
    "所选 IPM 数据手册。死区、FO 极性与最小脉宽仍待 C6 用手册核对。",
]:
    add_bullet(t)

# ================= 2 =================
add_heading("2 系统概述", 1)
add_heading("2.1 系统定位", 2)
add_para("FPGA 是实时电流控制器，载波固定 25 kHz。电流采样和 PWM 装载只认谷点。"
         "MCU 以 200 µs 周期中断访问 FPGA 寄存器，读走最近一拍的电压和电流，把对该拍样本估计的电角度和电角速度写回。两次写回之间，FPGA 每个谷点用这份速度外推角度。",
         space_after=6)

add_heading("2.2 数据路径", 2)
add_mono("""MCU：每 200µs 中断一次。经已有 SFP/Aurora 通路读写 AXI 寄存器
  读 SNAP_SEQ、uα、uβ、iα、iβ
  写 THETA_IN、SPEED_IN、SEQ_ECHO，再写 OBS_COMMIT
        ▼
motor_ctrl_core（clk_100m 与 clk_19m2 同源）
  amc1306_if：19.2MHz → SINC3 OSR=256 → 只取对齐谷点的 S0
  每个谷点把 uα、uβ、iα、iβ 和谷点序号写入快照
  clarke / park / PI / 矢量限幅 / 逆 Park / SVPWM
  theta_interp：提交生效后按谷点 θ += ω_step，再加 ANGLE_LEAD
  if_startup、sys_fsm、protect
  axi_regs：参数在谷点影子生效；观测提交在谷点受理""")
add_para("一次谷点到下一次谷点是一个控制拍，时长 40 µs。拍内计算在下一个谷点之前完成，比较值在下一个谷点装载。"
         "因此调制比产生该电压指令的电流样本晚一个载波周期。SINC3 还有约 1.5 个载波周期的群延迟。两部分延迟的处理见第 7.4 节。",
         space_after=6)

add_heading("2.3 控制模式", 2)
add_bullet("电流环模式：闭环量为 id、iq。id_ref、iq_ref 由 AXI 寄存器写入。速度环不在 FPGA 内。")
add_bullet("I-F 启动：电流 PI 保持闭合。角度来自内部积分器，电流指令来自 I_START，而不是寄存器 id_ref/iq_ref。")
add_bullet("无感运行：角度来自外部观测器并外推，电流指令来自寄存器。")
add_bullet("使能撤销：任意运行态立即进入 PWM 安全态并回到 READY，电机自由滑行。这不是故障。")

add_heading("2.4 范围", 2)
make_table(
    ["类别", "内容"],
    [
        ["本阶段交付",
         "电流采样、坐标变换、d/q PI、矢量限幅、线性区 SVPWM、死区与互锁、I-F 启动与切换、保护、角度外推、AXI4-Lite 寄存器、200 µs 观测快照与提交、可仿真的集成顶层"],
        ["本阶段不做",
         "SMO/PLL 算法、速度环、弱磁、解耦前馈、过调制、死区补偿、两相电流重构、母线电压闭环、MicroBlaze 应用软件、PCB"],
        ["已有通路",
         "SFP、Aurora 与 GTX。电机核心不解析光口帧，只提供 AXI 寄存器。已有通路负责把 MCU 的访问变成这些寄存器的读和写"],
        ["处理器软件",
         "Vivado Block Design 含 MicroBlaze、UART 和本 AXI 从机。交付 sw/reg_map.h、上电写入顺序，以及第 14.6 节的裸机例程"],
    ],
    widths=[3.4, 12.8],
    font_size=8,
)

# ================= 3 =================
add_heading("3 硬件平台与外部接口", 1)
add_heading("3.1 FPGA", 2)
make_table(
    ["项目", "规格"],
    [
        ["器件", "XC7K325T-2FFG900，速度等级 -2"],
        ["工具", "Vivado 2019.2 或项目已有基线；仿真用 Vivado XSIM；参考模型用 Python 3.10+ / pytest / numpy"],
        ["语言", "Verilog-2001。标识符与本文件一致。注释使用中文"],
        ["控制核心时钟", "100 MHz。实现后该时钟 WNS≥0、WHS≥0"],
        ["资源目标", "控制核心 LUT 与 DSP 占用不超过 XC7K325T 的 30%。该目标用于发现结构异常，不是性能上限"],
    ],
    widths=[3.6, 12.6],
    font_size=8,
)

add_heading("3.2 IPM", 2)
add_para("六路 PWM 为中心对齐互补输出。安全态是六路全部关断。默认极性为高有效，安全态输出全 0。"
         "PWM_CFG.bit0=1 时整组取反，安全态变为全 1。上下桥在死区和故障期间都必须同时关断。"
         "FO 为低有效。引脚经两级同步后，连续 3 个 100 MHz 时钟为低才确认，确认后的下一个时钟把 PWM 寄存器置为安全态。"
         "从引脚有效到寄存器进入安全态不超过 10 个主时钟，满足 1 µs 上限。FO 确认路径不使用软件轮询。", space_after=4)
make_table(
    ["项目", "基线"],
    [
        ["载波", "固定 25 kHz。一个载波内恰好 3 个 OSR=256 窗口，运行中不改频率"],
        ["计数", "三角波 0→PWM_PEAK→0，PWM_PEAK=2000。f_pwm = 100 MHz / (2×2000)"],
        ["比较装载", "只在谷点装载影子比较值"],
        ["死区", "只延迟上升沿。默认 2000 ns = 200 个 10 ns 时钟。允许 500～5000 ns，超出则钳位"],
        ["FO", "低有效，3 拍滤波后硬件封锁"],
    ],
    widths=[3.6, 12.6],
    font_size=8,
)
add_para("V0.2 同时写了“模 4000 的锯齿计数”和“增减三角计数”。中心对齐时一个载波是 4000 个 10 ns 时钟，峰值是 2000，不是把比较值放在 0～3999 的锯齿上。",
         space_after=6)

add_heading("3.3 AMC1306 电流采样", 2)
make_table(
    ["项目", "基线"],
    [
        ["通道", "A/B/C 各一片。控制律使用 Ia、Ib。Ic 用于过流和 ia+ib+ic 校验"],
        ["调制时钟", "19.2 MHz，占空比 50%。MMCM：DIVCLK=5，CLKFBOUT_MULT=48，VCO=960 MHz，CLKOUT0_DIVIDE=50。三片共用"],
        ["位流", "1 为 +1，0 为 -1。50% 占空对应 0 A。DATA_INV 按相取反"],
        ["抽取", "SINC3，OSR=256。19.2 MHz/256 = 75 kHz，每个 40 µs 载波恰好 3 个窗口"],
        ["为何不是 20 MHz", "20 MHz/256/25 kHz = 3.125，窗口边界不能每个载波重复。19.2 MHz 在 AMC1306 的 21 MHz 上限以内，且 3 个窗口等于 4000 个 100 MHz 时钟"],
        ["增益", "G = 256^3 = 2^24。归一化是算术右移 24 位，再乘 SCALE_I。满幅直流位流对应 ±1"],
        ["累加位宽", "积分器与梳状器使用 32 位。理论最少位数为 1+3×8 = 25"],
        ["群延迟", "3×(256-1)/2 个调制时钟 = 19.922 µs"],
        ["控制样本", "连续三个窗口记为 S0、S1、S2。S0 的终点对齐谷点，控制律和上行电流只用 S0。S1、S2 不进入 PI"],
        ["对齐", "S0 终点与谷点的误差不超过 1 个调制时钟（52 ns）。DEC_PHASE 范围 0～255"],
        ["标定", "SCALE_I 为 Q16.16，等于 I_FS/I_BASE，允许为负以修正分流方向"],
    ],
    widths=[3.2, 13.0],
    font_size=8,
)
add_para("满量程电流 I_FS = V_CLIP / R_SHUNT。V_CLIP 由芯片决定：AMC1306x25 为 ±250 mV，AMC1306x05 为 ±50 mV。"
         "I_BASE 必须不小于需要线性表示的峰值电流，避免控制量先于过流保护饱和。分流电阻和芯片后缀未到之前，SCALE_I 复位为 1.0，不阻塞 RTL。",
         space_after=4)
add_para("抽取器全部在 clk_19m2 上运行。sample_valid 同步进 clk_100m。19.2 MHz 与 100 MHz 每 1.25 µs 对齐一次（24 个调制时钟等于 125 个主时钟），单个窗口是 4000/3 个主时钟，所以不能要求每个窗口边界都落在主时钟整数沿上。",
         space_after=6)

add_heading("3.4 观测器：MCU 经 SFP 访问寄存器", 2)
add_para("MCU 定时器每 200 µs 进一次中断，200 µs 等于 5 个载波。中断里通过已有 SFP 通路访问电机核心的 AXI 寄存器：先读电压和电流，再把电角度和电角速度写回。电机核心不实现 SFP 编解码，也不再定义单独的观测帧。",
         space_after=4)
add_bullet("每个谷点把 uα、uβ、iα、iβ 和谷点序号写入快照。u 是限幅和逆 Park 之后的电压指令，i 是本拍 S0。一次中断读到的四个量必须属于同一个 SNAP_SEQ。")
add_bullet("MCU 写 THETA_IN（UQ32 电角度）、SPEED_IN（Q16.16，电角速度，单位 rad/s）和 SEQ_ECHO（所读快照的序号），然后写 OBS_COMMIT=1。")
add_bullet("正速度使电角度增加。机械转速由 MCU 乘极对数后写成电角速度，FPGA 内不保存极对数。")
add_bullet("提交在随后的谷点受理。序号差 n 为 0～20 时更新基准；超出则丢弃这次提交，原外推继续。")
add_bullet("SWITCH 与 SENSORLESS 中，距上次成功提交超过 LINK_TO 个谷点则链路故障。复位值 15 拍，即 600 µs，允许错过一次 200 µs 中断。")
add_para("电流环的谷点不随这路访问移动。MCU 决定何时更新角度，不决定何时采样和装载 PWM。一次中断里的读和写都要在下一次中断前完成。",
         space_after=6)

add_heading("3.5 时钟、复位与参数生效", 2)
add_bullet("clk_100m 与 clk_19m2 来自同一 MMCM，锁定后才允许退出 INIT。")
add_bullet("除这两路同源时钟外，任何时钟不得进入 motor_ctrl_core。SFP 与 Aurora 的时钟留在已有通路，观测数据只经 AXI 进入核心。")
add_bullet("复位源：上电/硬件复位、CTRL.SOFT_RST。释放时在各自时钟域同步。")
add_bullet("复位和故障期间 PWM 保持安全态。")
add_bullet("影响控制律的寄存器在写 AXI 时先进入缓冲，下一个谷点一次性影子装载，避免一拍内参数撕裂。")

add_heading("3.6 母线电压与温度", 2)
add_para("设计基线不接入母线电压 ADC 和温度 ADC。电压标幺以寄存器 VDC_NOM 为定义，默认 310 V；SVPWM 的占空比由标幺电压直接计算，P0 路径不读取实时母线电压。"
         "过压、欠压、过温的故障位和阈值寄存器保留，FAULT_MASK 复位时屏蔽这三项。板级若后来提供 ADC，接口协议另立章节，不从 16 位裸端口猜测。",
         space_after=6)

# ================= 4 =================
add_heading("4 模块架构", 1)
add_para("本章是 RTL 划分基线。算法公式仍以第 7 章为准，寄存器仍以第 8 章为准。"
         "模块之间只通过本章列出的端口连接。内部信号是该模块自己的寄存器或命名组合量，不跨模块引用。",
         space_after=4)
add_para("除单独说明外，时序模块都有 clk_100m_i 和低有效同步复位 rst_n_i，端口表中省略。"
         "组合模块没有时钟。复位期间：PWM 进入安全态，PI 积分、I-F 积分、角度基准和提交标志清零，快照清零。",
         space_after=4)

add_heading("4.1 职责边界", 2)
make_table(
    ["模块", "拥有的状态", "不负责"],
    [
        ["clk_rst_mgmt", "MMCM、两域复位、载波、谷点序号", "保护、角度、寄存器"],
        ["amc1306_if", "三通道 SINC3、定标、S0 保持", "Clarke、保护计数"],
        ["clarke", "无", "Ic、标定"],
        ["cordic_sincos", "16 级迭代", "角度外推"],
        ["park_ipark", "无，或至多 1 级结果寄存器", "限幅、PI"],
        ["pi_ctrl ×2", "各自的积分器", "矢量限幅；d/q 不共用积分器"],
        ["vlim", "除法进行中的商", "占空比、死区"],
        ["cmd_mux", "无", "影子寄存器；影子在 axi_regs"],
        ["if_startup", "定位/斜坡/过渡的积分与计数", "无感角外推"],
        ["theta_interp", "θ_now、ω_step、链路年龄", "SFP、快照"],
        ["obs_port", "快照、速度换算", "Park；不保存极对数"],
        ["svpwm", "比较值影子/工作值、死区计数", "电流环；载波计数不在这里"],
        ["protect", "故障锁存、滤波与确认计数", "状态跳转"],
        ["sys_fsm", "状态寄存器", "故障判定公式"],
        ["axi_regs", "AXI 握手、影子参数、提交缓冲", "控制律运算"],
        ["motor_ctrl_core", "计算相序号，以及谷点锁存的 iα、iβ", "芯片引脚、SFP"],
        ["top_integration", "引脚与 AXI 互联", "MMCM、算法"],
    ],
    widths=[3.4, 6.4, 6.4],
    font_size=8,
)
add_para("pi_d 与 pi_q 是同一份 RTL 的两个实例。B、C 通道的抽取器是 amc1306_if 内部的复制，不再单独成模块。",
         space_after=4)

add_heading("4.2 层次", 2)
add_mono("""top_integration
  引脚：时钟、复位、AMC1306、PWM、FO、LED
  AXI 互联：已有 SFP 通路 与 MicroBlaze 都接到 motor_ctrl_core.s_axi
  motor_ctrl_core
    clk_rst_mgmt
    amc1306_if → clarke
    axi_regs ↔ obs_port → theta_interp
    if_startup、cmd_mux、sys_fsm、protect
    cordic_sincos → park_ipark → pi_d/pi_q → vlim → park_ipark 逆变换 → svpwm""")
add_para("数据只有一条向前的计算链。vlim 的 limited 返回给两个 PI，只用于阻止下一次积分，不构成组合环。",
         space_after=4)

add_heading("4.3 谷点沿的更新顺序", 2)
add_para("载波由 0～3999 的相位计数生成。相位 0～1999 时载波值等于相位；相位 2000～3999 时载波值等于 3999−相位，因此载波值范围是 0～1999。"
         "比较值满量程仍是 PWM_PEAK=2000：比较值大于等于 2000 时整周导通，比较值为 0 时整周关断。pwm_tick 只在相位回到 0 的那个时钟为 1。",
         space_after=4)
add_para("在 pwm_tick 为 1 的时钟沿，motor_ctrl_core 按下面的顺序安排各模块的状态更新。同一沿内，模块使用更新前的谷点序号。",
         space_after=2)
add_bullet("锁存本拍 S0。Clarke 组合输出写入 i_alpha_r、i_beta_r。")
add_bullet("obs_port 把 i_alpha_r/i_beta_r 与上一计算相留下的 u_alpha_r/u_beta_r 写入快照，序号用更新前的 valley_cnt。")
add_bullet("若提交等待有效，obs_port 计算 n 与 ω_step，给出 accept 或 drop。")
add_bullet("theta_interp 按受理结果或按旧步长更新 θ_now。")
add_bullet("svpwm 把比较值影子装入工作寄存器。axi_regs 把参数影子装入生效值，并清除已被 accept 或 drop 消化的提交等待。")
add_bullet("valley_cnt 加 1，uint16 回绕。复位后的第一次谷点序号为 0。")
add_para("FO 封锁不经过这个顺序。protect 每个时钟都更新 FO 滤波，block 直接进 svpwm。",
         space_after=4)

add_heading("4.4 计算相", 2)
add_para("谷点沿之后的下一个时钟，核心把 cordic_start 拉高一拍。CORDIC 使用刚刚更新的 θ_use。完成后的同一计算相内做 Park、PI、矢量限幅和逆 Park，svpwm 更新比较值影子，obs 用的电压保持量也在这时更新。整条链必须在下一次 pwm_tick 之前结束。",
         space_after=4)
add_para("快照里的 u 是本谷点开始生效的电压指令，i 是本谷点的 S0。电压指令来自上一拍电流，电流是本拍新样本。这个一拍差别留给 MCU 观测器，FPGA 不再重做对齐。",
         space_after=4)

add_heading("4.5 模块互联", 2)
make_table(
    ["信号", "生产者", "使用者", "更新时机"],
    [
        ["pwm_tick, valley_cnt, carrier_cnt", "clk_rst_mgmt", "核心及各时序模块", "每时钟；tick 单拍"],
        ["ia/ib/ic, sample 保持", "amc1306_if", "clarke、protect", "S0 在谷点沿之前已经保持"],
        ["i_alpha_r, i_beta_r", "核心锁存 Clarke", "park、obs_port、回读", "谷点沿"],
        ["u_alpha_r, u_beta_r", "逆 Park 结果", "svpwm、obs_port、回读", "计算相结束"],
        ["snap_*", "obs_port", "axi_regs 读数据", "谷点沿"],
        ["commit_pend, theta_in, speed_in, seq_echo", "axi_regs", "obs_port", "AXI 写 OBS_COMMIT 时置位"],
        ["accept, drop, ω_step, n, theta_in", "obs_port", "theta_interp、axi_regs", "谷点沿"],
        ["theta_park, theta_now, link_age", "theta_interp", "cmd_mux、if_startup、protect", "谷点沿"],
        ["theta_if, id_if, iq_if, switch_req", "if_startup", "cmd_mux、sys_fsm", "谷点沿"],
        ["theta_use, id_ref, iq_ref", "cmd_mux", "cordic、pi", "组合，随输入变"],
        ["sin, cos", "cordic_sincos", "park_ipark", "计算相，done 后保持"],
        ["id, iq, ud, uq", "park 与 pi", "vlim、回读", "计算相"],
        ["ud_lim, uq_lim, limited", "vlim", "逆 Park、两个 PI 的 freeze", "计算相"],
        ["pwm_*", "svpwm", "引脚", "每时钟，比较装载在谷点沿"],
        ["fault, block", "protect", "sys_fsm、svpwm", "每时钟"],
        ["state, pwm_enable, mode, run_if", "sys_fsm", "cmd_mux、if_startup、svpwm、protect", "每时钟"],
        ["cfg 生效值", "axi_regs", "各使用者", "谷点沿从影子装入"],
    ],
    widths=[5.6, 3.2, 4.4, 3.0],
    font_size=7,
)

add_heading("4.6 端口与内部信号", 2)
add_para("方向“内部”表示不出现在端口上。位宽按有符号二进制补码理解，除非写明无符号。",
         space_after=4)

add_module("4.6.1 clk_rst_mgmt",
    "产生 100 MHz 与 19.2 MHz，并产生唯一的载波和谷点序号。MMCM 参数见第 3.3 节。锁定之前两路 rst_n 都为 0。",
    [
        ["clk_in_i", "1", "输入", "板级 100 MHz"],
        ["rst_hw_n_i / sw_reset_i", "1 / 1", "输入", "硬件复位低有效；软件复位高有效"],
        ["clk_100m_o / clk_19m2_o", "1 / 1", "输出", "同源时钟，19.2 MHz 占空比 50%"],
        ["rst_n_100_o / rst_n_19_o", "1 / 1", "输出", "各自时钟域同步释放"],
        ["pwm_tick_o", "1", "输出", "相位 0 时拉高一个 clk_100m"],
        ["carrier_cnt_o", "11", "输出", "无符号 0～1999"],
        ["valley_cnt_o", "16", "输出", "无符号谷点序号"],
        ["mmcm_locked_o", "1", "输出", "已同步到 clk_100m"],
    ],
    [
        ["phase_cnt", "12", "内部", "无符号 0～3999"],
        ["carrier_cnt", "11", "内部", "由 phase_cnt 折叠得到"],
        ["valley_cnt", "16", "内部", "在 tick 沿的末尾加 1"],
        ["locked_ff", "3", "内部", "MMCM locked 同步"],
        ["rst_ff_100 / rst_ff_19", "3 / 3", "内部", "复位释放移位链"],
    ])

add_module("4.6.2 amc1306_if",
    "三通道 SINC3，OSR=256。只把对齐谷点的 S0 送到 clk_100m。满幅直流位流算术右移 24 位后乘 SCALE_I，饱和到 Q31。DEC_PHASE 为 0～255，用来移动窗口相对谷点的相位。",
    [
        ["clk_100m_i / clk_19m2_i", "1 / 1", "输入", "同源"],
        ["rst_n_100_i / rst_n_19_i", "1 / 1", "输入", "分域复位"],
        ["data_a_i / data_b_i / data_c_i", "1", "输入", "位流，在 clk_19m2 上升沿采样"],
        ["data_inv_i", "3", "输入", "按相取反"],
        ["scale_i", "32", "输入", "SCALE_I，Q16.16，可为负"],
        ["dec_phase_i", "8", "输入", "无符号 0～255"],
        ["pwm_tick_i", "1", "输入", "只用于测量相位差"],
        ["mck_o", "1", "输出", "等于 clk_19m2"],
        ["ia_o / ib_o / ic_o", "32", "输出", "最近一次 S0，Q31，在 clk_100m 保持"],
        ["sinc_ovf_o", "1", "输出", "任一通道定标饱和，电平"],
    ],
    [
        ["bit_pm1_a/b/c", "2", "内部", "位流映射为 +1 或 −1"],
        ["integ1/2/3_a/b/c", "32", "内部", "三级积分，clk_19m2"],
        ["osr_cnt", "8", "内部", "0～255，三通道共用"],
        ["win_cnt", "2", "内部", "0 表示 S0，1 和 2 的结果丢弃"],
        ["comb_z1/2/3_a/b/c", "32", "内部", "抽取瞬间的梳状延迟"],
        ["raw_a/b/c", "32", "内部", "梳状输出算术右移 24 位"],
        ["s0_toggle", "1", "内部", "S0 完成时翻转，用于跨到 100 MHz"],
        ["sync_ff", "3", "内部", "clk_100m 上的同步"],
        ["ia_hold / ib_hold / ic_hold", "32", "内部", "S0 保持寄存器"],
        ["phase_delta", "16", "内部", "S0 同步脉冲到 pwm_tick 的时钟数，供联调"],
    ])

add_module("4.6.3 clarke",
    "组合逻辑。iα = ia，iβ = (ia + 2·ib) × 1239850262 / 2^31。常数是 round(2^31 / √3)。结果饱和到 Q31。",
    [
        ["ia_i / ib_i", "32 / 32", "输入", "Q31"],
        ["ialpha_o / ibeta_o", "32 / 32", "输出", "Q31"],
    ],
    [
        ["sum_a_2b", "34", "内部", "ia + (ib<<1)，多留符号位"],
        ["prod_beta", "66", "内部", "sum_a_2b 乘常数的积"],
    ])

add_module("4.6.4 cordic_sincos",
    "时序模块。start 为 1 的下一拍开始迭代，16 级旋转后按象限恢复。done 后 sin、cos 保持到下一次 start。绝对误差要求见 FR-02。",
    [
        ["theta_i", "32", "输入", "UQ32，在 start 当拍采样"],
        ["start_i", "1", "输入", "单拍"],
        ["sin_o / cos_o", "32 / 32", "输出", "Q31"],
        ["done_o", "1", "输出", "结果有效时拉高一拍，之后数据保持"],
    ],
    [
        ["quad", "2", "内部", "θ 的高 2 位"],
        ["x_r / y_r / z_r", "32", "内部", "当前迭代向量"],
        ["stage", "5", "内部", "0～15，完成后停在空闲"],
        ["atan_tab", "16×32", "内部", "与参考模型相同的反正切表"],
    ])

add_module("4.6.5 park_ipark",
    "组合逻辑，允许在积之后插入一级寄存器，但 done 之后、本计算相结束前必须出结果。Park 与逆 Park 使用同一对 sin、cos。公式见第 7.1 节。",
    [
        ["ialpha_i / ibeta_i", "32", "输入", "Q31"],
        ["ud_i / uq_i", "32", "输入", "限幅后的 Q31"],
        ["sin_i / cos_i", "32", "输入", "Q31"],
        ["id_o / iq_o", "32", "输出", "Q31"],
        ["ualpha_o / ubeta_o", "32", "输出", "Q31"],
    ],
    [
        ["mul_ac / mul_bs / mul_as / mul_bc", "64", "内部", "Park 的四次乘法"],
        ["mul_uc / mul_us / mul_vc / mul_vs", "64", "内部", "逆 Park 的四次乘法"],
    ])

add_module("4.6.6 pi_ctrl",
    "每个谷点对应的计算相更新一次。u = sat(Kp·e + integ)。integ 在 enable 为 1、freeze 为 0 且本次更新时加上 Ki·e，并饱和到 Q31。enable 为 0 时 integ 清零。freeze 来自本拍 vlim，只影响本次 integ 的写入，不改变已经加进 u 的旧积分。",
    [
        ["step_i", "1", "输入", "本拍计算完成、允许更新积分的单拍"],
        ["ref_i / fb_i", "32", "输入", "Q31"],
        ["kp_i / ki_i", "32", "输入", "Q16.16"],
        ["enable_i / freeze_i", "1", "输入", "使能；限幅冻结"],
        ["out_o", "32", "输出", "未做矢量限幅的轴电压"],
    ],
    [
        ["err", "32", "内部", "ref − fb，饱和"],
        ["prod_p / prod_i", "64", "内部", "Kp、Ki 乘法"],
        ["integ", "32", "内部", "积分寄存器，Q31"],
        ["sum", "32", "内部", "比例项加旧积分后的饱和结果"],
    ])

add_module("4.6.7 vlim",
    "ud^2+uq^2 不超过 U_MAX^2 时直通，limited 为 0。超过时两轴同乘一个比例，角度不变，limited 为 1。比例用恢复除法，在计算相内完成。",
    [
        ["ud_i / uq_i", "32", "输入", "PI 输出"],
        ["umax_i", "32", "输入", "Q31，无负值"],
        ["start_i", "1", "输入", "与 PI 的 step 同一拍，开始判断"],
        ["ud_o / uq_o", "32", "输出", "限幅后电压，完成后保持"],
        ["limited_o", "1", "输出", "本拍发生了缩放"],
        ["done_o", "1", "输出", "结果稳定时拉高一拍"],
    ],
    [
        ["mag2 / lim2", "64", "内部", "平方和与阈值平方"],
        ["quot", "32", "内部", "U_MAX 相对模长的比例"],
        ["div_cnt", "6", "内部", "除法节拍"],
        ["ud_r / uq_r", "32", "内部", "结果寄存器"],
    ])

add_module("4.6.8 cmd_mux",
    "组合逻辑。mode=1 时选用 I-F 的角度和电流；mode=2 时选用 theta_park 和寄存器电流指令；mode=0 时电流指令为 0，角度保持 theta_park 但不被使用。选出的电流矢量若超过 I_CMD_MAX，两轴同比缩小。",
    [
        ["mode_i", "2", "输入", "来自 sys_fsm"],
        ["theta_if_i / theta_park_i", "32", "输入", "UQ32"],
        ["id_if_i / iq_if_i", "32", "输入", "I-F 指令"],
        ["id_reg_i / iq_reg_i", "32", "输入", "影子装载后的寄存器指令"],
        ["i_cmd_max_i", "32", "输入", "Q31"],
        ["theta_o", "32", "输出", "送给 CORDIC"],
        ["id_ref_o / iq_ref_o", "32", "输出", "送给两个 PI"],
    ],
    [
        ["id_sel / iq_sel", "32", "内部", "限幅前的选择结果"],
        ["mag2", "64", "内部", "电流指令平方和"],
        ["id_sc / iq_sc", "32", "内部", "缩放后的指令"],
    ])

add_module("4.6.9 if_startup",
    "只在 run_i 为 1 时积分。相位依次为定位、斜坡、过渡。电流从 0 斜坡到带符号的 I_START，符号由 DIR 决定。斜坡阶段把电频率和 θ_if 按第 7.5 节积分。连续 SWITCH_N 次谷点同时满足转速和角度窗口才置 switch_req。过渡用短弧。角度差超过 THETA_ABORT 时 switch_fail 拉高一拍。",
    [
        ["run_i / dir_i", "1 / 1", "输入", "状态机允许 I-F；方向"],
        ["pwm_tick_i", "1", "输入", "积分节拍"],
        ["theta_now_i / omega_step_i", "32", "输入", "观测角和步长"],
        ["obs_new_i", "1", "输入", "本谷点有成功提交"],
        ["i_start_i / dfdt_i", "32", "输入", "Q31；Q16.16 Hz/s"],
        ["t_align_i / i_slew_n_i", "32", "输入", "谷点数"],
        ["w_switch_i / theta_win_i / switch_n_i", "32/32/16", "输入", "切换阈值"],
        ["blend_n_i / theta_abort_i", "16/32", "输入", "过渡长度和失败窗"],
        ["id_ref_o / iq_ref_o / theta_o", "32", "输出", "本拍 I-F 指令"],
        ["phase_o", "2", "输出", "0 定位，1 斜坡，2 过渡，3 完成"],
        ["switch_req_o / switch_fail_o", "1", "输出", "请求进入 SWITCH；失败脉冲"],
    ],
    [
        ["phase", "2", "内部", "内部相位，输出前打一拍"],
        ["slew_cnt / align_cnt / blend_cnt", "32", "内部", "各阶段计数"],
        ["match_cnt", "16", "内部", "角度窗口连续计数"],
        ["iq_cmd", "32", "内部", "当前 q 轴指令"],
        ["freq / freq_rem", "32", "内部", "电频率及其余数，Q16.16"],
        ["theta_if", "32", "内部", "I-F 角度"],
        ["dtheta_lat", "32", "内部", "过渡开始时锁存的短弧差"],
        ["wrap_err", "32", "内部", "环绕到半周以内的角度差"],
    ])

add_module("4.6.10 theta_interp",
    "谷点沿更新。受理时 θ_now = THETA_IN + n×ω_step，并换上新步长，年龄清零。未受理时 θ_now 加旧步长，年龄加 1。theta_park 在 θ_now 上再加 ANGLE_LEAD 个步长。",
    [
        ["pwm_tick_i", "1", "输入", "更新节拍"],
        ["accept_i", "1", "输入", "本谷点受理"],
        ["theta_in_i / omega_step_i / n_i", "32/32/5", "输入", "受理数据；n 为 0～20"],
        ["angle_lead_i", "8", "输入", "有符号超前拍数"],
        ["theta_now_o / theta_park_o", "32", "输出", "UQ32"],
        ["omega_step_o", "32", "输出", "当前正在使用的步长"],
        ["link_age_o", "16", "输出", "距上次受理的谷点数，饱和在 65535"],
    ],
    [
        ["theta_now", "32", "内部", "基准角"],
        ["step_hold", "32", "内部", "步长"],
        ["age", "16", "内部", "链路年龄"],
    ])

add_module("4.6.11 obs_port",
    "谷点沿写入快照并处理等待中的提交。ω_step = (SPEED_IN × 1791925356) 的 64 位积再右移 32 位。n = uint16(valley_cnt − SEQ_ECHO)。n 小于等于 20 则 accept，否则 drop，旧角度继续外推。",
    [
        ["pwm_tick_i / valley_cnt_i", "1 / 16", "输入", "更新前的序号"],
        ["ialpha_i / ibeta_i", "32", "输入", "本拍 S0 的 Clarke 结果"],
        ["ualpha_i / ubeta_i", "32", "输入", "上一计算相的电压指令"],
        ["pend_i", "1", "输入", "OBS_COMMIT 已写且尚未消化"],
        ["theta_in_i / speed_in_i / seq_echo_i", "32/32/16", "输入", "提交缓冲"],
        ["snap_seq_o", "16", "输出", "快照序号"],
        ["snap_ua/ub/ia/ib_o", "32", "输出", "四路快照"],
        ["accept_o / drop_o", "1", "输出", "单拍，与 tick 对齐"],
        ["theta_use_o / omega_step_o / n_o", "32/32/5", "输出", "仅 accept 时有效"],
    ],
    [
        ["snap_seq", "16", "内部", "快照寄存器"],
        ["snap_ua / snap_ub / snap_ia / snap_ib", "32", "内部", "快照寄存器"],
        ["wprod", "64", "内部", "速度乘常数"],
        ["n_now", "16", "内部", "序号差"],
    ])

add_module("4.6.12 svpwm",
    "用保持的 uα、uβ 按第 7.3 节计算三相比较值，写入影子。谷点沿把影子装入工作寄存器，再和 carrier_cnt 比较。死区只延迟上升沿。上下管同时为导通电平时强制两管进入安全电平。enable 为 0 或 block 为 1 时，不等谷点，下一个时钟就进入安全态。",
    [
        ["ualpha_i / ubeta_i", "32", "输入", "逆 Park 保持值"],
        ["calc_done_i", "1", "输入", "计算相结束，锁存影子"],
        ["pwm_tick_i", "1", "输入", "影子装入工作寄存器"],
        ["carrier_cnt_i", "11", "输入", "0～1999"],
        ["dead_ticks_i", "9", "输入", "0～500，由 ns/10 钳位后得到"],
        ["enable_i / block_i / pol_inv_i", "1", "输入", "运行；故障封锁；极性取反"],
        ["pwm_uh/ul/vh/vl/wh/wl_o", "1", "输出", "引脚电平"],
    ],
    [
        ["ua / ub / uc", "32", "内部", "逆 Clarke，Q31"],
        ["uzs", "32", "内部", "最小最大零序"],
        ["cmp_sh_a/b/c", "12", "内部", "影子，0～2000"],
        ["cmp_a/b/c", "12", "内部", "工作比较值"],
        ["dt_uh/ul/vh/vl/wh/wl", "9", "内部", "上升沿剩余延迟"],
        ["gate_raw_*", "1", "内部", "死区和互锁之前的比较结果"],
        ["safe_lvl", "1", "内部", "pol_inv 为 0 时安全电平为 0"],
    ])

add_module("4.6.13 protect",
    "每个时钟更新 FO 滤波和故障锁存。未屏蔽故障把 block 置 1。屏蔽项不锁存。清除脉冲只清掉当前条件已经不成立的位。过压、欠压、过温没有输入。",
    [
        ["ia_i / ib_i / ic_i", "32", "输入", "Q31"],
        ["iq_ref_i / omega_step_i", "32", "输入", "堵转用"],
        ["ipm_fo_i", "1", "输入", "低有效，异步引脚"],
        ["link_age_i / state_i", "16 / 4", "输入", "链路年龄；只在指定状态计数"],
        ["switch_fail_i / sinc_ovf_i", "1", "输入", "切换失败脉冲；抽取饱和电平"],
        ["pwm_tick_i", "1", "输入", "软件保护按谷点计数"],
        ["oc_th_i / oc_n_i / ph_th_i / ph_n_i", "32/16/32/16", "输入", "过流与缺相"],
        ["stall_t_if_i / stall_t_run_i", "32", "输入", "两段超时"],
        ["w_stall_i / i_stall_i / link_to_i", "32/32/16", "输入", "堵转与链路"],
        ["fault_mask_i / fault_clr_i", "16 / 1", "输入", "屏蔽；清除脉冲"],
        ["fault_o", "16", "输出", "锁存结果"],
        ["block_o", "1", "输出", "有未屏蔽故障时为 1"],
        ["pri_o", "16", "输出", "第 11 章优先码，无故障时为 65535"],
    ],
    [
        ["fo_ff", "3", "内部", "同步与 3 拍确认"],
        ["fo_hot", "1", "内部", "确认后的 FO"],
        ["oc_cnt / ph_cnt", "16", "内部", "连续超限计数"],
        ["stall_cnt", "32", "内部", "当前武装状态下的谷点计数"],
        ["fault_r", "16", "内部", "锁存"],
        ["sum_abc", "34", "内部", "ia+ib+ic，供缺相"],
    ])

add_module("4.6.14 sys_fsm",
    "每时钟根据第 9 章跳转。pwm_enable 只在定位、斜坡、过渡和无感四个状态为 1。mode 在这三个 I-F 相关状态为 1，无感状态为 2，其余为 0。run_if 与 I-F 三个状态一致。FAULT_CLR 只有在 FAULT 状态才被看成清除请求。",
    [
        ["enable_i / param_ok_i", "1", "输入", "运行请求；增益和 I_START 非 0"],
        ["mmcm_locked_i / sinc_ready_i", "1", "输入", "锁定；已经看到至少 3 次 S0"],
        ["fault_i / fault_clr_i", "16 / 1", "输入", "锁存故障；清除脉冲"],
        ["switch_req_i / phase_i", "1 / 2", "输入", "I-F 请求和相位"],
        ["state_o", "4", "输出", "第 9 章编码"],
        ["pwm_enable_o / mode_o / run_if_o", "1/2/1", "输出", "到 svpwm、cmd_mux、if_startup"],
    ],
    [
        ["state", "4", "内部", "状态寄存器。S0 次数在 motor_ctrl_core.s0_cnt"],
    ])

add_module("4.6.15 axi_regs",
    "AXI4-Lite 从机，与 clk_100m 同时钟。写保留地址返回 OKAY 且不改状态，读保留地址返回 0。控制参数写进影子，在 pwm_tick 装入生效值。OBS_COMMIT 写 1 时锁存 THETA_IN、SPEED_IN、SEQ_ECHO 并置 pend。accept 或 drop 的当拍清除 pend。FAULT_CLR 被状态机看见后由本模块清回 0。读控制寄存器返回生效值，不返回尚未装入的影子。",
    [
        ["s_axi_*", "AXI4-Lite", "从机", "32 位数据，字节地址"],
        ["pwm_tick_i", "1", "输入", "影子装载"],
        ["accept_i / drop_i", "1", "输入", "消化提交"],
        ["snap_*_i / theta_now_i / omega_step_i", "见第 8 章", "输入", "只读测量"],
        ["state_i / fault_i / pri_i / age_i", "4/16/16/16", "输入", "状态回读"],
        ["cfg_*_o", "见第 8 章", "输出", "已装载的 kp、ki、阈值、I-F 参数、ANGLE_LEAD"],
        ["pend_o", "1", "输出", "提交等待"],
        ["theta_in_o / speed_in_o / seq_echo_o", "32/32/16", "输出", "等待中的提交内容"],
        ["param_ok_o", "1", "输出", "生效的 KP_D、KP_Q、I_START 都非 0"],
        ["fault_clr_o / soft_reset_o / enable_o / dir_o", "1", "输出", "CTRL 位"],
    ],
    [
        ["aw_addr / w_data / ar_addr", "32", "内部", "通道锁存"],
        ["wr_state / rd_state", "2", "内部", "AXI 握手状态"],
        ["shadow_*", "32", "内部", "每个控制寄存器一份影子"],
        ["active_*", "32", "内部", "谷点装入后的生效值"],
        ["pend", "1", "内部", "提交等待"],
        ["pend_theta / pend_speed / pend_seq", "32/32/16", "内部", "提交缓冲"],
        ["fault_clr_r", "1", "内部", "写 1 后保持到被取走"],
    ])

add_module("4.6.16 motor_ctrl_core",
    "结构模块。按第 4.3 和第 4.4 节连接子模块，并保存跨拍的电流和电压。对外端口就是第 4.7 节。这里只列核心自己的寄存器。",
    [
        ["见第 4.7 节", "—", "—", "引脚和 AXI 不在子模块之间重复列出"],
    ],
    [
        ["i_alpha_r / i_beta_r", "32", "内部", "谷点沿锁存的 Clarke 结果"],
        ["u_alpha_r / u_beta_r", "32", "内部", "计算相结束锁存的电压指令"],
        ["id_r / iq_r", "32", "内部", "计算相结束锁存，供回读"],
        ["calc_phase", "6", "内部", "计算相节拍，0 为空闲"],
        ["cordic_start / calc_done", "1", "内部", "送给 CORDIC 和 vlim/svpwm 的单拍"],
        ["s0_cnt", "2", "内部", "复位后 S0 次数，满 3 则 sinc_ready"],
    ])

add_module("4.6.17 top_integration",
    "把电机核心接到板级引脚，并把 s_axi 接到块设计里的互联。SFP、GTX 和 Aurora 使用已有模块，不在本模块里重写。MicroBlaze 与 UART 也在块设计中。本模块不含 MMCM。",
    [
        ["clk_in_i / rst_hw_n_i", "1", "输入", "板级时钟和复位"],
        ["amc_data_a/b/c_i", "1", "输入", "三路位流"],
        ["amc_mck_o", "1", "输出", "19.2 MHz"],
        ["pwm_uh/ul/vh/vl/wh/wl_o", "1", "输出", "六路门极"],
        ["ipm_fo_i", "1", "输入", "低有效"],
        ["led_o", "4", "输出", "bit0 运行，bit1 无感，bit2 故障，bit3 受理心跳"],
    ],
    [
        ["无算法寄存器", "—", "内部", "只有连线。受理心跳在核心内由 accept 翻转后送到 led[3]"],
    ])

add_heading("4.7 控制核心对外端口", 2)
add_para("下面是 motor_ctrl_core 的全部对外端口。子模块端口不直接出核心，除非在这里再次列出。",
         space_after=3)
make_table(
    ["端口", "位宽", "方向", "说明"],
    [
        ["clk_in_i", "1", "输入", "板级 100 MHz"],
        ["rst_hw_n_i", "1", "输入", "硬件复位，低有效"],
        ["amc_data_a/b/c_i", "1×3", "输入", "ΔΣ 位流"],
        ["amc_mck_o", "1", "输出", "19.2 MHz 调制时钟"],
        ["pwm_uh/ul/vh/vl/wh/wl_o", "1×6", "输出", "已含死区、极性和安全态"],
        ["ipm_fo_i", "1", "输入", "低有效故障"],
        ["s_axi_*", "AXI4-Lite", "从机", "SFP 通路和 MicroBlaze 共用"],
        ["led_o", "4", "输出", "状态灯"],
    ],
    widths=[6.2, 2.4, 1.6, 6.0],
    font_size=8,
)

# ================= 5 =================
add_heading("5 功能需求", 1)
make_table(
    ["编号", "优先级", "需求", "验收准则"],
    [
        ["FR-01", "P0", "三路 SINC3（OSR=256）抽取并标定为 Q31 电流",
         "直流位流与参考模型逐拍一致；群延迟 382 或 383 个调制时钟；控制只取 S0"],
        ["FR-02", "P0", "幅值不变 Clarke、Park、逆 Park",
         "第 7.1 节恒等在 Q31 下往返误差不超过 4 LSB；CORDIC 误差小于 2^-14"],
        ["FR-03", "P0", "25 kHz d/q PI、矢量限幅、两轴同时抗饱和",
         "限幅前后电压矢量角度误差不超过 4 LSB；冻结后积分器数值不变。仿真闭环带宽见第 6 章"],
        ["FR-04", "P0", "线性区中心对齐 SVPWM",
         "第 7.3 节两个向量的比较值与参考模型相差不超过 1 个计数"],
        ["FR-05", "P0", "死区、互锁、极性、FO 封锁",
         "任意拍不出现上下管同时导通；FO 确认后 10 个主时钟内进入安全态"],
        ["FR-06", "P0", "200 µs 寄存器事务：快照读出，提交电角度和电角速度",
         "同一次快照的四个量序号相同；附录 C 的换算在受理谷点与参考模型相差不超过 1 LSB；n>20 的提交不改变基准"],
        ["FR-07", "P0", "两次成功提交之间按谷点外推",
         "受理后的角度等于 θ_in 加 n 次 ω_step，再按 ANGLE_LEAD 超前，uint32 回绕"],
        ["FR-08", "P0", "定位、频率斜坡、判据切换、线性过渡",
         "T_ALIGN=0 时跳过定位；过渡期间角度走短弧；超 THETA_ABORT 进入 FAULT"],
        ["FR-09", "P0", "AXI4-Lite 寄存器与谷点影子装载",
         "第 8 章复位值正确；控制参数在写入后的第二个谷点之前不会半新半旧"],
        ["FR-10", "P0", "过流、缺相、堵转、FO、链路、切换失败",
         "第 11 章每一行至少一条仿真用例；屏蔽位有效"],
        ["FR-11", "P0", "第 9 章状态机",
         "使能撤销不进入 FAULT；故障清除时若使能仍为 1，则停在 FAULT"],
        ["FR-12", "P1", "回读测量量和 ILA 探针表",
         "第 8 章回读寄存器在仿真中与内部信号一致；探针表随阶段 4 交付"],
    ],
    widths=[1.6, 1.3, 5.6, 7.7],
    font_size=7.5,
)
add_para("解耦前馈和过调制不设 P0 需求。V0.2 把二者写进电流环和 SVPWM 的必须项，但没有公式。它们列入 P2：解耦需要 Rs、Ld、Lq、λf 和实时电压基值；过调制需要单独的六边形策略。P0 在线性区内切圆处限幅。",
         space_after=6)

# ================= 6 =================
add_heading("6 性能与延迟预算", 1)
make_table(
    ["指标", "基线", "依据"],
    [
        ["载波", "25 kHz，固定", "100 MHz / 4000；内含 3 个 OSR=256 窗口"],
        ["抽取率 / 控制采样", "75 kHz / 25 kHz", "只用对齐谷点的 S0"],
        ["SINC3 群延迟", "19.922 µs", "382.5 / 19.2 MHz"],
        ["计算到装载", "1 个载波周期，40 µs", "谷点 k 的结果在谷点 k+1 装载"],
        ["调制中心", "装载后再过 20 µs", "中心对齐半周期"],
        ["采样到调制中心", "约 80 µs", "19.9 µs 群延迟 + 40 µs 装载 + 20 µs 到载波中心"],
        ["角度默认超前", "2 个 ω_step", "80 µs 约等于 2 个载波。ANGLE_LEAD 复位为 2"],
        ["电流环设计带宽", "1.5 kHz", "80 µs 在 1.5 kHz 处约 43°。5 kHz 处约 144°，仍不作验收"],
        ["仿真验收带宽", "占位电机上不小于 1.5 kHz", "附录 B，扫频或等效阶跃"],
        ["观测器更新", "MCU 每 200 µs 经 SFP 读写寄存器", "看门狗复位值 600 µs，可错过一次中断"],
        ["FO 到安全态", "不超过 10 个 100 MHz 时钟", "含 3 拍滤波"],
        ["死区", "500～5000 ns，默认 2000 ns", "按 100 MHz 换算，余数截断"],
    ],
    widths=[3.6, 5.4, 7.2],
    font_size=8,
)
add_para("OSR=256 把滤波器群延迟从约 60 µs 降到 19.9 µs。一拍装载和半拍调制中心仍然在，总延迟约 80 µs。"
         "因此确认 OSR=256 之后，设计带宽定为 1.5 kHz，而不是 5 kHz。",
         space_after=6)

# ================= 7 =================
add_heading("7 控制算法", 1)
add_heading("7.1 坐标变换", 2)
add_mono("""iα = ia
iβ = (ia + 2·ib) / √3
id =  iα·cosθ + iβ·sinθ
iq = -iα·sinθ + iβ·cosθ
uα = ud·cosθ - uq·sinθ
uβ = ud·sinθ + uq·cosθ""")
add_para("电流正方向为流入电机。传感器方向相反时把 SCALE_I 写成负数。θ 使用 UQ32，实现时先把角度折算到 CORDIC 的象限，再做旋转。",
         space_after=4)

add_heading("7.2 电流控制器", 2)
add_para("寄存器中的 Kp、Ki 是离散系数。主机按下面的式子换算后写入，RTL 只做乘加。Z_BASE = U_BASE / I_BASE，U_BASE = VDC_NOM / √3，Ts = 40 µs。设计带宽用 ωc = 2π·1500 rad/s。",
         space_after=2)
add_mono("""Kp_pu = ωc · L / Z_BASE
Ki_pu = ωc · Rs / Z_BASE · Ts
Kp_reg = round(Kp_pu · 2^16)
Ki_reg = round(Ki_pu · 2^16)""")
add_para("Rs、L 未提供时寄存器保持 0，状态机不允许进入 I-F。两轴 Ki 可以使用同一套公式。Ld 与 Lq 的差异留在已排除的解耦前馈里。",
         space_after=4)
add_para("抗饱和只使用 vlim 的冻结信号。两个 PI 要么同时积分，要么同时保持，避免一轴单独饱和把电压矢量角拉开。",
         space_after=4)

add_heading("7.3 SVPWM", 2)
add_para("uα、uβ 的 1.0 标幺定义为相电压基波峰值等于 Vdc/√3，也就是六边形内切圆。先做第 7.1 节的逆 Clarke，得到同一标幺下的 ua、ub、uc，再注入零序：",
         space_after=2)
add_mono("""uzs = -0.5 · (max(ua,ub,uc) + min(ua,ub,uc))
da = saturate(0.5 + (ua + uzs) / √3, 0, 1)
db、dc 同样计算
compare = round(d · PWM_PEAK)""")
add_para("该式与七段式中心对齐 SVPWM 等价。P0 不把矢量推到六边形边上。vlim 已把 |u| 限制在 U_MAX≤1。若舍入仍使比较值超出 0～PWM_PEAK，钳位到端点。",
         space_after=3)
add_para("验收向量，死区关闭、PWM_PEAK=2000：", space_after=2)
make_table(
    ["uα", "uβ", "da, db, dc", "compare"],
    [
        ["0", "0", "0.5, 0.5, 0.5", "1000, 1000, 1000"],
        ["√3/2", "0.5", "1, 0.5, 0", "2000, 1000, 0"],
    ],
    widths=[3.5, 3.0, 4.5, 5.2],
    font_size=8,
)
add_para("第二个向量在扇区中心，线性区边界上的占空比触及 0 和 1。RTL 与参考模型允许差 1 个计数。",
         space_after=4)

add_heading("7.4 角度时间契约", 2)
add_para("THETA_IN 是 SEQ_ECHO 那一拍 S0 的电角度，不是写寄存器瞬间的角度。MCU 用刚读到的电压、电流完成估计后，把角度、电角速度和那个 SNAP_SEQ 一起提交。FPGA 在受理谷点把角度推进到当前谷点：",
         space_after=2)
add_mono("""ω_step = (SPEED_IN × 1791925356) >> 32     // 64 位乘法，SPEED_IN 为 Q16.16 rad/s
n = uint16(valley_now - SEQ_ECHO)               // 仅 0～20 有效
θ_now = uint32(THETA_IN + n × ω_step)
此后每个谷点：θ_now = uint32(θ_now + ω_step)
θ_park = uint32(θ_now + ANGLE_LEAD × ω_step)""")
add_para("常数 1791925356 = round(2^48 × 40 µs / 2π)。1000 rad/s 电角速度对应每拍 27342611 个角度 LSB，约 100 Hz 电频率时每拍 17179869。右移结果与参考模型相差不超过 1 LSB。",
         space_after=3)
add_para("ANGLE_LEAD 复位为 2，只补偿第 6 章约 80 µs 的采样到调制中心延迟。MCU 中断和 SFP 访问造成的滞后由序号差 n 补偿，不重复加进 ANGLE_LEAD。",
         space_after=4)

add_heading("7.5 I-F 与切换", 2)
add_bullet("DIR=0：电频率向正方向增加，iq 目标为 +I_START。DIR=1：二者都为负。id 目标在 I-F 期间为 0。")
add_bullet("进入 IF_ALIGN 后，用 I_SLEW_N 个谷点把 iq 从 0 斜坡到目标，避免阶跃打到过流。")
add_bullet("T_ALIGN 个谷点内 θ_if=0。T_ALIGN=0 则直接进入斜坡。")
add_bullet("斜坡：电频率每拍增加 DFDT×Ts，用余数累加保证长期平均频率等于设定值。θ_if 每拍增加 f×Ts 对应的 UQ32。")
add_bullet("切换判据使用环绕到 [-0.5, 0.5) 的角度差。没有新的成功提交时，确认计数清零，不允许切换。")
add_bullet("过渡开始时锁存环绕角差 Δ。第 n 拍 θ = θ_if + Δ·n/BLEND_N，电流指令按同一比例从 I-F 指令走到寄存器指令。θ_if 在过渡期间继续积分。")
add_bullet("过渡中若环绕角差绝对值大于 THETA_ABORT，置切换失败故障。")
add_para("电频率到角度、DFDT 到电频率的定点余数算法在参考模型中一次写死，RTL 与该模型逐拍一致。规格书不另写一套舍入。",
         space_after=6)

# ================= 8 =================
add_heading("8 寄存器", 1)
add_para("基地址由 Block Design 决定。下表偏移是字节地址。未列出的偏移保留，读为 0。电流、电压、角度阈值是 Q31 或 UQ32；时间类寄存器的单位是谷点拍数，25 kHz 下 25000 拍 = 1 s。",
         space_after=4)
make_table(
    ["偏移", "名称", "访问", "复位值", "说明"],
    [
        ["0x00", "ID", "R", "0x464F4331", "字符 FOC1"],
        ["0x04", "VERSION", "R", "0x00010000", "RTL 1.0.0，与文档版本分开"],
        ["0x08", "CTRL", "R/W", "0", "bit0 ENABLE；bit2 SOFT_RST；bit3 FAULT_CLR 脉冲；bit4 DIR"],
        ["0x0C", "STATUS", "R", "0", "见 8.1"],
        ["0x10", "FAULT", "R", "0", "见第 11 章，粘滞"],
        ["0x14", "FAULT_MASK", "R/W", "0x020E", "bit1/2/3/9 复位为 1，屏蔽过压、欠压、过温和抽取饱和"],
        ["0x18", "PWM_CFG", "R/W", "0", "bit0 极性取反。载波峰值固定，不在此寄存器修改"],
        ["0x1C", "PWM_PEAK", "R", "2000", "只读"],
        ["0x20", "DEADTIME_NS", "R/W", "2000", "钳位到 500～5000"],
        ["0x24", "ID_REF", "R/W", "0", "Q31，无感态使用"],
        ["0x28", "IQ_REF", "R/W", "0", "Q31，无感态使用"],
        ["0x2C", "KP_D", "R/W", "0", "Q16.16"],
        ["0x30", "KI_D", "R/W", "0", "Q16.16，已含 Ts"],
        ["0x34", "KP_Q", "R/W", "0", "Q16.16"],
        ["0x38", "KI_Q", "R/W", "0", "Q16.16，已含 Ts"],
        ["0x3C", "U_MAX", "R/W", "0x7FFFFFFF", "Q31 电压矢量限幅"],
        ["0x40", "I_CMD_MAX", "R/W", "0x73333333", "电流指令矢量限幅，约 0.9 pu"],
        ["0x44", "SCALE_I", "R/W", "0x00010000", "Q16.16，复位表示 I_FS=I_BASE"],
        ["0x48", "DATA_INV", "R/W", "0", "bit0/1/2 分别取反 A/B/C"],
        ["0x4C", "DEC_PHASE", "R/W", "0", "0～255，相对谷点移动 S0 窗口"],
        ["0x50", "OC_TH", "R/W", "0x79999999", "相电流绝对值阈值，约 0.95 pu"],
        ["0x54", "OC_N", "R/W", "2", "连续超限拍数"],
        ["0x58", "PH_TH", "R/W", "0x0CCCCCCD", "零序阈值，约 0.1 pu"],
        ["0x5C", "PH_N", "R/W", "10", "连续拍数"],
        ["0x60", "I_START", "R/W", "0x26666666", "约 0.3 pu"],
        ["0x64", "I_SLEW_N", "R/W", "2500", "100 ms"],
        ["0x68", "DFDT", "R/W", "0", "Q16.16，电频率 Hz/s。0 表示不加速"],
        ["0x6C", "T_ALIGN", "R/W", "12500", "0.5 s；写 0 跳过定位"],
        ["0x70", "W_SWITCH", "R/W", "1717987", "|ω_step| 阈值，约 10 Hz 电频率"],
        ["0x74", "THETA_WIN", "R/W", "85899346", "UQ32，0.02 周，约 7.2° 电角度"],
        ["0x78", "SWITCH_N", "R/W", "10", "连续成功提交次数"],
        ["0x7C", "BLEND_N", "R/W", "200", "8 ms"],
        ["0x80", "THETA_ABORT", "R/W", "644245094", "UQ32 绝对值比较用 0.15 周"],
        ["0x84", "STALL_T_IF", "R/W", "125000", "启动到进入无感的时限，5 s"],
        ["0x88", "STALL_T_RUN", "R/W", "12500", "运行中堵转确认，0.5 s"],
        ["0x8C", "W_STALL", "R/W", "171799", "|ω_step| 低于约 1 Hz"],
        ["0x90", "I_STALL", "R/W", "0x1999999A", "|iq_ref| 高于约 0.2 pu 才判运行堵转"],
        ["0x94", "LINK_TO", "R/W", "15", "距上次成功提交的谷点上限，15 拍 = 600 µs"],
        ["0x98", "ANGLE_LEAD", "R/W", "2", "有符号 8 位，符号扩展保存"],
        ["0x9C", "VDC_NOM", "R/W", "0x01360000", "Q16.16 伏，310 V。P0 只给主机换算和记录"],
        ["0xA0", "I_BASE", "R/W", "0x00140000", "Q16.16 安，复位占位 20 A。P0 控制律不乘这个数"],
        ["0xA4", "OV_TH", "R/W", "0", "保留。屏蔽期间不动作"],
        ["0xA8", "UV_TH", "R/W", "0", "保留"],
        ["0xAC", "OT_TH", "R/W", "0", "保留"],
        ["0xB0", "OBS_CFG", "R/W", "1", "bit0=1 才受理提交。周期由 MCU 的 200 µs 中断决定"],
        ["0xB4", "OBS_AGE", "R", "0", "距上次成功提交的谷点数"],
        ["0xC0", "IA", "R", "—", "Q31"],
        ["0xC4", "IB", "R", "—", "Q31"],
        ["0xC8", "IC", "R", "—", "Q31"],
        ["0xCC", "IALPHA", "R", "—", "Q31"],
        ["0xD0", "IBETA", "R", "—", "Q31"],
        ["0xD4", "ID", "R", "—", "Q31"],
        ["0xD8", "IQ", "R", "—", "Q31"],
        ["0xDC", "UALPHA", "R", "—", "Q31"],
        ["0xE0", "UBETA", "R", "—", "Q31"],
        ["0xE4", "THETA_PARK", "R", "—", "UQ32，本拍实际使用角"],
        ["0xE8", "THETA_OBS", "R", "—", "UQ32"],
        ["0xEC", "OMEGA_STEP", "R", "—", "最近一次受理后换算出的每谷点步长"],
        ["0xF0", "VALLEY_CNT", "R", "—", "当前谷点序号低 16 位"],
        ["0x100", "SNAP_SEQ", "R", "0", "快照所属谷点序号，低 16 位"],
        ["0x104", "SNAP_UALPHA", "R", "0", "该序号的 uα，Q31"],
        ["0x108", "SNAP_UBETA", "R", "0", "该序号的 uβ，Q31"],
        ["0x10C", "SNAP_IALPHA", "R", "0", "该序号的 iα，Q31"],
        ["0x110", "SNAP_IBETA", "R", "0", "该序号的 iβ，Q31"],
        ["0x114", "THETA_IN", "R/W", "0", "待提交电角度，UQ32。写后保持到受理或被新值覆盖"],
        ["0x118", "SPEED_IN", "R/W", "0", "待提交电角速度，Q16.16，单位 rad/s"],
        ["0x11C", "SEQ_ECHO", "R/W", "0", "THETA_IN 对应的 SNAP_SEQ，低 16 位"],
        ["0x120", "OBS_COMMIT", "R/W", "0", "写 1 提交上述三项。读 bit0=1 表示尚未到谷点受理"],
        ["0x124", "OBS_DROP_CNT", "R", "0", "因 n>20 被丢弃的提交次数，低 16 位饱和"],
    ],
    widths=[1.5, 3.2, 1.4, 2.8, 7.3],
    font_size=7,
)

add_para("MCU 的 200 µs 事务只使用 0x100～0x120。0xC0 以后的实时回读会在两次 AXI 读之间被新的谷点改写，不能当作同一次快照。",
         space_after=4)

add_heading("8.1 CTRL 与 STATUS", 2)
add_para("CTRL 只保留使能、软复位、故障清除和方向。V0.2 的 bit1“运行模式”删除。运行模式由状态机产生，主机不能把角度源直接拨到无感。",
         space_after=3)
add_para("STATUS[3:0] 为状态编码。bit4 为 pwm_enable，bit5 为 link_ok，bit6 为 param_ok，bit7 为电压限幅，bit8 为 DIR 回读，bit9 为抽取饱和实时标志。"
         "bit15:10 保留。bit31:16 为优先码，数值等于第 11 章的故障位号；无故障时为 65535。",
         space_after=6)

# ================= 9 =================
add_heading("9 状态机", 1)
make_table(
    ["编码", "状态", "PWM", "角度与电流指令", "离开条件"],
    [
        ["0", "INIT", "安全态", "不运行 PI", "MMCM 锁定且 SINC 已输出至少 3 拍 → READY"],
        ["1", "READY", "安全态", "不运行 PI", "ENABLE=1 且 param_ok=1 且无粘滞故障 → IF_ALIGN"],
        ["2", "IF_ALIGN", "使能", "θ=0，电流斜坡到 I_START", "满 T_ALIGN → IF_RAMP。T_ALIGN=0 时同一拍离开"],
        ["3", "IF_RAMP", "使能", "θ_if 积分，电流保持 I_START", "switch_req → SWITCH"],
        ["4", "SWITCH", "使能", "角度短弧过渡，电流指令过渡", "BLEND_N 完成 → SENSORLESS"],
        ["5", "SENSORLESS", "使能", "θ_park，寄存器电流指令", "ENABLE=0 → READY"],
        ["6", "FAULT", "安全态", "PI 积分清零", "FAULT_CLR 且故障源已消失且 ENABLE=0 → READY"],
    ],
    widths=[1.3, 2.4, 1.8, 5.2, 5.5],
    font_size=7.5,
)
add_para("ENABLE 从 1 变 0 时，IF_ALIGN、IF_RAMP、SWITCH、SENSORLESS 都进入 READY，不进入 FAULT，PWM 同一拍进入安全态。", space_after=3)
add_para("任一未屏蔽故障在 INIT 以外出现时进入 FAULT。INIT 期间出现的 FO 保持到 READY 之后仍有效，并立即进入 FAULT。", space_after=3)
add_para("FAULT 中若只写 FAULT_CLR 而 ENABLE 仍为 1，状态保持 FAULT。必须先撤使能，再清除，然后重新使能，才允许再次启动。", space_after=3)
add_para("SOFT_RST 在任何状态把机器拉回 INIT，清故障锁存、PI 积分和观测器基准。", space_after=6)

# ================= 10 =================
add_heading("10 时序、报文与跨域", 1)
add_heading("10.1 谷点时序", 2)
add_bullet("三角计数到 0 时产生 pwm_tick，并锁存 S0 对应的 Ia/Ib/Ic。")
add_bullet("同一拍装载上一拍算好的比较值，影子装载寄存器，锁存上行 u、i。")
add_bullet("本拍剩余时间完成 Clarke、角度选择、Park、PI、限幅、逆 Park、占空比计算，结果供下一个谷点装载。")
add_bullet("OBS_COMMIT 可以在任意主时钟把提交置为待受理。换算、序号差判断和外推只在谷点进行。")
add_para("计算流水在 40 µs 内结束。100 MHz 下有 4000 个时钟。若综合后单拍组合过长，允许在模块间插入流水，但谷点到下一个谷点的输入输出关系必须保持第 7、9 章的定义。",
         space_after=4)

add_heading("10.2 MCU 的 200 µs 事务", 2)
add_para("每次中断按附录 C 的顺序访问寄存器。快照在谷点更新；中断与谷点不必对齐。读完四个数据后再读一次 SNAP_SEQ，两次序号不一致就丢弃这次读数并重读。写 OBS_COMMIT 之后，FPGA 最迟在下一个谷点给出受理或丢弃。",
         space_after=4)

add_heading("10.3 跨时钟", 2)
add_bullet("100 MHz 与 19.2 MHz 同源。抽取结果用锁定后的同步握手传递，这条路径不使用异步 FIFO。")
add_bullet("AXI 与核心同为 100 MHz。")
add_bullet("SFP 与 Aurora 的用户时钟停在已有通路里。进入电机核心的只有 clk_100m 域的 AXI 读写。")
add_bullet("FO 同步链在 100 MHz。")

# ================= 11 =================
add_heading("11 保护", 1)
make_table(
    ["位", "名称", "置位条件", "武装状态", "复位屏蔽"],
    [
        ["0", "过流", "任一相 |i| > OC_TH 连续 OC_N 拍", "除 INIT 外", "不屏蔽"],
        ["1", "过压", "保留，无 ADC 时不置位", "—", "屏蔽"],
        ["2", "欠压", "保留，无 ADC 时不置位", "—", "屏蔽"],
        ["3", "过温", "保留，无 ADC 时不置位", "—", "屏蔽"],
        ["4", "堵转", "启动：进入 IF_ALIGN 后 STALL_T_IF 拍仍未到 SENSORLESS。运行：无感态 |ω_step|<W_STALL 且 |iq_ref|>I_STALL 连续 STALL_T_RUN 拍",
         "启动三段 / 无感态", "不屏蔽"],
        ["5", "缺相", "|ia+ib+ic| > PH_TH 连续 PH_N 拍", "PWM 使能期间", "不屏蔽"],
        ["6", "FO", "滤波后的 FO 为低", "锁定后始终", "不屏蔽"],
        ["7", "链路", "link_age > LINK_TO", "SWITCH 与 SENSORLESS", "不屏蔽"],
        ["8", "切换失败", "if_startup.switch_fail", "SWITCH", "不屏蔽"],
        ["9", "抽取饱和", "sinc_ovf。实时状态在 STATUS.bit9；屏蔽时不锁存、不封锁", "PWM 使能期间可观察", "屏蔽"],
    ],
    widths=[1.0, 2.0, 7.2, 3.2, 1.8],
    font_size=7,
)
add_para("故障锁存直到清除。清除脉冲只清掉当前已经不成立的故障源；FO 仍为低或电流仍超限时，对应位保持，状态保持 FAULT。", space_after=3)
add_para("优先码按位号 6、0、7、8、5、4、1、2、3、9 的顺序取第一个已置位的位，写入 STATUS 高半字。这个顺序只影响显示。", space_after=3)
add_para("软件过流的响应是一个载波周期量级，不能代替 IPM 的硬件短路保护。FO 是快速通道。", space_after=6)

# ================= 12 =================
add_heading("12 修订对照与待确认项", 1)
add_heading("12.1 V0.2 中已在本版写死的问题", 2)
make_table(
    ["V0.2 表述", "问题", "现行口径"],
    [
        ["电流 Q31，单位 A", "Q31 是满量程分数，不是安培", "Q31 为相对 I_BASE 的标幺；安培换算在主机侧用 I_BASE"],
        ["θ 为 Q31，0～1 对应 0～2π", "有符号 Q31 不能表示完整的 [0,1)", "θ 使用 UQ32"],
        ["θ 直接加 ω·k·Tpwm", "ω 若是 rad/s 或另一套 Q31，量纲不相加", "下行改为 ω_step，LSB 与 UQ32 相同"],
        ["载波计数模 4000，又写三角波", "锯齿 4000 是边沿对齐；中心对齐峰值是 2000", "三角波峰值 2000，周期 4000 个时钟"],
        ["载波可调 20～30 kHz", "一改频率，3 个 OSR 窗口就不再等于一个载波", "固定 25 kHz，MCK 固定 19.2 MHz"],
        ["电流环带宽 ≥5 kHz", "群延迟加上 PWM 更新后，5 kHz 相位不够", "OSR=256 后设计带宽 1.5 kHz，验收不低于 1.5 kHz"],
        ["SINC 输出取高 32 位", "忽略抽取增益", "OSR=256 时右移 24 位，再乘 SCALE_I"],
        ["支持解耦前馈；支持过调制", "没有公式、系数和限幅定义", "降为 P2，P0 只做 PI 和内切圆限幅"],
        ["逐轴输出限幅", "两轴分别饱和会转动电压矢量", "矢量缩放，两轴同时冻结积分"],
        ["Aurora 已完成，同时把 GTX 和 CRC 设计进新模块", "范围边界不清", "核心只提供 AXI 寄存器。SFP 帧由已有通路处理"],
        ["本地 5 kHz 与 MCU 触发并存", "电流环时基和观测器时基被写成同一个", "电流环只认谷点。MCU 每 200 µs 读写寄存器"],
        ["帧长“如 32B / 16B”", "不能编码", "取消单独观测帧。交换内容就是附录 C 的寄存器事务"],
        ["CTRL.bit1 选择 I-F 或无感", "与状态机抢角度源", "删除该位，模式只由状态机输出"],
        ["使能=0 去 FAULT 或 READY", "斜杠两边都成立", "运行中撤使能去 READY；故障才去 FAULT"],
        ["平滑切换", "没有时间、路径和失败条件", "BLEND_N 短弧过渡，THETA_ABORT 失败"],
        ["寄存器偏移 0x01 且一项占两项", "无法判断是字地址还是双寄存器", "全部改为字节地址，一字一项"],
        ["FO 既要去抖又要立即封锁", "去抖时间未定义", "3 个主时钟滤波，总延迟 ≤10 拍"],
        ["过压过温为 P0，ADC 又可省略", "没有采样协议", "寄存器保留并默认屏蔽，本阶段不接 ADC"],
        ["I-F 开环", "容易做成电压开环 V/f", "明确为电流闭环、角度开环"],
        ["母线 310 V 已确认，电机参数空白", "PI 和保护阈值无法从物理单位算出", "控制内部用标幺；物理参数只用于主机写寄存器，不阻塞 RTL 结构"],
    ],
    widths=[4.3, 5.5, 6.4],
    font_size=7,
)

add_heading("12.2 确认结果", 2)
make_table(
    ["编号", "结论", "对正文的影响"],
    [
        ["C1", "OSR=256", "MCK 改为 19.2 MHz，每个载波 3 个窗口，控制取 S0。设计带宽 1.5 kHz"],
        ["C2", "只做线性区电流环", "解耦前馈和过调制保持在范围外"],
        ["C3", "本阶段不采母线电压和温度", "OV/UV/OT 保持屏蔽，占空比用标幺"],
        ["C4", "MCU 每 200 µs 经 SFP 读写寄存器", "读快照 u、i，写电角度、电角速度和样本序号，再提交。见附录 C"],
        ["C5", "交付 MicroBlaze 裸机例程", "范围增加第 14.6 节，阶段 5 增加 3 人日"],
        ["C6", "高有效，死区 2.0 µs，FO 低有效", "与 PWM 章复位值一致，安全态为六路低"],
    ],
    widths=[1.4, 5.8, 9.0],
    font_size=8,
)
add_para("电机 Rs、Ld、Lq、λf、极对数、额定电流、额定转速、分流电阻和 AMC1306 后缀需要在上电写寄存器前提供。缺少这些数时，仿真使用附录 B，RTL 仍按标幺开发。它们不单列成阻塞编码的确认项。",
         space_after=6)

# ================= 13 =================
add_heading("13 风险与关闭方式", 1)
make_table(
    ["编号", "风险", "关闭方式"],
    [
        ["R1", "角度用于下一拍 PWM 时已经变旧", "θ 对应该次读到的 SNAP_SEQ；序号差推进到当前谷点；ANGLE_LEAD 默认 2"],
        ["R2", "SFP 到 AXI 的转发若经过软件，可能超过 200 µs", "实时通路必须在下一次中断前完成附录 C 的读写。做不到时改用硬件主设备，不改电机算法"],
        ["R3", "I-F 切入观测角时失步", "短弧 BLEND_N、电流同步过渡、THETA_ABORT 和启动超时"],
        ["R4", "低速 SMO 角不可用", "W_SWITCH 以下禁止切换；obs 无效时清零确认计数"],
        ["R5", "80 µs 延迟下把带宽写成 5 kHz", "验收停在 1.5 kHz。OSR=256 已经用在缩短滤波器延迟，不再承诺 5 kHz"],
        ["R6", "无母线采样时，实际 Vdc 偏离 310 V 会改变电流响应", "P0 电压为占空比标幺，环路增益随真实 Vdc 变化。验收在标称 310 V 植物上进行，并在限制条款中写明"],
        ["R7", "缺相判据在传感器增益不一致时误动作", "PH_TH 可调，默认 0.1 pu。上电后用开环定位电流核对 ia+ib+ic"],
        ["R8", "死区造成的电压误差进入观测器", "P0 上行的是指令电压。死区补偿列为 P2，联调记录里单列这一项误差"],
    ],
    widths=[1.3, 6.5, 8.4],
    font_size=7.5,
)

# ================= 14 =================
add_heading("14 工程开发规划", 1)
add_para("计划按 1 名熟悉 FOC 的 FPGA 工程师估算，单位是人日，不是日历承诺。算法评审在阶段 1 结束时进行，约 0.5 人日。"
         "电机台架、Aurora 核和 SFP 成帧不在本计划内。电机侧要交付的是快照、提交和 200 µs 事务，已经包含在下面的人日里。",
         space_after=4)

add_heading("14.1 阶段与出口", 2)
make_table(
    ["阶段", "人日", "工作", "出口条件"],
    [
        ["0 需求基线", "1", "记录 C1–C6，含 200 µs 寄存器事务", "可以进入阶段 1"],
        ["1 参考模型", "5", "Python 定点模型、浮点对照、黄金向量", "第 15 章模型类用例通过，向量文件入库"],
        ["2 RTL 单元", "12", "按 14.3 的顺序编码和 XSIM 单元仿真", "P0 模块与向量逐拍或按容差通过"],
        ["3 集成", "6", "核心集成、回环观测器、故障注入、Python 闭环", "第 15 章集成类用例通过"],
        ["4 实现", "4", "Vivado 工程、XDC、综合实现、ILA 探针表", "clk_100m 时序收敛，资源低于 30%"],
        ["5 联调包与裸机", "5", "reg_map.h、上电顺序、第 14.6 节例程、抓波说明", "例程能读写寄存器、启动、停止、清故障并打印状态"],
    ],
    widths=[2.6, 1.4, 6.4, 5.8],
    font_size=7.5,
)
add_para("合计约 33 人日。SFP 帧处理沿用已有工程。若实测一次寄存器事务超过 200 µs，再单独立项改访问通路。",
         space_after=4)

add_heading("14.2 目录与编码约定", 2)
add_mono("""rtl/clk_rst_mgmt.v
rtl/amc1306_if.v
rtl/clarke.v
rtl/cordic_sincos.v
rtl/park_ipark.v
rtl/pi_ctrl.v
rtl/vlim.v
rtl/svpwm.v
rtl/theta_interp.v
rtl/if_startup.v
rtl/cmd_mux.v
rtl/protect.v
rtl/sys_fsm.v
rtl/obs_port.v
rtl/axi_regs.v
rtl/motor_ctrl_core.v
rtl/top_integration.v
sim/ref_model/          Python 包，定点算法的唯一舍入定义
sim/vectors/            由参考模型生成，RTL 只读
sim/tb/                 每个 P0 模块一个测试平台
constraints/motor.xdc
sw/reg_map.h
sw/mb_shell/
vivado/create_project.tcl""")
add_bullet("单个时钟域内使用同步 rst_n，不使用锁存器，不在组合逻辑里做算术反馈。")
add_bullet("定点舍入只存在于参考模型；RTL 注释标明对应的 Python 函数名。")
add_bullet("Vivado 工程文件可由 tcl 重建。xpr 和生成网表不作为规格的一部分。")

add_heading("14.3 实现顺序", 2)
add_para("顺序按数据依赖排列。前一项没有向量之前不写下一项的比较逻辑。clk_rst_mgmt 和 axi_regs 可以在阶段 1 后半与模型并行，因为它们不含控制舍入。",
         space_after=3)
add_bullet("定标常量、CRC、帧：参考模型基础设施。")
add_bullet("clarke、park、cordic、pi、vlim、svpwm。")
add_bullet("amc1306_if 的直流、斜坡和延迟。")
add_bullet("theta_interp、if_startup、cmd_mux。")
add_bullet("protect、sys_fsm。")
add_bullet("obs_port 的快照和提交，然后集成 motor_ctrl_core。")
add_bullet("top_integration 在阶段 4 连接 MMCM、引脚和 Aurora 适配。")

add_heading("14.4 需求追溯", 2)
make_table(
    ["需求", "模块", "主要测试"],
    [
        ["FR-01", "amc1306_if", "TC-ADC-01 直流增益；TC-ADC-02 群延迟与三通道独立"],
        ["FR-02", "clarke, cordic_sincos, park_ipark", "TC-PARK-01 往返；TC-CORDIC-01 误差"],
        ["FR-03", "pi_ctrl, vlim", "TC-PI-01 冻结；TC-VLIM-01 角度保持；TC-LOOP-01 带宽"],
        ["FR-04", "svpwm", "TC-SVPWM-01 第 7.3 节向量"],
        ["FR-05", "svpwm, protect", "TC-SVPWM-02 互锁与死区；TC-FO-01 封锁延迟"],
        ["FR-06 / FR-07", "obs_port, theta_interp, axi_regs", "TC-OBS-01 快照一致；TC-OBS-02 提交与丢弃；TC-TH-01 外推"],
        ["FR-08", "if_startup, cmd_mux", "TC-IF-01 定位跳过、短弧、中止"],
        ["FR-09 / FR-12", "axi_regs", "TC-AXI-01 复位值、影子装载、保留地址"],
        ["FR-10", "protect", "TC-PROT-01 到 TC-PROT-06，每个未屏蔽故障一条"],
        ["FR-11", "sys_fsm", "TC-FSM-01 撤使能；TC-FSM-02 清除互锁"],
    ],
    widths=[2.6, 5.4, 8.2],
    font_size=7.5,
)

add_heading("14.5 阶段内容", 2)
add_para("阶段 1 把第 7 章写成可执行模型。浮点模型只用于对照误差，定点模型才是 RTL 的基准。每个黄金向量文件包含输入、输出和允许误差。CORDIC 与 SVPWM 比较值使用第 5 章的容差，其余控制递归要求逐拍相同。",
         space_after=3)
add_para("阶段 2 的测试平台读取向量文件，不在 Verilog 里复制一套算法。发现不一致时先判断规格、模型、RTL 哪一侧偏离第 7 章，再改那一侧。",
         space_after=3)
add_para("阶段 3 的电流闭环分两层。第一层在 Python 中把定点控制器接到附录 B 的电机和理想逆变器上，检查阶跃、限幅和 I-F 切换。第二层在 XSIM 中把 motor_ctrl_core 接到理想压控电压源和 RL 负载，观测器使用桩：每 5 个谷点按附录 C 写入该快照序号对应的真值角度和电角速度。完整电机的每拍协仿真不是 P0 出口。",
         space_after=3)
add_para("阶段 4 约束 100 MHz 和 19.2 MHz，引脚在板级原理图确定前使用占位 XDC，并在文件头标明占位。ILA 至少能抓取 ia、ib、id、iq、theta_park、pwm 比较值、state 和 fault。探针表写入联调说明，不把调试核当作控制路径。",
         space_after=3)
add_para("阶段 5 的上电顺序固定为：写 SCALE、保护阈值和 I-F 参数，写 Kp/Ki，确认 STATUS.param_ok，撤使能并清除故障，最后置 ENABLE。示例数值使用附录 B，并标注不能直接用于未知电机。",
         space_after=4)

add_heading("14.6 裸机例程", 2)
add_para("例程运行在 Block Design 里的 MicroBlaze 上，UART 为 115200 8N1。固件不写死电机参数，只搬运寄存器。命令如下：",
         space_after=3)
add_bullet("r <地址>：读一个 32 位寄存器并用十六进制打印。")
add_bullet("w <地址> <数据>：写一个寄存器。地址和数据都是十六进制。")
add_bullet("start：FAULT 为 0 且 param_ok 为 1 时把 ENABLE 置 1，否则打印拒绝原因。")
add_bullet("stop：把 ENABLE 清 0。")
add_bullet("clear：仅在 ENABLE 为 0 时脉冲 FAULT_CLR。")
add_bullet("dump：打印 STATUS、FAULT、IA、IB、IC、ID、IQ、THETA_PARK、OMEGA_STEP、OBS_AGE、SNAP_SEQ。")
add_para("验收：在没有电机、观测端口由桩或常量驱动时，例程能完成写参数、start、dump、stop、clear。这不代替第 15 章的 RTL 用例。",
         space_after=6)

# ================= 15 =================
add_heading("15 验证与验收", 1)
add_heading("15.1 模型与 RTL", 2)
make_table(
    ["用例", "检查"],
    [
        ["TC-ADC-01", "恒定全 1 与全 0 位流分别归一化到 +SCALE 与 -SCALE，误差 0 LSB"],
        ["TC-ADC-02", "阶跃位流的群延迟为 382 或 383 个调制时钟；一个载波只采用 S0；B、C 在 A 激励时保持 0"],
        ["TC-PARK-01", "随机 αβ 与角度做 Park 再逆变换，电流误差 ≤4 LSB"],
        ["TC-CORDIC-01", "32 个均匀角度的 sin、cos 与浮点绝对误差 < 2^-14"],
        ["TC-PI-01", "限幅冻结后积分器保持；解除后继续累加"],
        ["TC-VLIM-01", "过幅输入的输出幅值不超过 U_MAX，角度相对输入变化 ≤4 LSB"],
        ["TC-SVPWM-01", "第 7.3 节两个向量，比较值误差 ≤1"],
        ["TC-SVPWM-02", "死区 200 拍内六路无上下管同时为导通电平；enable=0 时立即安全态"],
        ["TC-FO-01", "FO 拉低后不超过 10 个主时钟进入安全态；2 个时钟的毛刺不封锁"],
        ["TC-OBS-01", "一个谷点内连读 SNAP_SEQ 与 u、i，序号不变且等于该谷点；跨谷点后序号加 1"],
        ["TC-OBS-02", "按附录 C 提交后，受理谷点的 θ_now 与参考模型相差不超过 1 LSB；n=21 时基准不变且 OBS_DROP_CNT 加 1"],
        ["TC-TH-01", "受理之后每个谷点增加一个 ω_step；结果按 uint32 回绕"],
        ["TC-IF-01", "T_ALIGN=0 不停留；角度差 +0.9 周按 -0.1 周过渡；超 THETA_ABORT 故障"],
        ["TC-AXI-01", "复位值符合第 8 章；谷点前 RTL 仍用旧 Kp；保留地址读 0"],
        ["TC-FSM-01", "SENSORLESS 撤 ENABLE 到 READY，FAULT 位为 0"],
        ["TC-FSM-02", "故障仍在时 FAULT_CLR 无效；ENABLE 未撤时不能回 READY"],
        ["TC-PROT-01", "单相过流连续 2 拍封锁，1 拍超限不封锁"],
        ["TC-PROT-02", "零序超限 10 拍置缺相"],
        ["TC-PROT-03", "启动超过 STALL_T_IF 置堵转"],
        ["TC-PROT-04", "无感态低速且电流指令大，置堵转；电流指令为 0 时不置"],
        ["TC-PROT-05", "SWITCH 中停止提交，超过 LINK_TO 置链路故障；IF_RAMP 中停止提交只禁止切换"],
        ["TC-PROT-06", "默认屏蔽下抽取饱和只置 STATUS.bit9；去掉 bit9 屏蔽后锁存 FAULT 并封锁"],
    ],
    widths=[2.8, 13.4],
    font_size=7.5,
)

add_heading("15.2 闭环场景", 2)
make_table(
    ["用例", "场景", "通过标准"],
    [
        ["TC-LOOP-01", "附录 B 电机，无感角用真值，iq 从 0 到 0.3 pu",
         "仿真 -3 dB 带宽不小于 1.5 kHz，稳态误差小于 2% I_BASE"],
        ["TC-LOOP-02", "I-F 到真值角度的切换",
         "进入 SENSORLESS，切换过程无线路、切换失败和过流故障"],
        ["TC-LOOP-03", "无感运行中停止寄存器提交",
         "超过 LINK_TO 个谷点后进入 FAULT，PWM 为安全态"],
        ["TC-LOOP-04", "观测角叠加 0.2 周阶跃并保持",
         "若超过 THETA_ABORT，必须故障停机，不得继续使用跳变角"],
    ],
    widths=[2.6, 6.2, 7.4],
    font_size=7.5,
)
add_para("TC-LOOP-01 的 1.5 kHz 是控制器和占位电机共同的结果，用来核对增益公式和 80 µs 延迟补偿。它不是未知实机的承诺。",
         space_after=4)

add_heading("15.3 本阶段不验收的内容", 2)
add_bullet("实机转速精度、效率、振动和观测器收敛时间。观测器不在本工程。")
add_bullet("母线电压突变下的电流性能。P0 没有电压采样。")
add_bullet("过调制区电压利用率和死区补偿后的观测精度。")
add_bullet("Aurora 误码率、光模块和 GTX 眼图。这些属于已有 SFP 通路。本阶段验收到 AXI 寄存器事务为止。")

# ================= 附录 =================
add_heading("附录 A 定标", 1)
make_table(
    ["量", "格式", "1 LSB", "复位或示例"],
    [
        ["电流、电压", "Q31", "基值 / 2^31", "电流基值 I_BASE，电压基值 Vdc/√3"],
        ["电角度", "UQ32", "2π / 2^32", "0x00000000 与 d 轴和 α 轴重合"],
        ["ω_step", "int32", "与 UQ32 相同，每拍", "100 Hz 电频率约为 17179869"],
        ["Kp、Ki、SCALE_I、DFDT", "Q16.16", "1/65536", "SCALE_I 复位 0x00010000"],
        ["占空比较值", "整数", "1 / PWM_PEAK", "PWM_PEAK = 2000"],
        ["时间寄存器", "uint32 拍", "40 µs", "25000 拍 = 1 s"],
    ],
    widths=[4.0, 2.4, 4.4, 5.4],
    font_size=8,
)
add_para("主机显示安培时用 i_A = i_q31 / 2^31 × I_BASE。显示电频率时用 f_Hz = ω_step / 2^32 / Ts。这些乘法不在电流环内。",
         space_after=4)

add_heading("附录 B 仿真占位电机", 1)
add_para("只用于 TC-LOOP。数值是可计算的占位，不是项目电机。", space_after=3)
make_table(
    ["参数", "占位值"],
    [
        ["极对数", "4"],
        ["Rs", "0.5 Ω"],
        ["Ld = Lq", "2 mH"],
        ["λf", "0.05 Wb"],
        ["Vdc", "310 V"],
        ["I_BASE", "20 A"],
        ["U_BASE", "310/√3 V"],
        ["设计 ωc", "2π·1500 rad/s"],
    ],
    widths=[4.5, 6.0],
    font_size=8,
)
add_para("按第 7.2 节，Z_BASE ≈ 8.95 Ω，Kp_pu ≈ 2.11，Ki_pu ≈ 0.0211。写入寄存器前四舍五入到 Q16.16。阶段 5 的示例使用这组数。",
         space_after=4)

add_heading("附录 C MCU 每 200 µs 的寄存器事务", 1)
add_para("MCU 定时中断的周期是 200 µs。下面的地址是电机核心 AXI 从机上的字节偏移。SFP 如何寻址到这个从机，沿用已有通路。",
         space_after=3)
add_para("读，必须属于同一次快照：", space_after=2)
add_bullet("读 SNAP_SEQ，记为 seq。")
add_bullet("读 SNAP_UALPHA、SNAP_UBETA、SNAP_IALPHA、SNAP_IBETA。")
add_bullet("再读 SNAP_SEQ。与 seq 不同则本次作废，从头重读。同一中断内最多重读两次，仍不一致就跳过本次写回，让 FPGA 继续外推。")
add_para("MCU 用这次读到的电压、电流更新观测器，得到该 seq 对应样本的电角度和电角速度。电角速度单位是 rad/s，不是机械 rpm。",
         space_after=3)
add_para("写：", space_after=2)
add_bullet("写 THETA_IN 为 UQ32 电角度。")
add_bullet("写 SPEED_IN 为 Q16.16 电角速度，1 rad/s 写成 65536。")
add_bullet("写 SEQ_ECHO 为上面确认过的 seq。")
add_bullet("写 OBS_COMMIT 为 1。")
add_para("仿真桩不经过 SFP，按同样顺序写这四个寄存器，每 5 个谷点一次。",
         space_after=4)

out = r"F:\byd\nosensor\FPGA无传感器电机控制需求规格说明书.docx"
doc.save(out)
print("SAVED", out)
