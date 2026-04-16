CREATE EXTENSION IF NOT EXISTS pgaudit;
-- Creating a test table to log operations
CREATE TABLE app_data (
    id SERIAL PRIMARY KEY,
    details TEXT NOT NULL
);
