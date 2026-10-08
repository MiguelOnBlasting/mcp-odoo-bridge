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
    "res.partner": ["id", "name", "email", "phone", "city"],\n\
    "hr.employee": ["id", "name", "work_email", "work_phone", "department_id"],\n\
    "sale.order": ["id", "name", "partner_id", "amount_total", "state", "date_order"],\n\
    "account.move": ["id", "name", "partner_id", "amount_total", "state", "invoice_date", "move_type"],\n\
    "product.product": ["id", "display_name", "list_price", "qty_available"]\n\
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
    action = payload.get("action", "read")\n\
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
    # Sanitizacao robusta do domain para aceitar ilike / like\n\
    raw_domain = payload.get("domain", [])\n\
    if isinstance(raw_domain, str):\n\
        raw_domain_clean = raw_domain.strip()\n\
        if raw_domain_clean and raw_domain_clean != "{domain}":\n\
            try:\n\
                domain = json.loads(raw_domain_clean)\n\
            except Exception:\n\
                domain = []\n\
        else:\n\
            domain = []\n\
    elif isinstance(raw_domain, list):\n\
        domain = raw_domain\n\
    else:\n\
        domain = []\n\
        \n\
    try:\n\
        # 1. Login\n\
        res_auth = requests.post(f"{url}/jsonrpc", json={\n\
            "jsonrpc": "2.0", "method": "call",\n\
            "params": {"service": "common", "method": "login", "args": [db, username, password]},\n\
            "id": 1\n\
        }, timeout=15)\n\
        uid = res_auth.json().get("result")\n\
        if not uid:\n\
            return {"status": "error", "message": "Falha na autenticacao do Odoo"}\n\
            \n\
        # 2. Action: AGGREGATE\n\
        if action == "aggregate":\n\
            agg_field = payload.get("agg_field", "amount_total")\n\
            groupby = payload.get("groupby", [])\n\
            if isinstance(groupby, str) and groupby.strip() and groupby != "{groupby}":\n\
                try:\n\
                    groupby = json.loads(groupby)\n\
                except Exception:\n\
                    groupby = [groupby]\n\
            elif not isinstance(groupby, list):\n\
                groupby = []\n\
                \n\
            res = requests.post(f"{url}/jsonrpc", json={\n\
                "jsonrpc": "2.0", "method": "call",\n\
                "params": {\n\
                    "service": "object",\n\
                    "method": "execute_kw",\n\
                    "args": [db, uid, password, model, "read_group", [domain], [agg_field], groupby]\n\
                },\n\
                "id": 2\n\
            }, timeout=20)\n\
            return {"status": "success", "result": res.json().get("result", [])}\n\
            \n\
        # 3. Action: COUNT\n\
        elif action == "count":\n\
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
        # 4. Action: READ\n\
        else:\n\
            fields = payload.get("fields")\n\
            if isinstance(fields, str) and fields.strip() and fields != "{fields}":\n\
                try:\n\
                    fields = json.loads(fields)\n\
                except Exception:\n\
                    fields = None\n\
            if not fields or not isinstance(fields, list):\n\
                fields = KNOWN_FIELDS.get(model, ["id", "display_name"])\n\
                \n\
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
