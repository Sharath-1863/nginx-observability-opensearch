# Nginx Observability with Fluent Bit and OpenSearch

A hands-on DevOps/Linux observability project for collecting, storing, searching, and visualizing Nginx access and error logs using Fluent Bit, OpenSearch, and OpenSearch Dashboards.

## Architecture

Nginx
   |
   | access.log / error.log
   v
Fluent Bit
   |
   v
OpenSearch
   |
   | nginx-logs
   v
OpenSearch Dashboards
   |
   v
Discover / Monitoring Dashboard

## Components

- Nginx - Web server and log source
- Fluent Bit - Log collector and forwarding agent
- OpenSearch - Log storage and search engine
- OpenSearch Dashboards - Log visualization and monitoring
- Linux / SELinux - Server administration and security
- Git / GitHub - Version control and project documentation

## Log Sources

Nginx generates:

- `/var/log/nginx/access.log`
- `/var/log/nginx/error.log`

Fluent Bit monitors these files and sends the logs to OpenSearch.

## OpenSearch Index

Logs are stored in:

`nginx-logs`

The Dashboards data source/index pattern is:

`nginx-logs*`

## Dashboard

The Nginx monitoring dashboard currently contains:

1. Total Nginx Requests
2. HTTP Status Codes
3. Nginx Requests Over Time
4. Nginx Error Requests

The dashboard can be used to investigate:

- Successful requests
- 4xx errors
- 5xx errors
- Request traffic over time
- Nginx failures

## HTTP Error Testing

A test Nginx server is configured on port `8009` to generate controlled HTTP responses.

Available test endpoints:

- `/200`
- `/400`
- `/401`
- `/403`
- `/404`
- `/500`
- `/502`
- `/503`
- `/504`

Example:

```bash
curl -i http://localhost:8009/500
curl -i http://localhost:8009/502
curl -i http://localhost:8009/503
curl -i http://localhost:8009/504
