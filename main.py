import os, requests, json
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

DEFAULT_FIELDS = {
    "hr.employee": ["id", "name", "work_email", "job_title", "department_id"],
    "res.partner": ["id", "name", "email", "phone", "vat", "street", "city"],
    "sale.order": ["id", "name", "partner_id", "amount_total", "state", "date_order"],
    "product.product": ["id", "display_name", "list_price", "qty_available"]
}

@app.post("/query")
async def query_odoo(request: Request):
    try:
        body = await request.json()
        
        # Extração de parâmetros
        model = body.get("model", "hr.employee")
        action = body.get("action", "read")
        domain = body.get("domain") or []
        limit = int(body.get("limit", 5))
        
        # Tratamento de campos
        raw_fields = body.get("fields")
        if isinstance(raw_fields, list) and raw_fields:
            fields = raw_fields
        else:
            fields = DEFAULT_FIELDS.get(model, ["id", "display_name"])

        # Garantir que domain é lista
        if isinstance(domain, str):
            try:
                domain = json.loads(domain.replace("'", '"'))
            except Exception:
                domain = []

        url = os.environ.get("ODOO_URL", "").rstrip("/")
        db = os.environ.get("ODOO_DB")
        username = os.environ.get("ODOO_USERNAME")
        password = os.environ.get("ODOO_PASSWORD") or os.environ.get("ODOO_API_KEY")

        if not url:
            return JSONResponse(content={"status": "error", "message": "ODOO_URL não configurada."}, status_code=200)

        if not url.startswith("http"):
            url = "https://" + url

        # 1. Login Odoo
        auth_rpc = {
            "jsonrpc": "2.0",
            "method": "call",
            "params": {"service": "common", "method": "login", "args": [db, username, password]},
            "id": 1
        }
        res_auth = requests.post(f"{url}/jsonrpc", json=auth_rpc, timeout=10)
        uid = res_auth.json().get("result")
        
        if not uid:
            return JSONResponse(content={"status": "error", "message": "Falha de autenticacao no Odoo."}, status_code=200)

        # 2. Ação: Contagem
        if action == "count":
            count_rpc = {
                "jsonrpc": "2.0",
                "method": "call",
                "params": {
                    "service": "object",
                    "method": "execute_kw",
                    "args": [db, uid, password, model, "search_count", [domain]]
                },
                "id": 2
            }
            res_count = requests.post(f"{url}/jsonrpc", json=count_rpc, timeout=15)
            count_val = res_count.json().get("result", 0)
            return JSONResponse(content={"status": "success", "count": count_val}, status_code=200)

        # 3. Ação: Leitura (search_read)
        else:
            read_rpc = {
                "jsonrpc": "2.0",
                "method": "call",
                "params": {
                    "service": "object",
                    "method": "execute_kw",
                    "args": [db, uid, password, model, "search_read", [domain], {"fields": fields, "limit": limit}]
                },
                "id": 2
            }
            res_data = requests.post(f"{url}/jsonrpc", json=read_rpc, timeout=15)
            result = res_data.json().get("result", [])
            return JSONResponse(content={"status": "success", "data": result}, status_code=200)

    except Exception as e:
        return JSONResponse(content={"status": "error", "message": str(e)}, status_code=200)
