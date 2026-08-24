# Nginx Log Pipeline on RHEL 9 — Fluent Bit → OpenSearch → OpenSearch Dashboards

A log-shipping and monitoring pipeline for Nginx access/error logs, built on RHEL 9 using
Fluent Bit as the log shipper, OpenSearch as the indexing/storage backend, and
OpenSearch Dashboards as the visualization layer.

## Architecture

```
Client
  │
  ▼
Nginx
  ├── access.log
  └── error.log
        │
        ▼
   Fluent Bit
        │
        ▼
   OpenSearch
   (index: nginx-logs)
        │
        ▼
OpenSearch Dashboards
        │
        ▼
Nginx Application Monitoring Dashboard
```

## Components

| Component | Version | Port | Role |
|---|---|---|---|
| Nginx | RHEL AppStream | 80 (+ 8009 test) | Web server, log source |
| Fluent Bit | 5.1.1 (repo: Rocky/Alma 9) | — | Log shipper / parser |
| OpenSearch | 3.8.0 | 9200 | Log storage & indexing |
| OpenSearch Dashboards | 3.8.0 | 5601 | Visualization |

## Prerequisites

- RHEL 9 host with `dnf` access and an active AppStream repo
- Root or sudo privileges
- SELinux and firewalld enabled (handled explicitly below, not disabled)

Verify the base system before starting:

```bash
cat /etc/redhat-release
uname -m
dnf repolist
```

## 1. Install Nginx

Installed from the RHEL AppStream repo — no custom Nginx repo file needed.

```bash
dnf update -y
dnf install nginx -y
nginx -v
systemctl enable --now nginx
systemctl status nginx
nginx -t
curl http://localhost/
```

**Log files:**
- `/var/log/nginx/access.log`
- `/var/log/nginx/error.log`

```bash
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
```

## 2. Install OpenSearch

```bash
rpm --import https://artifacts.opensearch.org/publickeys/opensearch-release.pgp
curl -SL https://artifacts.opensearch.org/releases/bundle/opensearch/3.x/opensearch-3.x.repo \
  -o /etc/yum.repos.d/opensearch-3.x.repo
dnf clean all
dnf repolist
dnf list opensearch --showduplicates
```

OpenSearch 2.12+ requires a custom admin password for the demo security config.
**Never commit this password to Git** — export it as an environment variable instead.

```bash
env OPENSEARCH_INITIAL_ADMIN_PASSWORD='CHANGE_THIS_PASSWORD' dnf install 'opensearch-3.8.0' -y
systemctl enable --now opensearch
systemctl status opensearch
ss -tulnp | grep 9200
curl -k -u admin:'CHANGE_THIS_PASSWORD' https://localhost:9200
```

## 3. Install OpenSearch Dashboards

```bash
curl -SL https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/3.x/opensearch-dashboards-3.x.repo \
  -o /etc/yum.repos.d/opensearch-dashboards-3.x.repo
dnf clean all
dnf repolist
dnf list opensearch-dashboards --showduplicates

dnf install 'opensearch-dashboards-3.8.0' -y
systemctl enable --now opensearch-dashboards
systemctl status opensearch-dashboards
ss -tulnp | grep 5601
```

Access at `http://SERVER_IP:5601` once the server allows HTTP access.

## 4. Install Fluent Bit

RHEL 9 may need the AlmaLinux/RockyLinux repo family rather than CentOS — confirm against
current Fluent Bit docs before installing. If a working repo already exists in your lab,
keep it rather than overwriting.

```bash
cat > /etc/yum.repos.d/fluent-bit.repo <<'EOF'
[fluent-bit]
name = Fluent Bit
baseurl = https://packages.fluentbit.io/rockylinux/9/$basearch/
gpgcheck = 1
gpgkey = https://packages.fluentbit.io/fluentbit.key
repo_gpgcheck = 1
enabled = 1
EOF

dnf clean all
dnf repolist
dnf list fluent-bit --showduplicates
dnf install fluent-bit -y

rpm -qa | grep fluent-bit
rpm -ql fluent-bit | grep /bin/
/opt/fluent-bit/bin/fluent-bit --version
systemctl enable --now fluent-bit
systemctl status fluent-bit
```

> Verified working package in this lab: `fluent-bit-5.1.1-1.x86_64`

## 5. Configure Fluent Bit

**Main config:** `/etc/fluent-bit/fluent-bit.conf`
**Parser config:** `/etc/fluent-bit/parsers.conf`

```ini
[SERVICE]
    Flush        1
    Log_Level    info
    Parsers_File /etc/fluent-bit/parsers.conf

[INPUT]
    Name          tail
    Path          /var/log/nginx/access.log
    Parser        nginx
    Tag           nginx.access
    Read_from_Head On

[INPUT]
    Name          tail
    Path          /var/log/nginx/error.log
    Tag           nginx.error
    Read_from_Head On

[OUTPUT]
    Name              opensearch
    Match             nginx.*
    Host              127.0.0.1
    Port              9200
    HTTP_User         admin
    HTTP_Passwd       ${OPENSEARCH_PASSWORD}
    TLS               On
    TLS.Verify        Off
    Index             nginx-logs
    Suppress_Type_Name On
```

**Nginx access log parser** (`parsers.conf`):

```ini
[PARSER]
    Name        nginx
    Format      regex
    Regex       ^(?<remote>[^ ]*) (?<host>[^ ]*) (?<user>[^ ]*) \[(?<time>[^\]]*)\] "(?<method>\S+)(?: +(?<path>[^\"]*?)(?: +\S*)?)?" (?<code>[^ ]*) (?<size>[^ ]*)(?: "(?<referer>[^\"]*)" "(?<agent>[^\"]*)")?$
    Time_Key    time
    Time_Format %d/%b/%Y:%H:%M:%S %z
```

> Note: the regex above is reconstructed from a truncated snippet in the source lab notes —
> validate it against `fluent-bit -c fluent-bit.conf` before relying on it in production.

**Start / test:**

```bash
/opt/fluent-bit/bin/fluent-bit -c /etc/fluent-bit/fluent-bit.conf
journalctl -u fluent-bit -f
systemctl restart fluent-bit
systemctl status fluent-bit
```

## 6. Nginx Status-Code Test Endpoint

Used to generate synthetic HTTP status codes for testing the pipeline end-to-end.

```bash
cat > /etc/nginx/conf.d/status-test.conf <<'EOF'
server {
    listen 8009;
    location /200 { return 200 "OK\n"; }
    location /400 { return 400 "Bad Request\n"; }
    location /401 { return 401 "Unauthorized\n"; }
    location /403 { return 403 "Forbidden\n"; }
    location /404 { return 404 "Not Found\n"; }
    location /500 { return 500 "Internal Server Error\n"; }
    location /502 { return 502 "Bad Gateway\n"; }
    location /503 { return 503 "Service Unavailable\n"; }
    location /504 { return 504 "Gateway Timeout\n"; }
}
EOF

nginx -t
systemctl reload nginx
```

## 7. SELinux

```bash
getenforce
semanage port -l | grep http_port_t
ausearch -m AVC -ts recent

# If a required port isn't already allowed:
semanage port -a -t http_port_t -p tcp PORT
# e.g.:
semanage port -a -t http_port_t -p tcp 8001
```

In this lab, port `8009` was already present in `http_port_t`, so no additional rule was needed.

## 8. Firewall

```bash
firewall-cmd --state
firewall-cmd --list-all

# Only if remote Dashboards access is required:
firewall-cmd --permanent --add-port=5601/tcp
firewall-cmd --reload
firewall-cmd --list-ports
```

## 9. Verify the Pipeline

```bash
# Service status
systemctl is-active nginx
systemctl is-active fluent-bit
systemctl is-active opensearch
systemctl is-active opensearch-dashboards

# Generate traffic
curl http://localhost/
curl http://localhost/test123

# Generate test status codes
for code in 200 400 401 403 404 500 502 503 504; do
  curl -s -o /dev/null http://localhost:8009/$code
done

# Check Nginx access log
tail -20 /var/log/nginx/access.log

# Check OpenSearch index
curl -k -u admin:"$OPENSEARCH_PASSWORD" "https://localhost:9200/_cat/indices?v"

# Count ingested logs
curl -k -u admin:"$OPENSEARCH_PASSWORD" "https://localhost:9200/nginx-logs/_count?pretty"

# Search latest logs
curl -k -u admin:"$OPENSEARCH_PASSWORD" \
  "https://localhost:9200/nginx-logs/_search?sort=@timestamp:desc&size=10&pretty"
```

## 10. OpenSearch Dashboards Setup

1. Open `http://SERVER_IP:5601`
2. Create/select a data view (index pattern): `nginx-logs*`
3. Time field: `@timestamp`

**Recommended dashboard panels:**

1. Total Nginx Requests
2. HTTP Status Codes
3. Nginx Requests Over Time
4. Nginx Error Requests
5. Top Requested URLs
6. Recent Nginx Errors

## Troubleshooting

**Port already in use**
```bash
ss -tulnp | grep :8080
lsof -i :8080
```

**SELinux permission denied**
```bash
ausearch -m AVC -ts recent
semanage port -l | grep http_port_t
```

**Nginx upstream 502**
```bash
tail -50 /var/log/nginx/error.log
ss -tulnp
```

**Fluent Bit**
```bash
systemctl status fluent-bit
journalctl -u fluent-bit -n 50
```

**OpenSearch**
```bash
systemctl status opensearch
journalctl -u opensearch -n 50
ss -tulnp | grep 9200
```

**Dashboards**
```bash
systemctl status opensearch-dashboards
journalctl -u opensearch-dashboards -n 50
ss -tulnp | grep 5601
```

## Security Notes

- Never commit OpenSearch passwords, API keys, SSH private keys, TLS private keys,
  production logs, or `.env` files to Git.
- Use environment variables or a secret manager instead:

```bash
export OPENSEARCH_PASSWORD='your-password'
curl -k -u admin:"$OPENSEARCH_PASSWORD" https://localhost:9200
```
