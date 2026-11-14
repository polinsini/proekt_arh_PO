-- ============================================================
-- MIGRATION: доработка модели данных PostgreSQL (лаб. 4 / практика 3)
-- Исходное состояние: init_lab3.sql (схема «университет»)
--
-- Состав миграции:
--   1. specialty_courses  — M:N «специальности <-> дисциплины» (учебный план)
--   2. course_relations   — типизированные связи между дисциплинами
--   3. student_groups     — + enrollment_year, согласованность с course_number
--   4. courses            — + description; semester/is_elective переносятся
--                           в specialty_courses и удаляются
--   5. student_courses    — + semester; enrollment_type согласуется
--                           с учебным планом специальности (триггер)
--   6. attendance         — расширение до 16 недельных партиций
--                           (осенний семестр 2026: 2026-09-07 .. 2026-12-28)
--
-- Существующие данные не удаляются; наименования таблиц и идентификаторов
-- сохраняются; используются типы SERIAL / BIGSERIAL / INTEGER.
-- Запуск:
--   docker exec -i practice01-postgres psql -U admin -d practice_db \
--     -v ON_ERROR_STOP=1 < postgresql/migration_lab4.sql
-- ============================================================

BEGIN;

-- ============================================================
-- ШАГ 3. student_groups: атрибут enrollment_year
-- ============================================================
-- Год поступления восстанавливается из суффикса номера группы
-- (ИКБО-01-22 -> 2022, ИП-02-23 -> 2023, ИКБО-03-24 -> 2024).
ALTER TABLE student_groups ADD COLUMN enrollment_year INT;

UPDATE student_groups
SET enrollment_year = 2000 + (substring(group_number FROM '[0-9]{2}$'))::int;

-- Согласованность: набор данных соответствует осеннему семестру 2025/26,
-- поэтому course_number = 2025 - enrollment_year + 1 (константа 2026).
ALTER TABLE student_groups
  ALTER COLUMN enrollment_year SET NOT NULL,
  ADD CONSTRAINT chk_group_course_year
      CHECK (enrollment_year + course_number = 2026),
  ADD CONSTRAINT chk_group_year_suffix
      CHECK (enrollment_year % 100 = (substring(group_number FROM '[0-9]{2}$'))::int);

-- ============================================================
-- ШАГ 4a. courses: атрибут description (до переноса данных)
-- ============================================================
ALTER TABLE courses ADD COLUMN description TEXT;

UPDATE courses SET description = CASE code
  WHEN '09.ПАС'  THEN 'Теория и практика проектирования архитектуры программных систем: стили, паттерны, нефункциональные требования и архитектурные компромиссы.'
  WHEN '09.БД'   THEN 'Реляционная модель данных, SQL, нормализация, транзакции и индексы; проектирование и администрирование баз данных.'
  WHEN '10.ИБ'   THEN 'Угрозы информационной безопасности, криптографические методы защиты и практика защиты веб-приложений.'
  WHEN '09.МА'   THEN 'Проектирование распределённых систем на микросервисах: декомпозиция домена, Saga, service mesh и наблюдаемость.'
  WHEN '09.DEV'  THEN 'Непрерывная интеграция и доставка: пайплайны CI/CD, контейнеризация и деплой в Kubernetes.'
  WHEN '09.ОС'   THEN 'Устройство операционных систем: процессы и потоки, планирование, память, файловые системы и синхронизация.'
  WHEN '09.Web'  THEN 'Клиент-серверная разработка веб-приложений: HTTP, REST API, фронтенд-фреймворки и развёртывание.'
  WHEN '09.Тест' THEN 'Уровни и виды тестирования, пирамида тестов, модульные и сквозные тесты, автоматизация в CI.'
  WHEN '02.Алг'  THEN 'Асимптотический анализ, сортировки и поиск, графовые алгоритмы и базовые структуры данных.'
  WHEN '09.МЛ'   THEN 'Классические задачи машинного обучения: регрессия, классификация, метрики качества и нейронные сети.'
END;

-- ============================================================
-- ШАГ 1. specialty_courses: M:N «специальности <-> дисциплины»
-- ============================================================
CREATE TABLE specialty_courses (
    specialty_id  INT NOT NULL
                  CONSTRAINT fk_specialty_courses_specialty REFERENCES specialties,
    course_id     INT NOT NULL
                  CONSTRAINT fk_specialty_courses_course REFERENCES courses,
    semester      INT NOT NULL
                  CONSTRAINT chk_specialty_courses_semester CHECK (semester > 0),
    course_type   VARCHAR(20) NOT NULL
                  CONSTRAINT chk_specialty_courses_type
                  CHECK (course_type IN ('mandatory', 'elective')),
    CONSTRAINT pk_specialty_courses PRIMARY KEY (specialty_id, course_id)
);

-- Перенос существующих значений semester и is_elective из courses
-- (связь восстанавливается по фактическим зачислениям студентов).
-- is_elective: TRUE -> 'elective', FALSE -> 'mandatory'.
INSERT INTO specialty_courses (specialty_id, course_id, semester, course_type)
SELECT DISTINCT
       sg.specialty_id,
       sc.course_id,
       c.semester,
       CASE WHEN c.is_elective THEN 'elective' ELSE 'mandatory' END
FROM student_courses sc
JOIN students        st ON st.student_id = sc.student_id
JOIN student_groups  sg ON sg.group_id   = st.group_id
JOIN courses         c  ON c.course_id   = sc.course_id
ON CONFLICT DO NOTHING;

-- ============================================================
-- ШАГ 5. student_courses: атрибут semester + согласованность
--        enrollment_type с учебным планом специальности
-- ============================================================
ALTER TABLE student_courses ADD COLUMN semester INT;

-- Семестр изучения и тип зачисления берутся из учебного плана
-- специальности студента (specialty_courses).
UPDATE student_courses sc
SET semester        = m.semester,
    enrollment_type = m.course_type
FROM (
    SELECT st.student_id   AS student_id,
           scp.course_id   AS course_id,
           scp.semester    AS semester,
           scp.course_type AS course_type
    FROM students st
    JOIN student_groups    sg  ON sg.group_id = st.group_id
    JOIN specialty_courses scp ON scp.specialty_id = sg.specialty_id
) m
WHERE m.student_id = sc.student_id
  AND m.course_id  = sc.course_id
  AND (sc.semester IS DISTINCT FROM m.semester
       OR sc.enrollment_type <> m.course_type);

ALTER TABLE student_courses
  ALTER COLUMN semester SET NOT NULL,
  ADD CONSTRAINT chk_student_courses_semester CHECK (semester > 0);

-- Триггер: тип зачисления должен соответствовать типу дисциплины
-- в учебном плане специальности зачисляемого студента.
CREATE OR REPLACE FUNCTION fn_check_enrollment_type()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_specialty_id INT;
    v_course_type  VARCHAR(20);
BEGIN
    SELECT sg.specialty_id INTO v_specialty_id
    FROM students st
    JOIN student_groups sg ON sg.group_id = st.group_id
    WHERE st.student_id = NEW.student_id;

    SELECT course_type INTO v_course_type
    FROM specialty_courses
    WHERE specialty_id = v_specialty_id
      AND course_id    = NEW.course_id;

    IF v_course_type IS NULL THEN
        RAISE EXCEPTION
            'Дисциплина % отсутствует в учебном плане специальности %',
            NEW.course_id, v_specialty_id
            USING ERRCODE = '23503';
    END IF;

    IF NEW.enrollment_type <> v_course_type THEN
        RAISE EXCEPTION
            'Тип зачисления "%" не соответствует типу дисциплины "%" в учебном плане специальности %',
            NEW.enrollment_type, v_course_type, v_specialty_id
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END $$;

CREATE TRIGGER trg_student_courses_enrollment_type
BEFORE INSERT OR UPDATE OF student_id, course_id, enrollment_type
ON student_courses
FOR EACH ROW EXECUTE FUNCTION fn_check_enrollment_type();

-- ============================================================
-- ШАГ 4b. courses: удаление semester и is_elective
-- (значения уже перенесены в specialty_courses; связь с кафедрой
--  department_id сохранена)
-- ============================================================
ALTER TABLE courses
  DROP COLUMN semester,
  DROP COLUMN is_elective;

-- ============================================================
-- ШАГ 2. course_relations: логические связи между дисциплинами
-- ============================================================
CREATE TABLE course_relations (
    relation_id      SERIAL
                     CONSTRAINT pk_course_relations PRIMARY KEY,
    source_course_id INT NOT NULL
                     CONSTRAINT fk_course_relations_source REFERENCES courses,
    target_course_id INT NOT NULL
                     CONSTRAINT fk_course_relations_target REFERENCES courses,
    relation_type    VARCHAR(50) NOT NULL
                     CONSTRAINT chk_course_relations_type
                     CHECK (relation_type IN ('prerequisite', 'related', 'continuation')),
    CONSTRAINT chk_course_relations_no_self
        CHECK (source_course_id <> target_course_id),
    CONSTRAINT uq_course_relations
        UNIQUE (source_course_id, target_course_id, relation_type)
);

COMMENT ON CONSTRAINT chk_course_relations_no_self ON course_relations IS
    'Запрет связи дисциплины с самой собой';
COMMENT ON CONSTRAINT uq_course_relations ON course_relations IS
    'Запрет дублирования идентичных связей';

-- Тестовые данные: демонстрация всех трёх типов связей.
INSERT INTO course_relations (source_course_id, target_course_id, relation_type) VALUES
 (9,  2,  'prerequisite'),   -- Алгоритмы и структуры данных -> Базы данных
 (2,  1,  'prerequisite'),   -- Базы данных -> Проектирование архитектуры ПС
 (6,  3,  'prerequisite'),   -- Операционные системы -> Информационная безопасность
 (9,  10, 'prerequisite'),   -- Алгоритмы и структуры данных -> Машинное обучение
 (1,  4,  'continuation'),   -- Микросервисные архитектуры — продолжение ПАС
 (7,  8,  'continuation'),   -- Тестирование ПО — продолжение Web-программирования
 (4,  5,  'related'),        -- Микросервисные архитектуры <-> DevOps и CI/CD
 (2,  7,  'related');        -- Базы данных <-> Web-программирование

-- ============================================================
-- ШАГ 6. attendance: расширение до 16 недельных партиций
-- ============================================================
-- Семестр: осенний 2026/27, понедельники 2026-09-07 .. 2026-12-21.
-- Существующие партиции 2026_09_14 / 2026_09_21 / 2026_09_28 сохраняются
-- вместе с данными; добавляются недостающие 13 недельных партиций.
CREATE TABLE attendance_2026_09_07 PARTITION OF attendance
    FOR VALUES FROM ('2026-09-07') TO ('2026-09-14');
CREATE TABLE attendance_2026_10_05 PARTITION OF attendance
    FOR VALUES FROM ('2026-10-05') TO ('2026-10-12');
CREATE TABLE attendance_2026_10_12 PARTITION OF attendance
    FOR VALUES FROM ('2026-10-12') TO ('2026-10-19');
CREATE TABLE attendance_2026_10_19 PARTITION OF attendance
    FOR VALUES FROM ('2026-10-19') TO ('2026-10-26');
CREATE TABLE attendance_2026_10_26 PARTITION OF attendance
    FOR VALUES FROM ('2026-10-26') TO ('2026-11-02');
CREATE TABLE attendance_2026_11_02 PARTITION OF attendance
    FOR VALUES FROM ('2026-11-02') TO ('2026-11-09');
CREATE TABLE attendance_2026_11_09 PARTITION OF attendance
    FOR VALUES FROM ('2026-11-09') TO ('2026-11-16');
CREATE TABLE attendance_2026_11_16 PARTITION OF attendance
    FOR VALUES FROM ('2026-11-16') TO ('2026-11-23');
CREATE TABLE attendance_2026_11_23 PARTITION OF attendance
    FOR VALUES FROM ('2026-11-23') TO ('2026-11-30');
CREATE TABLE attendance_2026_11_30 PARTITION OF attendance
    FOR VALUES FROM ('2026-11-30') TO ('2026-12-07');
CREATE TABLE attendance_2026_12_07 PARTITION OF attendance
    FOR VALUES FROM ('2026-12-07') TO ('2026-12-14');
CREATE TABLE attendance_2026_12_14 PARTITION OF attendance
    FOR VALUES FROM ('2026-12-14') TO ('2026-12-21');
CREATE TABLE attendance_2026_12_21 PARTITION OF attendance
    FOR VALUES FROM ('2026-12-21') TO ('2026-12-28');

COMMIT;

-- ============================================================
-- ПРОВЕРКИ (выполняются после фиксации миграции)
-- ============================================================

-- 1) Дерево партиций (16 недельных партиций)
SELECT * FROM pg_partition_tree('public.attendance');

-- 2) Автоматическое распределение записей по партициям:
--    запись с датой декабря должна попасть в attendance_2026_12_07
INSERT INTO attendance (student_id, schedule_id, week_start_date, status)
SELECT min(st.student_id), min(sc.schedule_id), DATE '2026-12-09', 'attended'
FROM students st, schedule sc
WHERE st.status = 'active';

SELECT attendance_id,
       week_start_date,
       tableoid::regclass AS partition_name
FROM attendance
WHERE week_start_date = DATE '2026-12-09';

DELETE FROM attendance WHERE week_start_date = DATE '2026-12-09';
-- (удаляется только проверочная строка, данные миграции сохранены)

-- 3) Целостность внешних ключей после миграции
SELECT 'student_courses без студента' AS check_name, count(*) AS violations
FROM student_courses sc
WHERE NOT EXISTS (SELECT 1 FROM students st WHERE st.student_id = sc.student_id)
UNION ALL
SELECT 'student_courses без дисциплины', count(*)
FROM student_courses sc
WHERE NOT EXISTS (SELECT 1 FROM courses c WHERE c.course_id = sc.course_id)
UNION ALL
SELECT 'student_courses вне учебного плана', count(*)
FROM student_courses sc
JOIN students st        ON st.student_id = sc.student_id
JOIN student_groups sg  ON sg.group_id   = st.group_id
WHERE NOT EXISTS (
    SELECT 1 FROM specialty_courses scp
    WHERE scp.specialty_id = sg.specialty_id
      AND scp.course_id    = sc.course_id
      AND scp.semester     = sc.semester
      AND scp.course_type  = sc.enrollment_type)
UNION ALL
SELECT 'course_relations с несуществующей дисциплиной', count(*)
FROM course_relations cr
WHERE NOT EXISTS (SELECT 1 FROM courses c WHERE c.course_id = cr.source_course_id)
   OR NOT EXISTS (SELECT 1 FROM courses c WHERE c.course_id = cr.target_course_id);

-- 4) Сводка по мигрированным данным
SELECT 'specialty_courses (учебные планы)' AS item, count(*) AS rows FROM specialty_courses
UNION ALL SELECT 'course_relations (связи)',          count(*) FROM course_relations
UNION ALL SELECT 'student_groups с enrollment_year',  count(*) FROM student_groups WHERE enrollment_year IS NOT NULL
UNION ALL SELECT 'courses с description',             count(*) FROM courses WHERE description IS NOT NULL
UNION ALL SELECT 'student_courses с semester',        count(*) FROM student_courses WHERE semester IS NOT NULL;

-- 5) Негативные тесты ограничений (каждый должен быть ОТКЛОНЁН)
DO $$
DECLARE
    v_inserted BOOLEAN;
BEGIN
    -- 5.1 course_relations: запрет связи дисциплины с самой собой
    v_inserted := FALSE;
    BEGIN
        INSERT INTO course_relations (source_course_id, target_course_id, relation_type)
        VALUES (1, 1, 'related');
        v_inserted := TRUE;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK 5.1 самосвязь отклонена: %', SQLERRM;
    END;
    IF v_inserted THEN RAISE EXCEPTION 'FAIL 5.1: самосвязь прошла'; END IF;

    -- 5.2 course_relations: запрет дублирования идентичной связи
    v_inserted := FALSE;
    BEGIN
        INSERT INTO course_relations (source_course_id, target_course_id, relation_type)
        VALUES (2, 1, 'prerequisite');   -- такая связь уже есть
        v_inserted := TRUE;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK 5.2 дубль связи отклонён: %', SQLERRM;
    END;
    IF v_inserted THEN RAISE EXCEPTION 'FAIL 5.2: дубль связи прошёл'; END IF;

    -- 5.3 course_relations: недопустимый тип связи
    v_inserted := FALSE;
    BEGIN
        INSERT INTO course_relations (source_course_id, target_course_id, relation_type)
        VALUES (1, 2, 'unknown_type');
        v_inserted := TRUE;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK 5.3 неверный relation_type отклонён: %', SQLERRM;
    END;
    IF v_inserted THEN RAISE EXCEPTION 'FAIL 5.3: неверный relation_type прошёл'; END IF;

    -- 5.4 specialty_courses: недопустимый course_type
    v_inserted := FALSE;
    BEGIN
        INSERT INTO specialty_courses (specialty_id, course_id, semester, course_type)
        VALUES (1, 5, 6, 'optional');
        v_inserted := TRUE;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK 5.4 неверный course_type отклонён: %', SQLERRM;
    END;
    IF v_inserted THEN RAISE EXCEPTION 'FAIL 5.4: неверный course_type прошёл'; END IF;

    -- 5.5 specialty_courses: semester <= 0
    v_inserted := FALSE;
    BEGIN
        INSERT INTO specialty_courses (specialty_id, course_id, semester, course_type)
        VALUES (1, 5, 0, 'elective');
        v_inserted := TRUE;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK 5.5 semester=0 отклонён: %', SQLERRM;
    END;
    IF v_inserted THEN RAISE EXCEPTION 'FAIL 5.5: semester=0 прошёл'; END IF;

    -- 5.6 specialty_courses: дублирование составного PK
    v_inserted := FALSE;
    BEGIN
        INSERT INTO specialty_courses (specialty_id, course_id, semester, course_type)
        VALUES (1, 1, 6, 'mandatory');   -- пара (1,1) уже есть
        v_inserted := TRUE;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK 5.6 дубль PK(specialty,course) отклонён: %', SQLERRM;
    END;
    IF v_inserted THEN RAISE EXCEPTION 'FAIL 5.6: дубль PK прошёл'; END IF;

    -- 5.7 student_courses: enrollment_type не соответствует учебному плану
    v_inserted := FALSE;
    BEGIN
        INSERT INTO student_courses (student_id, course_id, enrollment_type, semester)
        VALUES (1, 4, 'mandatory', 6);   -- (специальность 1, курс 4) = elective
        v_inserted := TRUE;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK 5.7 несоответствие enrollment_type отклонено: %', SQLERRM;
    END;
    IF v_inserted THEN RAISE EXCEPTION 'FAIL 5.7: несоответствие enrollment_type прошло'; END IF;

    -- 5.8 student_courses: зачисление на дисциплину вне учебного плана
    v_inserted := FALSE;
    BEGIN
        INSERT INTO student_courses (student_id, course_id, enrollment_type, semester)
        VALUES (1, 10, 'elective', 6);   -- курс 10 не в плане специальности 1
        v_inserted := TRUE;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK 5.8 дисциплина вне учебного плана отклонена: %', SQLERRM;
    END;
    IF v_inserted THEN RAISE EXCEPTION 'FAIL 5.8: дисциплина вне плана прошла'; END IF;

    -- 5.9 student_groups: несогласованность course_number и enrollment_year
    v_inserted := FALSE;
    BEGIN
        UPDATE student_groups SET course_number = 5 WHERE group_id = 1;
        v_inserted := TRUE;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK 5.9 рассогласование курса и года поступления отклонено: %', SQLERRM;
    END;
    IF v_inserted THEN
        UPDATE student_groups SET course_number = 4 WHERE group_id = 1;
        RAISE EXCEPTION 'FAIL 5.9: рассогласование курса и года прошло';
    END IF;
END $$;
