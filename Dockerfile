FROM python:3.11-slim

RUN apt-get update && apt-get install -y nodejs npm && rm -rf /var/lib/apt/lists/*
RUN npm install -g cors-container
RUN pip install --no-cache-dir mcp-server-odoo

EXPOSE 10000

CMD ["sh", "-c", "python -m mcp_server_odoo --transport streamable-http --host 127.0.0.1 --port 9999 & cors-container --port 10000 --target http://127.0.0.1:9999"]
