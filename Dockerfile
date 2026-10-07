FROM python:3.11-slim

RUN pip install --no-cache-dir fastapi uvicorn

RUN echo 'import os, xmlrpc.client\n\
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
    if not all([url, db, username, password]):\n\
        return {"error": "Variaveis de ambiente em falta no Render"}\n\
        \n\
    try:\n\
        common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")\n\
        uid = common.authenticate(db, username, password, {})\n\
        \n\
        if not uid:\n\
            return {"error": "Falha na autenticacao Odoo"}\n\
            \n\
        models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")\n\
        count = models.execute_kw(db, uid, password, "sale.order", "search_count", [[["state", "in", ["draft", "sent", "sale"]]]])\n\
        \n\
        return {"count": count}\n\
    except Exception as e:\n\
        return {"error": str(e)}\n\
' > main.py

EXPOSE 10000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "10000"]
