FROM python:3.11-slim

RUN pip install --no-cache-dir mcp-server-odoo cors-proxy-server

EXPOSE 10000

ENV PORT=10000

CMD ["sh", "-c", "python -m mcp_server_odoo --transport streamable-http --host 127.0.0.1 --port 9999 & cors-proxy-server --port 10000 --target http://127.0.0.1:9999"]
