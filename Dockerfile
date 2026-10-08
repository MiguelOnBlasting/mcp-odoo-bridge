FROM python:3.11-slim

RUN pip install --no-cache-dir fastapi uvicorn requests

RUN echo 'import os, requests, json\n\
from fastapi import FastAPI, Request\n\
from fastapi.middleware.cors import CORSMiddleware\n\
\n\
app = FastAPI()\n\
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])\n\
\n\
@app.post("/query")\n\
async def query_odoo(request: Request):\n\
    try:\n\
        payload = await request.json()\n\
    except Exception:\n\
        payload = {}\n\
        \n\
    url = os.environ.get("ODOO_URL", "").rstrip("/")\n\
    db = os.environ.get("ODOO_DB")\n\
    username = os.environ.get("ODOO_USERNAME")\n\
    password = os.environ.get("ODOO_PASSWORD") or os.environ.get("ODOO_API_KEY")\n\
    \n\
    if not url.startswith("http"):\n\
        url = "https://" + url\n\
        \n\
    model = payload.get("model", "sale.order")\n\
    action = payload.get("action", "count")\n\
    limit = int(payload.get("limit", 5))\n\
    offset = int(payload.get("offset", 0))\n\
    \n\
    # Tratamento seguro para o domain (garante que e uma lista Python valida)\n\
    raw_domain = payload.get("domain", [])\n\
    if isinstance(raw_domain, str):\n\
        try:\n\
            domain = json.loads(raw_domain)\n\
        except Exception:\n\
            domain = []\n\
    elif isinstance(raw_domain, list):\n\
        domain = raw_domain\n\
    else:\n\
        domain = []\n\
        \n\
    fields = payload.get("fields")\n\
    if not fields:\n\
        if model == "res.partner":\n\
            fields = ["id", "name", "email", "phone"]\n\
        elif model == "hr.employee":\n\
            fields = ["id", "name", "work_email", "work_phone"]\n\
        elif model == "sale.order":\n\
            fields = ["id", "name", "partner_id", "amount_total", "state", "date_order"]\n\
        elif model == "account.move":\n\
            fields = ["id", "name", "partner_id", "amount_total", "state", "invoice_date", "move_type"]\n\
        else:\n\
            fields = ["id", "display_name"]\n\
            \n\
    try:\n\
        # 1. Autenticacao\n\
        res_auth = requests.post(f"{url}/jsonrpc", json={\n\
            "jsonrpc": "2.0", "method": "call",\n\
            "params": {"service": "common", "method": "login", "args": [db, username, password]},\n\
            "id": 1\n\
        }, timeout=8)\n\
        uid = res_auth.json().get("result")\n\
        if not uid:\n\
            return {"status": "error", "message": "Falha na autenticacao do Odoo"}\n\
            \n\
        # 2. Execucao de Count\n\
        if action == "count":\n\
            res = requests.post(f"{url}/jsonrpc", json={\n\
                "jsonrpc": "2.0", "method": "call",\n\
                "params": {\n\
                    "service": "object",\n\
                    "method": "execute_kw",\n\
                    "args": [db, uid, password, model, "search_count", [domain]]\n\
                },\n\
                "id": 2\n\
            }, timeout=8)\n\
            return {"status": "success", "count": res.json().get("result", 0)}\n\
            \n\
        # 3. Execucao de Read\n\
        else:\n\
            res = requests.post(f"{url}/jsonrpc", json={\n\
                "jsonrpc": "2.0", "method": "call",\n\
                "params": {\n\
                    "service": "object",\n\
                    "method": "execute_kw",\n\
                    "args": [db, uid, password, model, "search_read", [domain], {"fields": fields, "limit": limit, "offset": offset, "order": "id desc"}]\n\
                },\n\
                "id": 2\n\
            }, timeout=8)\n\
            return {"status": "success", "data": res.json().get("result", [])}\n\
            \n\
    except Exception as e:\n\
        return {"status": "error", "message": str(e)}\n\
' > main.py

EXPOSE 10000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "10000"]
