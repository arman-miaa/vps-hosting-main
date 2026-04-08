#!/bin/bash
set -euo pipefail

# 1) Non‑interactive APT
export DEBIAN_FRONTEND=noninteractive

# 2) Detect Ubuntu codename
CODENAME=$(grep -E '^UBUNTU_CODENAME=' /etc/os-release | cut -d= -f2)
echo "→ Detected Ubuntu: $CODENAME"

# 3) Install prerequisites + MongoDB without prompts
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive \
  apt-get install -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    gnupg curl

# 4) Add MongoDB GPG key & repo
curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc \
  | sudo gpg -o /usr/share/keyrings/mongodb-archive-keyring.gpg --dearmor

cat <<EOF | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
deb [signed-by=/usr/share/keyrings/mongodb-archive-keyring.gpg] \
    https://repo.mongodb.org/apt/ubuntu ${CODENAME}/mongodb-org/8.0 multiverse
EOF

# 5) Install MongoDB packages
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive \
  apt-get install -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    mongodb-org

# 6) Create data/log dirs
sudo mkdir -p /var/lib/mongodb /var/log/mongodb
sudo chown -R mongodb:mongodb /var/lib/mongodb /var/log/mongodb

# 7) Write your custom mongod.conf
sudo tee /etc/mongod.conf >/dev/null <<'EOL'
storage:
  dbPath: /var/lib/mongodb
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
net:
  port: 27017
  bindIp: 0.0.0.0
processManagement:
  timeZoneInfo: /usr/share/zoneinfo
replication:
  replSetName: rs0
EOL

# 8) Restart & enable
sudo systemctl daemon-reload
sudo systemctl enable --now mongod
sudo systemctl restart mongod

# 9) Give MongoDB a moment
sleep 5

# 10) Initialize replica set
echo "→ Initializing replica set…"
mongosh --quiet --eval '
  rs.initiate({
    _id: "rs0",
    members: [
      { _id: 0, host: "localhost:27017" }
    ]
  });
'

# 11) Show status & connection URL
echo "→ Replica set status:"
mongosh --quiet --eval 'printjson(rs.status())'

echo -e "\nMongoDB connection URL:"
echo "mongodb://localhost:27017/?replicaSet=rs0"