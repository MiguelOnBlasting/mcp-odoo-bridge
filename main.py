import os, requests, json
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

KNOWN_FIELDS = {
    "res.partner": ["id", "name", "email", "phone", "city"],
    "hr.employee": ["id", "name", "work_email", "work_phone", "department_id"],
    "sale.order": ["id", "name", "partner_id", "amount_total", "state", "date_order"],
    "account.move": ["id", "name", "partner_id", "amount_total", "state", "invoice_date", "move_type"],
    "product.product": ["id", "display_name", "list_price", "qty_available"]
}

def safe_parse_json(val):
    if not val or not isinstance(val, str):
        return val if isinstance(val, (list, dict)) else None
    clean = val.strip()
    if not clean or (clean.startswith("{") and clean.endswith("}") and ":" not in clean):
        return None
    clean_json = clean.replace("'", '"')
    try:
        return json.loads(clean_json)
    except Exception:
        return None

def parse_flexible_payload(payload):
    """Extrai model, action, domain, fields, etc., quer venham como dict ou como list posicional."""
    model = "sale.order"
    action = "read"
    domain = []
    fields = None
    agg_field = "amount_total"
    groupby = []
    limit = 5
    offset = 0

    if isinstance(payload, dict):
        model = payload.get("model") or model
        action = payload.get("action") or action
        domain = safe_parse_json(payload.get("domain")) or []
        fields = safe_parse_json(payload.get("fields"))
        agg_field = payload.get("agg_field") or agg_field
        groupby = safe_parse_json(payload.get("groupby")) or []
        try:
            limit = int(payload.get("limit", 5))
        except Exception:
            limit = 5
        try:
            offset = int(payload.get("offset", 0))
        except Exception:
            offset = 0

    elif isinstance(payload, list):
        # Interpretacao inteligente de listas posicionais enviadas pelo TypingMind
        for item in payload:
            if isinstance(item, str):
                if item in ["read", "count", "aggregate"]:
                    action = item
                elif "." in item:
                    model = item
                elif item in ["amount_total", "qty_available", "price_subtotal"]:
                    agg_field = item
            elif isinstance(item, list):
                if item and isinstance(item[0], list):
                    domain = item
                elif item and isinstance(item[0], str):
                    fields = item

    return model, action, domain, fields, agg_field, groupby, limit, offset

@app.post("/query")
async def query_odoo(request: Request):
    try:
        try:
            payload = await request.json()
        except Exception as pe:
            return JSONResponse(content={"status": "error", "message": f"Erro JSON no Payload: {str(pe)}"}, status_code=200)

        url = os.environ.get("ODOO_URL", "").rstrip("/")
        db = os.environ.get("ODOO_DB")
        username = os.environ.get("ODOO_USERNAME")
        password = os.environ.get("ODOO_PASSWORD") or os.environ.get("ODOO_API_KEY")

        if not url:
            return JSONResponse(content={"status": "error", "message": "ODOO_URL nao configurada no Render."}, status_code=200)

        if not url.startswith("http"):
            url = "https://" + url

        model, action, domain, fields, agg_field, groupby, limit, offset = parse_flexible_payload(payload)

        if not fields or not isinstance(fields, list):
            fields = KNOWN_FIELDS.get(model, ["id", "display_name"])

        # 1. Login no Odoo
        try:
            res_auth = requests.post(f"{url}/jsonrpc", json={
                "jsonrpc": "2.0", "method": "call",
                "params": {"service": "common", "method": "login", "args": [db, username, password]},
                "id": 1
            }, timeout=15)
            auth_data = res_auth.json()
            if "error" in auth_data:
                err_msg = auth_data["error"].get("data", {}).get("message") or auth_data["error"].get("message")
                return JSONResponse(content={"status": "error", "message": f"Erro Login Odoo: {err_msg}"}, status_code=200)
            uid = auth_data.get("result")
            if not uid:
                return JSONResponse(content={"status": "error", "message": "Credenciais invalidas no Odoo."}, status_code=200)
        except Exception as ae:
            return JSONResponse(content={"status": "error", "message": f"Falha ligacao Odoo: {str(ae)}"}, status_code=200)

        # 2. Execucao de chamadas
        if action == "aggregate":
            res = requests.post(f"{url}/jsonrpc", json={
                "jsonrpc": "2.0", "method": "call",
                "params": {
                    "service": "object",
                    "method": "execute_kw",
                    "args": [db, uid, password, model, "read_group", [domain], [agg_field], groupby]
                },
                "id": 2
            }, timeout=20)
            res_json = res.json()
            if "error" in res_json:
                err_details = res_json["error"].get("data", {}).get("message") or res_json["error"].get("message")
                return JSONResponse(content={"status": "error", "message": f"Erro read_group ({model}): {err_details}"}, status_code=200)
            return JSONResponse(content={"status": "success", "result": res_json.get("result", [])}, status_code=200)

        elif action == "count":
            res = requests.post(f"{url}/jsonrpc", json={
                "jsonrpc": "2.0", "method": "call",
                "params": {
                    "service": "object",
                    "method": "execute_kw",
                    "args": [db, uid, password, model, "search_count", [domain]]
                },
                "id": 2
            }, timeout=20)
            res_json = res.json()
            if "error" in res_json:
                err_details = res_json["error"].get("data", {}).get("message") or res_json["error"].get("message")
                return JSONResponse(content={"status": "error", "message": f"Erro search_count ({model}): {err_details}"}, status_code=200)
            return JSONResponse(content={"status": "success", "count": res_json.get("result", 0)}, status_code=200)

        else:
            res = requests.post(f"{url}/jsonrpc", json={
                "jsonrpc": "2.0", "method": "call",
                "params": {
                    "service": "object",
                    "method": "execute_kw",
                    "args": [db, uid, password, model, "search_read", [domain], {"fields": fields, "limit": limit, "offset": offset, "order": "id desc"}]
                },
                "id": 2
            }, timeout=20)
            res_json = res.json()
            if "error" in res_json:
                err_details = res_json["error"].get("data", {}).get("message") or res_json["error"].get("message")
                return JSONResponse(content={"status": "error", "message": f"Erro search_read ({model}): {err_details}"}, status_code=200)
            return JSONResponse(content={"status": "success", "data": res_json.get("result", [])}, status_code=200)

    except Exception as ge:
        return JSONResponse(content={"status": "error", "message": f"Excecao servidor: {str(ge)}"}, status_code=200)
