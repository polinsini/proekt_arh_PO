# 🔐 Подключение к базам данных — Practice 01

> Все сервисы запущены в Docker. Веб-интерфейсы (UI) и порты БД проброшены на `localhost`.

---

## 📊 Сводная таблица

| СУБД | Порт БД | Логин | Пароль | Веб-интерфейс | Логин UI | Пароль UI |
|---|---|---|---|---|---|---|
| PostgreSQL 16 | `5432` | `admin` | `secret` | pgAdmin: http://localhost:8083 | `admin@example.com` | `admin` |
| MongoDB 7 | `27017` | `admin` | `secret` | Mongo Express: http://localhost:8082 | `admin` | `admin` |
| Redis 7 | `6379` | — | `mypassword` | Redis Commander: http://localhost:8081 | — | — |
| Neo4j 5 | `7687` (Bolt) | `neo4j` | `mysecretpassword` | Neo4j Browser: http://localhost:7474 | `neo4j` | `mysecretpassword` |
| Elasticsearch 8 | `9200` | — *(без авторизации)* | — | Kibana: http://localhost:5601 | — | — |

---

## 🐘 PostgreSQL 16

### Параметры подключения
- **Хост:** `localhost`, **порт:** `5432`
- **База данных:** `practice_db`
- **Пользователь:** `admin`, **пароль:** `secret`
- **Строка подключения:** `postgresql://admin:secret@localhost:5432/practice_db`

### Через Docker
```bash
docker exec -it practice01-postgres psql -U admin -d practice_db
```

### Через UI (pgAdmin 4)
1. Открой **http://localhost:8083**
2. Войди: **Email:** `admin@example.com`, **пароль:** `admin`
3. При регистрации сервера укажи (внутри docker-сети host = имя контейнера):
   - **Host:** `postgres` (если регистрируешь сервер внутри pgAdmin)
   - **Port:** `5432`
   - **Username:** `admin`, **Password:** `secret`
   - **Database:** `practice_db`

### Из внешнего клиента (DBeaver, DataGrip, psql на хосте)
- **Host:** `localhost`, **Port:** `5432`, **DB:** `practice_db`, **User:** `admin`, **Password:** `secret`

---

## 🍃 MongoDB 7

### Параметры подключения
- **Хост:** `localhost`, **порт:** `27017`
- **База данных:** `practice_db` (данные лаб. 3)
- **Пользователь:** `admin`, **пароль:** `secret`, **authenticationDatabase:** `admin`
- **Строка подключения:** `mongodb://admin:secret@localhost:27017/practice_db?authSource=admin`

### Через Docker
```bash
docker exec -it practice01-mongodb mongosh -u admin -p secret --authenticationDatabase admin practice_db
```

### Через UI (Mongo Express)
1. Открой **http://localhost:8082**
2. Basic Auth браузера: **логин:** `admin`, **пароль:** `admin`

### Из внешнего клиента (Compass, mongosh на хосте)
- **URL:** `mongodb://admin:secret@localhost:27017/?authSource=admin`

---

## 🔑 Redis 7

### Параметры подключения
- **Хост:** `localhost`, **порт:** `6379`, **БД №:** `0`
- **Пароль:** `mypassword` (пользователь по умолчанию `default`)
- **Строка подключения:** `redis://default:mypassword@localhost:6379/0`

### Через Docker
```bash
docker exec -it practice01-redis redis-cli -a mypassword
```

### Через UI (Redis Commander)
1. Открой **http://localhost:8081**
2. Подключение уже настроено автоматически — ключи видны сразу

### Из внешнего клиента
```bash
redis-cli -h localhost -p 6379 -a mypassword
```

---

## 🕸 Neo4j 5 (Community)

### Параметры подключения
- **HTTP (Browser):** `http://localhost:7474`
- **Bolt (для драйверов):** `bolt://localhost:7687`
- **Пользователь:** `neo4j`, **пароль:** `mysecretpassword`

### Через Docker
```bash
docker exec -it practice01-neo4j cypher-shell -u neo4j -p mysecretpassword
```

### Через UI (Neo4j Browser)
1. Открой **http://localhost:7474**
2. Войди: **Connect URL:** `bolt://localhost:7687` (подставится сам), **Username:** `neo4j`, **Password:** `mysecretpassword`
3. Пример запроса: `MATCH (n) RETURN n LIMIT 25;`

### Из внешнего клиента
- **URI:** `neo4j://localhost:7687` или `bolt://localhost:7687`, **логин/пароль:** `neo4j` / `mysecretpassword`

---

## 🔍 Elasticsearch 8

### Параметры подключения
- **REST API:** `http://localhost:9200`
- **Авторизация:** отключена (`xpack.security.enabled=false`)
- **Кластер:** `practice-cluster`, узел: `es-node-1`

### Через Docker
```bash
docker exec -it practice01-elasticsearch curl http://localhost:9200/_cat/indices?v
```

### Через UI (Kibana Dev Tools)
1. Открой **http://localhost:5601**
2. Слева: **Management → Dev Tools** — консоль запросов
3. Пример:
   ```
   GET lab3_learning_content/_search
   {
     "query": { "match": { "content_text": "микросервисы" } }
   }
   ```

### Из внешнего клиента
```bash
curl http://localhost:9200/_cat/indices?v
```

---

## 📁 Имена Docker-контейнеров

| Контейнер | Образ | Что это |
|---|---|---|
| `practice01-postgres` | postgres:16-alpine | PostgreSQL-сервер |
| `practice01-pgadmin` | dpage/pgadmin4:latest | Веб-интерфейс PostgreSQL |
| `practice01-mongodb` | mongo:7 | MongoDB-сервер |
| `practice01-mongo-express` | mongo-express:1-20 | Веб-интерфейс MongoDB |
| `practice01-redis` | redis:7-alpine | Redis-сервер |
| `practice01-redis-commander` | rediscommander/redis-commander | Веб-интерфейс Redis |
| `practice01-neo4j` | neo4j:5-community | Neo4j-сервер + Browser |
| `practice01-elasticsearch` | elasticsearch:8.16.0 | Elasticsearch-сервер |
| `practice01-kibana` | kibana:8.16.0 | Веб-интерфейс Elasticsearch |

Полезные команды:
```bash
docker ps                                  # статус всех контейнеров
docker compose up -d                       # запустить (в папке нужной БД)
docker compose down                        # остановить (данные останутся в volume)
docker logs -f practice01-postgres         # логи контейнера
```

---

## ⚠️ Конфликт порта 5432 с локальным PostgreSQL

На Mac установлен локальный Homebrew **postgresql@15**, который при запуске занимает
`127.0.0.1:5432` и перехватывает подключения `localhost:5432` на себя вместо docker-контейнера.

- Локальный сервис **остановлен** (`brew services stop postgresql@15`), поэтому `localhost:5432` сейчас ведёт в контейнер `practice01-postgres` (PostgreSQL 16).
- Если для других проектов нужен локальный PG 15 — запусти `brew services start postgresql@15`, но тогда подключайся к `practice_db` только через pgAdmin (`localhost:8083`, host внутри docker-сети: `postgres`) или `docker exec`.

Проверка, кто слушает порт:
```bash
lsof -iTCP:5432 -sTCP:LISTEN -n -P    # должен быть только com.docke
PGPASSWORD=secret psql -h localhost -p 5432 -U admin -d practice_db -tc "SELECT version();"  # → PostgreSQL 16
```

---

## 🔄 Полная пересборка всех БД с нуля

```bash
./rebuild_all.sh
```

Скрипт очищает и заново заполняет все 5 БД из init-файлов:

| Шаг | БД | Что делает | Init-файл |
|---|---|---|---|
| 1 | PostgreSQL | DROP всех таблиц public → создание схемы (attendance партиционирован по `week_start_date`) | `postgresql/init_lab3.sql` |
| 2 | Redis | `FLUSHDB` → хеши `lab3:student:<card>` | `redis/init_lab3.txt` |
| 3 | MongoDB | `dropDatabase()` → коллекции `group_profiles`, `university_hierarchy` | `mongodb/init_lab3.js` |
| 4 | Neo4j | `DETACH DELETE` всех узлов → граф | `neo4j/init_lab3.cypher` |
| 5 | Elasticsearch | DELETE индекса → создание с маппингом → bulk-загрузка | `elasticsearch/init_lab3_mapping.json`, `elasticsearch/init_lab3_bulk.ndjson` |
