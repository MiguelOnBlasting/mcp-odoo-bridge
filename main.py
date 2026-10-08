import os, requests, json
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

DEFAULT_FIELDS = {
    "hr.employee": ["id", "name", "work_email", "job_title"],
    "res.partner": ["id", "name", "email", "phone"],
    "sale.order": ["id", "name", "amount_total", "state"],
    "product.product": ["id", "display_name", "list_price"]
}

@app.post("/query")
async def query_odoo(request: Request):
    try:
        body = await request.json()
        
        # Extrai os parâmetros
        model = body.get("model", "hr.employee")
        fields = body.get("fields") or DEFAULT_FIELDS.get(model, ["id", "display_name"])
        domain = body.get("domain") or []
        limit = int(body.get("limit", 5))

        # Garantir que domain é uma lista
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
            return JSONResponse(content={"status": "error", "message": "ODOO_URL nao configurada."}, status_code=200)

        if not url.startswith("http"):
            url = "https://" + url

        # 1. Autenticação no Odoo
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

        # 2. Leitura com Filtro (domain)
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
