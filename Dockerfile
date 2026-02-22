FROM python:3.10-slim

# Set working directory to a clear, named folder
WORKDIR /finance_docker_app

# Copy requirements first
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the app folder
COPY app/ ./app/

# Switch context to app folder so imports work
WORKDIR /finance_docker_app/app

# Initialize DB
RUN python schema.py

# Open Port 5000
EXPOSE 5000

# Run the App
CMD ["python", "main.py"]