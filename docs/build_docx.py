# -*- coding: utf-8 -*-
"""
把 docs/*.md 合并为一份 Word 方案书（无 pandoc 依赖，仅用 python-docx）
用法： python build_docx.py
输出： ../无感算法方案_方案书.docx
支持：# ~ #### 标题、表格、列表、代码块、图片、粗体、行内代码、引用
"""
import os
import re

from docx import Document
from docx.shared import Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "无感算法方案_方案书.docx")

CJK = "微软雅黑"
MONO = "Consolas"


def set_cjk(run, name=CJK):
    run.font.name = name
    rPr = run._element.get_or_add_rPr()
    rFonts = rPr.find(qn("w:rFonts"))
    if rFonts is None:
        rFonts = OxmlElement("w:rFonts")
        rPr.append(rFonts)
    rFonts.set(qn("w:eastAsia"), name)
    rFonts.set(qn("w:ascii"), name)
    rFonts.set(qn("w:hAnsi"), name)


def add_runs(par, text, size=10.5, bold=False, mono=False, color=None):
    """处理 **粗体** 与 `代码`"""
    tokens = re.split(r"(\*\*.+?\*\*|`[^`]+`)", text)
    for tok in tokens:
        if not tok:
            continue
        if tok.startswith("**") and tok.endswith("**") and len(tok) > 4:
            r = par.add_run(tok[2:-2])
            r.bold = True
            set_cjk(r)
        elif tok.startswith("`") and tok.endswith("`") and len(tok) > 2:
            r = par.add_run(tok[1:-1])
            r.font.name = MONO
            r.font.size = Pt(size - 1)
            r.font.color.rgb = RGBColor(0x8B, 0x1A, 0x1A)
        else:
            r = par.add_run(tok)
            set_cjk(r)
            r.bold = bold
        r.font.size = Pt(size)
        if color is not None:
            r.font.color.rgb = color


def add_table(doc, rows):
    if not rows:
        return
    ncol = max(len(r) for r in rows)
    table = doc.add_table(rows=0, cols=ncol)
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    for i, row in enumerate(rows):
        cells = table.add_row().cells
        for j in range(ncol):
            txt = row[j] if j < len(row) else ""
            cell = cells[j]
            cell.text = ""
            p = cell.paragraphs[0]
            add_runs(p, txt, size=8.5, bold=(i == 0))
            p.paragraph_format.space_before = Pt(1)
            p.paragraph_format.space_after = Pt(1)
            if i == 0:
                shd = OxmlElement("w:shd")
                shd.set(qn("w:fill"), "E8EEF7")
                cell._tc.get_or_add_tcPr().append(shd)
    doc.add_paragraph()


def add_code(doc, lines):
    for ln in lines:
        p = doc.add_paragraph()
        p.paragraph_format.space_before = Pt(0)
        p.paragraph_format.space_after = Pt(0)
        p.paragraph_format.left_indent = Cm(0.5)
        r = p.add_run(ln if ln else " ")
        r.font.name = MONO
        r.font.size = Pt(8)
        rPr = r._element.get_or_add_rPr()
        rFonts = OxmlElement("w:rFonts")
        rFonts.set(qn("w:eastAsia"), MONO)
        rFonts.set(qn("w:ascii"), MONO)
        rFonts.set(qn("w:hAnsi"), MONO)
        rPr.append(rFonts)
    doc.add_paragraph()


def add_image(doc, path, width_cm=15.5):
    if not os.path.exists(path):
        p = doc.add_paragraph()
        add_runs(p, "[缺图: %s]" % path, size=9, color=RGBColor(0xCC, 0, 0))
        return
    doc.add_picture(path, width=Cm(width_cm))
    doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER


def parse_md(doc, md_path):
    base = os.path.dirname(md_path)
    with open(md_path, encoding="utf-8") as f:
        lines = f.read().splitlines()

    i = 0
    n = len(lines)
    while i < n:
        ln = lines[i]
        s = ln.strip()

        if s.startswith("```"):
            i += 1
            buf = []
            while i < n and not lines[i].strip().startswith("```"):
                buf.append(lines[i])
                i += 1
            i += 1
            add_code(doc, buf)
            continue

        if s.startswith("#"):
            m = re.match(r"^(#{1,4})\s+(.*)$", s)
            if m:
                level = len(m.group(1))
                text = m.group(2)
                h = doc.add_heading(level=min(level, 4))
                add_runs(h, text, size={1: 18, 2: 14, 3: 12, 4: 11}[min(level, 4)], bold=True)
                i += 1
                continue

        if s.startswith("|"):
            rows = []
            while i < n and lines[i].strip().startswith("|"):
                raw = lines[i].strip().strip("|")
                cells = [c.strip() for c in raw.split("|")]
                if not all(re.fullmatch(r":?-{2,}:?", c) for c in cells):
                    rows.append(cells)
                i += 1
            add_table(doc, rows)
            continue

        if s.startswith("!["):
            m = re.match(r"!\[(.*?)\]\((.+?)\)", s)
            if m:
                p = os.path.normpath(os.path.join(base, m.group(2)))
                add_image(doc, p)
            i += 1
            continue

        if s.startswith("- ") or s.startswith("* "):
            p = doc.add_paragraph(style="List Bullet")
            add_runs(p, s[2:])
            i += 1
            continue

        m = re.match(r"^(\d+)\.\s+(.*)$", s)
        if m:
            p = doc.add_paragraph(style="List Number")
            add_runs(p, m.group(2))
            i += 1
            continue

        if s.startswith(">"):
            p = doc.add_paragraph()
            p.paragraph_format.left_indent = Cm(0.6)
            add_runs(p, s.lstrip("> ").strip(), size=9.5, color=RGBColor(0x55, 0x55, 0x55))
            i += 1
            continue

        if s in ("---", "***", "___"):
            doc.add_paragraph()
            i += 1
            continue

        if not s:
            i += 1
            continue

        p = doc.add_paragraph()
        p.paragraph_format.space_after = Pt(4)
        add_runs(p, s)
        i += 1


def add_toc(doc):
    p = doc.add_paragraph()
    run = p.add_run()
    fld = OxmlElement("w:fldChar"); fld.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText"); instr.set(qn("xml:space"), "preserve")
    instr.text = 'TOC \\o "1-3" \\h \\z \\u'
    sep = OxmlElement("w:fldChar"); sep.set(qn("w:fldCharType"), "separate")
    t = OxmlElement("w:t"); t.text = "（在 Word 中按 F9 更新目录）"
    end = OxmlElement("w:fldChar"); end.set(qn("w:fldCharType"), "end")
    run._r.append(fld); run._r.append(instr); run._r.append(sep)
    run._r.append(t); run._r.append(end)


def main():
    doc = Document()

    # 页面与默认字体
    sec = doc.sections[0]
    sec.top_margin = Cm(2.2)
    sec.bottom_margin = Cm(2.2)
    sec.left_margin = Cm(2.4)
    sec.right_margin = Cm(2.2)
    style = doc.styles["Normal"]
    style.font.name = CJK
    style.font.size = Pt(10.5)
    style.element.rPr.rFonts.set(qn("w:eastAsia"), CJK)

    # 封面
    for _ in range(4):
        doc.add_paragraph()
    p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run("300V/25A 表贴式 PMSM\n无位置传感器控制方案")
    r.bold = True; r.font.size = Pt(26); set_cjk(r)

    p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run("算法设计 · 硬件部署 · 仿真与验证计划")
    r.font.size = Pt(14); r.font.color.rgb = RGBColor(0x44, 0x44, 0x44); set_cjk(r)

    for _ in range(6):
        doc.add_paragraph()
    p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run("平台：DSP C6678（5 kHz 控制）+ FPGA 三相驱动板（FOC/电流环）+ SFP 光纤\n"
                  "版本：V0.1 评审稿")
    r.font.size = Pt(10.5); set_cjk(r)

    doc.add_page_break()

    # 目录
    h = doc.add_heading(level=1)
    add_runs(h, "目录", size=18, bold=True)
    add_toc(doc)
    doc.add_page_break()

    for i, name in enumerate(["01_无感算法设计方案.md",
                              "02_硬件部署与SFP接口方案.md",
                              "03_仿真与板级验证计划.md"]):
        parse_md(doc, os.path.join(HERE, name))
        if i < 2:
            doc.add_page_break()

    doc.save(OUT)
    print("saved:", OUT)


if __name__ == "__main__":
    main()
