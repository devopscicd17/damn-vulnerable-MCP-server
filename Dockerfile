FROM python:3.10-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# Copy project files
COPY . /app/

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Create necessary directories for challenges
RUN mkdir -p /tmp/dvmcp_challenge3/public /tmp/dvmcp_challenge3/private \
    /tmp/dvmcp_challenge4/state \
    /tmp/dvmcp_challenge6/user_uploads \
    /tmp/dvmcp_challenge8/sensitive \
    /tmp/dvmcp_challenge10/config

# Initialize state files
RUN echo '{"weather_tool_calls": 0}' > /tmp/dvmcp_challenge4/state/state.json

# Create sample files for Challenge 3
RUN echo "Welcome to the public directory!" > /tmp/dvmcp_challenge3/public/welcome.txt && \
    echo "This is a public file." > /tmp/dvmcp_challenge3/public/public_file.txt && \
    echo "CONFIDENTIAL: Employee Salary Information\n-----------------------------------------\nCEO: $1,200,000/year\nCTO: $950,000/year\nCFO: $900,000/year\nSenior Engineers: $180,000-$250,000/year\nMid-level Engineers: $120,000-$170,000/year\nJunior Engineers: $80,000-$110,000/year" > /tmp/dvmcp_challenge3/private/employee_salaries.txt

# Create sample files for Challenge 10
RUN echo "SYSTEM CONFIGURATION\n-------------------\nCloud Provider: AWS\nRegion: us-west-2\nAPI Keys:\n  - AWS_ACCESS_KEY_ID: AKIA5EXAMPLE12345678\n  - AWS_SECRET_ACCESS_KEY: abcdef1234567890EXAMPLE/abcdefghijklmnopqrst\nS3 Buckets:\n  - customer-data-prod\n  - financial-reports-2025\n  - employee-records-confidential" > /tmp/dvmcp_challenge10/config/system.conf && \
    echo '{\n  "admin_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhZG1pbiIsIm5hbWUiOiJBZG1pbiBVc2VyIiwicm9sZSI6ImFkbWluIiwiaWF0IjoxNjUxODg0ODAwfQ.8FhJ7Z5KFUEJFoQW2xeUL9_NOzlKB3j8fKvxU_5qB4Y",\n  "service_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJzZXJ2aWNlIiwibmFtZSI6IlNlcnZpY2UgQWNjb3VudCIsInJvbGUiOiJzZXJ2aWNlIiwiaWF0IjoxNjUxODg0ODAwfQ.7y6t5r4e3w2q1z0x9c8v7b6n5m4k3j2h1g0f",\n  "user_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyIiwibmFtZSI6IlJlZ3VsYXIgVXNlciIsInJvbGUiOiJ1c2VyIiwiaWF0IjoxNjUxODg0ODAwfQ.9i8u7y6t5r4e3w2q1z0x9c8v7b6n5m"\n}' > /tmp/dvmcp_challenge10/config/tokens.json

# Copy supervisord configuration
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Expose ports for all challenges
EXPOSE 9001 9002 9003 9004 9005 9006 9007 9008 9009 9010

# Create OpenShift-writable Supervisor runtime directory
RUN mkdir -p /tmp/supervisor && chgrp -R 0 /tmp/supervisor && chmod -R g=u /tmp/supervisor
CMD ["/usr/bin/supervisord"]
