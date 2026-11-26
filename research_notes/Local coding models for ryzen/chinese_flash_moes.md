# Chinese open-weight "Flash"/mid-size MoEs as local agentic-coding candidates (as of 2026-11-21)

Box: 1x R9700 32GB (ROCm, gfx1201) + ~85 GiB usable DDR5. Weight budget is about 110 GB total, minus KV cache and compute buffers, so in practice about 95–100 GB of weights for 128K+ context. Baseline: Qwen3.8-Flash-Next 125B/A6B at UD-IQ4_XS. Vendor scores: SWE-bench Pro 62.5 (Claude Code harness), SWE-bench Multilingual 81.0, DeepSWE 1.1 58.7, Toolathlon 73.5. Measured on the box: 80–95 tok/s decode.

Research budget note: about 18 tool calls. Most specs come from official HF model cards or Unsloth docs. Where a number comes from aggregators or blogs, it is marked.

## Q1: Specs per model (params, architecture, context, license, release)

### Takeaway
The three named "Flash" models are 300–430B-total MoEs. That is 2.5–3.5x the baseline's size, so "Flash" here does not mean they would fit locally. Only two models released in 2026 are in the baseline's size class: Ling-3.0-flash (124B/A5.1B) and Step 3.7 Flash (198B/A11B).

### Cited Findings
- **GLM-5.3-Flash (Z.ai):** 320B total / 18B active, natively multimodal. Hybrid sparse + linear attention ("lowers long-context serving costs"). 1,048,576 max context, 30T training tokens, and Low/High/Max thinking modes. License is not stated on the Unsloth page. It was released around late Aug / early Sep 2026: the Unsloth page refers to day-0 access and a "Sep 4" update. — [Unsloth docs GLM-5.3-Flash](https://unsloth.ai/docs/models/glm-5.3-flash). The HF arch name is `Glm5NextForConditionalGeneration` / GGUF arch `glm5next`. — [vcruz305 GGUF card](https://huggingface.co/vcruz305/GLM-5.3-Flash-GGUF)
- **MiMo-V2.6-Flash (Xiaomi):** 309B total / 15B active (safetensors show 311B). There are 48 layers: 39 sliding-window (window 128 tokens, 8 KV heads) and 9 global (4 KV heads). It has an MTP drafter, 1M context, and an MIT license. The HF repo is `XiaomiMiMo/MiMo-V2.6-Flash-RL`. — [HF model card](https://huggingface.co/XiaomiMiMo/MiMo-V2.6-Flash-RL). Weights reportedly landed on 2026-09-21, and a later MOPD checkpoint followed on 2026-09-27 (secondary sources). — [RITS/NYU Shanghai](https://rits.shanghai.nyu.edu/ai/xiaomi-open-sources-mimo-v2-6-pro-and-flash-plus-its-rl-stack/), [Baseten MOPD](https://www.baseten.co/library/mimo-v26-flash-mopd/)
- **MiniMax-M3.1-Flash (MiniMax):** 428B total / 23B active, base model MiniMax-M3. — [NVIDIA build model card](https://build.nvidia.com/minimaxai/minimax-m3.1-flash/modelcard). It uses sparse attention in all 60 decoder layers, quantization-aware training, and a draft head for speculative decoding. — [Raschka LLM architecture gallery](https://sebastianraschka.com/llm-architecture-gallery/models/minimax-m3-1-flash-428b/). Context is 1M. — [Fireworks](https://fireworks.ai/models/fireworks/minimax-m3p1-flash/). A secondary source says the model was released 2026-10-19, with weights on HF 2026-10-23 and a "252 GB download". — [aicybr](https://aicybr.com/blog/minimax-m31-flash-open-weights-428b-license-local-deployment), [magica](https://magica.com/news/minimax-m3-1-flash-weights-hugging-face). Another secondary source cautions that some pages borrow the 428B figure from the parent M3, but the NVIDIA card gives 428B/23B for M3.1-Flash itself. — [eesel](https://www.eesel.ai/blog/minimax-m3-1-flash)
- **Step 3.7 Flash (StepFun):** 198B-parameter sparse MoE VLM (196B LM + 1.8B vision encoder), ~11B active, 256K context, Apache 2.0, MTP speculative decoding. — [HF Step-3.7-Flash](https://huggingface.co/stepfun-ai/Step-3.7-Flash), [HF GGUF](https://huggingface.co/stepfun-ai/Step-3.7-Flash-GGUF). The release date is about 2026-05-28/30; secondary sources disagree. — [OpenRouter search results / AA](https://artificialanalysis.ai/models/step-3-7-flash). It is outside the Aug–Nov window but still the newest StepFun open "Flash". The predecessor, Step 3.5 Flash (Feb 2026), was 196B/A11B. — [arXiv 2602.10604](https://arxiv.org/html/2602.10604v2). StepFun's newest model, "Step 5 Preview", is described as 600B total / 27B active. — [Artificial Analysis Step 3.7 page note / OpenRouter](https://artificialanalysis.ai/models/step-3-7-flash)
- **Ling-3.0-flash (inclusionAI/Ant):** 124B total / 5.1B active (metadata says 127B). Hybrid-linear: 35 Kimi Delta Attention (KDA) layers + 7 Gated MLA layers. MoE has 512 routed experts + 1 shared, with 8 active. Trained 8K→32K→256K; SGLang example uses 262,144 ctx. MIT license, with MTP layers. — [HF model card](https://huggingface.co/inclusionAI/Ling-3.0-flash). It was announced around 2026-07-23/24, and weights were open-sourced around 2026-08-07 (secondary). — [aiweekly](https://aiweekly.co/alerts/inclusionai-ships-ling-30-flash-a-124b-moe-with-51b-active). The predecessor Ling-2.6-flash (Apr 2026) was 104B/A7.4B. — [OpenRouter](https://openrouter.ai/models/inclusionai/ling-2.6-flash)
- **Kimi (Moonshot):** No 2026 Kimi model fits. Kimi K3 is 2.8T params, with weights released 2026-07-27, and uses 69 KDA + 24 Gated MLA layers. — [RITS/NYU Shanghai](https://rits.shanghai.nyu.edu/ai/kimi-k3-open-weights-ship-2-8t-parameters-1-4-tb-to-run/), [The Decoder](https://the-decoder.com/moonshot-ai-releases-kimi-k3-open-weights-and-infrastructure-after-shaking-up-the-frontier-model-race/). K2.6 (~1T, Apr 2026) and K2.7 Code (June 2026) are also too big. The only small Kimi is Kimi Linear 48B-A3B from Oct 2025, which is old and weak. — same search results ([RITS K2.6](https://rits.shanghai.nyu.edu/ai/moonshot-ai-releases-kimi-k2-6-with-256k-context-and-300-agent-swarms/))
- **Hunyuan non-Hy4:** Hy3 is 295B / ~21B active. The preview came out 2026-04-23 and the full Apache-2.0 release on 2026-07-06. — [RITS/NYU Shanghai Hy3](https://rits.shanghai.nyu.edu/ai/tencent-releases-hy3-295b-open-moe-model-under-apache-2-0/), [digitalapplied](https://www.digitalapplied.com/blog/tencent-hunyuan-hy3-open-weight-reasoning-model-2026). VentureBeat's headline says Hy3 "wins everywhere except coding" against GLM-5.2. — [VentureBeat](https://venturebeat.com/ai/tencents-apache-licensed-hy3-takes-on-glm-5-2-at-half-the-size-and-wins-everywhere-except-coding/). Hunyuan-A13B (80B/13B) is from 2025. Hy4 is ~770B (secondary). — [tech-insider](https://tech-insider.org/tencent-hy4-open-source-770b-parameters-1m-token-context-2026/)
- **ByteDance Seed-OSS:** Only Seed-OSS-36B (dense, Aug 2025, Apache 2.0, 512K ctx). The 2026 Seed 2.0 family is API-only. — [Seed blog](https://seed.bytedance.com/en/blog/seed-oss-open-source-models-release), [Seed 2.0 launch](https://seed.bytedance.com/en/blog/seed2-0-正式发布)
- **Baidu ERNIE:** No open-weight successor to ERNIE 4.5 (2025) was found. ERNIE 5.0 (2.4T) is proprietary. — [VentureBeat](https://venturebeat.com/ai/baidu-unveils-proprietary-ernie-5-beating-gpt-5-performance-on-charts), [The Decoder](https://the-decoder.com/baidus-ernie-5-0-tops-all-chinese-ai-models-in-lmarena-with-2-4-trillion-parameters/?cmpscreencustom=1)
- **DeepSeek-V4.1-Flash** (Sep 2026) is reported by a secondary aggregator at 552B total, so it is far too big. — (from search summary, source not individually verified; treat as unconfirmed)

### Inferences
- In this generation, "Flash" from Z.ai, Xiaomi and MiniMax means a ~300–430B model with 15–23B active. Those models target a node of 4–8 accelerators, not a consumer box.
- The baseline's real peers on size (≈100–200B total, ≤11B active) are Ling-3.0-flash and Step 3.7 Flash.

### Gaps
- Step 3.7 Flash's attention layout is not on the HF card, so its KV cost per token is unknown. Step 3.5 Flash reportedly used hybrid SWA/full attention per its arXiv report, but I did not verify the ratio.
- GLM-5.3-Flash's license was not confirmed from a primary source.
- I found no Chinese open-weight model released Aug–Nov 2026 in the ≤130B-total class besides Ling-3.0-flash (weights Aug 2026). An extended search turned up nothing else.

## Q2: Coding-agent benchmarks vs. Qwen3.8-Flash-Next

### Takeaway
On vendor numbers, the large Flash models (MiMo, MiniMax, GLM) beat the baseline on DeepSWE v1.1. All three score higher than Qwen's 58.7: GLM 63.4, MiMo 67.9, MiniMax 73.7. Harness parity is unclear, though, and none of them fit the box. The two models that do fit score lower than the baseline on every overlapping metric reported.

### Cited Findings
- **GLM-5.3-Flash (vendor, via Unsloth; no harness named):** Terminal-Bench 2.1 84.3, DeepSWE v1.1 63.4, NL2Repo 56.3, Toolathlon Verified 78.4. No SWE-bench is listed. — [Unsloth docs](https://unsloth.ai/docs/models/glm-5.3-flash)
- **MiMo-V2.6-Flash (vendor; no harness named):** DeepSWE v1.1 67.9, Terminal-Bench 2.1 87.6, Terminal-Bench 4.0 28.8, ProgramBench 26.0, Toolathlon-Verified 73.6. No SWE-bench Verified/Pro/Multilingual is listed. — [HF card](https://huggingface.co/XiaomiMiMo/MiMo-V2.6-Flash-RL)
- **Cross-vendor table (given in the task, Inkling 2 Small card, mini-swe-agent v2.4.6):** DeepSWE v1.1 scores are GLM-5.3-Flash 63.4, MiMo 67.9, MiniMax-M3.1-Flash 73.7, DeepSeek-V4.1-Flash 77.0. The GLM and MiMo numbers match their own vendor cards exactly. That suggests the table reuses vendor numbers rather than running independent evaluations. This is an inference; verify before relying on it.
- **Step 3.7 Flash (vendor; no harness named):** SWE-Bench Pro 56.3, Terminal-Bench 2.1 59.5, Toolathlon 49.5, HLE w/ tool 48.1, ClawEval-1.1 67.1. — [HF card](https://huggingface.co/stepfun-ai/Step-3.7-Flash). Step 3.5 Flash (Feb 2026) scored SWE-bench Verified 74.4 and Terminal-Bench 2.0 51.0 (vendor). — [HF step-3.5-flash](https://huggingface.co/stepfun-ai/step-3.5-flash)
- **Ling-3.0-flash (vendor):** SWE-Bench Pro 56.6 and SWE-bench Multilingual 72.4, both on OpenHands with custom prompts. AIME26 93.2, HLE 22.7. Terminal-Bench 2.1 (Terminus 2) and other agent scores appear only in an image. — [HF card](https://huggingface.co/inclusionAI/Ling-3.0-flash)
- **Baseline (task context, vendor):** SWE-bench Pro 62.5 (Claude Code harness), Multilingual 81.0 (mini-SWE-agent), DeepSWE 1.1 58.7, Toolathlon 73.5.

### Inferences
- Ling-3.0-flash vs. baseline: SWE-bench Pro is 56.6 vs 62.5 and Multilingual is 72.4 vs 81.0. The harnesses differ (OpenHands vs Claude Code / mini-SWE-agent), but the gap is 6–9 points in the same direction on both. So the baseline is very likely stronger.
- Step 3.7 Flash vs. baseline: SWE-bench Pro is 56.3 vs 62.5 and Toolathlon is 49.5 vs 73.5. The baseline looks stronger, especially on tool use.
- On DeepSWE v1.1 (vendor), even the weakest large Flash (GLM 63.4) beats the baseline's 58.7. If any of them could run, it would plausibly be an upgrade, at a large speed cost.

### Gaps
- No independent results (SWE-rebench, Terminal-Bench leaderboard, Aider, Vals) were checked for these models within the budget.
- No same-harness head-to-head with Qwen3.8-Flash-Next was found for any model.
- MiniMax-M3.1-Flash's primary-source benchmark table was not fetched.

## Q3: GGUF availability, llama.cpp support, quant size vs. quality

### Takeaway
All candidates have GGUFs. At a ≥3-bit quant, only Ling-3.0-flash and Step 3.7 Flash fit in ~100 GB of weights. GLM-5.3-Flash's 3-bit quant is 120 GB, and its 2-bit quant has KLD 0.38.

### Cited Findings
- **GLM-5.3-Flash Unsloth GGUF** (BF16 641.6 GB; columns are size / mean KLD / top-1):
  - UD-IQ2_XXS: 101.8 GB / 0.450 / 76.3%
  - UD-Q2_K_XL: 108.7 GB / 0.380 / 78.3%
  - UD-IQ3_XXS: 120.4 GB / 0.284 / 81.6%
  - UD-Q3_K_XL: 147.5 GB / 0.160 / 86.3%
  - UD-IQ4_XS: 156.8 GB / 0.117

  Unsloth recommends 128–150 GB of RAM+VRAM for 3-bit. Support is via ggml-org llama.cpp PR #27754 / Unsloth fork branch `glm5next/upstream`, and the merge status is not stated. On 1xB200 at IQ1_S: 63 tok/s at short context, 49 tok/s at 64K after optimisation, and +MTP n=2 ≈ 86 tok/s. — [Unsloth docs](https://unsloth.ai/docs/models/glm-5.3-flash). Another GGUF repo requires the author's llama.cpp fork. — [vcruz305](https://huggingface.co/vcruz305/GLM-5.3-Flash-GGUF)
- **MiMo-V2.6-Flash:** The HF card links 39 community quantizations with "Use with llama.cpp", but the official serving docs cover only vLLM/SGLang/Transformers. — [HF card](https://huggingface.co/XiaomiMiMo/MiMo-V2.6-Flash-RL). Quant sizes were not checked.
- **Step 3.7 Flash official GGUF** (imatrix): IQ3_XXS 76 GB, Q3_K_M 94 GB, Q3_K_L 103 GB, IQ4_XS 105 GB, Q4_K_S 112 GB, Q8_0 209 GB, plus a 4 GB mmproj. The quickstart uses StepFun's llama.cpp fork (`step3.7` branch). — [HF GGUF](https://huggingface.co/stepfun-ai/Step-3.7-Flash-GGUF). Unsloth, bartowski, AesSedai and mudler (APEX) GGUFs also exist. AesSedai notes that MTP for StepFun is supported upstream "since b9480". — [search results: unsloth](https://huggingface.co/unsloth/Step-3.7-Flash-GGUF), [bartowski](https://huggingface.co/bartowski/Step-3.7-Flash-GGUF), [AesSedai disc.](https://huggingface.co/AesSedai/Step-3.7-Flash-GGUF/discussions/3). There is also a ROCm-specific community quant. — [jcbtc ROCmFPX Q3](https://huggingface.co/jcbtc/Step-3.7-Flash-ROCmFPX-Q3-QualityPlus)
- **Ling-3.0-flash bartowski GGUF:** IQ4_XS 68.7 GB, Q4_K_M 77.8 GB, Q5_K_M 90.7 GB, Q6_K 109.3 GB, Q8_0 135.6 GB. MTP layers are included (`--spec-type draft-mtp`). Built with llama.cpp b10472 "or newer". — [bartowski](https://huggingface.co/bartowski/Ling-3.0-flash-GGUF)
  - Conflicting support status: a July 2026 article says llama.cpp had the KDA kernels but no BailingMoE conversion path. — [0dev](https://0dev.duckdns.org/en/posts/integration-status-of-ling-3-0-flash-weights-across-major-inference-engines). Other GGUF cards (per the search summary) say PR #26608 was unmerged as of 2026-08-11 and point to forks with a known KDA forget-gate bug. A different card claims upstream support since Aug 2026. — [search results e.g. AtomicChat](https://huggingface.co/AtomicChat/Ling-3.0-flash-GGUF/discussions/1). Bartowski building with an upstream release number suggests it is upstream now, but this is not verified.
- **Hy3 (295B):** Too large at ≥3-bit by arithmetic (~295B × 3.5 bpw ≈ 130 GB). No GGUF data was checked.

### Inferences
- **Fit math** (weights + ~10–15 GB for KV/buffers):
  - **Ling-3.0-flash:** Q5_K_M (91 GB) or Q4_K_L (78 GB) fits easily. It can run at a higher quant than the baseline's IQ4_XS. KDA (linear) layers make 6 of every 7 layers constant-state, so KV at 128–256K should be small.
  - **Step 3.7 Flash:** Q3_K_M (94 GB) fits. IQ4_XS (105 GB) is borderline with 128K KV. Q4_K_S (112 GB) does not fit.
  - **GLM-5.3-Flash:** Only ≤2-bit fits (UD-Q2_K_XL 108.7 GB leaves essentially no room for KV). KLD 0.38 is well into degraded territory, so it fails the quality rule.
  - **MiMo-V2.6-Flash (309B):** Even ~3 bpw is roughly 115–120 GB. Fails.
  - **MiniMax-M3.1-Flash (428B):** ~3 bpw is roughly 160 GB. Fails.
  - **Kimi K3, Hy3, Hy4, DeepSeek-V4.1-Flash:** Fail.

### Gaps
- No Unsloth KLD data was found for Ling-3.0-flash or Step 3.7 Flash.
- Whether ik_llama.cpp or KTransformers support bailingmoe3 or Step 3.7 is unknown.
- ROCm/HIP correctness of the KDA kernels on gfx1201 is unverified.

## Q4: Expected speed on this box

### Takeaway
Ling-3.0-flash (5.1B active, mostly linear attention) should decode at roughly the baseline's speed or faster. Step 3.7 Flash (11B active) would likely decode at about half the baseline's speed. No R9700/RDNA4 reports were found for either.

### Cited Findings
- Step 3.7 Flash Q4_K_S, llama-batched-bench numbers from StepFun's own GGUF page:
  - Strix Halo 128 GB: 26.2 tok/s decode at 0 ctx, 15.1 tok/s at 64K. Prompt processing falls to 48.8 tok/s at 64K.
  - DGX Spark: 24.8 tok/s decode at 0 ctx, 13.0 tok/s at 128K. Prompt processing peaks at 754 tok/s.
  - M4 Max: 51.2 tok/s decode at 0 ctx, 9.7 tok/s at 256K.
  - Source: [HF GGUF](https://huggingface.co/stepfun-ai/Step-3.7-Flash-GGUF)
- Single DGX Spark at Q4_K_S: 26–27.5 tok/s. 2x Spark NVFP4 + MTP: ~32 tok/s. — [NVIDIA forum](https://forums.developer.nvidia.com/t/step-3-7-flash-nvfp4-with-mtp-on-2x-dgx-spark-standalone-recipe-262k-ctx-32-tok-s/373163)
- A SpecPicks claim of 42 tok/s on a 12 GB 3060 describes the model as 14B total, so it is unreliable. — [specpicks](https://specpicks.com/reviews/step-3-7-flash-benchmarks-local-12gb-2026)

### Inferences
- Decode on a DDR5 offload box is roughly bounded by active-expert bytes read from RAM per token. Step's ~11B active is about 1.8x the baseline's 6B, so expect roughly 40–50 tok/s at short context, falling faster with context if its attention is mostly full. Ling's 5.1B active should land around 80–100 tok/s, with flat long-context decode because of KDA. MTP could add more. These are estimates, not measurements.

### Gaps
- No R9700 / RX 9070 / 7900 XTX reports were found for any model in this list.

## Q5: Tool-calling / agent-harness / long-session reports

### Takeaway
There is very little independent agent-harness evidence for the two models that fit. Nothing Rust-specific was found.

### Cited Findings
- Step 3.7 Flash ships `step3p5` tool-call and reasoning parsers for vLLM/SGLang. The vendor names Hermes Agent, OpenClaw and Kilo Code as supported platforms. — [HF card](https://huggingface.co/stepfun-ai/Step-3.7-Flash)
- A community tool-eval scored a Step 3.7 Q3 quant 88/100. An NVIDIA forum AWQ test noted "very verbose thinking on planning, very sparse thinking on tool calling". — (from search summary; [NVIDIA forum AWQ thread](https://forums.developer.nvidia.com/t/step-3-7-awq-2xspark-48tg-at-c1-108toks-at-c8/373330); not individually verified)
- Ling-3.0-flash's vLLM path uses `ling3` tool-call/reasoning parsers. — [HF card](https://huggingface.co/inclusionAI/Ling-3.0-flash). No llama.cpp chat-template / tool-call reports were found.
- GLM-5.3-Flash: Unsloth recommends temp 0.95 / top_p 1.0 specifically for DeepSWE. — [Unsloth docs](https://unsloth.ai/docs/models/glm-5.3-flash)

### Inferences
- **Bottom line for the user:**
  - Only Ling-3.0-flash and Step 3.7 Flash are runnable at acceptable quality. Both score lower than Qwen3.8-Flash-Next on every vendor coding/tool metric that overlaps.
  - Ling-3.0-flash is the only one worth a side-by-side test, as a speed/long-context peer (larger quant possible, small KV). It is not expected to be an upgrade.
  - The models that would plausibly beat the baseline (MiniMax-M3.1-Flash > MiMo-V2.6-Flash > GLM-5.3-Flash on DeepSWE v1.1) do not fit at ≥3-bit. They would need about 128–160+ GB of RAM+VRAM.

### Gaps
- No opencode / Claude Code / Cline / Roo long-session reports were found for Ling-3.0-flash or Step 3.7 Flash on llama.cpp.
- No Rust-specific evaluations were found.
