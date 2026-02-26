FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY sync_workflows.py .

CMD ["python", "-u", "sync_workflows.py"]
