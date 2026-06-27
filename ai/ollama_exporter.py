import os, asyncio, httpx, json, logging, time
from fastapi import FastAPI, Request, Response
from fastapi.responses import StreamingResponse
import uvicorn
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://localhost:11434")
PORT = int(os.getenv("PORT", "8000"))

logging.basicConfig()
logger = logging.getLogger(__name__)
logger.setLevel(getattr(logging, os.getenv("LOG_LEVEL", "INFO").upper(), logging.INFO))

app = FastAPI()

REQUEST_COUNT     = Counter("ollama_requests_total",               "Total requests",                 ["model"])
TOTAL_DURATION    = Histogram("ollama_response_seconds",           "Total response time",            ["model"])
LOAD_DURATION     = Histogram("ollama_load_duration_seconds",      "Time loading the model",         ["model"])
PROMPT_EVAL_DUR   = Histogram("ollama_prompt_eval_duration_seconds", "Time evaluating prompt",       ["model"])
EVAL_DURATION     = Histogram("ollama_eval_duration_seconds",      "Time generating the response",   ["model"])
PROMPT_TOKENS     = Counter("ollama_tokens_processed_total",       "Tokens in the prompt",           ["model"])
GENERATED_TOKENS  = Counter("ollama_tokens_generated_total",       "Tokens in the response",         ["model"])
TOKENS_PER_SECOND = Histogram("ollama_tokens_per_second",          "Tokens generated per second",    ["model"],
                     buckets=[5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100])


def record_native(data, model):
    if not isinstance(data, dict):
        return
    ns = 1_000_000_000
    td = data.get("total_duration", 0)
    ld = data.get("load_duration", 0)
    pd = data.get("prompt_eval_duration", 0)
    pc = data.get("prompt_eval_count", 0)
    ed = data.get("eval_duration", 0)
    ec = data.get("eval_count", 0)
    if td > 0: TOTAL_DURATION.labels(model=model).observe(td / ns)
    if ld > 0: LOAD_DURATION.labels(model=model).observe(ld / ns)
    if pd > 0: PROMPT_EVAL_DUR.labels(model=model).observe(pd / ns)
    if pc > 0: PROMPT_TOKENS.labels(model=model).inc(pc)
    if ed > 0: EVAL_DURATION.labels(model=model).observe(ed / ns)
    if ec > 0: GENERATED_TOKENS.labels(model=model).inc(ec)
    if ed > 0 and ec > 0: TOKENS_PER_SECOND.labels(model=model).observe(ec / ed * ns)


def record_openai(usage, model, elapsed):
    if not usage:
        return
    pc = usage.get("prompt_tokens", 0)
    ec = usage.get("completion_tokens", 0)
    if pc > 0: PROMPT_TOKENS.labels(model=model).inc(pc)
    if ec > 0: GENERATED_TOKENS.labels(model=model).inc(ec)
    if elapsed > 0: TOTAL_DURATION.labels(model=model).observe(elapsed)
    if elapsed > 0 and ec > 0: TOKENS_PER_SECOND.labels(model=model).observe(ec / elapsed)


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.post("/api/chat")
@app.post("/api/generate")
async def native_proxy(request: Request):
    body = await request.json()
    model = body.get("model", "unknown")
    headers = {k: v for k, v in request.headers.items() if k not in ("host", "content-length", "content-type")}
    REQUEST_COUNT.labels(model=model).inc()
    if body.get("stream", False):
        async def stream():
            final = None
            async with httpx.AsyncClient(timeout=httpx.Timeout(900.0, read=900.0)) as client:
                async with client.stream("POST", f"{OLLAMA_HOST}{request.url.path}", headers=headers, json=body) as resp:
                    async for chunk in resp.aiter_bytes():
                        yield chunk
                        try:
                            for line in chunk.decode().strip().split('\n'):
                                if line.strip():
                                    d = json.loads(line)
                                    if d.get("done"):
                                        final = d
                        except Exception:
                            pass
            if final:
                record_native(final, model)
        return StreamingResponse(stream(), media_type="application/json")
    else:
        async with httpx.AsyncClient(timeout=httpx.Timeout(900.0, read=900.0)) as client:
            resp = await client.post(f"{OLLAMA_HOST}{request.url.path}", headers=headers, json=body)
        if resp.status_code == 200:
            try: record_native(resp.json(), model)
            except Exception: pass
        return Response(content=resp.content, status_code=resp.status_code, headers=dict(resp.headers))


def inject_think(body: dict) -> dict:
    """Prepend /think to the first user message if chat_template_kwargs.enable_thinking is set."""
    kwargs = body.get("chat_template_kwargs", {})
    if not kwargs.get("enable_thinking"):
        return body
    messages = body.get("messages", [])
    for i, msg in enumerate(messages):
        if msg.get("role") == "user":
            content = msg.get("content", "")
            if isinstance(content, str) and not content.startswith("/think"):
                messages = list(messages)
                messages[i] = {**msg, "content": f"/think\n{content}"}
                body = {**body, "messages": messages}
            break
    body.pop("chat_template_kwargs", None)
    return body


@app.post("/v1/chat/completions")
async def openai_proxy(request: Request):
    body = await request.json()
    body = inject_think(body)
    model = body.get("model", "unknown")
    headers = {k: v for k, v in request.headers.items() if k not in ("host", "content-length", "content-type")}
    REQUEST_COUNT.labels(model=model).inc()
    start = time.monotonic()
    if body.get("stream", False):
        async def stream():
            async with httpx.AsyncClient(timeout=httpx.Timeout(900.0, read=900.0)) as client:
                async with client.stream("POST", f"{OLLAMA_HOST}/v1/chat/completions", headers=headers, json=body) as resp:
                    async for chunk in resp.aiter_bytes():
                        yield chunk
                        try:
                            for line in chunk.decode().strip().split('\n'):
                                if line.startswith("data: ") and line != "data: [DONE]":
                                    d = json.loads(line[6:])
                                    usage = d.get("usage")
                                    if usage:
                                        record_openai(usage, model, time.monotonic() - start)
                        except Exception:
                            pass
        return StreamingResponse(stream(), media_type="text/event-stream")
    else:
        async with httpx.AsyncClient(timeout=httpx.Timeout(900.0, read=900.0)) as client:
            resp = await client.post(f"{OLLAMA_HOST}/v1/chat/completions", headers=headers, json=body)
        if resp.status_code == 200:
            try: record_openai(resp.json().get("usage"), model, time.monotonic() - start)
            except Exception: pass
        return Response(content=resp.content, status_code=resp.status_code, headers=dict(resp.headers))


@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"])
async def passthrough(request: Request, path: str):
    headers = {k: v for k, v in request.headers.items() if k not in ("host", "content-length")}
    async with httpx.AsyncClient(timeout=httpx.Timeout(900.0, read=900.0)) as client:
        resp = await client.request(method=request.method, url=f"{OLLAMA_HOST}/{path}",
                                    headers=headers, content=await request.body(), params=request.query_params)
    return Response(content=resp.content, status_code=resp.status_code, headers=dict(resp.headers))


if __name__ == "__main__":
    asyncio.run(uvicorn.Server(uvicorn.Config(app, host="0.0.0.0", port=PORT, log_level="info")).serve())
