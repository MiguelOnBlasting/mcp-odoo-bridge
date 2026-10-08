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

def parse_payload(body):
    """Extrai model, domain, fields, limit e action de QUALQUER formato de entrada."""
    model = "hr.employee"
    action = "read"
    domain = []
    fields = None
    limit = 5

    # Caso 1: Dicionário JSON tradicional
    if isinstance(body, dict):
        model = body.get("model") or model
        action = body.get("action") or action
        domain = body.get("domain") or []
        fields = body.get("fields")
        try: limit = int(body.get("limit", 5))
        except: limit = 5

    # Caso 2: Lista posicional enviada pelo TypingMind (ex: ["hr.employee", "count"])
    elif isinstance(body, list):
        for item in body:
            if isinstance(item, int):
                limit = item
            elif isinstance(item, str):
                if item in ["read", "count"]:
                    action = item
                elif "." in item:
                    model = item
            elif isinstance(item, list):
                if item and isinstance(item[0], list):
                    domain = item
                elif item and isinstance(item[0], str):
                    fields = item

    if not fields:
        fields = DEFAULT_FIELDS.get(model, ["id", "display_name"])

    return model, action, domain, fields, limit

@app.post("/query")
async def query_odoo(request: Request):
    try:
        try:
            body = await request.json()
        except Exception:
            body_bytes = await request.body()
            body = body_bytes.decode("utf-8").strip()

        model, action, domain, fields, limit = parse_payload(body)

        url = os.environ.get("ODOO_URL", "").rstrip("/")
        db = os.environ.get("ODOO_DB")
        username = os.environ.get("ODOO_USERNAME")
        password = os.environ.get("ODOO_PASSWORD") or os.environ.get("ODOO_API_KEY")

        if not url:
            return JSONResponse(content={"status": "error", "message": "ODOO_URL nao configurada."}, status_code=200)

        if not url.startswith("http"):
            url = "https://" + url

        # Login Odoo
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

        # Executa Contagem ou Leitura
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
