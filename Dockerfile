FROM python:3.11-slim

RUN pip install --no-cache-dir fastapi uvicorn requests

RUN echo 'import os, requests\n\
from fastapi import FastAPI\n\
from fastapi.middleware.cors import CORSMiddleware\n\
\n\
app = FastAPI()\n\
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])\n\
\n\
@app.api_route("/get_quotations", methods=["GET", "POST"])\n\
def get_quotations():\n\
    url = os.environ.get("ODOO_URL", "").rstrip("/")\n\
    db = os.environ.get("ODOO_DB")\n\
    username = os.environ.get("ODOO_USERNAME")\n\
    password = os.environ.get("ODOO_PASSWORD") or os.environ.get("ODOO_API_KEY")\n\
    \n\
    if not url.startswith("http"):\n\
        url = "https://" + url\n\
        \n\
    try:\n\
        # 1. Autenticacao no Odoo\n\
        auth_payload = {\n\
            "jsonrpc": "2.0",\n\
            "method": "call",\n\
            "params": {"service": "common", "method": "login", "args": [db, username, password]},\n\
            "id": 1\n\
        }\n\
        res_auth = requests.post(f"{url}/jsonrpc", json=auth_payload, timeout=5)\n\
        uid = res_auth.json().get("result")\n\
        \n\
        if not uid:\n\
            return {"error": f"Falha no login do Odoo. Resposta: {res_auth.text}"}\n\
            \n\
        # 2. Pesquisa de Cotacoes\n\
        data_payload = {\n\
            "jsonrpc": "2.0",\n\
            "method": "call",\n\
            "params": {\n\
                "service": "object",\n\
                "method": "execute_kw",\n\
                "args": [db, uid, password, "sale.order", "search_count", [[["state", "in", ["draft", "sent", "sale"]]]]]\n\
            },\n\
            "id": 2\n\
        }\n\
        res_data = requests.post(f"{url}/jsonrpc", json=data_payload, timeout=5)\n\
        return {"count": res_data.json().get("result", 0)}\n\
        \n\
    except Exception as e:\n\
        return {"error": f"Erro de ligacao: {str(e)}"}\n\
' > main.py

EXPOSE 10000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "10000"]
