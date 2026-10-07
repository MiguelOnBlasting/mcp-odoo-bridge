FROM python:3.11-slim

RUN pip install --no-cache-dir fastapi uvicorn requests

RUN echo 'import os, requests, xmlrpc.client, http.client\n\
from fastapi import FastAPI\n\
from fastapi.middleware.cors import CORSMiddleware\n\
\n\
class TimeoutTransport(xmlrpc.client.Transport):\n\
    def __init__(self, timeout=5, *args, **kwargs):\n\
        super().__init__(*args, **kwargs)\n\
        self.timeout = timeout\n\
    def make_connection(self, host):\n\
        conn = super().make_connection(host)\n\
        conn.timeout = self.timeout\n\
        return conn\n\
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
    if not all([url, db, username, password]):\n\
        return {"error": f"Falta variavel: URL={bool(url)}, DB={bool(db)}, USER={bool(username)}, PASS={bool(password)}"}\n\
    \n\
    transport = TimeoutTransport(timeout=5)\n\
    try:\n\
        common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common", transport=transport)\n\
        uid = common.authenticate(db, username, password, {})\n\
        if not uid:\n\
            return {"error": "Falha de Login: Utilizador, Base de Dados ou Chave/Password invalidos"}\n\
            \n\
        models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object", transport=transport)\n\
        count = models.execute_kw(db, uid, password, "sale.order", "search_count", [[["state", "in", ["draft", "sent", "sale"]]]])\n\
        return {"count": count}\n\
    except Exception as e:\n\
        return {"error": f"Erro Odoo: {str(e)}"}\n\
' > main.py

EXPOSE 10000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "10000"]
