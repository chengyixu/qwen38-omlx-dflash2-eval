# Qwen3.8-27B + DFlash2 on Apple Silicon

**Speculative Decoding, Prefix Cache, and Serving Controller Analysis**

**Chengyi Xu and Nexora — Nexora Research**

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Context: 262k](https://img.shields.io/badge/context-262%2C144-blue.svg)](MANIFEST.json)

---

## Overview

This repository packages the configuration manifests, benchmark results, and launch controllers evaluated for **Qwen3.8-27B 4-bit** paired with a **DFlash2 drafter** on Apple Silicon (M4 Max 64 GB).

### Key Architectural Components

1. **Target Model:** Qwen3.8-27B 4-bit affine quantized weights (16.6 GB).
2. **Speculative Drafter:** DFlash2 speculative drafter (`Qwen3.8-27B-DFlash2`), dynamically quantized at runtime.
3. **Prefix Caching:** L1 in-memory prefix cache (8 GB allocation budget), retaining KV states across multi-turn agent turns.
4. **Lifecycle Controller:** `bin/local-llm.command` ensuring fail-safe single-large-model mutual exclusion on Apple Silicon unified memory.

---

## Benchmark Findings & Measurement Caveats

### Multi-Turn Agent Acceleration

| Metric | Baseline llama.cpp | oMLX + DFlash2 (Prefix Cached) |
|---|---|---|
| Short Context Decode | ~15 tok/s | ~18–25 tok/s (sustained) |
| Cold 32.5k Prompt TTFT | 435 s (every turn) | 486 s (first turn only) |
| Subsequent Cached Turns | 435 s (every turn) | **8–16 s** |
| Long-Context Needle Retrieval | Untested (>32k cap) | **5/5 at 70k tokens** |

### Critical Measurement Caveat: The 809 tok/s Synthetic Anomaly

In early synthetic testing under zero background load, a short burst throughput of **~809 tok/s** was observed on an isolated micro-benchmark. **This measurement is an artifact of short, highly repetitive token sequences where DFlash2 achieved near-100% draft acceptance and does NOT represent realistic coding or reasoning performance.** 

In actual agentic workflows (e.g. debugging, tool calling, code generation), sustained decode throughput measures between **16–28 tok/s**, with the primary latency reduction delivered by **prefix cache reuse** rather than speculative decoding alone.

---

## Repository Contents

```
qwen38-omlx-dflash2-eval/
├── README.md              # Overview and benchmark analysis
├── CITATION.cff           # Citation metadata
├── LICENSE                # MIT License
├── MANIFEST.json          # Deployment and runtime specification
├── bin/
│   └── local-llm.command  # Sanitized single-large-model controller
├── docs/
│   └── README.md          # Technical serving notes and operational guide
└── tests/
    ├── local-llm-controller-test.sh # Controller contract test suite
    └── local-llm-menu-test.exp      # TUI menu expect test
```

---

## Citation

```bibtex
@dataset{xu2026qwen38dflash2eval,
  title  = {Qwen3.8-27B + DFlash2 on Apple Silicon: Speculative Decoding, Prefix Cache, and Serving Controller Analysis},
  author = {Xu, Chengyi and {{Nexora}}},
  year   = {2026},
  month  = oct,
  url    = {https://github.com/chengyixu/qwen38-omlx-dflash2-eval}
}
```

---

## License

MIT License. Copyright (c) 2026 Chengyi Xu and Nexora.
Model weights are property of their respective creators and are not distributed in this repository.
