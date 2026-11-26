# Qwen (non-Flash-Next) and Western/other open-weight models as local agentic-coding candidates (as of 2026-11-21)

Box: R9700 32GB (gfx1201) + ~85 GiB usable DDR5, so about 110 GB for weights plus KV cache. Baseline: Qwen3.8-Flash-Next (125B/6B active), UD-IQ4_XS, 80–95 tok/s decode.

Research budget note: this was a bounded sweep (~18 tool calls). Many figures come from secondary aggregators and are flagged as such. "Vendor" means self-reported by the lab. "Independent" means a third party such as Artificial Analysis (AA) or SWE-rebench.

## Q1: What does the Qwen lineup look like beyond Flash-Next, and is anything newer or stronger that fits?

### Takeaway
No Qwen open-weight release is newer than Flash-Next (2026-08-26). The only other open Qwen3.8 models are the 27B dense, which is weaker than Flash-Next on every shared vendor benchmark, and the 2.4T-A95B, which is far too large. Omni-Flash is API-only. There is no Qwen3.8-Coder and no open Qwen4; Flash-Next itself is the "Qwen4 architecture preview."

### Cited Findings
- Qwen3.8 GitHub news: "2026-08-12: Qwen3.8-2.4T-A95B" and "2026-08-14: Qwen3.8-27B" are available on HF/ModelScope. The page mentions no Coder or Omni variants and no Qwen4. — [QwenLM/Qwen3.8 GitHub](https://github.com/QwenLM/Qwen3.8)
- Qwen describes the open model as "an early preview of the Qwen4 architecture, now open-weight," with 125B params plus 51B n-gram embeddings. — [Qwen on X](https://x.com/Alibaba_Qwen/status/2092591393424515114); [Qwen blog](https://qwen.ai/blog?id=qwen3.8-flash-next)
- Six Qwen3.8 models exist. Four have open weights: 2.4T-A95B (Max), 27B, and Flash-Next, with the 2.4T counted as Max. API-only: qwen3.8-flash (hosted Flash-Next), Qwen3.8-Omni-Flash (2026-09-18), and Qwen3.8-LiveTranslate (2026-09-18). Licenses: 27B is Apache 2.0, Flash-Next uses the Qwen Community License 1.0, and the 2.4T uses a custom Max license. The page's dating is somewhat unreliable. — [Lindy blog (secondary)](https://www.lindy.ai/blog/qwen-3-8)
- Qwen3.8-Omni-Flash has no downloadable weights as of late September 2026. — [MarkTechPost](https://www.marktechpost.com/2026/09/18/alibaba-qwen-releases-qwen3-8-omni-flash/); [popularai.org](https://www.popularai.org/p/qwen3-8-omni-flash-local-gguf)
- Qwen3.8-27B card details:
  - Specs: dense 27B (28B on the Hub, with vision encoder). Hybrid layout "16 × (3 × (Gated DeltaNet → FFN) → 1 × (Gated Attention → FFN))", 64 layers. 262,144 native context, extendable to 1M with YaRN. Apache-2.0.
  - Vendor coding scores: Terminal Bench 2.1 (Terminus) 73.0, SWE-bench Pro 61.7, DeepSWE 1.1 42.2, NL2Repo 42.3, QwenSWEBench 79.0, LiveCodeBench v6 90.3.
  - Harness: SWE-Pro and DeepSWE were run in the Claude Code harness at temp 1.0, top_p 0.95, 256K context.
  - Same table's competitors: Muse Glimmer-30B scores SWE-Pro 51.2 and TB2.1 51.7. Opus 4.6 Max scores SWE-Pro 53.4 and TB2.1 78.2.
  - The card does not report SWE-bench Verified, SWE-bench Multilingual, or Toolathlon.
  - — [HF Qwen/Qwen3.8-27B](https://huggingface.co/Qwen/Qwen3.8-27B)
- The Qwen cards disagree slightly with each other. Qwen3.7-Plus scores SWE-Pro 57.6 on the 27B card but 55.8 on the Flash-Next card. — [Lindy (secondary)](https://www.lindy.ai/blog/qwen-3-8)
- Independent results (AA, via the GPUwerk ranking, checked 2026-11-07):
  - Qwen3.8-Flash-Next: Terminal-Bench 4.0 25.3.
  - Qwen3.8-27B (Xhigh): TB 4.0 5.6 and FrontierCode 14.9.
  - The 27B UD-Q4_K_XL GGUF is 17.6 GB.
  - — [GPUwerk](https://gpuwerk.com/blog/best-open-weight-coding-models/)
- Qwen3.8-2.4T-A95B is text-only and needs GPU servers; it does not fit this box. — [GitHub](https://github.com/QwenLM/Qwen3.8); [Lindy](https://www.lindy.ai/blog/qwen-3-8)
- Community 27B-vs-Nemotron-Lightning test (16 hard problems, Q4_K_M, RTX 5090): both scored 14/16. Qwen3.8-27B ran at 171 tok/s and used 17.5 GB VRAM at 64K context. — [HF discussion #103](https://huggingface.co/Qwen/Qwen3.8-27B/discussions/103)
- Atomic Chat (RTX 4090): Qwen3.8-27B 15.94 GiB quant at 48.5 tok/s. — [Atomic Chat](https://atomic.chat/blog/guides/best-local-llms-for-rtx-4090)

### Inferences
- Qwen3.8-27B fits fully in 32 GB VRAM. A Q6/Q8 quant is likely feasible: Q8 is roughly 28–29 GB, which is tight with KV cache, so Q6_K is the safer pick (estimate). It should not beat Flash-Next for long agentic work:
  - Flash-Next is ahead on every shared vendor row in the same harness, and by a wide margin on DeepSWE 1.1 (58.7 vs 42.2).
  - AA's independent TB 4.0 shows a large gap (25.3 vs 5.6). The 5.6 looks anomalously low and may reflect harness or tool-format failures rather than raw capability.
  - Its only plausible role is as a higher-precision dense fallback or a speculative-decoding pairing. Decode on an R9700 for a ~27B dense Q4–Q6 would likely be ~25–40 tok/s, slower than Flash-Next's 80–95 (estimate scaled from the 4090/5090 reports and R9700 bandwidth of ~640 GB/s).
- Nothing in the Qwen lineup is newer than or stronger than Flash-Next and also fits.

### Gaps
- No independent SWE-rebench, SWE-bench Verified, or Aider polyglot number found for either Qwen3.8 open model.
- No R9700 or ROCm tok/s measurement found for Qwen3.8-27B.
- Could not confirm whether a Qwen3.8-27B MTP or drafter head works in llama.cpp ROCm.

## Q2: Mistral (Devstral 2/3, Mistral Large 4, Codestral)

### Takeaway
No Devstral 3 was found. Devstral 2 (Dec 2025) is old relative to Flash-Next. Its 123B dense model would be very slow when spilled to RAM, and the 24B Small 2 fits but is a generation behind. Mistral Large 4 (1T MoE) does not fit at any sane quant.

### Cited Findings
- Devstral 2 (released Dec 9, 2025):
  - Devstral 2: 123B dense, 256K context, modified MIT license, SWE-bench Verified 72.2 (vendor).
  - Devstral Small 2: 24B, Apache 2.0 (per secondary source), SWE-bench Verified 68.0 (vendor).
  - — [Mistral announcement](https://mistral.ai/news/devstral-2-vibe-cli/); [SiliconANGLE](https://siliconangle.com/2025/12/09/mistral-ais-devstral-2-open-weights-vibe-coding-model-built-rival-best-proprietary-systems/)
- Mistral Large 4:
  - Timeline: API preview Oct 6, 2026. Open weights released Oct 29, 2026 as `mistralai/Mistral-Large-4-1T-A52B` in FP8 and NVFP4.
  - License: Mistral Ecosystem Open-Weight License. Model-as-a-service businesses need a separate license.
  - Active parameters: reported as 49B in the preview and 52B later.
  - — [SiliconANGLE](https://siliconangle.com/2026/10/29/mistral-releases-open-weights-for-mistral-large-4-providing-sovereign-control-for-the-companys-le-chonk-ai-model/)
- Mistral Large 4 (High) independent scores (AA): TB 4.0 24.7, which is slightly below Flash-Next's 25.3; FrontierCode 15.0; Agent Index 35.4 in Mistral Vibe. Its smallest listed GGUF is UD-IQ1_S at 233.0 GB. — [GPUwerk](https://gpuwerk.com/blog/best-open-weight-coding-models/)
- A secondary headline claims Mistral Large 4 scores "61.7% DeepSWE." Unverified. — [shattered.io](https://shattered.io/mistral-large-4-open-weight-1t-parameters-deepswe-61-7-2026/)
- No Devstral 3 or new Codestral release was found in the Aug–Nov 2026 window. — [search results summary; Mistral news](https://mistral.ai/news/devstral-2-vibe-cli/)

### Inferences
- Large 4 does not fit: 233 GB at about 1 bit is more than double the ~110 GB budget.
- Devstral 2 123B dense at Q4 (~70 GB, estimate) would need about half its weights in DDR5. Dense decode bound by DDR5 bandwidth (~60–80 GB/s) would give roughly 2–5 tok/s, which is unusable for long agent sessions.
- Devstral Small 2 (24B) fits in VRAM, but there is no evidence that it beats Qwen3.8-27B, which is itself below Flash-Next.

### Gaps
- No same-harness comparison of Devstral against Qwen3.8.
- No 2026 Devstral update found. The search may have missed a minor point release.

## Q3: NVIDIA Nemotron 3.5 (Super / Lightning)

### Takeaway
Nemotron 3.5 Super (120B/12B active, hybrid Mamba-MoE, Oct 2026) is the only Western model in roughly the same size class that plausibly fits (~70 GB at Q4). However, its vendor SWE-bench Pro score (51.78) is about 10 points below Flash-Next's (62.5), and it has twice the active parameters, so it is likely slower on this box. Lightning (30B/3B) is fast but weak by AA's index.

### Cited Findings
- NVIDIA page:
  - Release Oct 14, 2026.
  - Super: 120B total / 12B active, multimodal. Lightning: 30B / 3B active, text-only.
  - Hybrid Mamba-Transformer MoE with MTP heads, up to 1M context.
  - BF16 and NVFP4 checkpoints. The page names no specific license.
  - — [NVIDIA Research](https://research.nvidia.com/labs/nemotron/Nemotron-3.5-Super-and-Lightning/)
- Super vendor results:
  - SWE-bench Pro 51.78.
  - Terminal-Bench 2.1 62.7, or 71.9 with parallel execution plus self-verification.
  - DeepSWE pass@1 24.6, or 34.5 with parallel execution plus self-verification.
  - Harnesses are not named.
  - Claimed throughput is 1.90× Qwen3.8-Flash-Next's on GB200. NVIDIA gives no Qwen benchmark scores.
  - — [NVIDIA Research](https://research.nvidia.com/labs/nemotron/Nemotron-3.5-Super-and-Lightning/); [tech report PDF](https://research.nvidia.com/labs/nemotron/files/NVIDIA-Nemotron-3.5-Super-and-Lightning-Technical-Report.pdf); [arXiv](https://arxiv.org/html/2610.38095v1)
- The arXiv paper lists SWE-bench Verified 71.10 for Super 3.5 VL. Taken from a search snippet; the table context was not verified. — [arXiv](https://arxiv.org/html/2610.38095v1)
- GGUF and runtime support:
  - Super GGUF is in the Ollama registry via the llama.cpp runner, and llama.cpp reportedly added Nemotron 3.5 support. — [orcarouter](https://www.orcarouter.ai/blog/nemotron-3-5-super-ollama-local); [magica.com](https://magica.com/news/llama-cpp-nemotron-super-35-vl-bolt-local-inference)
  - "Smallest GGUF is Q4_K_M at about 70GB" for Super. Secondary, unverified. — [aiprofitboardroom](https://aiprofitboardroom.com/blog/nemotron-3-5-super-vl/)
- ROCm reports:
  - A Lightning GGUF metadata bug was fixed upstream (llama.cpp PR #27729, per a single-author gist), with ROCm partial and full offload validated. — [gist](https://gist.github.com/redoracle/5928f33e31621c9ad2f451aab35d4776)
  - Lightning ROCmFP4 quants decode at ~78–86 tok/s on Strix Halo, but need a custom fork. — [HF julianmb](https://huggingface.co/julianmb/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-ROCmFP4-GGUF)
- Lightning community comparison: same 14/16 score as Qwen3.8-27B on an RTX 5090 at 216 tok/s, but it hit the token cap twice and used about twice the tokens. AA intelligence is 6 for Lightning vs 20 for Qwen3.8-27B (Xhigh). — [HF discussion](https://huggingface.co/Qwen/Qwen3.8-27B/discussions/103); [Artificial Analysis](https://artificialanalysis.ai/models/comparisons/qwen3-8-27b-vs-nemotron-3-5-lightning)

### Inferences
- Super fits: ~70 GB Q4 with experts offloaded, plus Mamba layers that keep KV small at long context.
- Super is unlikely to beat Flash-Next:
  - SWE-Pro is 51.8 vs 62.5 (vendor numbers, different harnesses).
  - With 12B active vs 6B, CPU-offloaded decode would likely be about half of Flash-Next's, roughly 35–50 tok/s (estimate).
- Super is worth testing only if Flash-Next shows tool-call or long-session failure modes, since NVIDIA trained it specifically for multi-turn agentic robustness.

### Gaps
- No ROCm or R9700 tok/s figure for Super.
- No independent SWE-bench, SWE-rebench, or AA TB 4.0 score for Super found.
- License name unconfirmed (presumably NVIDIA Open Model License).
- No "Nemotron 3.5 Nano" exists; Lightning fills that slot.

## Q4: Meta (Muse Glimmer, Muse Spark Open, Llama)

### Takeaway
Muse Glimmer-30B (dense, Apache 2.0, Aug 2026) fits in VRAM and has good tool-use claims, but on Qwen's own table it trails Qwen3.8-27B by about 10 points on SWE-Pro, and therefore trails Flash-Next too. Muse Spark Open (816B MoE) does not fit and scores poorly on AA's TB 4.0.

### Cited Findings
- Muse Glimmer-30B specs: 29.6B dense plus ~1.8B vision encoder, local:global 3:1 attention, 131K context, Apache 2.0, released Aug 10, 2026. — [developersdigest](https://www.developersdigest.tech/blog/meta-muse-glimmer-30b-open-weights-local-agent); [MarkTechPost](https://www.marktechpost.com/2026/08/10/meta-ai-releases-muse-glimmer/)
- Muse Glimmer-30B vendor scores (high reasoning) vs Qwen3.6-27B:
  - SWE-Pro 51.2 vs 50.2.
  - SWE-bench Verified 76.0 vs 77.2.
  - TerminalBench 2.1 51.7 vs 60.7.
  - MCP Atlas 75.5 vs 62.5.
  - Gemma4-31B in the same table: SWE-Pro 36.9, Verified 66.6, TB2.1 43.4.
  - Meta reports the better of its own reproduction or the vendor's score for competitors.
  - — [developersdigest](https://www.developersdigest.tech/blog/meta-muse-glimmer-30b-open-weights-local-agent)
- Qwen's own table places Glimmer at SWE-Pro 51.2 and TB2.1 51.7, against Qwen3.8-27B at 61.7 and 73.0. — [HF Qwen3.8-27B](https://huggingface.co/Qwen/Qwen3.8-27B)
- Glimmer quantization and speed:
  - K-Quant-Dynamic targets 32 GB with 0.2% average degradation.
  - The ~17 GB quant shows 1.0% degradation.
  - RTX 5090 llama.cpp decode: 74.9 tok/s, or 233.4 tok/s with the DFlash drafter.
  - — [developersdigest](https://www.developersdigest.tech/blog/meta-muse-glimmer-30b-open-weights-local-agent)
- Muse Spark Open specs: 816B MoE, ~42B active, 1M context. BF16 is ~1.65 TB and NVFP4 ~537 GB. Muse Model License. Released around Oct 15, 2026. — [Meta docs](https://dev.meta.ai/docs/muse-spark-open); [Technology.org](https://www.technology.org/2026/10/16/meta-muse-spark-open-816b-open-weight-mac-studio/)
- Muse Spark Open (Xhigh) independent scores (AA): TB 4.0 8.1, FrontierCode 7.6, Agent Index 26.3 in Muse Code. Smallest GGUF is UD-IQ1_S at 175.6 GB. — [GPUwerk](https://gpuwerk.com/blog/best-open-weight-coding-models/)
- No new Llama release found in the window. Glimmer is described as Meta's first open-weight model since Llama 4. — [mer.vin](https://mer.vin/news/muse-glimmer-30b-is-metas-first-open-weight-model-since-llama-4/)

### Inferences
- Glimmer fits easily, but it is not a Flash-Next replacement for coding.
- Its DFlash drafter speedup is CUDA llama.cpp only; ROCm status is unknown.

### Gaps
- No independent SWE-bench numbers for Glimmer.
- No ROCm tok/s figure.
- No Rust-specific evidence.

## Q5: Google Gemma 4, OpenAI gpt-oss successors, Microsoft, IBM Granite, AI2 OLMo, Cohere, Reka, Arcee

### Takeaway
None of these are competitive with Flash-Next for agentic coding. Gemma 4 (April 2026) is a generation behind, gpt-oss has no successor, Granite 4.2 has no coding-agent numbers found, and Cohere's North Mini Code predates the window.

### Cited Findings
- Gemma 4:
  - Released Apr 2, 2026 with E2B, E4B, 26B-A4B MoE, and 31B dense; a 12B Unified variant appeared later. — [Wikipedia](https://en.wikipedia.org/wiki/Gemma_(language_model)); [Verdent](https://www.verdent.ai/guides/gemma-4-coding-agents)
  - LiveCodeBench v6: 80.0 for 31B and 77.1 for 26B-A4B (vendor). — [HF blog](https://huggingface.co/blog/gemma4)
  - In Meta's table, the 31B scores SWE-Pro 36.9 and Verified 66.6. — [developersdigest](https://www.developersdigest.tech/blog/meta-muse-glimmer-30b-open-weights-local-agent)
  - No Gemma 4.1 or newer release was found.
- OpenAI: no gpt-oss successor as of early Nov 2026, only the gpt-oss-safeguard classifiers. "gpt-oss-2" rumors are unconfirmed. — [aiwiki](https://aiwiki.ai/wiki/gpt_oss); [aiera.blog](https://aiera.blog/openai-open-weight-model-release-date/)
- IBM: Granite 4.2 (Aug 25, 2026) adds native reasoning, tool use, and coding. No SWE-bench numbers were found. — [IBM Research](https://research.ibm.com/blog/introducing-granite-4-2)
- Cohere: North Mini Code (30B/3B MoE, agentic coding, open weights on HF) released June 9, 2026. Benchmarks were not found. — [Cohere changelog](https://docs.cohere.com/v2/changelog); [nhimg](https://nhimg.org/cohere-llm-models-guide)
- Arcee: Trinity Large (400B, Jan 2026) is not coding-focused and too big for this box. — [Raschka](https://magazine.sebastianraschka.com/p/a-dream-of-spring-for-open-weight)
- AI2 OLMo, Microsoft, Reka: no relevant Aug–Nov 2026 open coding release found.
- Other non-Qwen entries on GPUwerk's AA TB 4.0 ranking are either Chinese or too large, or both: Kimi K3.1 Pro, GLM-5.3, MiMo, DeepSeek V4.1 Flash, Step 5, MiniMax. Out of scope here, but two are notable for fit:
  - GLM-5.3-Flash: TB 4.0 32.8, UD-Q2_K_XL 108.7 GB. Borderline fit at 2-bit.
  - Nanbeige4.3-33B: TB 4.0 29.8 (AA), DeepSWE 65.5 (vendor), Q4_K_M 20.8 GB. Fits fully in 32 GB VRAM.
  - Both score above Flash-Next's 25.3 on AA TB 4.0.
  - — [GPUwerk](https://gpuwerk.com/blog/best-open-weight-coding-models/)

### Inferences
- In this scope, no Western model beats Flash-Next on any benchmark available.
- Nanbeige4.3-33B and GLM-5.3-Flash should be handed to whoever covers Chinese models. They are the only fitting models found that outscore Flash-Next on an independent agentic benchmark.

### Gaps
- No coding-agent benchmarks found for Granite 4.2, North Mini Code, or OLMo.
- Microsoft and Reka coverage was not searched in depth.

## Q6: Independent leaderboards, tool-call reliability, Rust evidence

### Takeaway
Independent data is thin for the models that fit. AA TB 4.0 is the most consistent cross-model independent measure found. On it, Flash-Next (25.3) beats every Western candidate measured: Mistral Large 4 24.7, Muse Spark Open 8.1, and Qwen3.8-27B 5.6. No Rust-specific evidence was found for any candidate.

### Cited Findings
- AA Terminal-Bench 4.0 scores (via GPUwerk, 2026-11-07): Flash-Next 25.3, Mistral Large 4 (High) 24.7, Muse Spark Open 8.1, Qwen3.8-27B 5.6. — [GPUwerk](https://gpuwerk.com/blog/best-open-weight-coding-models/)
- SWE-rebench snapshot (2026-11-07, via BenchLM aggregator):
  - Top open models: GLM-5 62.8, GLM-5.1 62.7, DeepSeek V3.2 60.9, Kimi K2.5 58.5.
  - No Qwen3.8 or Western small-model entries were found.
  - Qwen3.6-27B scored 31.2 on SWE-rebench (secondary).
  - — [BenchLM](https://benchlm.ai/benchmarks/swe-rebench)
- Tool-call evidence:
  - Meta claims Glimmer is trained to diagnose and retry failed tool calls. — [developersdigest](https://www.developersdigest.tech/blog/meta-muse-glimmer-30b-open-weights-local-agent)
  - Nemotron Lightning over-thinks and hits token caps. — [HF discussion](https://huggingface.co/Qwen/Qwen3.8-27B/discussions/103)

### Inferences
- For long-running Rust agent work on this box, Flash-Next remains the best-supported choice in this scope.
- Nemotron 3.5 Super is the only same-class fitting alternative worth an A/B test, and it is expected to be slower and weaker on vendor numbers.

### Gaps
- No Aider polyglot results for any 2026 model.
- No SWE-bench Multilingual results outside Qwen's cards.
- No Rust-specific agent reports found.
- The AA TB 4.0 numbers come through an aggregator rather than AA directly.
