FROM python:3.11-slim

RUN pip install --no-cache-dir mcp-server-odoo corsproxy

EXPOSE 10000

CMD ["python", "-m", "mcp_server_odoo", "--transport", "streamable-http", "--host", "0.0.0.0", "--port", "10000"]
