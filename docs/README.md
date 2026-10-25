# Qwen 3.8 27B + DFlash2 (oMLX z-lab fork)

This directory is the canonical local deployment on this Mac, replacing the
retired llama.cpp Cold-Fusion-GAIN setup.

## Runtime

- Endpoint: `http://127.0.0.1:7870/v1` (OpenAI-compatible; `/v1/messages` Anthropic-compatible)
- Model ID: `Qwen3.8-27B-4bit`
- Server: oMLX `0.6.2-dflash2` (z-lab fork, installed at `/Applications/oMLX.app`)
- Speculative decoding: DFlash2 draft (`~/Models/mlx/Qwen3.8-27B-DFlash2`, on-the-fly 4-bit)
- Context window: **262,144 tokens** native (validated to 70k+)
- Prefix cache: L1 in-memory (8 GB budget), survives across requests

## Why this config won (measured on this machine, M4 Max 64 GB)

| Metric | Old llama.cpp DFlash2 | New llama.cpp AR | mlx-lm vanilla | **oMLX fork + DFlash2** |
|---|---|---|---|---|
| Decode tok/s (short ctx) | ~15 | ~350 median | ~10 | **~809 median** |
| TTFT @ 32.5k fresh prompt | 435 s every turn | 373 s | — | 486 s **once** |
| TTFT with cached prefix | n/a (>32k cap) | n/a | — | **8–16 s** |
| Long-ctx needle QA | untested | untested | gibberish (corrupt dl) | **5/5 @ 70k** |

The prefix cache is the agentic win: a coding-agent session pays the big prefill
once; each subsequent tool-call turn reuses the cached KV and answers in seconds.

## Control

```bash
# Double-click with no arguments for the model/action menu.
~/Desktop/local-llm.command

# Qwen remains the default for existing scripts.
~/Desktop/local-llm.command qwen status
~/Desktop/local-llm.command qwen restart

# The same Desktop command controls Ornith and retains its dry-run mode.
~/Desktop/local-llm.command ornith status
~/Desktop/local-llm.command ornith --dry-run start

# Inspect or stop all local runtimes together. Starting both is refused because
# they compete for unified Metal memory.
~/Desktop/local-llm.command all status
```

LaunchAgent label: `local.omlx.qwen38-dflash2` (KeepAlive, starts at login).
Logs: `~/Library/Logs/LocalLLM/qwen38-omlx-dflash2.log`.

`~/Desktop/local-llm.command` is the only Desktop local-model launcher. The
Ornith implementation remains under `~/Models/ornith-256k/deploy/` and is
called by this controller; it is not a second Desktop shortcut.

## Files this deployment uses

1. `/Applications/oMLX.app` — z-lab fork DMG (`oMLX-0.6.2-zlab-dflash2-arm64-signed.dmg`)
2. `~/Models/mlx/Qwen3.8-27B-4bit` — target model (16.6 GB, SHA-256 verified against HF)
3. `~/Models/mlx/Qwen3.8-27B-DFlash2` — DFlash2 drafter (BF16, quantized at load)
4. `~/.omlx/model_settings.json` — enables DFlash for the target model
   (block size 5 per z-lab guidance for quantized targets, adaptive verify, L1 cache on)

## API auth

The server requires an API key (from `~/.omlx/settings.json`). Clients must send
`Authorization: Bearer <key>`; the controller exports it via
`~/OWLSpace/provider.env` as `OMLX_API_KEY`.

## Recommended sampling (per Qwen3.8 model card)

- Thinking mode: `temperature=1.0, top_p=0.95, top_k=20`
- Instruct mode: `temperature=0.7, top_p=0.80, top_k=20`
- `reasoning_effort`: xhigh (default) / medium / low

## Reproducibility / provenance

- Target weights: https://huggingface.co/mlx-community/Qwen3.8-27B-4bit (commit 3e6447f)
- Drafter: https://huggingface.co/z-lab/Qwen3.8-27B-DFlash2 (mirror of incoai/)
- Fork server: https://github.com/z-lab/omlx-fork releases @ 0.6.2-dflash2
- DFlash project: https://github.com/z-lab/dflash

## Retired

- `~/Models/qwen38-gain-dflash2/` (llama.cpp GGUF pair, 18 GB) — superseded;
  safe to delete once this profile has been validated in daily use.
- Homebrew `omlx` service is stopped/disabled (it conflicted on port 7880).

## Known caveats

- First request after a cold start loads ~19 GB into Metal (~60 s) and runs slow
  while swap drains; keep the service warm.
- Fresh long prompts (>30k) still cost ~500 s to prefill — that's one-time per
  unique context thanks to the prefix cache.
- The brew `llama.cpp` was upgraded to 0.2.0 (build 10566) during testing; its
  `--spec-type draft-dflash` expects newer GGUF tensor layouts than the retired
  pair had.
