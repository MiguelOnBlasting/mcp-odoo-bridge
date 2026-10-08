import os, requests, json, ast
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

DEFAULT_FIELDS = {
    "hr.employee": ["id", "name", "work_email", "job_title", "department_id"],
    "res.partner": ["id", "name", "email", "phone", "vat", "street", "city"],
    "sale.order": ["id", "name", "partner_id", "amount_total", "state", "date_order"],
    "sale.order.line": [
        "id", "order_id", "order_partner_id", "product_id", 
        "price_unit", "discount", "price_reduce", "product_uom_qty", "price_subtotal", "create_date"
    ],
    "account.move": ["id", "name", "partner_id", "amount_total", "amount_residual", "state", "payment_state", "move_type", "invoice_date"],
    "account.move.line": [
        "id", "move_id", "partner_id", "product_id", 
        "price_unit", "discount", "quantity", "price_subtotal", "date"
    ],
    "product.product": ["id", "display_name", "list_price", "qty_available"],
    "product.template": ["id", "name", "list_price", "qty_available"]
}

def clean_domain(domain_raw):
    """Normaliza e limpa a lista de filtros domain."""
    if not domain_raw:
        return []
    
    if isinstance(domain_raw, str):
        try:
            domain_raw = json.loads(domain_raw)
        except Exception:
            try:
                domain_raw = ast.literal_eval(domain_raw)
            except Exception:
                return []

    if isinstance(domain_raw, list):
        cleaned = []
        for item in domain_raw:
            if isinstance(item, str):
                try:
                    parsed_item = json.loads(item)
                    if isinstance(parsed_item, list):
                        cleaned.append(parsed_item)
                except Exception:
                    try:
                        parsed_item = ast.literal_eval(item)
                        if isinstance(parsed_item, list):
                            cleaned.append(parsed_item)
                    except Exception:
                        pass
            elif isinstance(item, list):
                cleaned.append(item)
        return cleaned

    return []

def resolve_partner_domain(domain, url, db, uid, password):
    """Traduções automáticas de nomes de parceiros em IDs caso o Odoo exija IDs diretos."""
    new_domain = []
    for clause in domain:
        if isinstance(clause, list) and len(clause) == 3:
            field, op, val = clause[0], clause[1], clause[2]
            # Se for filtro por partner_id com texto em ilike
            if field in ["partner_id", "order_partner_id", "partner_id.name"] and op in ["ilike", "="] and isinstance(val, str):
                try:
                    # Procura os IDs dos parceiros correspondentes ao nome
                    res = requests.post(f"{url}/jsonrpc", json={
                        "jsonrpc": "2.0", "method": "call",
                        "params": {
                            "service": "object", "method": "execute_kw",
                            "args": [db, uid, password, "res.partner", "search_read", [[["name", "ilike", val]]], {"fields": ["id"], "limit": 10}]
                        }, "id": 99
                    }, timeout=5)
                    partner_ids = [p["id"] for p in res.json().get("result", [])]
                    if partner_ids:
                        target_field = "order_partner_id" if field == "order_partner_id" else "partner_id"
                        new_domain.append([target_field, "in", partner_ids])
                        continue
                except Exception:
                    pass
            # Corrige parceiro_id.name para partner_id
            if field == "partner_id.name":
                clause[0] = "partner_id"
        new_domain.append(clause)
    return new_domain

@app.post("/query")
async def query_odoo(request: Request):
    try:
        try:
            body = await request.json()
        except Exception:
            body_bytes = await request.body()
            body = json.loads(body_bytes.decode("utf-8").strip())

        model = body.get("model", "hr.employee")
        raw_domain = body.get("domain") or []
        limit = int(body.get("limit", 5))
        order = body.get("order", "id desc")

        domain = clean_domain(raw_domain)
        fields = DEFAULT_FIELDS.get(model, ["id", "display_name"])

        url = os.environ.get("ODOO_URL", "").rstrip("/")
        db = os.environ.get("ODOO_DB")
        username = os.environ.get("ODOO_USERNAME")
        password = os.environ.get("ODOO_PASSWORD") or os.environ.get("ODOO_API_KEY")

        if not url:
            return JSONResponse(content={"status": "error", "message": "ODOO_URL não configurada."}, status_code=200)

        if not url.startswith("http"):
            url = "https://" + url

        # 1. Login no Odoo
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

        # Trata resolução automática de clientes para modelos de linhas
        if model in ["account.move.line", "sale.order.line"]:
            domain = resolve_partner_domain(domain, url, db, uid, password)

        # 2. Contagem (se limit == 0)
        if limit == 0:
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

        # 3. Leitura com Ordenação (search_read)
        else:
            read_rpc = {
                "jsonrpc": "2.0",
                "method": "call",
                "params": {
                    "service": "object",
                    "method": "execute_kw",
                    "args": [db, uid, password, model, "search_read", [domain], {
                        "fields": fields, 
                        "limit": limit,
                        "order": order
                    }]
                },
                "id": 2
            }
            res_data = requests.post(f"{url}/jsonrpc", json=read_rpc, timeout=15)
            result = res_data.json().get("result", [])
            return JSONResponse(content={"status": "success", "data": result}, status_code=200)

    except Exception as e:
        return JSONResponse(content={"status": "error", "message": str(e)}, status_code=200)