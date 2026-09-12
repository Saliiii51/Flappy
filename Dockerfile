FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY serve.py .
# Frontend istenirse web/ de kopyalanır, ama prod backend genelde WS-only çalışır.
COPY web ./web
ENV SERVE_HTTP=false
CMD ["python", "serve.py"]
