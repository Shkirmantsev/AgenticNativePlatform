from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title="echo-mcp-stub")

class Payload(BaseModel):
    text: str

@app.get("/healthz")
def healthz():
    return {"status": "ok"}

@app.post("/mcp")
def mcp(payload: Payload):
    return {"echo": payload.text}
