RHEL 9 — Nginx + Fluent Bit + OpenSearch + OpenSearch Dashboards
1. Check the RHEL system
cat /etc/redhat-release
uname -m
dnf repolist
2. Nginx — install from RHEL repositories
Nginx can be installed from the RHEL repositories/AppStream in this lab. No custom Nginx repository file is required.
dnf update -y
dnf install nginx -y
nginx -v
systemctl enable --now nginx
systemctl status nginx
nginx -t
curl http://localhost/
Nginx log files
/var/log/nginx/access.log
/var/log/nginx/error.log
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
3. OpenSearch — create the YUM repository
OpenSearch's official RPM/YUM documentation provides a repository file under /etc/yum.repos.d/.
rpm --import https://artifacts.opensearch.org/publickeys/opensearch-release.pgp
curl -SL https://artifacts.opensearch.org/releases/bundle/opensearch/3.x/opensearch-3.x.repo -o /etc/yum.repos.d/opensearch-3.
dnf clean all
dnf repolist
dnf list opensearch --showduplicates
Install OpenSearch 3.8.0
env OPENSEARCH_INITIAL_ADMIN_PASSWORD='CHANGE_THIS_PASSWORD' dnf install 'opensearch-3.8.0' -y
systemctl enable opensearch
systemctl start opensearch
systemctl status opensearch
ss -tulnp | grep 9200
curl -k -u admin:'CHANGE_THIS_PASSWORD' https://localhost:9200
For OpenSearch 2.12 and later, a custom admin password is required for the demo security configuration. Do not commit
the password to Git.
4. OpenSearch Dashboards — create the YUM repository
curl -SL https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/3.x/opensearch-dashboards-3.x.repo -o /etc/yum
dnf clean all
dnf repolist
dnf list opensearch-dashboards --showduplicates
Install OpenSearch Dashboards 3.8.0
dnf install 'opensearch-dashboards-3.8.0' -y
systemctl enable opensearch-dashboards
systemctl start opensearch-dashboards
systemctl status opensearch-dashboards
ss -tulnp | grep 5601
Open the dashboard in a browser using http://SERVER_IP:5601 when the server is configured for HTTP access.
5. Fluent Bit — repository file
Fluent Bit uses a YUM repository file named fluent-bit.repo under /etc/yum.repos.d/. The exact repository family should
match the supported RHEL-compatible platform. Fluent Bit's current documentation notes that RHEL 9 may require the
AlmaLinux/RockyLinux repository family rather than a CentOS repository.
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
If your lab already has a working Fluent Bit repository, keep that repository rather than replacing it. In the earlier lab
session, the package fluent-bit-5.1.1-1.x86_64 installed successfully.
Install Fluent Bit
dnf install fluent-bit -y
rpm -qa | grep fluent-bit
rpm -ql fluent-bit | grep /bin/
/opt/fluent-bit/bin/fluent-bit --version
systemctl enable --now fluent-bit
systemctl status fluent-bit
6. Fluent Bit configuration
Main configuration: /etc/fluent-bit/fluent-bit.conf. Parser configuration: /etc/fluent-bit/parsers.conf.
[SERVICE]
Flush 1
Log_Level info
Parsers_File /etc/fluent-bit/parsers.conf
[INPUT]
Name tail
Path /var/log/nginx/access.log
Parser nginx
Tag nginx.access
Read_from_Head On
[INPUT]
Name tail
Path /var/log/nginx/error.log
Tag nginx.error
Read_from_Head On
[OUTPUT]
Name opensearch
Match nginx.*
Host 127.0.0.1
Port 9200
HTTP_User admin
HTTP_Passwd ${OPENSEARCH_PASSWORD}
TLS On
TLS.Verify Off
Index nginx-logs
Suppress_Type_Name On
Nginx parser
[PARSER]
Name nginx
Format regex
Regex ^(?<remote>[^ ]*) (?<host>[^ ]*) (?<user>[^ ]*) \[(?<time>[^\]]*)\] "(?<method>\S+)(?: +(?<path>[^\"]*?)(?: +\
Time_Key time
Time_Format %d/%b/%Y:%H:%M:%S %z
Start/test Fluent Bit
/opt/fluent-bit/bin/fluent-bit -c /etc/fluent-bit/fluent-bit.conf
journalctl -u fluent-bit -f
systemctl restart fluent-bit
systemctl status fluent-bit
7. Nginx status-test.conf
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
8. SELinux for custom Nginx ports
getenforce
semanage port -l | grep http_port_t
ausearch -m AVC -ts recent
# If a required port is not already allowed:
semanage port -a -t http_port_t -p tcp PORT
# Example:
semanage port -a -t http_port_t -p tcp 8001
In the lab, port 8009 was already present in the http_port_t list, so it could be used without adding another SELinux rule.
9. Firewall
firewall-cmd --state
firewall-cmd --list-all
# Only if remote Dashboards access is required:
firewall-cmd --permanent --add-port=5601/tcp
firewall-cmd --reload
firewall-cmd --list-ports
10. Verify the complete pipeline
# Nginx
systemctl is-active nginx
# Fluent Bit
systemctl is-active fluent-bit
# OpenSearch
systemctl is-active opensearch
# OpenSearch Dashboards
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
# Count Nginx logs
curl -k -u admin:"$OPENSEARCH_PASSWORD" "https://localhost:9200/nginx-logs/_count?pretty"
# Search latest logs
curl -k -u admin:"$OPENSEARCH_PASSWORD" "https://localhost:9200/nginx-logs/_search?sort=@timestamp:desc&size=10&pretty"
11. OpenSearch Dashboards setup
OpenSearch Dashboards is the visualization layer. Create/select the data view/index pattern nginx-logs* and use
@timestamp as the time field.
Browser:
http://SERVER_IP:5601
Data view:
nginx-logs*
Time field:
@timestamp
Recommended dashboard panels
1. Total Nginx Requests
2. HTTP Status Codes
3. Nginx Requests Over Time
4. Nginx Error Requests
5. Top Requested URLs
6. Recent Nginx Errors
12. Troubleshooting
Port already in use
ss -tulnp | grep :8080
lsof -i :8080
SELinux permission denied
ausearch -m AVC -ts recent
semanage port -l | grep http_port_t
Nginx upstream 502
tail -50 /var/log/nginx/error.log
ss -tulnp
Fluent Bit
systemctl status fluent-bit
journalctl -u fluent-bit -n 50
OpenSearch
systemctl status opensearch
journalctl -u opensearch -n 50
ss -tulnp | grep 9200
Dashboards
systemctl status opensearch-dashboards
journalctl -u opensearch-dashboards -n 50
ss -tulnp | grep 5601
13. Git security
Never commit OpenSearch passwords, API keys, SSH private keys, TLS private keys, production logs, or .env files. Use
environment variables or a secret manager.
export OPENSEARCH_PASSWORD='your-password'
# Example:
curl -k -u admin:"$OPENSEARCH_PASSWORD" https://localhost:9200
14. Final architecture
Client
|
v
Nginx
|
+--> access.log
|
+--> error.log
|
v
Fluent Bit
|
v
OpenSearch
nginx-logs
|
v
OpenSearch Dashboards
|
v
Nginx Application Monitoring Dashboard

