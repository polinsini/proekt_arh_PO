// ============================================================
// LAB 3 (актуализировано, практика 3): Neo4j 5 — GRAPH
// Student -MEMBER_OF-> Group, Group -BELONGS_TO-> Specialty
// Student -STUDIES / CHOOSES-> Course, Course -HAS_LESSON-> Lesson
// Student -ATTENDED / MISSED-> Schedule
// Specialty -PLAN_INCLUDES {semester, course_type}-> Course  (= specialty_courses, M:N)
// Course -PREREQUISITE_OF / CONTINUATION_OF / RELATED_TO-> Course (= course_relations)
// Масштаб: 1000 студентов, 34 группы, 6 специальностей, 10 курсов, 30 занятий
//   semester и is_elective больше НЕ свойства Course: они переехали
//   в учебный план на рёбрах PLAN_INCLUDES (как в PostgreSQL)
// ============================================================
// Формула генерации студентов (единая для PostgreSQL / MongoDB / Neo4j / Redis):
//   группа g = (i-1) % 34 + 1; номер в группе k = (i-1) / 34 + 1;
//   зачётка = pad(g,2) + pad(k,3); ФИО из массивов по индексам (i*7, i*3, i*7);
//   статус: (i*13)%100 < 88 active, < 95 academic_leave, иначе expelled
// ============================================================

MATCH (n) DETACH DELETE n;

// ---------- Группы (34, + enrollment_year = год поступления по суффиксу) ----------
UNWIND [
 {name: 'ИКБО-01-22', cn: 4, ey: 2022}, {name: 'ИКБО-02-23', cn: 3, ey: 2023}, {name: 'ИКБО-03-24', cn: 2, ey: 2024},
 {name: 'ИКБО-04-22', cn: 4, ey: 2022}, {name: 'ИКБО-05-23', cn: 3, ey: 2023}, {name: 'ИКБО-06-24', cn: 2, ey: 2024},
 {name: 'ИКБО-07-22', cn: 4, ey: 2022}, {name: 'ИКБО-08-23', cn: 3, ey: 2023}, {name: 'ИКБО-09-24', cn: 2, ey: 2024},
 {name: 'ИКБО-10-22', cn: 4, ey: 2022},
 {name: 'ИП-01-22', cn: 4, ey: 2022},  {name: 'ИП-02-23', cn: 3, ey: 2023},  {name: 'ИП-03-24', cn: 2, ey: 2024},
 {name: 'ИП-04-22', cn: 4, ey: 2022},  {name: 'ИП-05-23', cn: 3, ey: 2023},  {name: 'ИП-06-24', cn: 2, ey: 2024},
 {name: 'БИБ-01-23', cn: 3, ey: 2023}, {name: 'БИБ-02-23', cn: 3, ey: 2023}, {name: 'БИБ-03-24', cn: 2, ey: 2024},
 {name: 'БИБ-04-22', cn: 4, ey: 2022}, {name: 'БИБ-05-23', cn: 3, ey: 2023}, {name: 'БИБ-06-24', cn: 2, ey: 2024},
 {name: 'ИСТ-01-22', cn: 4, ey: 2022}, {name: 'ИСТ-02-23', cn: 3, ey: 2023}, {name: 'ИСТ-03-24', cn: 2, ey: 2024},
 {name: 'ИСТ-04-22', cn: 4, ey: 2022}, {name: 'ИСТ-05-23', cn: 3, ey: 2023},
 {name: 'ПИНФ-01-22', cn: 4, ey: 2022}, {name: 'ПИНФ-02-23', cn: 3, ey: 2023}, {name: 'ПИНФ-03-24', cn: 2, ey: 2024}, {name: 'ПИНФ-04-22', cn: 4, ey: 2022},
 {name: 'МО-01-23', cn: 3, ey: 2023}, {name: 'МО-02-24', cn: 2, ey: 2024}, {name: 'МО-03-22', cn: 4, ey: 2022}
] AS row
CREATE (:Group {name: row.name, course_number: row.cn, enrollment_year: row.ey});

// ---------- Специальности (6) ----------
UNWIND [
 {code: '09.03.01', name: 'Информатика и вычислительная техника'},
 {code: '09.03.04', name: 'Программная инженерия'},
 {code: '10.03.01', name: 'Информационная безопасность'},
 {code: '09.03.02', name: 'Информационные системы и технологии'},
 {code: '09.03.03', name: 'Прикладная информатика'},
 {code: '02.03.03', name: 'Математическое обеспечение и администрирование информационных систем'}
] AS row
CREATE (:Specialty {code: row.code, name: row.name});

// ---------- Группа -> Специальность ----------
UNWIND [
 {g: 'ИКБО-01-22', s: '09.03.01'}, {g: 'ИКБО-02-23', s: '09.03.01'}, {g: 'ИКБО-03-24', s: '09.03.01'},
 {g: 'ИКБО-04-22', s: '09.03.01'}, {g: 'ИКБО-05-23', s: '09.03.01'}, {g: 'ИКБО-06-24', s: '09.03.01'},
 {g: 'ИКБО-07-22', s: '09.03.01'}, {g: 'ИКБО-08-23', s: '09.03.01'}, {g: 'ИКБО-09-24', s: '09.03.01'},
 {g: 'ИКБО-10-22', s: '09.03.01'},
 {g: 'ИП-01-22', s: '09.03.04'}, {g: 'ИП-02-23', s: '09.03.04'}, {g: 'ИП-03-24', s: '09.03.04'},
 {g: 'ИП-04-22', s: '09.03.04'}, {g: 'ИП-05-23', s: '09.03.04'}, {g: 'ИП-06-24', s: '09.03.04'},
 {g: 'БИБ-01-23', s: '10.03.01'}, {g: 'БИБ-02-23', s: '10.03.01'}, {g: 'БИБ-03-24', s: '10.03.01'},
 {g: 'БИБ-04-22', s: '10.03.01'}, {g: 'БИБ-05-23', s: '10.03.01'}, {g: 'БИБ-06-24', s: '10.03.01'},
 {g: 'ИСТ-01-22', s: '09.03.02'}, {g: 'ИСТ-02-23', s: '09.03.02'}, {g: 'ИСТ-03-24', s: '09.03.02'},
 {g: 'ИСТ-04-22', s: '09.03.02'}, {g: 'ИСТ-05-23', s: '09.03.02'},
 {g: 'ПИНФ-01-22', s: '09.03.03'}, {g: 'ПИНФ-02-23', s: '09.03.03'}, {g: 'ПИНФ-03-24', s: '09.03.03'}, {g: 'ПИНФ-04-22', s: '09.03.03'},
 {g: 'МО-01-23', s: '02.03.03'}, {g: 'МО-02-24', s: '02.03.03'}, {g: 'МО-03-22', s: '02.03.03'}
] AS row
MATCH (g:Group {name: row.g}), (s:Specialty {code: row.s})
CREATE (g)-[:BELONGS_TO]->(s);

// ---------- Студенты (1000) ----------
UNWIND range(1, 1000) AS i
WITH i,
     split('Иванов|Смирнов|Кузнецов|Соколов|Попов|Лебедев|Козлов|Новиков|Морозов|Волков|Петров|Егоров|Павлов|Семёнов|Голубев|Виноградов|Богданов|Воробьёв|Фёдоров|Михайлов|Беляев|Тарасов|Белов|Комаров|Орлов|Киселёв|Макаров|Никитин|Зайцев|Соловьёв', '|') AS sur,
     split('Иван|Алексей|Дмитрий|Сергей|Андрей|Максим|Никита|Павел|Артём|Кирилл', '|') AS mn,
     split('Анна|Мария|Елена|Екатерина|Ольга|Наталья|Ирина|Светлана|Татьяна|Юлия', '|') AS fn,
     split('Иванович|Сергеевич|Андреевич|Дмитриевич|Александрович|Николаевич|Петрович|Михайлович', '|') AS mp,
     split('Ивановна|Сергеевна|Андреевна|Дмитриевна|Александровна|Николаевна|Петровна|Михайловна', '|') AS fp
WITH i, sur, mn, fn, mp, fp,
     ((i - 1) % 34) + 1 AS gid, ((i - 1) / 34) + 1 AS kin, (i % 2 = 1) AS male
WITH i, gid, kin, male,
     sur[(i * 7) % size(sur)] AS surname,
     CASE WHEN male THEN mn[(i * 3) % size(mn)] ELSE fn[(i * 3) % size(fn)] END AS firstname,
     CASE WHEN male THEN mp[(i * 7) % size(mp)] ELSE fp[(i * 7) % size(fp)] END AS patronymic
CREATE (:Student {
  record_book: (CASE WHEN gid < 10 THEN '0' ELSE '' END) + toString(gid) +
               (CASE WHEN kin < 10 THEN '00' WHEN kin < 100 THEN '0' ELSE '' END) + toString(kin),
  full_name: (CASE WHEN male THEN surname ELSE surname + 'а' END) + ' ' + firstname + ' ' + patronymic,
  status: CASE WHEN (i * 13) % 100 < 88 THEN 'active'
               WHEN (i * 13) % 100 < 95 THEN 'academic_leave'
               ELSE 'expelled' END
});

// ---------- MEMBER_OF ----------
UNWIND range(1, 1000) AS i
WITH ((i - 1) % 34) + 1 AS gid, ((i - 1) / 34) + 1 AS kin
WITH (CASE WHEN gid < 10 THEN '0' ELSE '' END) + toString(gid) +
     (CASE WHEN kin < 10 THEN '00' WHEN kin < 100 THEN '0' ELSE '' END) + toString(kin) AS rb,
     split('ИКБО-01-22|ИКБО-02-23|ИКБО-03-24|ИКБО-04-22|ИКБО-05-23|ИКБО-06-24|ИКБО-07-22|ИКБО-08-23|ИКБО-09-24|ИКБО-10-22|ИП-01-22|ИП-02-23|ИП-03-24|ИП-04-22|ИП-05-23|ИП-06-24|БИБ-01-23|БИБ-02-23|БИБ-03-24|БИБ-04-22|БИБ-05-23|БИБ-06-24|ИСТ-01-22|ИСТ-02-23|ИСТ-03-24|ИСТ-04-22|ИСТ-05-23|ПИНФ-01-22|ПИНФ-02-23|ПИНФ-03-24|ПИНФ-04-22|МО-01-23|МО-02-24|МО-03-22', '|')[gid - 1] AS gname
MATCH (st:Student {record_book: rb})
MATCH (g:Group {name: gname})
CREATE (st)-[:MEMBER_OF]->(g);

// ---------- Курсы (10; semester/is_elective перенесены в PLAN_INCLUDES, + description) ----------
UNWIND [
 {id: 1, code: '09.ПАС',  name: 'Проектирование архитектуры программных систем',
  desc: 'Теория и практика проектирования архитектуры программных систем: стили, паттерны, нефункциональные требования и архитектурные компромиссы.'},
 {id: 2, code: '09.БД',   name: 'Базы данных',
  desc: 'Реляционная модель данных, SQL, нормализация, транзакции и индексы; проектирование и администрирование баз данных.'},
 {id: 3, code: '10.ИБ',   name: 'Информационная безопасность',
  desc: 'Угрозы информационной безопасности, криптографические методы защиты и практика защиты веб-приложений.'},
 {id: 4, code: '09.МА',   name: 'Микросервисные архитектуры',
  desc: 'Проектирование распределённых систем на микросервисах: декомпозиция домена, Saga, service mesh и наблюдаемость.'},
 {id: 5, code: '09.DEV',  name: 'DevOps и CI/CD',
  desc: 'Непрерывная интеграция и доставка: пайплайны CI/CD, контейнеризация и деплой в Kubernetes.'},
 {id: 6, code: '09.ОС',   name: 'Операционные системы',
  desc: 'Устройство операционных систем: процессы и потоки, планирование, память, файловые системы и синхронизация.'},
 {id: 7, code: '09.Web',  name: 'Web-программирование',
  desc: 'Клиент-серверная разработка веб-приложений: HTTP, REST API, фронтенд-фреймворки и развёртывание.'},
 {id: 8, code: '09.Тест', name: 'Тестирование программного обеспечения',
  desc: 'Уровни и виды тестирования, пирамида тестов, модульные и сквозные тесты, автоматизация в CI.'},
 {id: 9, code: '02.Алг',  name: 'Алгоритмы и структуры данных',
  desc: 'Асимптотический анализ, сортировки и поиск, графовые алгоритмы и базовые структуры данных.'},
 {id: 10, code: '09.МЛ',  name: 'Машинное обучение',
  desc: 'Классические задачи машинного обучения: регрессия, классификация, метрики качества и нейронные сети.'}
] AS row
CREATE (:Course {course_id: row.id, code: row.code, name: row.name, description: row.desc});

// ---------- Учебный план: Specialty -PLAN_INCLUDES-> Course (M:N, = specialty_courses в PostgreSQL) ----------
// Одна дисциплина может относиться к нескольким специальностям;
// semester и course_type живут на ребре, а не в узле Course.
UNWIND [
 {sp: '09.03.01', cid: 1,  sem: 6, t: 'mandatory'}, {sp: '09.03.01', cid: 2,  sem: 4, t: 'mandatory'}, {sp: '09.03.01', cid: 4,  sem: 6, t: 'elective'},
 {sp: '09.03.04', cid: 1,  sem: 6, t: 'mandatory'}, {sp: '09.03.04', cid: 2,  sem: 4, t: 'mandatory'}, {sp: '09.03.04', cid: 7,  sem: 5, t: 'elective'}, {sp: '09.03.04', cid: 8,  sem: 6, t: 'elective'},
 {sp: '10.03.01', cid: 3,  sem: 5, t: 'mandatory'}, {sp: '10.03.01', cid: 6,  sem: 4, t: 'mandatory'}, {sp: '10.03.01', cid: 10, sem: 6, t: 'elective'},
 {sp: '09.03.02', cid: 2,  sem: 4, t: 'mandatory'}, {sp: '09.03.02', cid: 6,  sem: 4, t: 'mandatory'}, {sp: '09.03.02', cid: 7,  sem: 5, t: 'elective'},
 {sp: '09.03.03', cid: 9,  sem: 3, t: 'mandatory'}, {sp: '09.03.03', cid: 7,  sem: 5, t: 'mandatory'}, {sp: '09.03.03', cid: 8,  sem: 6, t: 'elective'},
 {sp: '02.03.03', cid: 9,  sem: 3, t: 'mandatory'}, {sp: '02.03.03', cid: 6,  sem: 4, t: 'mandatory'}, {sp: '02.03.03', cid: 10, sem: 6, t: 'elective'}, {sp: '02.03.03', cid: 4,  sem: 6, t: 'elective'}
] AS row
MATCH (s:Specialty {code: row.sp}), (c:Course {course_id: row.cid})
CREATE (s)-[:PLAN_INCLUDES {semester: row.sem, course_type: row.t}]->(c);

// ---------- Связи дисциплин (= course_relations в PostgreSQL) ----------
// prerequisite: исходная дисциплина предшествует целевой
UNWIND [
 {a: 9, b: 2},   // Алгоритмы -> Базы данных
 {a: 2, b: 1},   // Базы данных -> Проектирование архитектуры ПС
 {a: 6, b: 3},   // Операционные системы -> Информационная безопасность
 {a: 9, b: 10}   // Алгоритмы -> Машинное обучение
] AS row
MATCH (ca:Course {course_id: row.a}), (cb:Course {course_id: row.b})
CREATE (ca)-[:PREREQUISITE_OF]->(cb);

// continuation: дисциплина b — продолжение дисциплины a
UNWIND [
 {a: 1, b: 4},   // Микросервисные архитектуры — продолжение ПАС
 {a: 7, b: 8}    // Тестирование ПО — продолжение Web-программирования
] AS row
MATCH (ca:Course {course_id: row.a}), (cb:Course {course_id: row.b})
CREATE (cb)-[:CONTINUATION_OF]->(ca);

// related: связанные дисциплины (направление условно)
UNWIND [
 {a: 4, b: 5},   // Микросервисные архитектуры <-> DevOps и CI/CD
 {a: 2, b: 7}    // Базы данных <-> Web-программирование
] AS row
MATCH (ca:Course {course_id: row.a}), (cb:Course {course_id: row.b})
CREATE (ca)-[:RELATED_TO]->(cb);

// ---------- Занятия (30) ----------
UNWIND [
 {id: 1,  type: 'lecture',  title: 'Введение в архитектуру ПО', ord: 1},
 {id: 2,  type: 'practice', title: 'Проектирование микросервисов', ord: 2},
 {id: 3,  type: 'lab',      title: 'Разработка API Gateway', ord: 3},
 {id: 4,  type: 'lecture',  title: 'Реляционная модель данных', ord: 1},
 {id: 5,  type: 'practice', title: 'SQL: сложные запросы', ord: 2},
 {id: 6,  type: 'lab',      title: 'Проектирование и нормализация БД', ord: 3},
 {id: 7,  type: 'lecture',  title: 'Основы криптографии', ord: 1},
 {id: 8,  type: 'practice', title: 'Анализ уязвимостей веб-приложений', ord: 2},
 {id: 9,  type: 'lab',      title: 'Настройка межсетевого экрана', ord: 3},
 {id: 10, type: 'lecture',  title: 'Паттерны микросервисов', ord: 1},
 {id: 11, type: 'practice', title: 'Docker и контейнеризация', ord: 2},
 {id: 12, type: 'lab',      title: 'Service Mesh на практике', ord: 3},
 {id: 13, type: 'lecture',  title: 'Введение в CI/CD', ord: 1},
 {id: 14, type: 'practice', title: 'Пайплайн сборки в GitHub Actions', ord: 2},
 {id: 15, type: 'lab',      title: 'Деплой в Kubernetes', ord: 3},
 {id: 16, type: 'lecture',  title: 'Процессы и потоки', ord: 1},
 {id: 17, type: 'practice', title: 'Системные вызовы POSIX', ord: 2},
 {id: 18, type: 'lab',      title: 'Синхронизация потоков', ord: 3},
 {id: 19, type: 'lecture',  title: 'Архитектура веб-приложений', ord: 1},
 {id: 20, type: 'practice', title: 'REST API на Python', ord: 2},
 {id: 21, type: 'lab',      title: 'Одностраничное приложение', ord: 3},
 {id: 22, type: 'lecture',  title: 'Виды и уровни тестирования', ord: 1},
 {id: 23, type: 'practice', title: 'Модульные тесты на pytest', ord: 2},
 {id: 24, type: 'lab',      title: 'Автоматизация UI-тестов', ord: 3},
 {id: 25, type: 'lecture',  title: 'Сложность алгоритмов', ord: 1},
 {id: 26, type: 'practice', title: 'Сортировки и поиск', ord: 2},
 {id: 27, type: 'lab',      title: 'Графовые алгоритмы', ord: 3},
 {id: 28, type: 'lecture',  title: 'Задачи и типы машинного обучения', ord: 1},
 {id: 29, type: 'practice', title: 'Регрессия и классификация', ord: 2},
 {id: 30, type: 'lab',      title: 'Нейронная сеть на PyTorch', ord: 3}
] AS row
CREATE (:Lesson {lesson_id: row.id, lesson_type: row.type, title: row.title, order_number: row.ord});

// ---------- Курс -> Занятия ----------
UNWIND [
 {code: '09.ПАС',  ids: [1, 2, 3]},
 {code: '09.БД',   ids: [4, 5, 6]},
 {code: '10.ИБ',   ids: [7, 8, 9]},
 {code: '09.МА',   ids: [10, 11, 12]},
 {code: '09.DEV',  ids: [13, 14, 15]},
 {code: '09.ОС',   ids: [16, 17, 18]},
 {code: '09.Web',  ids: [19, 20, 21]},
 {code: '09.Тест', ids: [22, 23, 24]},
 {code: '02.Алг',  ids: [25, 26, 27]},
 {code: '09.МЛ',   ids: [28, 29, 30]}
] AS row
MATCH (c:Course {code: row.code}), (l:Lesson)
WHERE l.lesson_id IN row.ids
CREATE (c)-[:HAS_LESSON]->(l);

// ---------- Расписание (204: 34 группы x 2 недели x 3 пары) ----------
UNWIND range(1, 34) AS gid
UNWIND range(0, 1) AS w
UNWIND range(0, 2) AS j
WITH gid, w, j, ((gid - 1) * 3 + j) AS ph,
     CASE WHEN gid <= 10 THEN 1 WHEN gid <= 16 THEN 2 WHEN gid <= 22 THEN 3
          WHEN gid <= 27 THEN 4 WHEN gid <= 31 THEN 5 ELSE 6 END AS sp,
     (gid - 1) * 6 + w * 3 + j + 1 AS sid
WITH gid, sid, ph, w, j,
     CASE sp WHEN 1 THEN 1 WHEN 2 THEN 1 WHEN 3 THEN 3 WHEN 4 THEN 2 WHEN 5 THEN 9 ELSE 9 END AS a,
     CASE sp WHEN 1 THEN 2 WHEN 2 THEN 2 WHEN 3 THEN 6 WHEN 4 THEN 6 WHEN 5 THEN 7 ELSE 6 END AS b
WITH gid, sid, ph, w, j, a, b,
     CASE WHEN w = 0 THEN CASE j WHEN 0 THEN (a - 1) * 3 + 1 WHEN 1 THEN (a - 1) * 3 + 2 ELSE (b - 1) * 3 + 1 END
          ELSE CASE j WHEN 0 THEN (a - 1) * 3 + 3 WHEN 1 THEN (b - 1) * 3 + 2 ELSE (b - 1) * 3 + 3 END END AS lid
CREATE (:Schedule {
  schedule_id: sid,
  lesson_title: split('Введение в архитектуру ПО|Проектирование микросервисов|Разработка API Gateway|Реляционная модель данных|SQL: сложные запросы|Проектирование и нормализация БД|Основы криптографии|Анализ уязвимостей веб-приложений|Настройка межсетевого экрана|Паттерны микросервисов|Docker и контейнеризация|Service Mesh на практике|Введение в CI/CD|Пайплайн сборки в GitHub Actions|Деплой в Kubernetes|Процессы и потоки|Системные вызовы POSIX|Синхронизация потоков|Архитектура веб-приложений|REST API на Python|Одностраничное приложение|Виды и уровни тестирования|Модульные тесты на pytest|Автоматизация UI-тестов|Сложность алгоритмов|Сортировки и поиск|Графовые алгоритмы|Задачи и типы машинного обучения|Регрессия и классификация|Нейронная сеть на PyTorch', '|')[lid - 1],
  group: split('ИКБО-01-22|ИКБО-02-23|ИКБО-03-24|ИКБО-04-22|ИКБО-05-23|ИКБО-06-24|ИКБО-07-22|ИКБО-08-23|ИКБО-09-24|ИКБО-10-22|ИП-01-22|ИП-02-23|ИП-03-24|ИП-04-22|ИП-05-23|ИП-06-24|БИБ-01-23|БИБ-02-23|БИБ-03-24|БИБ-04-22|БИБ-05-23|БИБ-06-24|ИСТ-01-22|ИСТ-02-23|ИСТ-03-24|ИСТ-04-22|ИСТ-05-23|ПИНФ-01-22|ПИНФ-02-23|ПИНФ-03-24|ПИНФ-04-22|МО-01-23|МО-02-24|МО-03-22', '|')[gid - 1],
  date: date('2026-09-21') + duration({days: w * 7 + ph % 5}),
  start_time: split('09:00|10:40|11:40|14:00', '|')[ph % 4],
  end_time: split('10:30|12:10|13:10|15:30', '|')[ph % 4],
  room: split('А-301|А-302|А-303|Л-102|Л-105|Б-201|Б-105|Б-107|В-401|В-405|В-410', '|')[ph % 11]
});

// ---------- STUDIES (обязательные) и CHOOSES (электив) ----------
// (= student_courses в PostgreSQL; семестр зачисления выводится через цепочку
//  Student -MEMBER_OF-> Group -BELONGS_TO-> Specialty -PLAN_INCLUDES-> Course)
// Тип зачисления соответствует учебному плану: для ПрИнф (09.03.03)
// Web-программирование в плане elective, поэтому зачисление на него —
// ребро CHOOSES для всех студентов специальности.
UNWIND range(1, 1000) AS i
WITH i, ((i - 1) % 34) + 1 AS gid, ((i - 1) / 34) + 1 AS kin
WITH i, (CASE WHEN gid < 10 THEN '0' ELSE '' END) + toString(gid) +
        (CASE WHEN kin < 10 THEN '00' WHEN kin < 100 THEN '0' ELSE '' END) + toString(kin) AS rb,
    CASE WHEN gid <= 10 THEN 1 WHEN gid <= 16 THEN 2 WHEN gid <= 22 THEN 3
         WHEN gid <= 27 THEN 4 WHEN gid <= 31 THEN 5 ELSE 6 END AS sp
WITH i, rb, sp,
     CASE sp WHEN 1 THEN 1 WHEN 2 THEN 1 WHEN 3 THEN 3 WHEN 4 THEN 2 WHEN 5 THEN 9 ELSE 9 END AS a,
     CASE sp WHEN 1 THEN 2 WHEN 2 THEN 2 WHEN 3 THEN 6 WHEN 4 THEN 6 WHEN 5 THEN 7 ELSE 6 END AS b,
     CASE sp WHEN 1 THEN [4] WHEN 2 THEN [7, 8] WHEN 3 THEN [10] WHEN 4 THEN [7] WHEN 5 THEN [8] ELSE [10, 4] END AS electives
WITH i, rb,
     [a] + (CASE WHEN sp = 5 THEN [] ELSE [b] END) AS mandatory_ids,
     [x IN electives | {id: x, forced: false}] +
     [x IN (CASE WHEN sp = 5 THEN [7] ELSE [] END) | {id: x, forced: true}] AS elective_items
MATCH (st:Student {record_book: rb})
UNWIND mandatory_ids AS mid
MATCH (cm:Course {course_id: mid})
CREATE (st)-[:STUDIES]->(cm)
WITH DISTINCT st, i, elective_items
UNWIND elective_items AS ei
WITH st, i, ei.id AS eid, ei.forced AS forced
WHERE forced OR (i * 17 + eid) % 100 < 50
MATCH (c:Course {course_id: eid})
CREATE (st)-[:CHOOSES]->(c);

// ---------- ATTENDED / MISSED (~6000 связей) ----------
UNWIND range(1, 1000) AS i
WITH i, ((i - 1) % 34) + 1 AS gid, ((i - 1) / 34) + 1 AS kin
WITH i, (CASE WHEN gid < 10 THEN '0' ELSE '' END) + toString(gid) +
        (CASE WHEN kin < 10 THEN '00' WHEN kin < 100 THEN '0' ELSE '' END) + toString(kin) AS rb,
    (gid - 1) * 6 AS base
UNWIND range(base + 1, base + 6) AS sid
MATCH (st:Student {record_book: rb})
MATCH (sc:Schedule {schedule_id: sid})
WITH st, sc, (i * 17 + sid) % 100 < 85 AS attended
FOREACH (_ IN CASE WHEN attended THEN [1] ELSE [] END | CREATE (st)-[:ATTENDED]->(sc))
FOREACH (_ IN CASE WHEN NOT attended THEN [1] ELSE [] END | CREATE (st)-[:MISSED]->(sc));
