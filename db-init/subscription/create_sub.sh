#!/bin/sh
set -e

echo "Creating logical replication subscription on RDS..."

PGPASSWORD="$DB_PASSWORD" psql \
  -h "$DB_HOST" \
  -p "${DB_PORT:-5432}" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  -v ON_ERROR_STOP=1 \
  -c "CREATE SUBSCRIPTION migracion_sub CONNECTION 'host=$GCP_HOST port=5432 dbname=$DB_NAME user=repl_user password=$GCP_REPL_PASSWORD sslmode=require' PUBLICATION migracion_pub WITH (copy_data = true);"

echo "Subscription created. Checking status..."

PGPASSWORD="$DB_PASSWORD" psql \
  -h "$DB_HOST" \
  -p "${DB_PORT:-5432}" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  -c "SELECT subname, subenabled FROM pg_subscription;"

echo "Done."
