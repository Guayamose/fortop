#!/bin/bash
set -euo pipefail
exec > >(tee -a /var/log/fortop-bootstrap.log) 2>&1
export DEBIAN_FRONTEND=noninteractive

# A new, dedicated data disk is formatted only if it has no filesystem.
data_device=/dev/disk/by-id/google-fortop-data
for attempt in $(seq 1 60); do test -b "$data_device" && break; sleep 1; done
test -b "$data_device"
if ! blkid "$data_device" >/dev/null; then mkfs.ext4 -F -L fortop-data "$data_device"; fi
mkdir -p /srv/fortop
if ! findmnt /srv/fortop >/dev/null; then mount "$data_device" /srv/fortop; fi
data_uuid=$(blkid -s UUID -o value "$data_device")
if ! grep -q "UUID=$data_uuid " /etc/fstab; then
  echo "UUID=$data_uuid /srv/fortop ext4 defaults,nofail 0 2" >> /etc/fstab
fi
install -d -m 0750 -o 1000 -g 1000 /srv/fortop/storage
install -d -m 0700 /srv/fortop/postgres /srv/fortop/backup-staging

apt-get update -qq
apt-get install -y --no-install-recommends ca-certificates curl gnupg uidmap dbus-user-session slirp4netns fuse-overlayfs acl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
printf 'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable\n' > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-ce-rootless-extras
install -d /etc/docker
cat > /etc/docker/daemon.json <<'JSON'
{"log-driver":"local","log-opts":{"max-size":"10m","max-file":"3"},"live-restore":true}
JSON
systemctl enable --now docker
install -d /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/fortop-data.conf <<'UNIT'
[Unit]
RequiresMountsFor=/srv/fortop
UNIT
systemctl daemon-reload
systemctl restart docker

# The worker receives only this rootless daemon's socket. The web process has
# no Docker socket. Repository code is parsed in no-network, read-only containers.
if ! id fortop-sandbox >/dev/null 2>&1; then
  useradd --uid 2001 --create-home --home-dir /srv/fortop/sandbox --shell /bin/bash fortop-sandbox
fi
chmod 0700 /srv/fortop/sandbox
install -d /etc/systemd/system/user@.service.d
cat > /etc/systemd/system/user@.service.d/delegate.conf <<'UNIT'
[Service]
Delegate=cpu cpuset io memory pids
UNIT
systemctl daemon-reload
loginctl enable-linger fortop-sandbox
systemctl start user@2001.service
runuser -u fortop-sandbox -- env XDG_RUNTIME_DIR=/run/user/2001 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/2001/bus dockerd-rootless-setuptool.sh install --force
runuser -u fortop-sandbox -- env XDG_RUNTIME_DIR=/run/user/2001 DOCKER_HOST=unix:///run/user/2001/docker.sock docker pull node:24.19.0-bookworm-slim
setfacl -m u:1000:rw /run/user/2001/docker.sock
# ACLs are renewed on every rootless daemon restart, including VM restarts.
setfacl -m u:1000:x /run/user/2001
install -d -o 2001 -g 2001 /srv/fortop/sandbox/.config/systemd/user/docker.service.d
cat > /srv/fortop/sandbox/.config/systemd/user/docker.service.d/fortop-acl.conf <<'UNIT'
[Service]
ExecStartPre=/usr/bin/setfacl -m u:1000:x /run/user/2001
ExecStartPost=/usr/bin/setfacl -m u:1000:rw /run/user/2001/docker.sock
UNIT
chown -R 2001:2001 /srv/fortop/sandbox/.config
install -d /etc/systemd/system/user@2001.service.d
cat > /etc/systemd/system/user@2001.service.d/fortop-data.conf <<'UNIT'
[Unit]
RequiresMountsFor=/srv/fortop
UNIT
systemctl daemon-reload
runuser -u fortop-sandbox -- env XDG_RUNTIME_DIR=/run/user/2001 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/2001/bus systemctl --user daemon-reload
runuser -u fortop-sandbox -- env XDG_RUNTIME_DIR=/run/user/2001 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/2001/bus systemctl --user restart docker
docker pull postgres:17-alpine

install -m 0750 -d /usr/local/lib/fortop
cat > /usr/local/lib/fortop/backup <<'BACKUP'
#!/bin/bash
set -euo pipefail
umask 077
exec 9>/run/fortop-backup.lock
flock -n 9 || exit 0
docker inspect fortop-db >/dev/null 2>&1 || exit 0
backup_path=$(mktemp -d /srv/fortop/backup-staging/run.XXXXXX)
trap 'rm -rf "$backup_path"' EXIT
for database in fortop_production fortop_production_queue fortop_production_cache fortop_production_cable; do
  docker exec fortop-db pg_dump -U fortop --format=custom "$database" > "$backup_path/$database.dump"
  docker exec -i fortop-db pg_restore --list < "$backup_path/$database.dump" >/dev/null
done
tar -C /srv/fortop/storage -czf "$backup_path/documents.tar.gz" .
backup_stamp=$(date -u +%Y%m%dT%H%M%SZ)
tar -C "$backup_path" -cf "$backup_path/fortop.tar" fortop_production.dump fortop_production_queue.dump fortop_production_cache.dump fortop_production_cable.dump documents.tar.gz
gcloud storage cp "$backup_path/fortop.tar" "gs://fortop-ai-gkecke-backups/$backup_stamp/fortop.tar" --project=fortop-ai-gkecke --quiet
echo "Fortop backup completed: $backup_stamp"
BACKUP
chmod 0700 /usr/local/lib/fortop/backup
cat > /etc/systemd/system/fortop-backup.service <<'UNIT'
[Unit]
Description=Fortop PostgreSQL and documents backup to Google Cloud Storage
Requires=docker.service
After=docker.service
[Service]
Type=oneshot
ExecStart=/usr/local/lib/fortop/backup
UNIT
cat > /etc/systemd/system/fortop-backup.timer <<'UNIT'
[Unit]
Description=Daily Fortop backups
[Timer]
OnCalendar=*-*-* 03:00:00 UTC
RandomizedDelaySec=1200
Persistent=true
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now fortop-backup.timer
touch /var/lib/fortop-bootstrap-complete
echo 'Fortop bootstrap complete'
