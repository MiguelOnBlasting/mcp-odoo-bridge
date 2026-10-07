FROM python:3.11-slim

RUN pip install --no-cache-dir fastapi uvicorn requests

RUN echo 'import os, requests\n\
from fastapi import FastAPI\n\
from fastapi.middleware.cors import CORSMiddleware\n\
\n\
app = FastAPI()\n\
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])\n\
\n\
@app.post("/get_quotations")\n\
def get_quotations():\n\
    url = os.environ.get("ODOO_URL", "").rstrip("/")\n\
    db = os.environ.get("ODOO_DB")\n\
    username = os.environ.get("ODOO_USERNAME")\n\
    password = os.environ.get("ODOO_PASSWORD") or os.environ.get("ODOO_API_KEY")\n\
    \n\
    if not all([url, db, username, password]):\n\
        return {"error": "Variaveis de ambiente em falta no Render"}\n\
        \n\
    try:\n\
        auth_req = requests.post(f"{url}/jsonrpc", json={\n\
            "jsonrpc": "2.0", "method": "call",\n\
            "params": {"service": "common", "method": "login", "args": [db, username, password]}\n\
        }, timeout=10)\n\
        \n\
        uid = auth_req.json().get("result")\n\
        if not uid:\n\
            return {"error": "Falha na autenticacao com Odoo (verifique utilizador/chave)"}\n\
            \n\
        data_req = requests.post(f"{url}/jsonrpc", json={\n\
            "jsonrpc": "2.0", "method": "call",\n\
            "params": {"service": "object", "method": "execute_kw", "args": [db, uid, password, "sale.order", "search_count", [[["state", "in", ["draft", "sent", "sale"]]]]}\n\
        }, timeout=10)\n\
        \n\
        return {"count": data_req.json().get("result", 0)}\n\
    except Exception as e:\n\
        return {"error": str(e)}\n\
' > main.py

EXPOSE 10000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "10000"]
