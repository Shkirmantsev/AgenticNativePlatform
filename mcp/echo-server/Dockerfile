FROM python:3.12-slim
WORKDIR /app
RUN pip install fastapi uvicorn pydantic
COPY server.py /app/server.py
EXPOSE 3001
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "3001"]
