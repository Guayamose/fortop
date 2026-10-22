#!/bin/sh
set -eu
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --set ON_ERROR_STOP=1 --set fortop_password="$FORTOP_DATABASE_PASSWORD" <<'SQL'
CREATE ROLE fortop LOGIN PASSWORD :'fortop_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
SELECT format('CREATE DATABASE %I OWNER fortop', database_name)
FROM (VALUES ('fortop_production'), ('fortop_production_queue'), ('fortop_production_cache'), ('fortop_production_cable')) AS names(database_name) \gexec
SQL
