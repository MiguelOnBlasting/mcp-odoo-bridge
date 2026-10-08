FROM python:3.11-slim

RUN pip install --no-cache-dir fastapi uvicorn requests

RUN echo 'import os, requests, json, traceback\n\
from fastapi import FastAPI, Request\n\
from fastapi.responses import JSONResponse\n\
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
        try:\n\
            payload = await request.json()\n\
        except Exception as pe:\n\
            return JSONResponse(content={"status": "error", "message": f"Erro de parsing JSON no Payload: {str(pe)}"}, status_code=200)\n\
            \n\
        url = os.environ.get("ODOO_URL", "").rstrip("/")\n\
        db = os.environ.get("ODOO_DB")\n\
        username = os.environ.get("ODOO_USERNAME")\n\
        password = os.environ.get("ODOO_PASSWORD") or os.environ.get("ODOO_API_KEY")\n\
        \n\
        if not url:\n\
            return JSONResponse(content={"status": "error", "message": "Variavel ODOO_URL nao configurada no Render."}, status_code=200)\n\
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
        # Tratar domain de forma ultra flexivel\n\
        raw_domain = payload.get("domain", [])\n\
        if isinstance(raw_domain, str):\n\
            raw_domain_clean = raw_domain.strip()\n\
            if raw_domain_clean and raw_domain_clean != "{domain}":\n\
                try:\n\
                    domain = json.loads(raw_domain_clean)\n\
                except Exception as de:\n\
                    return JSONResponse(content={"status": "error", "message": f"Sintaxe invalida no domain ({raw_domain_clean}): {str(de)}"}, status_code=200)\n\
            else:\n\
                domain = []\n\
        elif isinstance(raw_domain, list):\n\
            domain = raw_domain\n\
        else:\n\
            domain = []\n\
            \n\
        # 1. Login no Odoo\n\
        try:\n\
            res_auth = requests.post(f"{url}/jsonrpc", json={\n\
                "jsonrpc": "2.0", "method": "call",\n\
                "params": {"service": "common", "method": "login", "args": [db, username, password]},\n\
                "id": 1\n\
            }, timeout=15)\n\
            auth_data = res_auth.json()\n\
            if "error" in auth_data:\n\
                err_msg = auth_data["error"].get("data", {}).get("message") or auth_data["error"].get("message")\n\
                return JSONResponse(content={"status": "error", "message": f"Erro de Login no Odoo: {err_msg}"}, status_code=200)\n\
            uid = auth_data.get("result")\n\
            if not uid:\n\
                return JSONResponse(content={"status": "error", "message": "Autenticacao recusada: Credenciais invalidas no Odoo."}, status_code=200)\n\
        except Exception as ae:\n\
            return JSONResponse(content={"status": "error", "message": f"Falha ao ligar ao Odoo (Login Timeout/URL): {str(ae)}"}, status_code=200)\n\
            \n\
        # 2. Execucao de chamadas (Aggregate, Count, Read)\n\
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
            \n\
            res_json = res.json()\n\
            if "error" in res_json:\n\
                err_details = res_json["error"].get("data", {}).get("message") or res_json["error"].get("message")\n\
                return JSONResponse(content={"status": "error", "message": f"Erro no read_group ({model}): {err_details}"}, status_code=200)\n\
            return JSONResponse(content={"status": "success", "result": res_json.get("result", [])}, status_code=200)\n\
            \n\
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
            \n\
            res_json = res.json()\n\
            if "error" in res_json:\n\
                err_details = res_json["error"].get("data", {}).get("message") or res_json["error"].get("message")\n\
                return JSONResponse(content={"status": "error", "message": f"Erro no search_count ({model}): {err_details}"}, status_code=200)\n\
            return JSONResponse(content={"status": "success", "count": res_json.get("result", 0)}, status_code=200)\n\
            \n\
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
            \n\
            res_json = res.json()\n\
            if "error" in res_json:\n\
                err_details = res_json["error"].get("data", {}).get("message") or res_json["error"].get("message")\n\
                return JSONResponse(content={"status": "error", "message": f"Erro Odoo no search_read ({model}): {err_details}"}, status_code=200)\n\
            return JSONResponse(content={"status": "success", "data": res_json.get("result", [])}, status_code=200)\n\
            \n\
    except Exception as ge:\n\
        return JSONResponse(content={"status": "error", "message": f"Excecao no servidor Bridge: {str(ge)}"}, status_code=200)\n\
' > main.py

EXPOSE 10000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "10000"]
