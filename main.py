import os, requests, json, re
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

def get_valid_model_fields(url, db, uid, password, model):
    """Consulta o Odoo via fields_get para descobrir os campos reais da tabela."""
    try:
        res = requests.post(f"{url}/jsonrpc", json={
            "jsonrpc": "2.0", "method": "call",
            "params": {
                "service": "object",
                "method": "execute_kw",
                "args": [db, uid, password, model, "fields_get", [], {"attributes": ["string", "type"]}]
            },
            "id": 99
        }, timeout=5)
        res_json = res.json()
        if "result" in res_json and isinstance(res_json["result"], dict):
            return set(res_json["result"].keys())
    except Exception:
        pass
    return None

def parse_any_payload(raw_data):
    """Converte QUALQUER tipo de dados (dict, list, string) numa consulta estruturada."""
    model = "sale.order"
    action = "read"
    domain = []
    fields = None
    agg_field = "amount_total"
    groupby = []
    limit = 5
    offset = 0

    # 1. Se vier como Dicionario JSON
    if isinstance(raw_data, dict):
        model = raw_data.get("model") or model
        action = raw_data.get("action") or action
        domain = raw_data.get("domain") or []
        fields = raw_data.get("fields")
        agg_field = raw_data.get("agg_field") or agg_field
        groupby = raw_data.get("groupby") or []
        try: limit = int(raw_data.get("limit", 5))
        except: limit = 5
        try: offset = int(raw_data.get("offset", 0))
        except: offset = 0

    # 2. Se vier como Lista Posicional
    elif isinstance(raw_data, list):
        for item in raw_data:
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

    # 3. Se vier como String Bruta
    elif isinstance(raw_data, str):
        str_val = raw_data.strip()
        if "hr.employee" in str_val: model = "hr.employee"
        elif "res.partner" in str_val: model = "res.partner"
        elif "account.move" in str_val: model = "account.move"
        elif "product.product" in str_val: model = "product.product"
        
        if "count" in str_val: action = "count"
        elif "aggregate" in str_val: action = "aggregate"
        else: action = "read"

    # Se domain for string, tenta JSON
    if isinstance(domain, str):
        try: domain = json.loads(domain)
        except: domain = []

    # Se fields for string, tenta JSON
    if isinstance(fields, str):
        try: fields = json.loads(fields)
        except: fields = None

    return model, action, domain, fields, agg_field, groupby, limit, offset

@app.post("/query")
async def query_odoo(request: Request):
    try:
        # Extrai os dados sem falhar no parsing de JSON rígido
        try:
            payload = await request.json()
        except Exception:
            try:
                body_bytes = await request.body()
                body_str = body_bytes.decode("utf-8").strip()
                try:
                    payload = json.loads(body_str)
                except Exception:
                    payload = body_str
            except Exception as pe:
                return JSONResponse(content={"status": "error", "message": f"Erro leitura payload: {str(pe)}"}, status_code=200)

        url = os.environ.get("ODOO_URL", "").rstrip("/")
        db = os.environ.get("ODOO_DB")
        username = os.environ.get("ODOO_USERNAME")
        password = os.environ.get("ODOO_PASSWORD") or os.environ.get("ODOO_API_KEY")

        if not url:
            return JSONResponse(content={"status": "error", "message": "ODOO_URL nao configurada."}, status_code=200)

        if not url.startswith("http"):
            url = "https://" + url

        model, action, domain, raw_fields, agg_field, groupby, limit, offset = parse_any_payload(payload)

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

        # 2. Validacao dinamica de campos com Odoo ORM (descarta automaticamente campos que nao existem)
        valid_odoo_fields = get_valid_model_fields(url, db, uid, password, model)
        
        if raw_fields and isinstance(raw_fields, list):
            cleaned_fields = []
            for f in raw_fields:
                if isinstance(f, str):
                    if valid_odoo_fields:
                        if f in valid_odoo_fields:
                            cleaned_fields.append(f)
                    else:
                        cleaned_fields.append(f)
            fields = cleaned_fields if cleaned_fields else KNOWN_FIELDS.get(model, ["id", "display_name"])
        else:
            fields = KNOWN_FIELDS.get(model, ["id", "display_name"])

        # 3. Execucao das chamadas Odoo
        try:
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
        except Exception as oe:
            return JSONResponse(content={"status": "error", "message": f"Erro na execucao Odoo: {str(oe)}"}, status_code=200)

    except Exception as ge:
        return JSONResponse(content={"status": "error", "message": f"Excecao servidor: {str(ge)}"}, status_code=200)
