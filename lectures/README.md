# FPGA 混沌电路与黎曼零点 — 实验教程系列

## 面向对象
本科三/四年级，已修《数字电路》和《模拟电子技术》，了解基本 Verilog 语法。

## 实验平台
- ALINX AX7020 (Zynq-7020) 或同类 Zynq 开发板
- Vivado 2022.2+（仿真不需要板子，纯 Vivado Simulator 即可）
- AN108 AD/DA 模块（Lab 4 上板时使用，仿真阶段不需要）

## 课程结构

### Lab 1: 定点数运算与 Vivado 仿真入门 (2 学时)
**目标**: 掌握 Q4.28 定点数乘法，学会用 Vivado 写 testbench 看波形
- 实验内容: 实现定点乘法器，用 testbench 验证 1.5 × 1.5 = 2.25
- 学到: 定点数表示、Vivado 项目创建、仿真波形查看
- 交付: 截图证明仿真波形正确

### Lab 2: Logistic 映射 — 从周期到混沌 (3 学时)
**目标**: 在 FPGA 上实现 x_{n+1} = 1 - μx²，观察分岔现象
- 实验内容: 实现 Logistic 迭代核心，扫描 μ 参数，在仿真中画分岔图
- 学到: 混沌动力学、分岔、Lyapunov 指数的直观理解
- 交付: μ 从 0.5 到 2.0 的分岔图 (Python 读仿真数据画图)

### Lab 3: Hénon 映射 — 二维混沌与奇异吸引子 (3 学时)
**目标**: 扩展到二维，实现 Hénon 映射，观察蝴蝶形吸引子
- 实验内容: 双通道迭代 + 非自治冷却调度
- 学到: 二维混沌、奇异吸引子、非自治系统
- 交付: x-y 相图 + 冷却过程中的轨迹演化

### Lab 4: 黎曼零点提取 — 从混沌到数论 (4 学时)
**目标**: 从 FPGA 混沌输出中提取黎曼零点，验证谱同构
- 实验内容: 长轨迹采集 → Markov/DMD 分析 → 零点匹配
- 学到: Markov 转移矩阵、本征值分析、希尔伯特-波利亚猜想
- 交付: 前 6 个黎曼零点的匹配表格 + 误差分析

## 文件结构
```
lectures/
├── README.md              (本文件)
├── lab1_basics/           Lab 1: 定点数与仿真
│   ├── fixed_mult.v       定点乘法器
│   ├── tb_fixed_mult.v    testbench
│   └── lab1_guide.md      实验指导书
├── lab2_logistic/         Lab 2: Logistic 映射
│   ├── logistic_iter.v    迭代核心
│   ├── tb_logistic.v      testbench (扫描 μ)
│   ├── plot_bifurcation.py  画分岔图
│   └── lab2_guide.md      实验指导书
├── lab3_henon/            Lab 3: Hénon 映射
│   ├── henon_iter.v       双通道迭代
│   ├── tb_henon.v         testbench
│   ├── plot_attractor.py  画吸引子
│   └── lab3_guide.md      实验指导书
└── lab4_riemann/          Lab 4: 黎曼零点
    ├── chaos_with_cooling.v  带冷却的完整引擎
    ├── tb_riemann.v       testbench (长轨迹)
    ├── analyze_zeros.py   Markov + DMD 分析
    └── lab4_guide.md      实验指导书
```
