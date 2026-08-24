#!/bin/bash

# Set your password before running:
# export OPENSEARCH_PASSWORD='your-password'

BASE_URL="https://localhost:9200"
AUTH="admin:${OPENSEARCH_PASSWORD}"

echo "=== Document Count ==="
curl -k -u "$AUTH" \
  "$BASE_URL/nginx-logs/_count?pretty"

echo
echo "=== Latest 10 Logs ==="
curl -k -u "$AUTH" \
  "$BASE_URL/nginx-logs/_search?sort=@timestamp:desc&size=10&pretty"

echo
echo "=== HTTP Error Logs (400+) ==="
curl -k -u "$AUTH" \
  -X GET "$BASE_URL/nginx-logs/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "range": {
        "code": {
          "gte": "400"
        }
      }
    }
  }'
