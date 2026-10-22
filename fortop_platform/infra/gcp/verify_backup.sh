#!/bin/bash
# Run on the VM as root. Restores ONLY into a new temporary database.
set -euo pipefail
umask 077
source_uri=${1:?Pass the gs:// URL of the Fortop backup to verify}
if ! [[ "$source_uri" =~ ^gs://fortop-ai-gkecke-backups/[0-9]{8}T[0-9]{6}Z/fortop\.tar$ ]]; then
  echo 'Unexpected backup location' >&2
  exit 1
fi
restore_path=$(mktemp -d /srv/fortop/backup-staging/restore.XXXXXX)
restore_database="fortop_restore_$(date +%s)_$$"
cleanup() {
  docker exec fortop-db dropdb -U postgres --if-exists "$restore_database" >/dev/null 2>&1 || true
  rm -rf "$restore_path"
}
trap cleanup EXIT
gcloud storage cp "$source_uri" "$restore_path/fortop.tar" --project=fortop-ai-gkecke --quiet
for database in fortop_production fortop_production_queue fortop_production_cache fortop_production_cable; do
  # Stream fixed members to files; never extract arbitrary paths or symlinks.
  tar -xOf "$restore_path/fortop.tar" "$database.dump" > "$restore_path/database.dump"
  docker exec fortop-db createdb -U postgres "$restore_database"
  docker exec -i fortop-db pg_restore -U postgres --no-owner --no-privileges --exit-on-error --dbname="$restore_database" < "$restore_path/database.dump"
  tables=$(docker exec fortop-db psql -U postgres --dbname="$restore_database" -Atc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")
  test "$tables" -gt 0
  docker exec fortop-db dropdb -U postgres "$restore_database"
  echo "Restore verified: $database ($tables tables)"
done
tar -xOf "$restore_path/fortop.tar" documents.tar.gz > "$restore_path/documents.tar.gz"
tar -tzf "$restore_path/documents.tar.gz" >/dev/null
echo 'Document archive integrity verified. Production databases were not modified.'
