FROM python:3.11-slim
RUN pip install --no-cache-dir mcp-server-odoo
EXPOSE 10000
CMD ["python", "-m", "mcp_server_odoo", "--transport", "streamable-http", "--port", "10000"]
