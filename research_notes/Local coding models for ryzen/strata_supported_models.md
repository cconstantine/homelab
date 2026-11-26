# Strata-supported models as replacements for Qwen3.8-Flash-Next on "ryzen" (1x R9700 32 GB, ~85 GiB RAM)

Research date: 2026-11-21. Strata sources were fetched from the GitHub API and raw files (docs at HEAD, release notes v0.1.0 to v0.2.18, issues). Model cards were fetched from Hugging Face. "Vendor" means the model's maker or quantizer reported the number. "Strata-measured" means the Strata maintainer measured it, and Strata says these are internal runs whose logs are not published ([commit de9c0448](https://github.com/Niko1221/Strata/commits/main/docs/DEEPSEEK41.md)).

## Q1: DeepSeek V4.1-Flash (and the 1017 revision): architecture, license, quants in Strata, fit, measured R9700 speed, context, tools, bugs

### Takeaway
DeepSeek V4.1-Flash is a 763B-total MoE: a 552B transformer, 8B active in prefill and 16B in decode, plus a 196B Engram lookup table. It is MIT-licensed and supports 1M context. **Strata removed DeepSeek support in 0.2.14 (2026-11-15). 0.2.13, the version on ryzen, is the last one that runs it**, using the separate `strata-dsv41` engine 0.1.59. The maintainer says it "will come back to Strata soon" but gives no date.

Of the unpruned sets, only part of each fits in 32 GB VRAM plus about 85 GiB RAM: their backbones are 121 to 155 GB, so the rest streams from the SSD. The 72 GB ISTA-DAS Coder fits in RAM plus VRAM. On one R9700, measured decode was about 11 to 27 tok/s, roughly 3 to 8 times slower than the 80 to 95 tok/s baseline.

### Cited Findings
**Architecture, license and context (vendor)**
- 552B backbone parameters, multimodal (image and text), contexts up to 1M tokens. It is a 40-layer Causal Encoder-Decoder (20 encoder plus 20 decoder layers). The decoder's global KV is projected from the final encoder states, so the model activates **8B parameters per token in prefill and 16B in decode**. — [DeepSeek-V4.1-Flash model card](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash)
- The KV/attention design is CSA2 (Compressed Sparse Attention 2), with layer modes Full, Reindex and Reuse and a Hierarchical Sparse Indexer. "SWA Bounded Replay" cuts the persistent KV footprint to about 1/8 of DeepSeek-V4-Flash's. The global KV per token is about 4x smaller than V4-Flash's and 437x smaller than DeepSeek-V1's. — [DeepSeek model card](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash)
- 1 shared expert plus 384 routed experts per MoE layer, 6 routed active per token. Engram conditional memory has 196B parameters and is read by token-based lookup. The model has DSpark speculative decoding. Pre-training used 45T tokens, with context extended to 1M. The license is MIT. — [DeepSeek model card](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash)
- 763.2B total parameters, 551.9B of them in the transformer, and a 1M-token context window. — [ISTA-DASLab GSQ-RCO GGUF card](https://huggingface.co/ISTA-DASLab/DeepSeek-V4.1-Flash-1017-GSQ-RCO-GGUF)
- The 1017 revision is described as "a minor update" with gains in reasoning, coding and agentic work and shorter output. It is MIT-licensed and recommends 1M context, temperature 1.0 and top_p 1.0. — [DeepSeek-V4.1-Flash-1017 card](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash-1017)
- Neither model ships a Jinja chat template; DeepSeek ships encoding.py and the Rust `deepseek-recipe` instead. ISTA's GGUFs embed a template adapted from Unsloth's DeepSeek-V4.1 release. — [DeepSeek card](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash), [ISTA card](https://huggingface.co/ISTA-DASLab/DeepSeek-V4.1-Flash-1017-GSQ-RCO-GGUF)

**Strata removed DeepSeek after 0.2.13**
- docs/DEEPSEEK41.md: "Strata no longer runs DeepSeek V4.1-Flash. Version 0.2.13 was the last one that set it up and started it." — [DEEPSEEK41.md](https://github.com/Niko1221/Strata/blob/main/docs/DEEPSEEK41.md)
- Commit f1fce328 (2026-11-11), "DeepSeek out (7/7)", deleted the dsv41 build scripts for CUDA and HIP and `third_party/project-maya`. — [commit history for DEEPSEEK41.md](https://api.github.com/repos/Niko1221/Strata/commits?path=docs/DEEPSEEK41.md)
- Since 0.2.14 the DeepSeek engines stay at 0.1.59 and the update feed fetches them from the 0.2.13 release. 0.2.18 lists `strata-dsv41` linux-x86_64-hip-rx9070 as staying at 0.1.59. — [Strata releases](https://github.com/Niko1221/Strata/releases), [AMD_HIP.md line 9](https://github.com/Niko1221/Strata/blob/main/docs/AMD_HIP.md)
- On 2026-11-19 the maintainer wrote in issue #6072: "DeepSeek will come back to Strata soon. For now, Strata 0.2.13 is the last version that runs DeepSeek models", and gave rollback steps. A community member links the removal to a dispute with Project Maya, the fork that the dsv41 engine was ported from (MIT). That explanation is speculation, not confirmed. — [Issue #6072](https://github.com/Niko1221/Strata/issues/6072), [Issue #6048](https://github.com/Niko1221/Strata/issues/6048), [Issue #6291](https://github.com/Niko1221/Strata/issues/6291)
- One user in #6072 reports Project Maya's DeepSeek engine reaching the same speed as Strata after tuning (`--experts 5`, `--ssd-cache auto`, `DS4_STORE_ROOM_GB`). This is a single anecdote on an RTX 3070. — [Issue #6072](https://github.com/Niko1221/Strata/issues/6072)

**DeepSeek sets Strata offered (≤0.2.13)**

All disk sizes include the 110.6 GB IQ4_NL Engram file, which every set shares.

| Set | Backbone | Total on disk | Quality vs original model |
|---|---|---|---|
| ISTA-DAS IQ1_M (1.75 bpw) | 120.72 GB | 231.3 GB (239 GB with drafter in Strata) | KL 0.217, ppl +21% (Strata) |
| ISTA-DAS IQ2_XXS (2.00 bpw), ISTA's recommended set | 138.24 GB | 248.8 GB (257 GB) | KL 0.170 / later 0.171, ppl 3.630 vs 3.140 (Strata) |
| ISTA-DAS IQ2_XS (2.25 bpw), Strata's pick for code and agents | 155.23 GB | 265.8 GB (274 GB) | KL 0.107 / 0.109, ppl 3.405 (Strata) |
| Unsloth UD-IQ1_S | n/a | 241 GB download | KL 0.114 vs Unsloth's Q8_K_XL |
| Unsloth UD-IQ1_M | n/a | 258 GB download | KL 0.087 vs Unsloth's Q8_K_XL |
| ISTA-DAS Coder (IQ2_XXS, 192/384 experts) | 72.12 GB | 182.7 GB (191 GB with 8 GB drafter) | KL 0.397, top-1 76.4%, ppl 4.645 |

Sources: [ISTA GGUF card](https://huggingface.co/ISTA-DASLab/DeepSeek-V4.1-Flash-1017-GSQ-RCO-GGUF), [Strata v0.2.4 notes](https://github.com/Niko1221/Strata/releases/tag/v0.2.4), [v0.2.9 notes](https://github.com/Niko1221/Strata/releases/tag/v0.2.9), [v0.2.10 notes](https://github.com/Niko1221/Strata/releases/tag/v0.2.10)

- ISTA (vendor), measured on AIME25, GPQA-D and LCB v6: IQ2_XXS keeps 100.0% of the base model's task average, IQ2_XS 99.8% and IQ1_M 98.7%. — [ISTA card](https://huggingface.co/ISTA-DASLab/DeepSeek-V4.1-Flash-1017-GSQ-RCO-GGUF)
- Strata's measurement, with Unsloth Q8_K_XL as the reference on 4x R9700 and 6 experts per token:

  | Set | KL | Top-1 | Perplexity | 61-task suite | Agent loops |
  |---|---|---|---|---|---|
  | UD-IQ1_S | 0.114 | 87.2% | +4.8% | 53/61 | 5/10 |
  | UD-IQ1_M | 0.087 | 88.8% | +3.0% | 53/61 | 6/10 |
  | ISTA-DAS 2.25 | 0.110 | 87.4% | +8.9% | 56/61 | 6/10 |

  No set produced an invalid tool call. — [v0.2.9 notes](https://github.com/Niko1221/Strata/releases/tag/v0.2.9)
- The Engram table "stays on the SSD... not counted in RAM (keep it on an NVMe drive)". — [v0.2.10 notes](https://github.com/Niko1221/Strata/releases/tag/v0.2.10)
- The engine keeps the busiest experts in RAM and reads the rest from SSD with direct reads. The tested comfortable size was 64 GB RAM with a 12 GB+ GPU. — [v0.2.4 notes](https://github.com/Niko1221/Strata/releases/tag/v0.2.4)

**Measured speed on one R9700 (gfx1201), Strata-measured**

| Release / engine | Set and conditions | Decode | Prompt / start |
|---|---|---|---|
| v0.2.4, engine 0.1.49 | IQ2_XS | ~11 tok/s | prompt not measured |
| v0.2.7 | 2.25 set | n/a | 32K prompt 382–444 tok/s, 8K prompt 200–286 tok/s (8K is SSD-limited and variable) |
| v0.2.9 | 2.25 set, 2,366 of 15,360 experts on the card, 6 experts/token | 12–18 tok/s (23 on one 22-token answer) | n/a |
| v0.2.10, package 0.1.55 | ISTA-DAS Coder | 22.8 tok/s | start 54 s |
| v0.2.10, test engine | ISTA-DAS Coder | 25.6 tok/s | n/a |
| v0.2.10, RAM capped | ISTA-DAS Coder | 20.9 tok/s at 40 GB, 18.5 at 32 GB, 15.0 at 24 GB, 8.0 at 16 GB | n/a |
| v0.2.11 | DeepSeek 2.25bpw | 4–25 tok/s | 371 s first launch (one-time prep plus 165 s load) |
| v0.2.13 (release check) | IST-DAS-2.25bpw | 14.5–27 tok/s | 366 s launch to ready, vs IQ3_S 133 s at 91–98 tok/s on the same card |

Sources: [v0.2.4](https://github.com/Niko1221/Strata/releases/tag/v0.2.4), [v0.2.7](https://github.com/Niko1221/Strata/releases/tag/v0.2.7), [v0.2.9](https://github.com/Niko1221/Strata/releases/tag/v0.2.9), [v0.2.10](https://github.com/Niko1221/Strata/releases/tag/v0.2.10), [v0.2.11](https://github.com/Niko1221/Strata/releases/tag/v0.2.11), [v0.2.13](https://github.com/Niko1221/Strata/releases/tag/v0.2.13)

- For comparison, 4x R9700 with the 2.25 set reached decode 88.9–95.0 tok/s on code and 73.5–79.7 on agent tasks, and a 32K prompt at 1,127–1,697 tok/s. Four cards matter because about 12,147 of 15,360 experts fit in VRAM. — [v0.2.7 notes](https://github.com/Niko1221/Strata/releases/tag/v0.2.7), [v0.2.9](https://github.com/Niko1221/Strata/releases/tag/v0.2.9)

**Context, tools and known bugs in Strata**
- Context: "DeepSeek can use 512K and 1M contexts... with a plain 'not tested yet' note past 256K. The default stays 8K." Prompts longer than a few thousand tokens at 512K or 1M were listed as untested. — [v0.2.7 notes](https://github.com/Niko1221/Strata/releases/tag/v0.2.7)
- Thinking budget: by default DeepSeek thinks for at most 32,768 tokens. — [v0.2.4](https://github.com/Niko1221/Strata/releases/tag/v0.2.4)
- Conversation and system-prompt cache on disk (up to 2 GB), so returning agents and sub-agents answer sooner. — [v0.2.4.2](https://github.com/Niko1221/Strata/releases/tag/v0.2.4)
- Tool calls: with the model in memory, 8/8 tool calls were correct. With about 13% of the experts in memory (most streamed from SSD) at temperature 0.6, 1 in 5 runs put a "DSML" marker inside the tool argument. This was still listed as a known issue in 0.2.11. — [v0.2.10 notes](https://github.com/Niko1221/Strata/releases/tag/v0.2.10), [v0.2.11](https://github.com/Niko1221/Strata/releases/tag/v0.2.11)
- Nondeterminism at temperature 0: the expert cache moves experts between CPU and GPU. On HIP the CPU lane computes part of the experts, which adds to the effect. `--no-expert-cache=on` fixes it but costs 58% of decode on one R9700. — [v0.2.9](https://github.com/Niko1221/Strata/releases/tag/v0.2.9), [v0.2.10](https://github.com/Niko1221/Strata/releases/tag/v0.2.10)
- A bug fixed in 0.2.8 truncated replies mid-word, e.g. "Nerazim" came out as "Neraz". — [v0.2.8](https://github.com/Niko1221/Strata/releases/tag/v0.2.8)
- The Linux AMD DeepSeek package is built for gfx1200 and gfx1201. — [v0.2.10](https://github.com/Niko1221/Strata/releases/tag/v0.2.10)
- Strata's MTP drafting is auto-picked for DeepSeek. DSpark raised 4x R9700 decode from 31 to 55–69 tok/s in 0.2.4. — [v0.2.10](https://github.com/Niko1221/Strata/releases/tag/v0.2.10), [v0.2.4](https://github.com/Niko1221/Strata/releases/tag/v0.2.4)

### Inferences
- **Fit on ryzen (32 GB VRAM plus about 85 GiB, roughly 91 GB, usable RAM):**
  - The unpruned IQ2_XXS backbone (138 GB) and IQ2_XS backbone (155 GB) exceed about 117–123 GB of combined memory once buffers and the KV cache are allowed for, so some experts stream from NVMe.
  - IQ1_M (121 GB) is borderline.
  - The ISTA-DAS Coder (72 GB) fits fully in RAM plus VRAM.
  - Ryzen has more RAM than Strata's single-R9700 test box. That box got 20.9 tok/s at a 40 GB RAM cap for the Coder, so ryzen would likely land near the uncapped 22.8–25.6 tok/s. That is still about 3.5x slower than the Qwen baseline.
- Prompt reading at roughly 0.2–0.45K tok/s on one card is 3–10x slower than the baseline's 1.2–2.2K tok/s. At 100K–250K contexts, a cold re-read of the full context would take several minutes. That is a serious handicap for multi-hour agentic sessions.
- **Maintenance risk:** the user is pinned to 0.2.13, and DeepSeek is frozen at dsv41 engine 0.1.59 with no further fixes until the promised return. Upgrading Strata past 0.2.13 would drop DeepSeek.

### Gaps
- No Strata measurement of DeepSeek on one R9700 at contexts of 100K or more, and no long agent soak on one card.
- No measured prompt speed for the ISTA-DAS Coder on one R9700.
- I could not confirm whether the 0.2.13 Docker image `ghcr.io/niko1221/strata:*-rocm-gfx120x` bundles `strata-dsv41`. The removal commit touches only comments in `docker/build.sh` and `entrypoint.sh`, and the HIP rx9070 packages used to carry `strata-dsv41`. Check this inside the running container.
- No R9700-specific HIP bug for DeepSeek turned up beyond the general items above.
- I did not find a statement on Claude Code or opencode compatibility for DeepSeek specifically in Strata. Strata's server is OpenAI-compatible, and tool turns were tested in release checks.

## Q2: Coding-agent benchmarks for DeepSeek V4.1-Flash vs Qwen3.8-Flash-Next

### Takeaway
On the vendor's own numbers, DeepSeek V4.1-Flash-1017 is clearly ahead of the Qwen baseline:
- DeepSWE v1.1: 77.0 (mini-SWE v2) against Qwen3.8-Flash-Next's 58.7.
- The original V4.1-Flash scored 74.2 on mini-SWE and 65.5 on OpenCode.

No independent SWE-rebench or Aider results were found. These are full-precision figures; the 1–2 bit quants Strata runs will lose some of this.

### Cited Findings
- **DeepSeek V4.1-Flash, vendor, maximum reasoning effort (100), temperature 1.0, top_p 0.95:**

  | Benchmark | Harness | V4.1-Flash | DS-V4-Flash |
  |---|---|---|---|
  | DeepSWE v1.1 | mini-SWE | 74.2 | 54.4 |
  | Terminal-Bench 2.1 | DSH Minimal, 1M context | 90.6 | 82.7 |
  | Terminal-Bench 3.0 | DSH Minimal, 1M context | 30.0 | 7.6 |
  | Terminal-Bench 4.0 | DSH Minimal, 1M context | 31.2 | 7.0 |
  | NL2Repo | DSH Minimal | 64.0 | n/a |
  | ProgramBench | DSH Minimal | 20.3 | n/a |
  | SEC-Bench Pro | Claude Code | 62.8 | n/a |

  — [DeepSeek card](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash)
- **By scaffold (vendor; N=8 on DeepSWE v1.1, N=3 on TB 2.1, max_steps 500, 1M context):**

  | Scaffold | DeepSWE v1.1 | Terminal-Bench 2.1 |
  |---|---|---|
  | Claude Code | 69.8 | 88.0 |
  | Codex | 65.6 | 84.1 |
  | **OpenCode** | **65.5** | **85.0** |
  | Pi | 66.2 | 86.1 |
  | mini-SWE | 74.2 | 90.3 |
  | DSH Minimal | 72.6 | 90.6 |

  — [DeepSeek card](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash)
- **DeepSeek V4.1-Flash-1017, vendor:**

  | Benchmark | Harness | 1017 | Original V4.1-Flash |
  |---|---|---|---|
  | DeepSWE v1.1 | Mini-SWE-V2 | 77.0 | 74.2 |
  | Terminal-Bench 4.0 | Claude Code | 42.3 | 31.2 |
  | ProgramBench | n/a | 29.1 | n/a |
  | NL2Repo | n/a | 68.2 | n/a |

  — [1017 card](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash-1017)
- **SWE-bench Verified (base 1017, FP8/FP4, reasoning effort 50), reported by ISTA:** 81.20. LiveCodeBench v6: 89.71. — [ISTA Coder card](https://huggingface.co/ISTA-DASLab/DeepSeek-V4.1-Flash-1017-GSQ-RCO-Coder-GGUF)
- The base-model card shows no SWE-bench Pro, SWE-bench Multilingual or Aider polyglot numbers for V4.1-Flash. — [DeepSeek card](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash)
- **Independent leaderboards:**
  - The Arena Coding Index lists DeepSeek-V4.1-Flash-20261017 (Max) at #28 of 65 with 1,133, per search snippet; I did not open the page. — [arena.ai](https://arena.ai/leaderboard/agent/code/models/deepseek-v4.1-flash-20261017-max-wzul)
  - A write-up cites Datacurve's DeepSWE v1.1 board with V4.1 Flash at 74.20. This is identical to the vendor figure, so it may not be an independent rerun. — [orcarouter blog](https://www.orcarouter.ai/blog/deepseek-v4-1-flash-benchmark), [dev.to](https://dev.to/breachprotocol/deepseek-re-trained-v4-flash-without-touching-the-architecture-and-its-coding-agent-score-went-from-3a8p)
- **Baseline comparison (Qwen3.8-Flash-Next vendor scores, as given in the assignment; I did not re-fetch the Qwen card):** DeepSWE 1.1 58.7, SWE-bench Pro 62.5, SWE-bench Multilingual 81.0. The Qwen card lists DeepSeek-V4-Flash-0731 at DeepSWE 1.1 54.4. That matches DeepSeek's own V4-Flash figure of 54.4, so the two cards line up on that benchmark.

### Inferences
- On the shared benchmark, DeepSWE v1.1, DeepSeek V4.1-Flash-1017 at full precision is about 18 points above Qwen3.8-Flash-Next (77.0 vs 58.7), though the harnesses may differ: mini-SWE v2 against whatever Qwen used.
- With OpenCode as the harness the gap narrows: V4.1-Flash scores 65.5, about 7 points above Qwen's 58.7.
- This is the strongest quality argument for DeepSeek. It is offset by roughly 4x slower decode and 3–10x slower prompt reading on one R9700, plus the quantization losses (Strata KL 0.11–0.40 for the sets that fit).

### Gaps
- No SWE-bench Pro or Multilingual numbers for DeepSeek V4.1-Flash, so there is no like-for-like comparison with Qwen's 62.5 and 81.0.
- No independent SWE-rebench, Vals.ai, Artificial Analysis or Aider polyglot scores found in this pass.
- No agent benchmarks on quantized (1–2 bit) DeepSeek, other than the Coder's SWE-bench Verified figure under Q3.

## Q3: Strata's "Coder" models: what they are, and benchmarks vs baseline

### Takeaway
There are two "Coder" models, and the 0.2.17 notes describe the Qwen one:
- **Strata's "Coder"** (`--family coder`, 256 experts, 48 layers, 23.42 GiB of experts, pin bba88856f8c3) is ISTA-DASLab's **Qwen3.8-Flash-Next GSQ-RCO Coder**. It is the same model as the baseline with half its experts pruned (256 of 512) and the rest stored at about 3.5 bpw (IQ1_M container, IQ3_S-like experts).
- **The "ISTA-DAS Coder"** (0.2.10, DeepSeek only, ≤0.2.13) is DeepSeek-V4.1-Flash-1017 with 192 of 384 experts kept.

The Qwen Coder is smaller and not higher-quality than the baseline's UD-IQ4_XS, so it is not an upgrade on a box that already fits 4-bit.

### Cited Findings
**Qwen3.8-Flash-Next Coder**
- 0.2.17 notes: "The Coder model's pin is the 2026-10-19 build (revision bba88856f8c3), shard 1 of 29,608,446,496 bytes... 256 experts per layer, 48 layers, 23.42 GiB of experts." It decodes at 127–150 tok/s on an RTX 4090. — [v0.2.17 notes](https://github.com/Niko1221/Strata/releases/tag/v0.2.17)
- ISTA card (vendor): the base has 512 experts across 48 layers, 10 active per token. The Coder keeps 256, chosen by RCO on code, agentic and vision calibration data, and stores the remaining weights at 3.5 bpw. — [ISTA Qwen Coder card](https://huggingface.co/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF)
  - Files: shard 1 is 29.6 GB and must stay resident; shard 2 is a 28.8 GB n-gram table (IQ4_NL) that can stay on disk; total 58.4 GB. License Apache-2.0, inherited from the base.
- **Benchmarks (ISTA, vendor, xhigh reasoning effort):** after the Oct-17 build, SWE-bench Verified is 79.20 against 82.80 for the BF16 base (95.7%), and LiveCodeBench v6 is 87.43 against 87.43 (100%). The earlier build scored 75.60 on SWE-bench Verified. — [ISTA Qwen Coder card](https://huggingface.co/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF)
- Strata's MODELS.md still says "91% of the full model's SWE-bench Verified", which matches the old 75.6/82.8. It also says the Coder is "weaker outside code and in languages other than English, Chinese and other CJK text included". — [MODELS.md](https://github.com/Niko1221/Strata/blob/main/docs/MODELS.md)
- **Measured speeds (Strata):**

  | Hardware / engine | Short-chat decode | Decode at 128K | 32K prompt |
  |---|---|---|---|
  | RTX 5070 12 GB, engine 0.1.26 | 55 tok/s | 43 tok/s | 2,180 tok/s |
  | RX 9070 XT 16 GB, pre-0.1.40 | 44 tok/s | 33 tok/s | 1,420 tok/s |
  | Arc Pro B70 (user report) | 70–78 tok/s | n/a | n/a |

  On the R9700, the WMMA prompt-attention change (0.1.32) took Coder IQ1_M prompts from 1,784 to 2,427 tok/s at 4K and from 1,797 to 2,700 at 16K. — [MODELS.md](https://github.com/Niko1221/Strata/blob/main/docs/MODELS.md), [AMD_HIP.md](https://github.com/Niko1221/Strata/blob/main/docs/AMD_HIP.md), [release notes v0.1.37–39](https://github.com/Niko1221/Strata/releases)

**DeepSeek ISTA-DAS Coder**
- Repo `ISTA-DASLab/DeepSeek-V4.1-Flash-1017-GSQ-RCO-Coder-GGUF`, revision 0b1d5da5, MIT license. It keeps 192 of 384 experts per layer at IQ2_XXS quantization. The backbone is 72.12 GB, about 1.05 bits per original transformer parameter, and the Engram adds 110.6 GB. — [ISTA DS Coder card](https://huggingface.co/ISTA-DASLab/DeepSeek-V4.1-Flash-1017-GSQ-RCO-Coder-GGUF), [v0.2.10](https://github.com/Niko1221/Strata/releases/tag/v0.2.10)
- **Benchmarks (ISTA, vendor, reasoning effort 50):** SWE-bench Verified 77.00 against 81.20 for the base (94.8%); LiveCodeBench v6 88.57 against 89.71 (98.7%). — [ISTA DS Coder card](https://huggingface.co/ISTA-DASLab/DeepSeek-V4.1-Flash-1017-GSQ-RCO-Coder-GGUF)
- **Strata quality measurement:** KL 0.397, top-1 76.4%, perplexity 4.645 against 3.140 for the original. By part, KL is 0.230 on code and 0.199 on agent text. Its 61-task suite scored 54/61, the same as the 2.00 and 2.25 sets. — [v0.2.10](https://github.com/Niko1221/Strata/releases/tag/v0.2.10)
- **Speed on one R9700:** 22.8 tok/s (package 0.1.55) and 25.6 tok/s (test engine). — [v0.2.10](https://github.com/Niko1221/Strata/releases/tag/v0.2.10)

### Inferences
- The Qwen Coder is the same base model as the baseline, with half its experts removed and more aggressive quantization. Its SWE-bench Verified of 79.2 sits below the base model's 82.8, and the UD-IQ4_XS baseline is closer to full quality.
  - Its only advantages are VRAM and RAM headroom, which ryzen does not need, and possibly faster prompt reading. It would not outperform the baseline for agentic Rust.
  - Its weakness outside code is a minor concern for Rust, though Rust is less represented than Python in calibration sets. That last point is my assumption, not sourced.
- The DeepSeek ISTA-DAS Coder is the only DeepSeek variant that fits ryzen's RAM plus VRAM. Its full-precision parent scores much higher on DeepSWE than Qwen. After pruning and 2-bit quantization, though, its SWE-bench Verified of 77.0 is below the Qwen BF16 base's 82.8 on ISTA's own cards (different reasoning efforts: 50 vs xhigh).
  - It is unclear whether it beats the Qwen UD-IQ4_XS baseline on agentic coding.
  - It is clearly about 3.5–4x slower to decode, and runs only on Strata ≤0.2.13.

### Gaps
- No DeepSWE, SWE-bench Pro or Terminal-Bench results for either Coder model. ISTA reports only SWE-bench Verified and LCB v6.
- No R9700 decode measurement for the Qwen Coder on a current engine.

## Q4: Other models in Strata's catalog and their relevance

### Takeaway
Current Strata (0.2.18) supports only Qwen-family models. Apart from the baseline and quant variants of the same model, the candidates are Qwen3.6-35B-A3B, which is faster but a much smaller model, and Swift 1.5, a shorter-thinking fine-tune. The only real upgrade within the same model is a higher-bit Unsloth quant, and ryzen's RAM is just at the margin for UD-Q4_K_XL.

### Cited Findings
- **Families in MODELS.md:**
  - Qwen3.8-Flash-Next ISTA-DASLab sizes Q2_0, IQ2_XS, IQ3_XXS and IQ3_S (37.6–54.8 GB).
  - The Coder.
  - Swift 1.5, an UkisAI fine-tune that "thinks much shorter... about the same quality", same speed and RAM as the original, under its own license.
  - Unsloth UD-IQ4_XS to Q8_0.
  - Gyro-S and Gyro-M (agentionai trellis quantization; Gyro-M decodes 16–21% slower than Q2_0 on an R9700).
  - NVFP4 (NVIDIA only).
  - OrcaRouter Uncensored IQ3_XXS (manual setup only).
  - Qwen3.6-35B-A3B.

  — [MODELS.md](https://github.com/Niko1221/Strata/blob/main/docs/MODELS.md)
- **Unsloth Qwen3.8-Flash-Next files:**

  | File | Download | Experts | RAM for all experts | Same top token as Q8_0 |
  |---|---|---|---|---|
  | UD-IQ4_XS | 94 GB | 55 GiB | ~72 GB | 88.9% |
  | UD-Q4_K_XL | 111 GB | 72 GiB | ~88 GB | 93.1% |
  | UD-Q5_K_XL | 158 GB | 92 GiB | ~108 GB | 94.6% |

  Setup keeps every expert in RAM only when they fit with 16 GB to spare; otherwise it streams the rest from SSD. — [MODELS.md](https://github.com/Niko1221/Strata/blob/main/docs/MODELS.md)
- **Older R9700 Unsloth speeds (engines before 0.1.45.3):**

  | File | Story decode | Code decode | 32K prompt |
  |---|---|---|---|
  | UD-Q4_K_XL | 63 tok/s | 87 tok/s | 1,110–1,320 tok/s |
  | UD-Q5_K_XL | 57–60 tok/s | 82 tok/s | 810–1,260 tok/s |
  | IQ3_S | 75 tok/s | 95 tok/s | n/a |

  — [MODELS.md](https://github.com/Niko1221/Strata/blob/main/docs/MODELS.md)
- **Qwen3.6-35B-A3B** (35B total, 3B active, 256 experts, Apache 2.0), Unsloth MTP GGUFs:

  | File | Size | RAM setup plans for |
  |---|---|---|
  | UD-Q4_K_XL | 22.9 GB | 32 GB |
  | UD-Q6_K_XL | 32.6 GB | 44 GB |
  | Q8_0 | 37.8 GB | 52 GB |

  R9700 decode was 117.8 tok/s on UD-Q4_K_XL. — [MODELS.md](https://github.com/Niko1221/Strata/blob/main/docs/MODELS.md)
- **Strata's position on other architectures:** a community comment in #6072 says the maintainer declined in issue #310 to support other MoE architectures (DeepSeek, GLM). This is second-hand. — [Issue #6072](https://github.com/Niko1221/Strata/issues/6072)

### Inferences
- **Qwen3.6-35B-A3B** is only about 25% faster to decode (117.8 against 80–95 tok/s) and is a much smaller model. It is unlikely to beat Flash-Next on long agentic Rust work; I found no benchmark evidence in Strata docs either way.
- **UD-Q4_K_XL** of the same Qwen model needs about 88 GB of RAM for all experts, slightly more than ryzen's ~85 GiB budget. Strata would keep most experts in RAM and stream a few. It would give a modest quality gain (93.1% vs 88.9% top-1 agreement with Q8_0, KL 0.056 vs 0.101), probably at a small speed cost. This is the lowest-risk "better quality" option, but it is not a different model.
- **Swift 1.5** may help multi-hour agent runs through shorter thinking. Quality claims are vendor-only, and its license needs checking.

### Gaps
- No coding-agent benchmarks for Swift 1.5, Gyro or Qwen3.6-35B-A3B were gathered in this pass.
- I did not verify Strata's setup.py catalog source directly; MODELS.md and the release notes were used instead.

## Q5: Quality of Strata's quants (KL numbers)

### Takeaway
For Qwen3.8-Flash-Next, the baseline's UD-IQ4_XS has mean KL 0.101 against Q8_0. UD-Q4_K_XL (0.056) and UD-Q5_K_XL (0.038) are better, while IQ3_S (0.144) and Q2_0 (0.315) are worse. For DeepSeek, the sets that fit ryzen are much further from their reference, but the references differ, so the KL figures are not directly comparable across models.

### Cited Findings
- **QUANTS.md, Qwen3.8-Flash-Next** (AMD box: EPYC 7452 plus R9700, HIP; 4,995 positions; KL(Q8_0 || quant) over Q8_0's top 64 tokens). — [QUANTS.md](https://github.com/Niko1221/Strata/blob/main/docs/QUANTS.md)

  | Quant | Same top token as Q8_0 | Mean KL | KL p99 | Perplexity (Q8_0: 4.052) |
  |---|---|---|---|---|
  | UD-Q6_K_XL | 94.61% | 0.033 | 0.494 | 4.020 |
  | UD-Q5_K_XL | 94.55% | 0.038 | 0.636 | 4.024 |
  | UD-Q4_K_XL | 93.09% | 0.056 | 0.829 | 4.068 |
  | **UD-IQ4_XS (baseline)** | **88.91%** | **0.101** | **1.596** | **4.120** |
  | IQ3_S | 87.69% | 0.144 | 1.975 | 4.097 |
  | IQ3_XXS | 84.46% | 0.202 | 2.433 | 4.119 |
  | Q2_0 | 80.60% | 0.315 | 3.643 | 4.475 |

- I found no KL figure for the Qwen Coder in QUANTS.md.
- **DeepSeek, measured by Strata against the original model (4,995 positions):**

  | Set | KL | Perplexity (original 3.140) | Top-1 |
  |---|---|---|---|
  | ISTA-DAS 2.25 | 0.109 | 3.405 | n/a |
  | ISTA-DAS 2.00 | 0.171 | 3.630 | n/a |
  | ISTA-DAS Coder | 0.397 | 4.645 | 76.4% |

  Against Unsloth's Q8_K_XL reference: UD-IQ1_M 0.087, UD-IQ1_S 0.114, ISTA 2.25 0.110. — [v0.2.10](https://github.com/Niko1221/Strata/releases/tag/v0.2.10), [v0.2.9](https://github.com/Niko1221/Strata/releases/tag/v0.2.9)

### Inferences
- On ryzen, DeepSeek in RAM plus VRAM means the Coder, at KL 0.397. That is a much larger departure from its parent than the baseline's 0.101. Even so, the DeepSeek parent's much higher DeepSWE score might keep it competitive.
- The unpruned DeepSeek sets are near the baseline's KL level (0.087–0.11), but they need SSD streaming on ryzen. That makes them slower still and carries the known risk of broken tool calls while streaming.

### Gaps
- KL figures are measured against different references (Q8_0, original FP8/FP4, Unsloth Q8_K_XL), so they cannot be compared directly across models.
- No end-to-end agent benchmark on any Strata quant of either model.
