# Hardware feasibility: big MoE / dense LLMs on 1x R9700 32GB + Ryzen 9 7950X3D + 93 GiB DDR5

Scope: what decode (tg) and prompt-processing (pp) speeds, and what usable context, to expect on this box for a model of a given total/active size and quant, per runtime. Baseline to beat: Qwen3.8-Flash-Next (125B total / ~6B active) on Strata = decode 80–95 tok/s, prompt 1.2–2.2K tok/s at 100–246K context; the same box on llama.cpp `--n-cpu-moe 40` = pp 286–449 / tg 12.5–29 tok/s (user's own measurements, from the assignment brief).

Research date 2026-11-21. Research ran to about 17 tool calls, so some model-specific numbers (GLM-5.x, MiniMax-M3.x, MiMo, Hy4-Flash) were not found and are listed under Gaps.

---

## 1. Community benchmarks: big MoEs on 16–32 GB AMD/NVIDIA GPUs with DDR5 offload

### Takeaway
Off Strata, every measured 100–300B MoE with CPU expert offload on a single 24–32 GB card and desktop dual-channel DDR5 decodes at roughly **10–30 tok/s**, with prompt processing of roughly **65–450 tok/s**. That is 3–8x slower decode and 3–10x slower prefill than Strata gets on this box. The only runtime that measurably reaches about 90 tok/s decode and roughly 700–2,000 tok/s prefill with a model larger than VRAM on an R9700 is Strata, and only for Qwen3.8-Flash-Next.

### Cited Findings
**Strata (Qwen3.8-Flash-Next only)**
- **R9700 32 GB, gfx1201** (Strata frozen 0.1.40.3, ROCm 7.2.3, ISTA IQ3_S, int8 KV, 147,456 max context, MTP spec 4). Host: two EPYC 9334 with 503 GiB RAM, not a desktop CPU. Medians:

  | Input tokens | Prompt tok/s | Decode tok/s |
  | ---: | ---: | ---: |
  | 1K | 632.9 | 101.9 |
  | 4K | 768.1 | 96.4 |
  | 32K | 750.5 | 95.6 |
  | 128K | 718.4 | 87.6 |

  The expert cache auto-sized to 13,021 slots (24.71 GiB) of VRAM, and peak process VRAM was 30.84 GiB. The PCIe probe measured 36.9 GB/s H2D. — [Strata R9700 community bench (2026-10-08)](https://raw.githubusercontent.com/Niko1221/Strata/HEAD/docs/bench-results/2026-10-08-community-r9700-linux/README.md)
- **RX 9070 16 GB (gfx1201), Ryzen 7 5800X3D, 64 GB** (Strata 0.1.41, Windows HIP, IQ3_XXS, 131K context): decode 58.7 / 57.9 / 57.9 tok/s and prompt 586 / 804 / 833 tok/s at 4.2K / 33.5K / about 130K tokens. Needle recall was 6/6 at 33.5K and 130K. — [Strata COMMUNITY_BENCHMARKS.md](https://github.com/Niko1221/Strata/blob/HEAD/docs/COMMUNITY_BENCHMARKS.md)
- **RX 7900 XTX 24 GB, Ryzen 9 7950X3D (same CPU as this box), 64 GB RAM** (ROCm 7.1, IQ3_XXS, 262,144 context, int8 KV, Strata v0.2.15-era HIP MMQ build, 2026-09-29): prefill 447–966 tok/s on 4.2K–8.8K prompts, decode 55.5–59.2 tok/s. — [Strata AMD_HIP_PERFORMANCE.md](https://github.com/Niko1221/Strata/blob/HEAD/docs/AMD_HIP_PERFORMANCE.md)
- **Other Strata reference points (same model):**
  - 2x TITAN RTX: decode 70.9–77.3, prompt 869–1,627 tok/s at 4K–128K.
  - Strix Halo 395 laptop at 70 W (UD-IQ4_XS): decode 59.2 / 57.8 / 42.0 and prompt 969–1,067 tok/s at 8K / 32K / 131K.
  - Radeon Pro VII 16 GB, IQ2_XS: decode about 24, prompt 284–350.

  — [Strata COMMUNITY_BENCHMARKS.md](https://github.com/Niko1221/Strata/blob/HEAD/docs/COMMUNITY_BENCHMARKS.md)

**llama.cpp with expert offload (`--n-cpu-moe` / `-ot exps=CPU`)**
- **DeepSeek-V4-Flash (284B total / 13B active)**, mainline llama.cpp after PR #24162 (merged around late June 2026):
  - RTX 3090 Ti 24 GB, Ryzen 9950X, 96 GB DDR5-6400, ubergarm IQ2_XXS/Q2_K mix with Q8 attention and shared experts, `--n-cpu-moe 40`, `-c 98304`: about **150 tok/s pp and about 15 tok/s tg** at short context. This is the closest analogue to this box.
  - `-ctk q8_0 -ctv q8_0` produced garbled output.
  - On RTX 5090 + 5070 Ti with 8-channel RAM, Q4_K_M-XL, `--n-cpu-moe 48`, 135K context: pp 64–74 and tg 18.8–20.3 tok/s.
  - One user found its agentic output weaker than Qwen3.6-27B. On one coding task it took 46.5 minutes against about 8 minutes for Qwen3.6-27B.

  — [HF antirez/deepseek-v4-gguf discussion #16](https://huggingface.co/antirez/deepseek-v4-gguf/discussions/16)
- **DeepSeek V4 Flash on other hardware:**
  - A single RTX Pro 6000 96 GB with the 146 GB FP4/FP8 GGUF partly offloaded gets about 8–12 tok/s at about 32K. That guide used a pre-merge fork branch. — [aimastery guide](https://www.aimastery.page/guides/run-deepseek-v4-flash-locally-llamacpp)
  - A DGX Spark gets 19.7 tok/s single-stream at 131K context per slot. — [NVIDIA forum](https://forums.developer.nvidia.com/t/1x-dgx-spark-deepseek-v4-flash-0731-on-llama-cpp-131k-ctx-slot-19-7-tok-s-single-stream-52-tok-s-4-concurrent/379129) (search snippet only)
- **gpt-oss-120b (about 117B total / 5.1B active, MXFP4)**, compiled by GPUwerk from third-party sources:

  | GPU | RAM / settings | tg tok/s |
  | --- | --- | ---: |
  | RTX 4090 | `--n-cpu-moe 28` | 21.96 |
  | RTX 4090 | `--cpu-moe` | 17.77 |
  | RTX 5090 | `--n-cpu-moe 21` | about 30 |
  | RTX 4070 12 GB | DDR5-6000 2ch | about 28 (pp about 428) |
  | RTX 4070 12 GB | DDR5 at 2,000 MT/s | about 10 |
  | 2x RTX 3090, 7950X, DDR5-5000 | DeepSeek-R1 IQ1_S_R4 | 10.1 tg, about 20 pp |

  The DDR5 2,000 MT/s row shows that decode tracks RAM bandwidth. — [GPUwerk](https://gpuwerk.com/blog/moe-cpu-offload-llama-cpp/)
- **R9700 as a USB4 eGPU on a Framework 13** (topology-limited, from a search-result summary that I did not open):

  | Model | Setting | ROCm tg | Vulkan tg |
  | --- | --- | ---: | ---: |
  | gpt-oss-120b | `--n-cpu-moe 20` | n/a | 13.1 |
  | Qwen Coder Next 80B-A3B | `--n-cpu-moe 19` | 15.3 | 14.6 |
  | Qwen3.5-122B-A10B Q3_K_M | `--n-cpu-moe 25` | 9.3 | 7.8 |

  — [Framework community post](https://community.frame.work/t/fw13-amd-radeon-9700-egpu-razer-core-x-v2-fedora-44-kernel-6-19-rocm-and-vulkan-performance-and-working-setup/82437)
- **Qwen3 122B on 2x R9700** (fully in VRAM, RADV) went from 15 to 48 tok/s tg, about 40 of that from `-ub 2048` alone (builds b9222 to b10068). — [llama.cpp discussion #21043](https://github.com/ggml-org/llama.cpp/discussions/21043)
- **MiniMax-M2.1 UD-Q4_K_XL** with experts on CPU and 72 GB VRAM: about 19–20 tok/s. — [HF unsloth/MiniMax-M2.1-GGUF discussion #2](https://huggingface.co/unsloth/MiniMax-M2.1-GGUF/discussions/2) (search snippet)
- **Pure CPU expert offload with no cache:** a llama.cpp feature request reports roughly 0.5–1 tok/s on a 4090 with a Qwen3-series MoE, and about 21 tok/s with a per-session expert cache. Upstream llama.cpp has no GPU hot-expert cache; this is an open feature request. — [llama.cpp issue #20757](https://github.com/ggml-org/llama.cpp/issues/20757)

### Inferences
- This box's own llama.cpp result for Qwen3.8-Flash-Next (tg 12.5–29, pp 286–449) is consistent with the community llama.cpp offload numbers above. Strata's about 3–5x decode advantage on the same model comes from three things: the VRAM expert cache, MTP speculative decoding, and large-chunk prefill with expert streaming over PCIe.
- For any non-Strata model larger than about 30 GB at the chosen quant, plan on llama.cpp-class numbers: **tg about 10–25 tok/s and pp about 100–450 tok/s**, falling further at long context.
- A 13B-active model such as DeepSeek-V4-Flash should land at about 12–18 tok/s tg here. DDR5 on the 7950X3D is probably slower than the 3090 Ti host's DDR5-6400, so 15 tok/s is an upper-middle estimate.

### Gaps
- I found no measurements of GLM-5.x (-Air/-Flash), MiniMax-M3.x, MiMo, Hy4-Flash or Qwen3.8 non-Flash variants on a single 24–32 GB GPU with offload. Searches returned nothing model-specific.
- I found no R9700-in-a-slot llama.cpp `--n-cpu-moe` sweeps at 64K–256K depth.

---

## 2. Rule-of-thumb decode/prefill model, and how much hot-expert caching helps

### Takeaway
Use **decode tok/s ≈ η · BW_RAM / (bytes of active expert weights read from RAM per token)**, with η ≈ 0.4–0.6 on llama.cpp. GPU-resident layers add a small fixed time. For this box (dual-channel DDR5, roughly 60–80 GB/s usable), that gives roughly 25–40 tok/s for 5B-active at about 4 bits, 12–20 for 13B-active at 2–3 bits, and under 10 for 20B-plus active.

A VRAM hot-expert cache (Strata) moves most expert reads to VRAM at 640 GB/s; MTP or speculative decoding then multiplies the result by about 1.6–1.8x. Together these explain about 90 tok/s against about 20.

### Cited Findings
- **Formula:** decode ceiling = RAM bandwidth ÷ expert GB read per token, with real runs reaching "about 40 to 60%" of the ceiling.
  - Bandwidth = channels × MT/s × 8 bytes, so dual-channel DDR5-6000 = 96 GB/s.
  - gpt-oss-120b reads about 1.90 GB of experts per token (MXFP4), so the ceiling is about 50 tok/s and the measured result about 28 tok/s.
  - Qwen3-235B-A22B reads 5.36 GB per token at UD-Q2_K_XL and 8.11 GB at UD-Q4_K_XL.
  - Qwen3-235B-A22B UD-Q2_K_XL on ik_llama.cpp measured 7.5–8.0 tok/s at 16K.

  — [GPUwerk](https://gpuwerk.com/blog/moe-cpu-offload-llama-cpp/)
- **Prefill on llama.cpp:** for batches above 32 tokens, llama.cpp copies CPU-held expert weights to the GPU over PCIe and computes there, and larger `-b`/`-ub` (for example 4096) amortize the copy. Prefill is therefore bounded by PCIe bandwidth × batch size rather than by CPU speed. — [GPUwerk](https://gpuwerk.com/blog/moe-cpu-offload-llama-cpp/)
- **Strata's design:**
  - GPU holds: attention and DeltaNet mixers, routers, shared experts, the head, the MTP layer, the hottest part of the KV cache (from 64K, the rest streams from RAM), and an expert cache filling the rest of VRAM.
  - RAM holds: all experts, which the CPU computes in place (AVX-512) in parallel with the GPU.
  - Strata says "every extra GB holds ~700 more experts".
  - MTP drafts up to 3 tokens, with 2.4–3.2 tokens accepted per pass, making output "1.6–1.8x sooner".
  - Prefill uses chunks of up to 8,192 tokens, with the next layer's experts streamed over PCIe during attention.

  — [Strata HOW_IT_WORKS.md](https://github.com/Niko1221/Strata/blob/HEAD/docs/HOW_IT_WORKS.md)
- **Strata cache hit-rate effects:**
  - Adaptive expert admission (`STRATA_ADAPT_FETCH`) raised the hit rate from 54–61% to 71–78% with a cache holding 16% of experts, worth +10% decode.
  - Running out of VRAM headroom matters a great deal: 453 slots (0.86 GiB) separated 13.7 from 102 tok/s in one report.
  - A 2x Xeon box with a 98% VRAM hit rate reached 65.5–75.1 tok/s.

  — [Strata DETAILS.md](https://github.com/Niko1221/Strata/blob/HEAD/docs/DETAILS.md)
- **Default Strata HIP path:** `--pcie-frac` auto (a share of expert misses fetched over PCIe instead of computed on CPU) is the default for gfx1200/gfx1201. — [Strata DETAILS.md](https://github.com/Niko1221/Strata/blob/HEAD/docs/DETAILS.md)
- **Cache pressure from KV:** a larger KV cache in VRAM shrinks the expert cache and makes systems fall back to on-demand expert fetches (MoE-Infinity, DeepSeek-V2-Lite, up to 128K). In llama.cpp, a 40,960-token KV starved the expert page cache for Qwen3-30B-A3B on a constrained device, and shrinking context raised decode about 2.7x. — [MoE-Infinity](https://arxiv.org/pdf/2401.14361); [Budgeting Bytes](https://arxiv.org/pdf/2609.04238)
- **KTransformers on ROCm:** support is "Beta". It was tested only on a 7900 XTX with EPYC 9274F and ROCm 6.2.4 PyTorch, Marlin kernels are unsupported (KLinearTorch must be used instead), and "Q8 linear implementation ... shows suboptimal performance". There is no RDNA4 validation. — [KTransformers ROCm doc](https://kvcache-ai.github.io/ktransformers/en/ROCm.html)
- **ik_llama.cpp:** an RX 7900 XTX user reports that "Vulkan and ROCm backends are not the focus of this fork", that the Vulkan backend is slower than mainline, and that they could not compile it with HIP. The post is undated. — [ik_llama.cpp discussion #562](https://github.com/ikawrakow/ik_llama.cpp/discussions/562)

### Inferences
**Worked model for this box** (assumptions: BW_RAM ≈ 65 GB/s usable, η ≈ 0.5, so about 32 GB/s effective; the assumption is not measured, see Gaps):

| Active experts read from RAM per token | Expected tg |
| ---: | ---: |
| about 2 GB (5B active at about 3–4 bit; gpt-oss-120b class) | about 15–30 tok/s |
| about 4–5 GB (13B active at 2.5–3 bit; DeepSeek-V4-Flash class) | about 7–15 tok/s |
| about 8 GB (20B-plus active at 3–4 bit) | about 4–8 tok/s |

Putting more expert layers on the GPU via a lower `--n-cpu-moe` scales this by 1 / (1 − fraction of expert bytes in VRAM). Static per-layer offload gets little from a 32 GB card when the expert pool is 50–100 GB.

- **Strata-style hot-expert caching** turns a 24 GiB cache of a Zipf-skewed expert distribution into roughly 60–98% VRAM hits. On top of that come MTP at about 1.6–1.8x and in-place AVX-512 CPU compute. The net effect is about 4–5x over llama.cpp on the same model and box (90 against about 20 tok/s).
- **KTransformers and ik_llama.cpp** offer CPU-side kernel speedups on CUDA, but neither has a credible validated path on gfx1201 today. Treat them as non-options unless a recent R9700 report appears.
- **Prefill estimate:** with llama.cpp offload, prefill is limited by PCIe copy of expert weights per ubatch. Expect a few hundred tok/s, which matches the observed pp 286–449. Strata reaches 700–2,000 by using 8K chunks and overlapping streaming.

### Gaps
- I did not measure or find a source for the actual DDR5 speed and STREAM bandwidth of this box. A 93.4 GiB visible total suggests non-standard DIMMs (for example 2x48 GB). If it is a four-DIMM configuration, it probably runs below DDR5-5200. A quick `mlc` or STREAM run would pin BW_RAM.
- I found no published Strata hit-rate figure specifically for the R9700 at 128K–246K context.

---

## 3. Long-context KV cost by attention type, and which architectures stay fast on llama.cpp

### Takeaway
Hybrid linear-attention models (Qwen3-Next / Qwen3.8-Flash-Next, with DeltaNet in most layers) and compressed or sparse attention (DeepSeek MLA, V4's CSA+HCA) keep KV small enough for 128–256K on a 32 GB card. Classic full-GQA models at 128K+ eat VRAM that would otherwise hold experts, which hurts offloaded decode twice: less expert cache, plus attention over the long KV.

There is little measured llama.cpp data past 64K on RDNA4. The best data point shows a dense 27B with MTP decoding at 42.8 tok/s at 3.7K and 28.0 at 59K on ROCm.

### Cited Findings
- **Qwen3.6-27B Q8_0 + MTP, q4_0 KV, single R9700, llama.cpp `full-rocm` b9209, ROCm 7.2.1:**

  | Prompt tokens | pp tok/s | tg tok/s |
  | ---: | ---: | ---: |
  | about 3.7K | 960 | 42.8 |
  | about 22K | 898 | 35.7 |
  | about 48K | 756 | 30.4 |
  | about 59K | 708 | 28.0 |

  Power draw was about 298 W. — [llama.cpp discussion #21043](https://github.com/ggml-org/llama.cpp/discussions/21043)
- **Dual R9700, Qwen3.6-35B-A3B UD-Q8_K_XL, f16 KV:** pp 4,701 at 16K and 3,249 at 64K. tg held at 83.5 tok/s at 64K depth with no drop: 72.8 at tg128 and 83.6 at 16K. MTP lifted it to about 89. — [llama.cpp discussion #21043](https://github.com/ggml-org/llama.cpp/discussions/21043)
- **Strata on R9700:** decode fell only from 101.9 to 87.6 tok/s between 1K and 128K, with int8 KV and 32,768 resident KV cells (the rest streamed from RAM). — [Strata R9700 bench](https://raw.githubusercontent.com/Niko1221/Strata/HEAD/docs/bench-results/2026-10-08-community-r9700-linux/README.md)
- **Strata KV and state sizes:** from 64K only the most-read part of the KV stays on GPU and the rest streams from RAM. A DeltaNet state checkpoint is 118 MB for Qwen3.8-Flash-Next. — [Strata HOW_IT_WORKS.md](https://github.com/Niko1221/Strata/blob/HEAD/docs/HOW_IT_WORKS.md); [Strata DETAILS.md](https://github.com/Niko1221/Strata/blob/HEAD/docs/DETAILS.md)
- **DeepSeek-V4-Flash:** uses "hybrid CSA+HCA attention" (compressed/sparse). — [aimastery guide](https://www.aimastery.page/guides/run-deepseek-v4-flash-locally-llamacpp)
  - A 3090 Ti user ran 98,304 context with only 24 GB VRAM (and about 135K on another rig), raising `--n-cpu-moe` to free VRAM for context. KV quantization to q8_0 garbled output at the time. — [HF discussion #16](https://huggingface.co/antirez/deepseek-v4-gguf/discussions/16)
- **Prefill depth on CUDA (Nemotron 30B-A3B hybrid):** llama-bench pp fell from about 1,883 tok/s at 8K to about 996 at 48K. — [NVIDIA forum](https://forums.developer.nvidia.com/t/what-prompt-processing-speed-can-one-expect-above-500k-ctx/355437) (search summary)
- **vLLM pre-allocated KV on R9700:** the startup log of a Qwen3-30B-A3B AWQ run showed 17.54 GiB of weights and 7.71 GiB of KV holding 84,224 tokens. — [deepindeepsea R9700 vLLM Part 1](https://deepindeepsea.github.io/r9700-vllm-blogs/part1-r9700-meet-the-card.html)

### Inferences
- KV-per-token sizes in this section come from my background knowledge of the architectures, not from a source I fetched in this run. The report writer should verify them against model configs.
  - **GQA, all layers full attention** (for example a 60-layer model with 8 KV heads × 128 dim, fp16): about 240 KB/token, or about 30 GB at 128K. This doesn't fit alongside experts on 32 GB. q8 KV halves it, and many such models use KV quant poorly.
  - **Hybrid DeltaNet 3:1** (Qwen3-Next / Qwen3.8-Flash-Next, Qwen3.5/3.6): only about 1/4 of layers keep KV, plus a fixed-size recurrent state. That makes 256K cheap, which is why Strata and llama.cpp keep decode flat to 128K.
  - **MLA** (DeepSeek V2/V3, Kimi): a compressed latent of about 70 KB/token at fp16. DeepSeek V4's CSA+HCA compresses further.
  - **Sliding window + global layers** (gpt-oss: alternating 128-token SWA and full layers; Gemma): about half the full-layer KV.
- **On llama.cpp with expert offload**, context length costs twice: KV takes VRAM that would otherwise hold expert layers (a higher `--n-cpu-moe` means slower decode), and attention compute grows with depth. Hybrid linear-attention and MLA/CSA models degrade least.
- **For agentic coding at 100–250K context on this box**, favor hybrid linear-attention or compressed-attention models. A full-GQA 100B+ MoE at 200K would likely need q8 or q4 KV and push most experts to CPU.

### Gaps
- I found no measured llama.cpp tg/pp at 128K–256K depth on any RDNA4 card for an offloaded MoE.
- I did not fetch per-model KV-per-token sizes for GLM-5.x, MiniMax-M3, MiMo or Hy4-Flash, or the exact KV size of DeepSeek V4's CSA+HCA.

---

## 4. Quantization quality: how low can big MoEs go?

### Takeaway
Unsloth's own data and guidance put the practical floor for tool calling and agentic use at **UD-Q2_K_XL**. Below it (IQ2_S, 1-bit), tool calling and non-thinking modes break down, with failed or looping tool calls. 3-bit and 4-bit are the best size-to-accuracy range.

Unsloth claims its new Dynamic V3.1 (Nov 2026) 1-bit quants of DeepSeek-V4.1-Flash and Qwen3.8-Flash-Next score well on agentic benchmarks. That is a vendor claim that conflicts with its own earlier guidance, so treat it with caution.

### Cited Findings
- **Unsloth Dynamic v3.0 guidance:**
  - Don't use 1-bit quants for tool calling: models "may fail to call tools, loop on calls, or call them incorrectly".
  - The recommended minimum is UD-Q2_K_XL.
  - Below Q2_K_XL, set `presence_penalty` ≥ 1.5 to curb looping, and keep thinking on, since non-reasoning modes can produce empty output at 1-bit.
  - On Qwen3.8-27B, 32-token greedy agreement with BF16 drops from about 25% at UD-Q2_K_XL to 8–10% at IQ2_S and below.

  — [Unsloth Dynamic 3.0 docs](https://unsloth.ai/docs/basics/dynamic-3.0-ggufs)
- **Unsloth Dynamic V3.1 (Nov 2026) claims:**

  | Model / quant | DeepSWE v1.1 | Terminal Bench 2.1 | Automation Bench |
  | --- | ---: | ---: | ---: |
  | DeepSeek-V4.1-Flash-1017 IQ1_S | 65.8% | 69.5% | 51.5% |
  | Qwen3.8-Flash-Next 1-bit | 54.0% | 68.3% | n/a |

  Unsloth also claims 10–15% higher accuracy and about 50% fewer tokens than other quants of equal size. These are vendor results with no BF16 baseline given in the text. — [Unsloth Dynamic 3.0 docs](https://unsloth.ai/docs/basics/dynamic-3.0-ggufs)
- **Older KLD data (Gemma 3 27B, Unsloth v2.0):**

  | Quant | KLD |
  | --- | ---: |
  | IQ1_S | 0.97 |
  | IQ2_XXS | 0.52 |
  | IQ2_M | 0.26 |
  | Q2_K_XL | 0.22 |
  | Q3_K_XL | 0.081 |
  | Q4_K_XL | 0.024 |

  MMLU 5-shot: Q4_K_XL 71.47%, Q2_K_XL 68.70%, BF16 71.5%. — [Unsloth docs](https://unsloth.ai/docs/basics/dynamic-3.0-ggufs)
- **Aider Polyglot, DeepSeek V3.1 (Sept 2025):** dynamic 3-bit scored 75.6%. In non-reasoning mode, 5-bit scored 70.7% Pass-2 and 1-bit 55.7%. — [Unsloth Aider page](https://unsloth.ai/docs/basics/unsloth-dynamic-2.0-ggufs/unsloth-dynamic-ggufs-on-aider-polyglot)
- **Strata's Qwen3.8-Flash-Next packs:**

  | Pack | Size | Top-token agreement with Q8_0 |
  | --- | ---: | ---: |
  | ISTA Q2_0 | 37.6 GB | n/a |
  | ISTA IQ2_XS | 39.2 GB | n/a |
  | ISTA IQ3_XXS | 47.0 GB | n/a |
  | ISTA IQ3_S | 54.8 GB | n/a ("matches the full model on the published tests") |
  | Unsloth UD-IQ4_XS | 55 GiB experts | 88.9% |
  | Unsloth UD-Q4_K_XL | 72 GiB experts | 93.1% |
  | Unsloth UD-Q5_K_XL | 92 GiB experts | 94.6% |

  The Coder IQ1_M variant prunes half the experts and claims 91% of the full model's SWE-bench Verified. — [Strata MODELS.md](https://github.com/Niko1221/Strata/blob/HEAD/docs/MODELS.md)
- **Pairing ISTA IQ3_XXS with Strata:** a matched 32K coding comparison on an RX 9060 XT passed 9/9 tasks for both IQ2_XS and IQ3_XXS, with IQ2_XS decoding about 17% faster. — [Strata COMMUNITY_BENCHMARKS.md](https://github.com/Niko1221/Strata/blob/HEAD/docs/COMMUNITY_BENCHMARKS.md)

### Inferences
- **For agentic coding with tool calls, budget at least about 2.7–3.5 bits per weight average** (UD-Q2_K_XL to Q3_K_XL class) for 100–300B MoEs. Under the 85 GiB usable RAM + VRAM budget minus KV and OS, that caps total parameters at about 200–230B at about 3 bits, or about 280B at about 2.3 bits (DeepSeek-V4-Flash at IQ2_XXS-mix is about at that edge).
- **The 1-bit agentic claims** (V3.1) are worth a test because they would let 284B-class models fit easily, but they come from the vendor only.

### Gaps
- I found no independent (non-vendor) agentic or tool-calling evaluation of 2–3-bit quants for GLM-5.x, MiniMax-M3 or DeepSeek-V4-Flash.

---

## 5. vLLM / SGLang on gfx1201

### Takeaway
vLLM runs on the R9700 for models that fit entirely in 32 GB, but only via vendor dev images or community forks:
- AMD `rocm/vllm-dev` navi image (vLLM 0.16, AWQ via compressed-tensors).
- Capicua25x `vllm-rocm-rdna4` (vLLM 0.28.0, focused on MXFP4, with FP8 partial).

FP8 on gfx1201 is only partly upstream, and AITER (AMD's fast MoE/attention kernels) targets Instinct cards. vLLM CPU offload is not MoE-expert-aware: it streams offloaded weights every forward pass. **vLLM and SGLang are not a realistic route for a model larger than 32 GB on this box.** I found no SGLang gfx1201 evidence.

### Cited Findings
- **AMD field engineer blog (May 2026):** R9700 with vLLM 0.16 from `rocm/vllm-dev:rocm7.2.1_navi_ubuntu24.04_py3.12_pytorch_2.9_vllm_0.16.0` on ROCm 7.2.1.
  - AWQ 4-bit loads as compressed-tensors.
  - A dense 14B AWQ model ran single-stream at 7.5 tok/s, which looks anomalously low next to llama.cpp's about 30 tok/s for a 27B Q4.
  - Qwen3-30B-A3B AWQ startup: 17.54 GiB weights, 7.71 GiB KV = 84K tokens, VRAM at about 92% pre-allocated.

  — [deepindeepsea R9700 vLLM Part 1](https://deepindeepsea.github.io/r9700-vllm-blogs/part1-r9700-meet-the-card.html)
- **Capicua25x/vllm-rocm-rdna4** (vLLM 0.28.0-rdna4, rc12 dated 2026-08-28) is a fork carrying a native MXFP4 linear kernel and a spec-decode fix for gfx1200/1201.
  - Validated models include Ornith-1.5-35B-A3B MXFP4, Gemma-4-26B-A4B MXFP4 (262K window) and Gemma-4-31B dense MXFP4 (262K with fp8 KV).
  - The page gives no absolute tok/s, and does not mention AWQ, GPTQ, GGUF or CPU offload.

  — [GitHub Capicua25x/vllm-rocm-rdna4](https://github.com/Capicua25x/vllm-rocm-rdna4)
- **Native FP8 on RDNA4 in vLLM:** one write-up says it is not fully merged and needs local patches and kernel configs. Another says vLLM PR #28649 adds gfx1201 FP8, with the gap on the AITER side. A third-party guide says prebuilt AMD wheels mark AWQ and GPTQ unsupported. These conflict, and all are search snippets. — [vLLM forum](https://discuss.vllm.ai/t/native-fp8-wmma-support-for-amd-rdna4-rx-9070-xt-r9700-in-vllm/1900); [ROCm/aiter issue #900 (gfx1201 support question)](https://github.com/ROCm/aiter/issues/900); [vdf.ai](https://vdf.ai/blog/amd-radeon-ai-pro-r9700-local-llm/)
- **vLLM CPU offload for MoE:** the offload "moves weights to CPU memory and streams them to the GPU during each forward pass ... slow ... no support for on-demand loading of only the gated experts". A hot-expert GPU cache for MoE is an RFC (#33869), not confirmed shipped. — [vLLM forum](https://discuss.vllm.ai/t/enable-expert-offloading/1884); [vLLM RFC #33869](https://github.com/vllm-project/vllm/issues/33869)
- **Multi-R9700 regression:** a 4x R9700 vLLM 0.23 / ROCm 7.14 upgrade thread reports a 50% regression on one model. — [Level1Techs](https://forum.level1techs.com/t/vllm-0-23-x-rocm-7-14-upgrade-on-4x-radeon-ai-pro-r9700-50-regression-on-one-model-unaffected-on-another-but-a-free-9-via-kernel-tuning/253460) (title only)

### Inferences
- vLLM is only worth considering on this box for a model that fits in VRAM: a 27–35B dense or A3B MoE at 4-bit (AWQ or MXFP4) or FP8, and preferably for concurrent agent sessions, where batching helps. For single-stream agentic use, llama.cpp is as fast or faster and much simpler on RDNA4.
- Streaming every offloaded weight over PCIe (about 37 GB/s) per token would give under 1 tok/s for a 50 GB offloaded model.

### Gaps
- I found no SGLang-on-gfx1201 reports, no measured single-stream vLLM tok/s on the R9700 for a 27–35B model in FP8/MXFP4, and no Lemonade-stack data. Lemonade appears to package llama.cpp ROCm builds ([lemonade-sdk/llamacpp-rocm](https://github.com/lemonade-sdk/llamacpp-rocm)), so expect llama.cpp performance.

---

## 6. Dense 27–32B and small MoEs fully in 32 GB VRAM on the R9700

### Takeaway
A dense 27B at Q4 decodes at about **29–33 tok/s** on llama.cpp (Vulkan or ROCm) with pp about 800–990 tok/s. MTP speculative decoding lifts it to **about 47–65 tok/s**, and Q8_0 + MTP at 49K context runs at about 59–65 tok/s on Vulkan. Decode falls with depth (Q8+MTP on ROCm: 42.8 tok/s at 3.7K, 28 at 59K).

A35B-A3B MoE fully in VRAM runs at about 150–164 tok/s decode and 3–4K tok/s prompt. Full offload of a dense 27B is about 3x slower in decode than Strata's 125B MoE.

### Cited Findings
- **Single R9700, Vulkan** (llama.cpp b8554–8740, Mesa 25.2–26.0):
  - Qwen3.5-27B Q4_K_M: tg128 29.1–33.2, pp2048 799–993. Best results came from RADV with `-ub 2048`, `rm_kq=1` and ASPM performance mode.
  - Qwen3.5-35B-A3B UD-Q4_K_XL: tg 147.8–163.7 and pp2048 2,381–3,971 (with `-ub 2048`, RADV; AMDVLK + gfx queue gave the top tg).

  — [llama.cpp discussion #21043](https://github.com/ggml-org/llama.cpp/discussions/21043)
- **MTP on a dense 27B, single R9700:**
  - Qwen3.6-27B UD-Q4_K_XL, q4_0 KV, Vulkan b9203: tg 28.2 to 47.4 (mtp-3), and tg at 16K depth 29.8 to 50.4. pp2048 dropped from 924 to 840.
  - Qwen3.8-27B Q8_0 + MTP, Vulkan: baseline about 59.2 tok/s. Tuned with parallel 3, draft-n-max 7, ubatch 288 and 49K context: an average of 64.95 tok/s over 60 requests (range 53–79).

  — [llama.cpp discussion #21043](https://github.com/ggml-org/llama.cpp/discussions/21043)
- **ROCm against Vulkan:** ROCm with `-sm tensor` was faster for large dense models on dual GPUs, Vulkan faster for small MoEs. A 2x R9700 ROCm 7.2.0 run (b9940) of a Qwen3.6-27B Q6_K gave pp512 812 and tg 33.6. — [llama.cpp discussion #21043](https://github.com/ggml-org/llama.cpp/discussions/21043)
- **R9700 against RTX 5090** on Qwen3.5-35B-A3B: R9700 Vulkan tg about 127.4 tok/s in that comparison. — [llama.cpp discussion #19890](https://github.com/ggml-org/llama.cpp/discussions/19890)
- **R9700 specs:** 32 GB GDDR6, 640 GB/s, 64 MB Infinity Cache, 300 W, PCIe 5.0 x16. — [deepindeepsea](https://deepindeepsea.github.io/r9700-vllm-blogs/part1-r9700-meet-the-card.html)

### Inferences
- Decode ceiling for dense models fully in VRAM ≈ 640 GB/s ÷ weight bytes: about 16 GB at Q4 gives about 40 tok/s, and about 29 GB at Q8 gives about 22 tok/s. Measured runs reach about 75–80% of that before MTP.
- **Context:** a dense 27B at Q4 (about 16–17 GB) leaves about 13 GB for KV. A hybrid-attention Qwen3.6/3.8-27B can then reach 128–256K with q8 or q4 KV, as one user ran Q8_0 weights at 49K. A full-GQA dense 32B would be limited to roughly 64K at f16 KV.
- **Compared with the baseline:** a dense 27B is 2–3x slower in decode (about 30–60 against 80–95 tok/s) and similar or slower in prefill (about 700–990 against 1.2–2.2K tok/s at depth). It would only win on model quality per token. A 35B-A3B in VRAM beats Strata on speed (about 150 tok/s) but is a much smaller model.

### Gaps
- I found no published R9700 numbers for a dense 27–32B at 128K+ depth.
- I found no ROCm/HIP single-R9700 llama-bench at depth 64K–128K for dense models.
- I found no Phoronix R9700 LLM results.

---

## Summary feasibility table (synthesis; each row draws on the sections above)

| Model class (total/active, quant) | Fits 85 GiB RAM + 32 GB VRAM? | Runtime | Expected decode | Expected prefill | Usable context |
| --- | --- | --- | --- | --- | --- |
| Qwen3.8-Flash-Next 125B/6B, IQ3_S | yes | Strata | 80–100 tok/s (measured on the R9700) | 700–2,000 tok/s | 128–262K measured |
| Same model, ISTA packs | yes | llama.cpp `--n-cpu-moe` | 12–29 (measured on this box) | 286–449 | limited by VRAM after expert layers |
| gpt-oss-120b class, about 117B/5B, MXFP4 | yes | llama.cpp offload | about 15–28 (inference from 4070/4090/5090 data, eGPU R9700 13.1) | about 300–450 | 128K (SWA keeps KV small) |
| DeepSeek-V4-Flash 284B/13B, IQ2_XXS mix (about 80 GB) | borderline | llama.cpp offload | about 10–15 (3090 Ti + DDR5-6400: 15) | about 100–150 | about 98K demonstrated on 24 GB; KV quant broken at the time |
| 200–235B / 20B-plus active, Q2–Q3 | borderline | llama.cpp offload | about 5–9 | under 150 | about 32–64K comfortable |
| Dense 27B, Q4–Q8 | yes (VRAM only) | llama.cpp Vulkan/ROCm (+MTP) | 29–33, or 47–65 with MTP; falls with depth | 700–990 | 49–64K measured; more with q4 KV |
| 35B-A3B MoE, Q4–Q8 | yes (VRAM only) | llama.cpp Vulkan | 150–164 | 3–4K | 64K+ measured (on dual cards) |
| Any MoE larger than 32 GB | n/a | vLLM / SGLang | impractical: no expert-aware offload on ROCm | n/a | n/a |
