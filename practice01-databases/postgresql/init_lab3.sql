-- ============================================================
-- LAB 3 (актуализировано, практика 3): PostgreSQL 16 — MASTER / Source of Truth
-- Нормализованная модель:
-- университет -> институты -> факультеты -> кафедры ->
-- специальности -> группы -> студенты
-- курсы -> занятия (лекции/практики/лабораторные)
-- учебный план: specialty_courses (M:N специальности <-> дисциплины)
-- связи дисциплин: course_relations (prerequisite/related/continuation)
-- расписание, посещаемость (партиционирование по week_start_date,
-- 16 недельных партиций осеннего семестра 2026/27)
--
-- Эквивалентная доработка существующей БД выполняется скриптом
-- migration_practice3.sql (та же структура, но поверх старой схемы).
-- ============================================================

-- ---------- Очистка старой схемы ----------
DROP TABLE IF EXISTS attendance CASCADE;
DROP TABLE IF EXISTS attendance_2026_09_07, attendance_2026_09_14, attendance_2026_09_21,
                    attendance_2026_09_28, attendance_2026_10_05, attendance_2026_10_12,
                    attendance_2026_10_19, attendance_2026_10_26, attendance_2026_11_02,
                    attendance_2026_11_09, attendance_2026_11_16, attendance_2026_11_23,
                    attendance_2026_11_30, attendance_2026_12_07, attendance_2026_12_14,
                    attendance_2026_12_21 CASCADE;
DROP TABLE IF EXISTS attendance, schedule, lessons, student_courses,
                 course_relations, specialty_courses,
                 courses, students, student_groups, specialties, department_specialties,
                 departments, faculties, institutes, universities,
                 lecture_materials, lecture_tags,
                 tags, lecture_courses, lectures CASCADE;

-- ---------- 1. Университеты ----------
CREATE TABLE universities (
    university_id   SERIAL PRIMARY KEY,
    name            VARCHAR(200) NOT NULL,
    short_name      VARCHAR(50),
    city            VARCHAR(100)
);

-- ---------- 2. Институты ----------
CREATE TABLE institutes (
    institute_id    SERIAL PRIMARY KEY,
    university_id   INT NOT NULL REFERENCES universities,
    name            VARCHAR(200) NOT NULL,
    short_name      VARCHAR(50)
);

-- ---------- 3. Факультеты ----------
CREATE TABLE faculties (
    faculty_id      SERIAL PRIMARY KEY,
    institute_id    INT NOT NULL REFERENCES institutes,
    name            VARCHAR(200) NOT NULL
);

-- ---------- 4. Кафедры ----------
CREATE TABLE departments (
    department_id   SERIAL PRIMARY KEY,
    faculty_id      INT NOT NULL REFERENCES faculties,
    name            VARCHAR(200) NOT NULL,
    short_name      VARCHAR(50)
);

-- ---------- 5. Специальности ----------
CREATE TABLE specialties (
    specialty_id    SERIAL PRIMARY KEY,
    department_id   INT NOT NULL REFERENCES departments,
    code            VARCHAR(20) NOT NULL UNIQUE,
    name            VARCHAR(200) NOT NULL
);

-- ---------- 6. Группы ----------
-- enrollment_year — год поступления; согласован с course_number
-- (набор данных соответствует осеннему семестру 2025/26:
--  course_number = 2025 - enrollment_year + 1, т.е. year + course = 2026)
CREATE TABLE student_groups (
    group_id        SERIAL PRIMARY KEY,
    specialty_id    INT NOT NULL REFERENCES specialties,
    group_number    VARCHAR(20) NOT NULL UNIQUE,
    course_number   INT NOT NULL,
    enrollment_year INT NOT NULL,
    CONSTRAINT chk_group_course_year
        CHECK (enrollment_year + course_number = 2026),
    CONSTRAINT chk_group_year_suffix
        CHECK (enrollment_year % 100 = (substring(group_number FROM '[0-9]{2}$'))::int)
);

-- ---------- 7. Студенты ----------
CREATE TABLE students (
    student_id          SERIAL PRIMARY KEY,
    group_id            INT NOT NULL REFERENCES student_groups,
    record_book_number  VARCHAR(20) NOT NULL UNIQUE,
    full_name           VARCHAR(200) NOT NULL,
    email               VARCHAR(200),
    status              VARCHAR(20) NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'academic_leave', 'expelled'))
);

-- ---------- 8. Курсы ----------
-- semester и is_elective перенесены на уровень учебного плана
-- (таблица specialty_courses); связь с кафедрой department_id сохранена.
CREATE TABLE courses (
    course_id       SERIAL PRIMARY KEY,
    department_id   INT NOT NULL REFERENCES departments,
    code            VARCHAR(20) NOT NULL UNIQUE,
    name            VARCHAR(200) NOT NULL,
    description     TEXT
);

-- ---------- 9. Учебный план: специальности <-> дисциплины (M:N) ----------
-- Одна дисциплина может относиться к нескольким специальностям.
CREATE TABLE specialty_courses (
    specialty_id    INT NOT NULL
                    CONSTRAINT fk_specialty_courses_specialty REFERENCES specialties,
    course_id       INT NOT NULL
                    CONSTRAINT fk_specialty_courses_course REFERENCES courses,
    semester        INT NOT NULL
                    CONSTRAINT chk_specialty_courses_semester CHECK (semester > 0),
    course_type     VARCHAR(20) NOT NULL
                    CONSTRAINT chk_specialty_courses_type
                    CHECK (course_type IN ('mandatory', 'elective')),
    CONSTRAINT pk_specialty_courses PRIMARY KEY (specialty_id, course_id)
);

-- ---------- 10. Связи между дисциплинами ----------
CREATE TABLE course_relations (
    relation_id       SERIAL
                      CONSTRAINT pk_course_relations PRIMARY KEY,
    source_course_id  INT NOT NULL
                      CONSTRAINT fk_course_relations_source REFERENCES courses,
    target_course_id  INT NOT NULL
                      CONSTRAINT fk_course_relations_target REFERENCES courses,
    relation_type     VARCHAR(50) NOT NULL
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

-- ---------- 11. Зачисление студентов на курсы ----------
-- enrollment_type должен соответствовать course_type из учебного плана
-- специальности студента (контролируется триггером trg_student_courses_enrollment_type).
CREATE TABLE student_courses (
    student_id        INT NOT NULL REFERENCES students,
    course_id         INT NOT NULL REFERENCES courses,
    enrollment_type   VARCHAR(20) NOT NULL
                      CHECK (enrollment_type IN ('mandatory', 'elective')),
    semester          INT NOT NULL
                      CONSTRAINT chk_student_courses_semester CHECK (semester > 0),
    PRIMARY KEY (student_id, course_id)
);

-- ---------- 12. Занятия: лекции / практики / лабораторные ----------
CREATE TABLE lessons (
    lesson_id       SERIAL PRIMARY KEY,
    course_id       INT NOT NULL REFERENCES courses,
    lesson_type     VARCHAR(20) NOT NULL
                    CHECK (lesson_type IN ('lecture', 'practice', 'lab')),
    title           VARCHAR(200) NOT NULL,
    description     TEXT,
    content_text    TEXT,
    equipment       TEXT,
    order_number    INT NOT NULL,
    tags            TEXT[] NOT NULL DEFAULT '{}',
    UNIQUE (course_id, order_number)
);

-- ---------- 13. Расписание ----------
CREATE TABLE schedule (
    schedule_id     SERIAL PRIMARY KEY,
    lesson_id       INT NOT NULL REFERENCES lessons,
    group_id        INT NOT NULL REFERENCES student_groups,
    lesson_date     DATE NOT NULL,
    start_time      TIME NOT NULL,
    end_time        TIME NOT NULL,
    room            VARCHAR(20)
);

-- ---------- 14. Посещаемость: PARTITION BY RANGE (week_start_date) ----------
-- Осенний семестр 2026/27: 16 недельных партиций,
-- понедельники 2026-09-07 .. 2026-12-21 (каждая — одна календарная неделя).
CREATE TABLE attendance (
    attendance_id   BIGSERIAL,
    student_id      INT NOT NULL REFERENCES students,
    schedule_id     INT NOT NULL REFERENCES schedule,
    week_start_date DATE NOT NULL,
    status          VARCHAR(10) NOT NULL DEFAULT 'attended'
                    CHECK (status IN ('attended', 'missed')),
    PRIMARY KEY (attendance_id, week_start_date)
) PARTITION BY RANGE (week_start_date);

CREATE TABLE attendance_2026_09_07 PARTITION OF attendance
    FOR VALUES FROM ('2026-09-07') TO ('2026-09-14');
CREATE TABLE attendance_2026_09_14 PARTITION OF attendance
    FOR VALUES FROM ('2026-09-14') TO ('2026-09-21');
CREATE TABLE attendance_2026_09_21 PARTITION OF attendance
    FOR VALUES FROM ('2026-09-21') TO ('2026-09-28');
CREATE TABLE attendance_2026_09_28 PARTITION OF attendance
    FOR VALUES FROM ('2026-09-28') TO ('2026-10-05');
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

-- ============================================================
-- ДАННЫЕ
-- ============================================================

INSERT INTO universities (name, short_name, city) VALUES
('Российский технологический университет', 'РТУ МИРЭА', 'Москва');

INSERT INTO institutes (university_id, name, short_name) VALUES
(1, 'Институт перспективных технологий и индустриального программирования', 'ИПТИП'),
(1, 'Институт электронной техники', 'ИЭТ');

INSERT INTO faculties (institute_id, name) VALUES
(1, 'Факультет программной инженерии'),
(1, 'Факультет кибербезопасности'),
(2, 'Факультет вычислительной техники');

INSERT INTO departments (faculty_id, name, short_name) VALUES
(1, 'Кафедра архитектуры программных систем', 'АПС'),
(1, 'Кафедра индустриального программирования', 'ИП'),
(2, 'Кафедра информационной безопасности', 'ИБ'),
(3, 'Кафедра вычислительной техники', 'ВТ'),
(3, 'Кафедра прикладной информатики', 'ПрИнф'),
(3, 'Кафедра математического обеспечения', 'МО');

INSERT INTO specialties (department_id, code, name) VALUES
(1, '09.03.01', 'Информатика и вычислительная техника'),
(2, '09.03.04', 'Программная инженерия'),
(3, '10.03.01', 'Информационная безопасность'),
(4, '09.03.02', 'Информационные системы и технологии'),
(5, '09.03.03', 'Прикладная информатика'),
(6, '02.03.03', 'Математическое обеспечение и администрирование информационных систем');

-- 34 группы: ИКБО (1-10), ИП (11-16), БИБ (17-22), ИСТ (23-27), ПИНФ (28-31), МО (32-34)
-- enrollment_year — по суффиксу номера группы (-22 -> 2022, -23 -> 2023, -24 -> 2024)
INSERT INTO student_groups (specialty_id, group_number, course_number, enrollment_year) VALUES
(1, 'ИКБО-01-22', 4, 2022), (1, 'ИКБО-02-23', 3, 2023), (1, 'ИКБО-03-24', 2, 2024),
(1, 'ИКБО-04-22', 4, 2022), (1, 'ИКБО-05-23', 3, 2023), (1, 'ИКБО-06-24', 2, 2024),
(1, 'ИКБО-07-22', 4, 2022), (1, 'ИКБО-08-23', 3, 2023), (1, 'ИКБО-09-24', 2, 2024),
(1, 'ИКБО-10-22', 4, 2022),
(2, 'ИП-01-22', 4, 2022), (2, 'ИП-02-23', 3, 2023), (2, 'ИП-03-24', 2, 2024),
(2, 'ИП-04-22', 4, 2022), (2, 'ИП-05-23', 3, 2023), (2, 'ИП-06-24', 2, 2024),
(3, 'БИБ-01-23', 3, 2023), (3, 'БИБ-02-23', 3, 2023), (3, 'БИБ-03-24', 2, 2024),
(3, 'БИБ-04-22', 4, 2022), (3, 'БИБ-05-23', 3, 2023), (3, 'БИБ-06-24', 2, 2024),
(4, 'ИСТ-01-22', 4, 2022), (4, 'ИСТ-02-23', 3, 2023), (4, 'ИСТ-03-24', 2, 2024),
(4, 'ИСТ-04-22', 4, 2022), (4, 'ИСТ-05-23', 3, 2023),
(5, 'ПИНФ-01-22', 4, 2022), (5, 'ПИНФ-02-23', 3, 2023), (5, 'ПИНФ-03-24', 2, 2024), (5, 'ПИНФ-04-22', 4, 2022),
(6, 'МО-01-23', 3, 2023), (6, 'МО-02-24', 2, 2024), (6, 'МО-03-22', 4, 2022);

-- 1000 студентов: детерминированная генерация.
-- Формула (единая для PostgreSQL / MongoDB / Neo4j / Redis):
--   группа g = (i-1) % 34 + 1; номер в группе k = (i-1) / 34 + 1;
--   зачётка = lpad(g,2) || lpad(k,3); ФИО из массивов по индексам (i*7, i*3, i*7);
--   статус: (i*13)%100 < 88 active, < 95 academic_leave, иначе expelled;
--   email = транслит(фамилия).транслит(имя).<i, 4 знака>@example.edu
INSERT INTO students (group_id, record_book_number, full_name, email, status)
WITH cfg AS (
  SELECT
    ARRAY['Иванов','Смирнов','Кузнецов','Соколов','Попов','Лебедев','Козлов','Новиков',
          'Морозов','Волков','Петров','Егоров','Павлов','Семёнов','Голубев','Виноградов',
          'Богданов','Воробьёв','Фёдоров','Михайлов','Беляев','Тарасов','Белов','Комаров',
          'Орлов','Киселёв','Макаров','Никитин','Зайцев','Соловьёв'] AS surnames,
    ARRAY['Иван','Алексей','Дмитрий','Сергей','Андрей','Максим','Никита','Павел','Артём','Кирилл'] AS male_names,
    ARRAY['Анна','Мария','Елена','Екатерина','Ольга','Наталья','Ирина','Светлана','Татьяна','Юлия'] AS female_names,
    ARRAY['Иванович','Сергеевич','Андреевич','Дмитриевич','Александрович','Николаевич','Петрович','Михайлович'] AS male_patronymics,
    ARRAY['Ивановна','Сергеевна','Андреевна','Дмитриевна','Александровна','Николаевна','Петровна','Михайловна'] AS female_patronymics
),
g AS (
  SELECT i,
         ((i - 1) % 34) + 1 AS gid,
         ((i - 1) / 34) + 1 AS kin,
         (i % 2) = 1        AS is_male
  FROM generate_series(1, 1000) AS i
),
x AS (
  SELECT g.i, g.gid, g.kin, g.is_male,
         c.surnames[((g.i * 7) % 30) + 1] AS sn,
         CASE WHEN g.is_male THEN c.male_names[((g.i * 3) % 10) + 1]
              ELSE c.female_names[((g.i * 3) % 10) + 1] END AS fn,
         CASE WHEN g.is_male THEN c.male_patronymics[((g.i * 7) % 8) + 1]
              ELSE c.female_patronymics[((g.i * 7) % 8) + 1] END AS pt,
         CASE WHEN g.is_male THEN c.surnames[((g.i * 7) % 30) + 1]
              ELSE c.surnames[((g.i * 7) % 30) + 1] || 'а' END AS sn_full
  FROM g CROSS JOIN cfg c
)
SELECT
  x.gid,
  lpad(x.gid::text, 2, '0') || lpad(x.kin::text, 3, '0'),
  x.sn_full || ' ' || x.fn || ' ' || x.pt,
  lower(replace(translate(x.sn_full,
           'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя',
           'ABVGDEEZZIYKLMNOPRSTUFHCCSS__YEUAabvgdeezziyklmnoprstufhccss__yeua'), '_', ''))
    || '.'
  || lower(replace(translate(x.fn,
           'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя',
           'ABVGDEEZZIYKLMNOPRSTUFHCCSS__YEUAabvgdeezziyklmnoprstufhccss__yeua'), '_', ''))
    || '.' || lpad(x.i::text, 4, '0') || '@example.edu',
  CASE WHEN (x.i * 13) % 100 < 88 THEN 'active'
       WHEN (x.i * 13) % 100 < 95 THEN 'academic_leave'
       ELSE 'expelled' END
FROM x;

INSERT INTO courses (department_id, code, name, description) VALUES
(1, '09.ПАС',  'Проектирование архитектуры программных систем',
 'Теория и практика проектирования архитектуры программных систем: стили, паттерны, нефункциональные требования и архитектурные компромиссы.'),
(1, '09.БД',   'Базы данных',
 'Реляционная модель данных, SQL, нормализация, транзакции и индексы; проектирование и администрирование баз данных.'),
(3, '10.ИБ',   'Информационная безопасность',
 'Угрозы информационной безопасности, криптографические методы защиты и практика защиты веб-приложений.'),
(1, '09.МА',   'Микросервисные архитектуры',
 'Проектирование распределённых систем на микросервисах: декомпозиция домена, Saga, service mesh и наблюдаемость.'),
(1, '09.DEV',  'DevOps и CI/CD',
 'Непрерывная интеграция и доставка: пайплайны CI/CD, контейнеризация и деплой в Kubernetes.'),
(1, '09.ОС',   'Операционные системы',
 'Устройство операционных систем: процессы и потоки, планирование, память, файловые системы и синхронизация.'),
(2, '09.Web',  'Web-программирование',
 'Клиент-серверная разработка веб-приложений: HTTP, REST API, фронтенд-фреймворки и развёртывание.'),
(2, '09.Тест', 'Тестирование программного обеспечения',
 'Уровни и виды тестирования, пирамида тестов, модульные и сквозные тесты, автоматизация в CI.'),
(6, '02.Алг',  'Алгоритмы и структуры данных',
 'Асимптотический анализ, сортировки и поиск, графовые алгоритмы и базовые структуры данных.'),
(5, '09.МЛ',   'Машинное обучение',
 'Классические задачи машинного обучения: регрессия, классификация, метрики качества и нейронные сети.');

-- Учебный план: semester и course_type теперь здесь (ранее — courses.semester, courses.is_elective).
-- Одна дисциплина может относиться к нескольким специальностям
-- (ПАС и БД — у ИВТ и ПИ; БД и ОС — у ИВТ, ИСТ и МО и т.д.).
INSERT INTO specialty_courses (specialty_id, course_id, semester, course_type) VALUES
-- 09.03.01 ИВТ:  ПАС + БД обязательные, электив МА
(1, 1, 6, 'mandatory'), (1, 2, 4, 'mandatory'), (1, 4, 6, 'elective'),
-- 09.03.04 ПИ:   ПАС + БД обязательные, элективы Web, Тест
(2, 1, 6, 'mandatory'), (2, 2, 4, 'mandatory'), (2, 7, 5, 'elective'), (2, 8, 6, 'elective'),
-- 10.03.01 ИБ:   ИБ + ОС обязательные, электив МЛ
(3, 3, 5, 'mandatory'), (3, 6, 4, 'mandatory'), (3, 10, 6, 'elective'),
-- 09.03.02 ИСТ:  БД + ОС обязательные, электив Web
(4, 2, 4, 'mandatory'), (4, 6, 4, 'mandatory'), (4, 7, 5, 'elective'),
-- 09.03.03 ПрИнф: Алг + Web обязательные, электив Тест
(5, 9, 3, 'mandatory'), (5, 7, 5, 'mandatory'), (5, 8, 6, 'elective'),
-- 02.03.03 МО:   Алг + ОС обязательные, элективы МЛ, МА
(6, 9, 3, 'mandatory'), (6, 6, 4, 'mandatory'), (6, 10, 6, 'elective'), (6, 4, 6, 'elective');

-- Логические связи между дисциплинами: prerequisite / related / continuation
INSERT INTO course_relations (source_course_id, target_course_id, relation_type) VALUES
 (9,  2,  'prerequisite'),   -- Алгоритмы и структуры данных -> Базы данных
 (2,  1,  'prerequisite'),   -- Базы данных -> Проектирование архитектуры ПС
 (6,  3,  'prerequisite'),   -- Операционные системы -> Информационная безопасность
 (9,  10, 'prerequisite'),   -- Алгоритмы и структуры данных -> Машинное обучение
 (1,  4,  'continuation'),   -- Микросервисные архитектуры — продолжение ПАС
 (7,  8,  'continuation'),   -- Тестирование ПО — продолжение Web-программирования
 (4,  5,  'related'),        -- Микросервисные архитектуры <-> DevOps и CI/CD
 (2,  7,  'related');        -- Базы данных <-> Web-программирование

-- Зачисление: 2 обязательных курса по специальности + элективы (~50% студентов).
-- enrollment_type и semester берутся из учебного плана (specialty_courses),
-- поэтому тип зачисления автоматически соответствует типу дисциплины в плане.
WITH sp_map (specialty_id, course_a, course_b, electives) AS (
  VALUES (1::int, 1::int, 2::int, ARRAY[4]::int[]),        -- ИВТ:  ПАС+БД, электив МА
         (2::int, 1::int, 2::int, ARRAY[7, 8]::int[]),     -- ПИ:   ПАС+БД, элективы Web, Тест
         (3::int, 3::int, 6::int, ARRAY[10]::int[]),       -- ИБ:   ИБ+ОС, электив МЛ
         (4::int, 2::int, 6::int, ARRAY[7]::int[]),        -- ИСТ:  БД+ОС, электив Web
         (5::int, 9::int, 7::int, ARRAY[8]::int[]),        -- ПрИнф: Алг+Web, электив Тест
         (6::int, 9::int, 6::int, ARRAY[10, 4]::int[])     -- МО:   Алг+ОС, элективы МЛ, МА
),
plan AS (
  SELECT sg.specialty_id, scp.course_id, scp.course_type, scp.semester
  FROM student_groups sg
  JOIN specialty_courses scp ON scp.specialty_id = sg.specialty_id
  GROUP BY sg.specialty_id, scp.course_id, scp.course_type, scp.semester
),
enr AS (
  SELECT sg.specialty_id, st.student_id, m.course_a AS course_id
  FROM students st
  JOIN student_groups sg ON sg.group_id = st.group_id
  JOIN sp_map m ON m.specialty_id = sg.specialty_id
  UNION
  SELECT sg.specialty_id, st.student_id, m.course_b
  FROM students st
  JOIN student_groups sg ON sg.group_id = st.group_id
  JOIN sp_map m ON m.specialty_id = sg.specialty_id
  UNION
  SELECT sg.specialty_id, st.student_id, e
  FROM students st
  JOIN student_groups sg ON sg.group_id = st.group_id
  JOIN sp_map m ON m.specialty_id = sg.specialty_id
  CROSS JOIN LATERAL unnest(m.electives) AS e
  WHERE (st.student_id * 17 + e) % 100 < 50
)
INSERT INTO student_courses (student_id, course_id, enrollment_type, semester)
SELECT enr.student_id, enr.course_id, plan.course_type, plan.semester
FROM enr
JOIN plan ON plan.specialty_id = enr.specialty_id
         AND plan.course_id    = enr.course_id;

-- Триггер: enrollment_type обязан совпадать с course_type учебного плана
-- специальности зачисляемого студента.
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

INSERT INTO lessons (course_id, lesson_type, title, description, content_text, equipment, order_number, tags) VALUES
(1, 'lecture',  'Введение в архитектуру ПО',
                'Основные понятия, роли и стили архитектуры программных систем.',
                'Архитектура ПО определяет высокоуровневую структуру системы и принципы её развития. Рассматриваются монолит, слоистая архитектура, гексагональная архитектура и критерии выбора стиля. Отдельное внимание уделяется нефункциональным требованиям и архитектурным компромиссам.',
                'Проектор, презентационный экран.',
                1, ARRAY['архитектура', 'введение', 'специальная дисциплина']),
(1, 'practice', 'Проектирование микросервисов',
                'Разработка модели декомпозиции домена на микросервисы.',
                'Студенты выполняют декомпозицию предметной области интернет-магазина на ограниченные контексты. Определяются границы сервисов, контракты API и стратегия управления данными. Результат оформляется в виде C4-диаграммы контейнеров.',
                'Компьютерный класс (12 ПК), редактор диаграмм draw.io.',
                2, ARRAY['микросервисы', 'проектирование', 'практика']),
(1, 'lab',      'Разработка API Gateway',
                'Реализация единой точки входа для микросервисной системы.',
                'В лабораторной работе реализуется API Gateway: маршрутизация запросов, агрегация ответов и проверка токенов. Настраиваются rate limiting и circuit breaker. Тестируется отказоустойчивость при недоступности backend-сервиса.',
                'Сервер Dell PowerEdge R740 (3 шт.), коммутатор Cisco Catalyst 2960 (2 шт.).',
                3, ARRAY['api', 'gateway', 'лабораторная']),
(2, 'lecture',  'Реляционная модель данных',
                'Таблицы, ключи, ограничения и нормализация схем.',
                'Реляционная модель основана на отношениях, атрибутах и ключах. Изучаются нормальные формы от 1НФ до 3НФ и аномалии обновления. Обсуждаются ограничения целостности и внешние ключи как инструмент согласованности.',
                'Проектор, презентационный экран.',
                1, ARRAY['бд', 'sql', 'реляционная модель']),
(2, 'practice', 'SQL: сложные запросы',
                'Многотабличные соединения, подзапросы и оконные функции.',
                'Отрабатываются JOIN разных типов, коррелированные подзапросы и CTE. Отдельный блок посвящён оконным функциям для аналитических отчётов. Практика выполняется на схеме «университет».',
                'Компьютерный класс (12 ПК), PostgreSQL 16, DBeaver.',
                2, ARRAY['sql', 'запросы', 'практика']),
(2, 'lab',      'Проектирование и нормализация БД',
                'Проектирование схемы базы данных до третьей нормальной формы.',
                'По описанию предметной области строится ER-диаграмма и логическая модель. Схема нормализуется до 3НФ, затем обоснованно денормализуется под нагрузку чтения. Итоговая схема переносится в PostgreSQL.',
                'Компьютерный класс (12 ПК), PostgreSQL 16, pgAdmin 4.',
                3, ARRAY['нормализация', 'er-диаграмма', 'лабораторная']),
(3, 'lecture',  'Основы криптографии',
                'Симметричные и асимметричные шифры, хеши и подписи.',
                'Изучаются симметричные шифры (AES) и асимметричные (RSA, эллиптические кривые). Разбираются хеш-функции, электронная подпись и инфраструктура открытых ключей. Обсуждаются типовые ошибки применения криптографии.',
                'Проектор, презентационный экран.',
                1, ARRAY['криптография', 'безопасность', 'шифрование']),
(3, 'practice', 'Анализ уязвимостей веб-приложений',
                'Практический разбор OWASP Top 10.',
                'Студенты находят и эксплуатируют уязвимости в учебном приложении: инъекции, XSS, некорректный контроль доступа. Для каждой уязвимости формулируется контрмера. Работа ведётся в изолированной среде.',
                'Компьютерный класс (12 ПК), изолированный стенд с учебным приложением (DVWA).',
                2, ARRAY['уязвимости', 'owasp', 'безопасность']),
(3, 'lab',      'Настройка межсетевого экрана',
                'Фильтрация трафика с помощью nftables.',
                'Настраивается политика «запрещено всё, кроме разрешённого» для веб-сервера. Составляются правила фильтрации и NAT, ведётся журналирование. Проверяется защита от сканирования портов.',
                'Маршрутизатор MikroTik hEX (4 шт.), межсетевой экран pfSense на мини-ПК (2 шт.).',
                3, ARRAY['firewall', 'сеть', 'лабораторная']),
(4, 'lecture',  'Паттерны микросервисов',
                'Saga, Circuit Breaker, Strangler Fig и другие паттерны.',
                'Рассматриваются паттерны распределённых транзакций (Saga), устойчивости (Circuit Breaker, Retry, Bulkhead) и миграции монолита (Strangler Fig). Каждый паттерн разбирается вместе с антипаттернами и стоимостью внедрения.',
                'Проектор, презентационный экран.',
                1, ARRAY['микросервисы', 'паттерны', 'электив']),
(4, 'practice', 'Docker и контейнеризация',
                'Упаковка сервисов в контейнеры и оркестрация compose.',
                'Сервис упаковывается в образ на базе многоступенчатой сборки. Поднимается локальное окружение из нескольких сервисов через Compose. Обсуждаются healthcheck, лимиты ресурсов и управление конфигурацией.',
                'Ноутбуки (12 шт.), Docker Desktop, доступ к Docker Hub.',
                2, ARRAY['docker', 'контейнеры', 'практика']),
(4, 'lab',      'Service Mesh на практике',
                'Управление трафиком в Istio.',
                'Разворачивается service mesh на базе Istio для кластера из трёх сервисов. Настраиваются канареечные релизы, взаимный TLS и observability. Оценивается накладная сложность mesh-инфраструктуры.',
                'Сервер Dell PowerEdge R740 (3 шт.), коммутатор Cisco Catalyst 2960 (2 шт.), кластер Kubernetes.',
                3, ARRAY['istio', 'service mesh', 'лабораторная']),
(5, 'lecture',  'Введение в CI/CD',
                'Непрерывная интеграция и доставка: понятия, этапы, метрики.',
                'Разбираются понятия непрерывной интеграции, доставки и развёртывания. Строится типовой конвейер: сборка, статический анализ, тесты, артефакты, релиз. Обсуждаются метрики DORA и типовые ошибки организации пайплайнов.',
                'Проектор, презентационный экран.',
                1, ARRAY['ci/cd', 'devops', 'электив']),
(5, 'practice', 'Пайплайн сборки в GitHub Actions',
                'Автоматизация сборки и тестов сервиса.',
                'Настраивается workflow в GitHub Actions: сборка образа, прогон модульных тестов, публикация артефакта в registry. Добавляются кэш зависимостей и матрица версий. Разбирается работа с секретами репозитория.',
                'Ноутбуки (12 шт.), доступ к GitHub и GitHub Actions.',
                2, ARRAY['github actions', 'сборка', 'практика']),
(5, 'lab',      'Деплой в Kubernetes',
                'Развёртывание сервиса в кластере Kubernetes.',
                'Сервис разворачивается в учебном кластере Kubernetes: Deployment, Service, ConfigMap и Secret. Настраиваются пробы готовности и живости, лимиты ресурсов. Проверяется обновление версии без простоя.',
                'Сервер Dell PowerEdge R740 (3 шт.), учебный кластер Kubernetes, kubectl.',
                3, ARRAY['kubernetes', 'деплой', 'лабораторная']),
(6, 'lecture',  'Процессы и потоки',
                'Понятия процесса и потока, планирование выполнения.',
                'Рассматриваются процессы и потоки, их состояния, контекстное переключение и планировщики. Разбираются алгоритмы планирования (FCFS, SJF, Round Robin) и межпроцессное взаимодействие. Обсуждаются гонки, взаимные блокировки и средства синхронизации.',
                'Проектор, презентационный экран.',
                1, ARRAY['ос', 'процессы', 'лекция']),
(6, 'practice', 'Системные вызовы POSIX',
                'Работа с процессами и файлами через системные вызовы.',
                'Студенты пишут программы на C с fork, exec, wait и файловыми дескрипторами. Отрабатываются пайпы, перенаправление ввода-вывода и сигналы. Практика выполняется в Linux-окружении.',
                'Компьютерный класс (12 ПК), Linux, gcc.',
                2, ARRAY['posix', 'linux', 'практика']),
(6, 'lab',      'Синхронизация потоков',
                'Мьютексы, условные переменные и типовые ошибки.',
                'Реализуется многопоточная очередь задач с мьютексами и условными переменными. Анализируются гонки данных и дедлоки с помощью ThreadSanitizer. Измеряется производительность при разном числе потоков.',
                'Компьютерный класс (12 ПК), Linux, gcc, pthread, ThreadSanitizer.',
                3, ARRAY['потоки', 'синхронизация', 'лабораторная']),
(7, 'lecture',  'Архитектура веб-приложений',
                'HTTP, клиент-серверная модель, слои веб-приложения.',
                'Разбираются протокол HTTP, модель запрос-ответ, REST и слои типового веб-приложения: клиент, API, бизнес-логика, хранилище. Обсуждаются куки, сессии, JWT и базовая безопасность веб-стека.',
                'Проектор, презентационный экран.',
                1, ARRAY['web', 'http', 'лекция']),
(7, 'practice', 'REST API на Python',
                'Разработка CRUD API с FastAPI.',
                'Реализуется CRUD REST API с валидацией входных данных и подключением к PostgreSQL. Добавляются обработка ошибок, логирование и автодокументация OpenAPI. API тестируется через curl и pytest.',
                'Компьютерный класс (12 ПК), Python 3, FastAPI, PostgreSQL 16.',
                2, ARRAY['rest', 'api', 'практика']),
(7, 'lab',      'Одностраничное приложение',
                'SPA на современном фреймворке.',
                'Разрабатывается SPA: компоненты, роутинг, состояние и обмен с REST API. Настраивается сборка проекта и подключение макета. Результат разворачивается на локальном веб-сервере.',
                'Компьютерный класс (12 ПК), Node.js 20, Vite.',
                3, ARRAY['spa', 'frontend', 'лабораторная']),
(8, 'lecture',  'Виды и уровни тестирования',
                'Классификация тестов, пирамида тестирования.',
                'Изучаются уровни тестирования: модульное, интеграционное, системное и приёмочное. Разбираются пирамида тестов, техники чёрного и белого ящика, метрики покрытия. Обсуждается стоимость дефектов на разных этапах разработки.',
                'Проектор, презентационный экран.',
                1, ARRAY['тестирование', 'qa', 'лекция']),
(8, 'practice', 'Модульные тесты на pytest',
                'Тест-кейсы, фикстуры и параметризация.',
                'Пишутся модульные тесты на pytest: фикстуры, параметризация, моки зависимостей. Настраивается измерение покрытия, проверяется поведение на граничных случаях. Обсуждаются правила хорошего теста.',
                'Компьютерный класс (12 ПК), Python 3, pytest.',
                2, ARRAY['pytest', 'модульные тесты', 'практика']),
(8, 'lab',      'Автоматизация UI-тестов',
                'Сквозные тесты веб-интерфейса.',
                'Автоматизируются сквозные сценарии веб-приложения: поиск элементов, ожидания, работа с формами. Тесты запускаются в headless-браузере и интегрируются в CI. Формируется отчёт о прогонах.',
                'Компьютерный класс (12 ПК), Playwright, headless Chromium.',
                3, ARRAY['ui', 'playwright', 'лабораторная']),
(9, 'lecture',  'Сложность алгоритмов',
                'Асимптотический анализ, O-нотация.',
                'Вводятся асимптотические оценки O, Θ и Ω, разбирается анализ циклов и рекурсии. Сравниваются решения одной задачи разной сложности. Обсуждаются типовые классы алгоритмов и пределы их применимости.',
                'Проектор, презентационный экран.',
                1, ARRAY['алгоритмы', 'сложность', 'лекция']),
(9, 'practice', 'Сортировки и поиск',
                'Классические алгоритмы сортировки и бинарный поиск.',
                'Реализуются сортировки (quick, merge, heap) и бинарный поиск, сравнивается их поведение на разных данных. Замеряется время выполнения и число сравнений. Обсуждаются устойчивость и выбор алгоритма под задачу.',
                'Компьютерный класс (12 ПК), Python 3.',
                2, ARRAY['сортировки', 'поиск', 'практика']),
(9, 'lab',      'Графовые алгоритмы',
                'Обходы в глубину и ширину, кратчайшие пути.',
                'Реализуются BFS, DFS и алгоритм Дейксты на списках смежности. Решается задача маршрутизации на тестовом графе дорожной сети. Оценивается сложность структур данных для очереди с приоритетом.',
                'Компьютерный класс (12 ПК), Python 3, graphviz.',
                3, ARRAY['графы', 'bfs', 'лабораторная']),
(10, 'lecture', 'Задачи и типы машинного обучения',
                'Обучение с учителем, без учителя, метрики качества.',
                'Разбираются постановки задач ML: регрессия, классификация, кластеризация. Вводится схема эксперимента: train/validation/test, переобучение, регуляризация. Обсуждаются метрики качества и базовая гигиена данных.',
                'Проектор, презентационный экран.',
                1, ARRAY['ml', 'метрики', 'электив']),
(10, 'practice','Регрессия и классификация',
                'Первые модели на scikit-learn.',
                'Строятся модели линейной регрессии и логистической классификации на scikit-learn: подготовка признаков, обучение, кросс-валидация. Результаты интерпретируются через метрики и графики ошибок.',
                'Компьютерный класс (12 ПК), Python 3, scikit-learn, Jupyter.',
                2, ARRAY['sklearn', 'регрессия', 'практика']),
(10, 'lab',     'Нейронная сеть на PyTorch',
                'Обучение простой сети на табличных данных.',
                'Реализуется небольшая нейросеть на PyTorch: тензоры, цикл обучения, оптимизатор. Сеть обучается на табличном наборе данных, подбираются гиперпараметры. Итог сравнивается с классической моделью sklearn.',
                'Компьютерный класс (12 ПК), Python 3, PyTorch, Jupyter.',
                3, ARRAY['pytorch', 'нейросети', 'лабораторная']);

-- Расписание: каждой группе 2 недели × 3 пары (6 занятий на группу, 204 строки)
WITH sp_map (specialty_id, course_a, course_b) AS (
  VALUES (1::int, 1::int, 2::int), (2::int, 1::int, 2::int), (3::int, 3::int, 6::int),
         (4::int, 2::int, 6::int), (5::int, 9::int, 7::int), (6::int, 9::int, 6::int)
),
grp AS (
  SELECT sg.group_id, m.course_a, m.course_b
  FROM student_groups sg JOIN sp_map m ON m.specialty_id = sg.specialty_id
),
slots AS (
  SELECT grp.group_id, grp.course_a, grp.course_b, w.w, j.j
  FROM grp CROSS JOIN generate_series(0, 1) AS w CROSS JOIN generate_series(0, 2) AS j
)
INSERT INTO schedule (lesson_id, group_id, lesson_date, start_time, end_time, room)
SELECT
  CASE WHEN s.w = 0 THEN
         CASE s.j WHEN 0 THEN (s.course_a - 1) * 3 + 1
                  WHEN 1 THEN (s.course_a - 1) * 3 + 2
                  ELSE   (s.course_b - 1) * 3 + 1 END
       ELSE
         CASE s.j WHEN 0 THEN (s.course_a - 1) * 3 + 3
                  WHEN 1 THEN (s.course_b - 1) * 3 + 2
                  ELSE   (s.course_b - 1) * 3 + 3 END
  END,
  s.group_id,
  DATE '2026-09-21' + s.w * 7 + ((s.group_id - 1) * 3 + s.j) % 5,
  (ARRAY['09:00','10:40','11:40','14:00']::time[])[((s.group_id - 1) * 3 + s.j) % 4 + 1],
  (ARRAY['10:30','12:10','13:10','15:30']::time[])[((s.group_id - 1) * 3 + s.j) % 4 + 1],
  (ARRAY['А-301','А-302','А-303','Л-102','Л-105','Б-201','Б-105','Б-107','В-401','В-405','В-410'])
    [((s.group_id - 1) * 3 + s.j) % 11 + 1]
FROM slots s;

-- Посещаемость: все студенты по расписанию своих групп (~6000 строк)
INSERT INTO attendance (student_id, schedule_id, week_start_date, status)
SELECT
  st.student_id,
  sc.schedule_id,
  sc.lesson_date - (EXTRACT(ISODOW FROM sc.lesson_date)::int - 1),
  CASE WHEN (st.student_id * 17 + sc.schedule_id) % 100 < 85 THEN 'attended' ELSE 'missed' END
FROM schedule sc
JOIN students st ON st.group_id = sc.group_id;
