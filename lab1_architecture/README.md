# ЛР №1 — 10 студентов с минимальной посещаемостью лекций по фразе

## Что реализовано

`gateway` — FastAPI, выдача JWT по `/auth/login`, JWT-проверка на `/api/lab1/low-attendance`, проксирование к сервису. `lab1` — отдельный контейнер, полнотекстовая выборка по Elasticsearch `lab3_learning_content`, затем SQL-расчёт по PostgreSQL `practice_db`. Redis используется только как дополнительная проверка существования карточки `lab3:student:<record_book_number>`. MongoDB и Neo4j для этого запроса не нужны: графовые обходы и чтение вложенных документов не улучшают поиск текста и расчёт посещаемости.

**Никакие таблицы, индексы или данные исходных БД проект не меняет.** Он читает существующие данные. `rebuild_all.sh` перед работой запускается отдельно, если необходимо заполнить БД.

## Запуск на macOS

1. Запустите существующие пять БД привычными `docker compose up -d` в их папках. Убедитесь, что контейнеры называются `practice01-postgres`, `practice01-redis`, `practice01-mongodb`, `practice01-neo4j`, `practice01-elasticsearch`.
2. Создайте общую Docker-сеть и подключите к ней требуемые БД (каждый `connect` выполняется лишь один раз; ошибка `already exists` безопасна):

```bash
docker network create lab1-shared
docker network connect lab1-shared practice01-postgres
docker network connect lab1-shared practice01-elasticsearch
docker network connect lab1-shared practice01-redis
```

3. В папке с этой работой:

```bash
cp .env.example .env
# В .env замените секреты, пароль PostgreSQL и демо-пароль.
# Подобрать надёжные секреты: openssl rand -hex 32
docker compose up --build -d
docker compose ps
```

4. Откройте http://localhost:8000/docs (Swagger UI). Выдайте JWT:

```bash
curl -sS -X POST http://localhost:8000/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"student","password":"ПАРОЛЬ_ИЗ_ENV"}'
```

5. Вставьте выданный `access_token` в запрос (или в Swagger нажмите `Authorize` при наличии UI auth controls):

```bash
TOKEN='ВСТАВЬТЕ_ACCESS_TOKEN'
curl -sS -G http://localhost:8000/api/lab1/low-attendance \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode 'term=архитектура' \
  --data-urlencode 'date_from=2026-09-21' \
  --data-urlencode 'date_to=2026-09-27'
```

## Проверка шагов

- `GET /health` — API Gateway работает.
- `POST /auth/login` — получен JWT; без него отчёт должен отвечать 401.
- Elasticsearch: Kibana Dev Tools: `GET lab3_learning_content/_count`; полнотекстовый запрос по `архитектура`.
- PostgreSQL: pgAdmin: `SELECT COUNT(*) FROM attendance;`, `SELECT COUNT(*) FROM schedule;`.
- `GET /api/lab1/low-attendance` — JSON: `matched_lectures`, `students`, `steps`, процент посещения и период.
- `docker compose logs gateway lab1` — диагностические сообщения при ошибках подключения.

## Правила расчёта

- Отбираются **только лекции**, для которых Elasticsearch нашёл заданную фразу в `title`, `description`, `content_text` или `tags`.
- Учитываются только занятия из `schedule` в заданных датах и студенты группы, записанные на курс через `student_courses`.
- Процент = `COUNT(уникальных занятий со status='attended') / COUNT(уникальных запланированных лекций) * 100`.
- Если строки посещаемости нет, занятие входит в знаменатель, но не в числитель (трактуется как отсутствие подтверждения посещения). Это правило следует согласовать с преподавателем.
- Результат сортируется по проценту возрастанию и ограничен 10 студентами.
- Для имеющегося примера данных все занятия относятся к сентябрю 2026 года; запрос вне дат занятий возвращает пустой список.
- Поле `matched_lectures` показывает найденные тексты независимо от даты. Поле `students` — результат отбора по периоду.

## Ограничения и важные замечания

- Из `rebuild_all.sh` известны пути к исходным файлам, но сами `init_lab3.*` здесь не предоставлены. Поэтому ожидается, что схемы/индексы в БД соответствуют практической №3 и `practice3.docx`. Проверяйте реальные имена таблиц в pgAdmin.
- Elasticsearch для поиска возвращает до 1000 документов; для крупной базы потребуется `search_after` / пагинация.
- Здесь используется учебный аккаунт из .env; для production нужна БД пользователей, хеширование паролей, управление ролями, HTTPS.
- `lab1` внутри Docker не публикует порт наружу и проверяет `X-Internal-Token`; только `gateway` доступен с хоста.
- Схема не требует синхронизации/CDC, поскольку это ЛР №1, а CDC вводится в следующих лабораторных работах.
