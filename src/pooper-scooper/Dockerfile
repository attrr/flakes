FROM --platform=$TARGETPLATFORM docker.io/library/python:3.12-alpine

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main_fastapi.py .

EXPOSE 8000
ENTRYPOINT ["python", "main_fastapi.py"]
CMD ["--host", "0.0.0.0", "--port", "8000"]
