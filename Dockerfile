FROM python:3.11-slim

RUN pip install --no-cache-dir fastapi uvicorn requests

RUN echo 'import os, requests\n\
from fastapi import FastAPI\n\
from fastapi.middleware.cors import CORSMiddleware\n\
from starlette.concurrency import run_in_threadpool\n\
\n\
app = FastAPI()\n\
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])\n\
\n\
def fetch_odoo_data():\n\
    url = os.environ.get("ODOO_URL", "").rstrip("/")\n\
    db = os.environ.get("ODOO_DB")\n\
    username = os.environ.get("ODOO_USERNAME")\n\
    password = os.environ.get("ODOO_PASSWORD") or os.environ.get("ODOO_API_KEY")\n\
    \n\
    if not url.startswith("http"):\n\
        url = "https://" + url\n\
        \n\
    session = requests.Session()\n\
    try:\n\
        # Autenticacao com timeout rigoroso de 4s\n\
        auth_resp = session.post(f"{url}/jsonrpc", json={\n\
            "jsonrpc": "2.0", "method": "call",\n\
            "params": {"service": "common", "method": "login", "args": [db, username, password]},\n\
            "id": 1\n\
        }, timeout=4)\n\
        \n\
        uid = auth_resp.json().get("result")\n\
        if not uid:\n\
            return {"error": f"Login recusado pelo Odoo. Resposta: {auth_resp.text[:100]}"}\n\
            \n\
        # Consulta das cotacoes com timeout de 4s\n\
        data_resp = session.post(f"{url}/jsonrpc", json={\n\
            "jsonrpc": "2.0", "method": "call",\n\
            "params": {\n\
                "service": "object", "method": "execute_kw",\n\
                "args": [db, uid, password, "sale.order", "search_count", [[["state", "in", ["draft", "sent", "sale"]]]]]\n\
            },\n\
            "id": 2\n\
        }, timeout=4)\n\
        \n\
        return {"count": data_resp.json().get("result", 0)}\n\
    except Exception as e:\n\
        return {"error": f"Falha ao conectar ao Odoo ({url}): {str(e)}"}\n\
\n\
@app.api_route("/get_quotations", methods=["GET", "POST"])\n\
async def get_quotations():\n\
    return await run_in_threadpool(fetch_odoo_data)\n\
' > main.py

EXPOSE 10000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "10000"]
