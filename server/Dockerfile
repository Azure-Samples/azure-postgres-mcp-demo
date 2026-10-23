FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY horizondb.py .
USER 10001
ENV MCP_TRANSPORT=streamable-http
EXPOSE 8080
CMD ["python", "horizondb.py"]
