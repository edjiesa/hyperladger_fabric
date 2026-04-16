FROM postgres:15

RUN apt-get update && apt-get install -y postgresql-15-pgaudit && rm -rf /var/lib/apt/lists/*

# Copy configuration
COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY init-pgaudit.sql /docker-entrypoint-initdb.d/

CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]
