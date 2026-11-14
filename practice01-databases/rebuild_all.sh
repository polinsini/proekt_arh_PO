#!/usr/bin/env bash
# ============================================================
# LAB 3: полная пересборка всех 5 БД с нуля по целевой схеме
#   1. PostgreSQL 16  — MASTER / Source of Truth (нормализованная модель,
#                       attendance: PARTITION BY RANGE (week_start_date))
#   2. Redis 7        — KEY-VALUE / CACHE (lab3:student:<card>)
#   3. MongoDB 7      — DOCUMENT / COMPOSITION (group_profiles,
#                       university_hierarchy)
#   4. Neo4j 5        — GRAPH (Student/Group/Specialty/Course/Lesson/Schedule)
#   5. Elasticsearch 8 — FULL-TEXT (lab3_learning_content)
#
# Использование: ./rebuild_all.sh
# Требует запущенные контейнеры: docker compose up -d в папках БД.
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# ---------- 1. PostgreSQL 16: дропнуть ВСЁ в public, залить init_lab3.sql ----------
echo "=== [1/5] PostgreSQL 16 — drop all + rebuild ==="
docker exec -i practice01-postgres psql -U admin -d practice_db -v ON_ERROR_STOP=1 <<'SQL'
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
    EXECUTE 'DROP TABLE IF EXISTS public.' || quote_ident(r.tablename) || ' CASCADE';
  END LOOP;
END $$;
SQL
docker exec -i practice01-postgres psql -U admin -d practice_db -v ON_ERROR_STOP=1 \
  < "$ROOT/postgresql/init_lab3.sql"

# ---------- 2. Redis 7: FLUSHDB + залить lab3:student:<card> ----------
echo "=== [2/5] Redis 7 — FLUSHDB + rebuild ==="
docker exec practice01-redis redis-cli -a mypassword --no-auth-warning FLUSHDB
docker exec -i practice01-redis redis-cli -a mypassword --no-auth-warning \
  < "$ROOT/redis/init_lab3.txt"

# ---------- 3. MongoDB 7: drop database + залить коллекции ----------
echo "=== [3/5] MongoDB 7 — drop database + rebuild ==="
docker exec practice01-mongodb mongosh -u admin -p secret \
  --authenticationDatabase admin --quiet \
  --eval 'db.getSiblingDB("practice_db").dropDatabase()'
docker exec -i practice01-mongodb mongosh -u admin -p secret \
  --authenticationDatabase admin practice_db < "$ROOT/mongodb/init_lab3.js"

# ---------- 4. Neo4j 5: DETACH DELETE всех узлов + залить граф ----------
echo "=== [4/5] Neo4j 5 — wipe + rebuild ==="
docker exec -i practice01-neo4j cypher-shell -u neo4j -p mysecretpassword \
  --format plain < "$ROOT/neo4j/init_lab3.cypher"

# ---------- 5. Elasticsearch 8: удалить индекс, создать с маппингом, bulk ----------
echo "=== [5/5] Elasticsearch 8 — delete index + rebuild ==="
curl -fsS -X DELETE 'http://localhost:9200/lab3_learning_content' > /dev/null || true
curl -fsS -X PUT 'http://localhost:9200/lab3_learning_content' \
  -H 'Content-Type: application/json' \
  --data-binary "@$ROOT/elasticsearch/init_lab3_mapping.json" > /dev/null
curl -fsS -X POST 'http://localhost:9200/_bulk?refresh=wait_for' \
  -H 'Content-Type: application/x-ndjson' \
  --data-binary "@$ROOT/elasticsearch/init_lab3_bulk.ndjson" > /dev/null

# ---------- Проверка ----------
echo
echo "=== Результат ==="
docker exec practice01-postgres psql -U admin -d practice_db -c \
  "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;"
docker exec practice01-redis redis-cli -a mypassword --no-auth-warning --scan --pattern 'lab3:*' | wc -l | xargs echo "Redis keys:"
docker exec practice01-mongodb mongosh -u admin -p secret --authenticationDatabase admin practice_db --quiet \
  --eval 'db.getCollectionNames().forEach(c => print(c + ": " + db[c].countDocuments()))'
docker exec practice01-neo4j cypher-shell -u neo4j -p mysecretpassword --format plain \
  "MATCH (n) RETURN labels(n)[0] AS label, count(*) AS cnt ORDER BY label;"
echo -n "Elasticsearch docs: "
curl -fsS 'http://localhost:9200/lab3_learning_content/_count'
echo
