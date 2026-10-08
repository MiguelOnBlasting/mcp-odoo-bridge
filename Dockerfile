FROM python:3.11-slim

RUN pip install --no-cache-dir fastapi uvicorn requests

RUN echo 'import os, requests, json\n\
from fastapi import FastAPI, Request\n\
from fastapi.middleware.cors import CORSMiddleware\n\
\n\
app = FastAPI()\n\
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])\n\
\n\
KNOWN_FIELDS = {\n\
    "res.partner": ["id", "name", "email", "phone"],\n\
    "hr.employee": ["id", "name", "work_email", "work_phone"],\n\
    "sale.order": ["id", "name", "amount_total", "state", "date_order"],\n\
    "account.move": ["id", "name", "amount_total", "state", "invoice_date"],\n\
    "product.product": ["id", "display_name", "list_price"]\n\
}\n\
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
    \n\
    try:\n\
        limit = int(payload.get("limit", 5))\n\
    except Exception:\n\
        limit = 5\n\
    try:\n\
        offset = int(payload.get("offset", 0))\n\
    except Exception:\n\
        offset = 0\n\
        \n\
    raw_domain = payload.get("domain", [])\n\
    if isinstance(raw_domain, str):\n\
        try:\n\
            domain = json.loads(raw_domain) if raw_domain.strip() and raw_domain != "{domain}" else []\n\
        except Exception:\n\
            domain = []\n\
    elif isinstance(raw_domain, list):\n\
        domain = raw_domain\n\
    else:\n\
        domain = []\n\
        \n\
    fields = payload.get("fields")\n\
    if not fields or not isinstance(fields, list):\n\
        fields = KNOWN_FIELDS.get(model, ["id", "display_name"])\n\
        \n\
    try:\n\
        # 1. Login com timeout estendido de 15s\n\
        res_auth = requests.post(f"{url}/jsonrpc", json={\n\
            "jsonrpc": "2.0", "method": "call",\n\
            "params": {"service": "common", "method": "login", "args": [db, username, password]},\n\
            "id": 1\n\
        }, timeout=15)\n\
        uid = res_auth.json().get("result")\n\
        if not uid:\n\
            return {"status": "error", "message": "Falha na autenticacao do Odoo"}\n\
            \n\
        # 2. Count com timeout de 20s\n\
        if action == "count":\n\
            res = requests.post(f"{url}/jsonrpc", json={\n\
                "jsonrpc": "2.0", "method": "call",\n\
                "params": {\n\
                    "service": "object",\n\
                    "method": "execute_kw",\n\
                    "args": [db, uid, password, model, "search_count", [domain]]\n\
                },\n\
                "id": 2\n\
            }, timeout=20)\n\
            return {"status": "success", "count": res.json().get("result", 0)}\n\
            \n\
        # 3. Read com timeout de 20s e campos leves\n\
        else:\n\
            res = requests.post(f"{url}/jsonrpc", json={\n\
                "jsonrpc": "2.0", "method": "call",\n\
                "params": {\n\
                    "service": "object",\n\
                    "method": "execute_kw",\n\
                    "args": [db, uid, password, model, "search_read", [domain], {"fields": fields, "limit": limit, "offset": offset, "order": "id desc"}]\n\
                },\n\
                "id": 2\n\
            }, timeout=20)\n\
            return {"status": "success", "data": res.json().get("result", [])}\n\
            \n\
    except Exception as e:\n\
        return {"status": "error", "message": str(e)}\n\
' > main.py

EXPOSE 10000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "10000"]
