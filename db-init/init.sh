#!/bin/sh
set -e

echo "Initializing database schema and seed data..."

PGPASSWORD="$DB_PASSWORD" psql \
  -h "$DB_HOST" \
  -p "${DB_PORT:-5432}" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  -f /app/schema.sql

echo "Database initialized successfully."
