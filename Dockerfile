FROM python:3.10-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 5000
# Ensure schema.py runs to create the database before starting the app
RUN python app/schema.py
CMD ["python", "app/main.py"]