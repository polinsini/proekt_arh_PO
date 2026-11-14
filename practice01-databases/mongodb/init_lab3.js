// ============================================================
// LAB 3 (актуализировано, практика 3): MongoDB 7 — DOCUMENT / COMPOSITION
// Коллекция group_profiles: группа одним документом
//   (группа, enrollment_year, специальность, students[], courses[], lessons[])
// Коллекция university_hierarchy:
//   university -> institutes[] -> departments[] -> specialties[] -> groups[]
// Коллекция course_relations: связи дисциплин (= PostgreSQL course_relations)
// Масштаб: 1000 студентов, 34 группы, 6 кафедр, 6 специальностей, 10 курсов
//
// Соответствие новой модели PostgreSQL:
//   - учебный план (specialty_courses) -> SPECIALTIES[*].plan: {code, semester, type}
//     (semester больше НЕ свойство курса — он в учебном плане специальности)
//   - enrollment_year (student_groups) -> enrollment_year группы
//   - description (courses) -> COURSES[*].description
// ============================================================

// ---------- Очистка старых коллекций ----------
db.orders.drop();
db.lecture_materials.drop();
db.students.drop();
db.group_profiles.drop();
db.university_hierarchy.drop();
db.course_relations.drop();

// ---------- Справочники для генерации ----------
const SURNAME = ['Иванов', 'Смирнов', 'Кузнецов', 'Соколов', 'Попов', 'Лебедев', 'Козлов', 'Новиков',
                 'Морозов', 'Волков', 'Петров', 'Егоров', 'Павлов', 'Семёнов', 'Голубев', 'Виноградов',
                 'Богданов', 'Воробьёв', 'Фёдоров', 'Михайлов', 'Беляев', 'Тарасов', 'Белов', 'Комаров',
                 'Орлов', 'Киселёв', 'Макаров', 'Никитин', 'Зайцев', 'Соловьёв'];
const MALE_NAME = ['Иван', 'Алексей', 'Дмитрий', 'Сергей', 'Андрей', 'Максим', 'Никита', 'Павел', 'Артём', 'Кирилл'];
const FEMALE_NAME = ['Анна', 'Мария', 'Елена', 'Екатерина', 'Ольга', 'Наталья', 'Ирина', 'Светлана', 'Татьяна', 'Юлия'];
const MALE_PATR = ['Иванович', 'Сергеевич', 'Андреевич', 'Дмитриевич', 'Александрович', 'Николаевич', 'Петрович', 'Михайлович'];
const FEMALE_PATR = ['Ивановна', 'Сергеевна', 'Андреевна', 'Дмитриевна', 'Александровна', 'Николаевна', 'Петровна', 'Михайловна'];

const TRANSLIT = { 'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e', 'ж': 'z', 'з': 'z',
                   'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r',
                   'с': 's', 'т': 't', 'у': 'u', 'ф': 'f', 'х': 'h', 'ц': 'c', 'ч': 'c', 'ш': 's', 'щ': 's',
                   'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'u', 'я': 'a' };
function translit(s) {
  return s.toLowerCase().split('').map(c => TRANSLIT[c] ?? c).join('');
}

// ---------- Специальности и группы ----------
// plan = учебный план специальности (= specialty_courses: код, семестр, тип)
const SPECIALTIES = {
  '09.03.01': { name: 'Информатика и вычислительная техника',
                department: 'Кафедра архитектуры программных систем', institute: 'ИПТИП',
                plan: [ { code: '09.ПАС', semester: 6, type: 'mandatory' },
                        { code: '09.БД',  semester: 4, type: 'mandatory' },
                        { code: '09.МА',  semester: 6, type: 'elective' } ] },
  '09.03.04': { name: 'Программная инженерия',
                department: 'Кафедра индустриального программирования', institute: 'ИПТИП',
                plan: [ { code: '09.ПАС',  semester: 6, type: 'mandatory' },
                        { code: '09.БД',   semester: 4, type: 'mandatory' },
                        { code: '09.Web',  semester: 5, type: 'elective' },
                        { code: '09.Тест', semester: 6, type: 'elective' } ] },
  '10.03.01': { name: 'Информационная безопасность',
                department: 'Кафедра информационной безопасности', institute: 'ИПТИП',
                plan: [ { code: '10.ИБ', semester: 5, type: 'mandatory' },
                        { code: '09.ОС', semester: 4, type: 'mandatory' },
                        { code: '09.МЛ', semester: 6, type: 'elective' } ] },
  '09.03.02': { name: 'Информационные системы и технологии',
                department: 'Кафедра вычислительной техники', institute: 'ИЭТ',
                plan: [ { code: '09.БД',  semester: 4, type: 'mandatory' },
                        { code: '09.ОС',  semester: 4, type: 'mandatory' },
                        { code: '09.Web', semester: 5, type: 'elective' } ] },
  '09.03.03': { name: 'Прикладная информатика',
                department: 'Кафедра прикладной информатики', institute: 'ИЭТ',
                plan: [ { code: '02.Алг',  semester: 3, type: 'mandatory' },
                        { code: '09.Web',  semester: 5, type: 'elective' },
                        { code: '09.Тест', semester: 6, type: 'elective' } ] },
  '02.03.03': { name: 'Математическое обеспечение и администрирование информационных систем',
                department: 'Кафедра математического обеспечения', institute: 'ИЭТ',
                plan: [ { code: '02.Алг', semester: 3, type: 'mandatory' },
                        { code: '09.ОС',  semester: 4, type: 'mandatory' },
                        { code: '09.МЛ',  semester: 6, type: 'elective' },
                        { code: '09.МА',  semester: 6, type: 'elective' } ] }
};

const GROUPS = [
  { name: 'ИКБО-01-22', year: 22, spec: '09.03.01' }, { name: 'ИКБО-02-23', year: 23, spec: '09.03.01' },
  { name: 'ИКБО-03-24', year: 24, spec: '09.03.01' }, { name: 'ИКБО-04-22', year: 22, spec: '09.03.01' },
  { name: 'ИКБО-05-23', year: 23, spec: '09.03.01' }, { name: 'ИКБО-06-24', year: 24, spec: '09.03.01' },
  { name: 'ИКБО-07-22', year: 22, spec: '09.03.01' }, { name: 'ИКБО-08-23', year: 23, spec: '09.03.01' },
  { name: 'ИКБО-09-24', year: 24, spec: '09.03.01' }, { name: 'ИКБО-10-22', year: 22, spec: '09.03.01' },
  { name: 'ИП-01-22', year: 22, spec: '09.03.04' },  { name: 'ИП-02-23', year: 23, spec: '09.03.04' },
  { name: 'ИП-03-24', year: 24, spec: '09.03.04' },  { name: 'ИП-04-22', year: 22, spec: '09.03.04' },
  { name: 'ИП-05-23', year: 23, spec: '09.03.04' },  { name: 'ИП-06-24', year: 24, spec: '09.03.04' },
  { name: 'БИБ-01-23', year: 23, spec: '10.03.01' }, { name: 'БИБ-02-23', year: 23, spec: '10.03.01' },
  { name: 'БИБ-03-24', year: 24, spec: '10.03.01' }, { name: 'БИБ-04-22', year: 22, spec: '10.03.01' },
  { name: 'БИБ-05-23', year: 23, spec: '10.03.01' }, { name: 'БИБ-06-24', year: 24, spec: '10.03.01' },
  { name: 'ИСТ-01-22', year: 22, spec: '09.03.02' }, { name: 'ИСТ-02-23', year: 23, spec: '09.03.02' },
  { name: 'ИСТ-03-24', year: 24, spec: '09.03.02' }, { name: 'ИСТ-04-22', year: 22, spec: '09.03.02' },
  { name: 'ИСТ-05-23', year: 23, spec: '09.03.02' },
  { name: 'ПИНФ-01-22', year: 22, spec: '09.03.03' }, { name: 'ПИНФ-02-23', year: 23, spec: '09.03.03' },
  { name: 'ПИНФ-03-24', year: 24, spec: '09.03.03' }, { name: 'ПИНФ-04-22', year: 22, spec: '09.03.03' },
  { name: 'МО-01-23', year: 23, spec: '02.03.03' },  { name: 'МО-02-24', year: 24, spec: '02.03.03' },
  { name: 'МО-03-22', year: 22, spec: '02.03.03' }
];

// ---------- Курсы и занятия ----------
// semester в курсе больше не хранится — он в учебном плане специальности
// (= новая структура PostgreSQL: courses без semester/is_elective, с description)
const COURSES = {
  '09.ПАС':  { name: 'Проектирование архитектуры программных систем',
               description: 'Теория и практика проектирования архитектуры программных систем: стили, паттерны, нефункциональные требования и архитектурные компромиссы.' },
  '09.БД':   { name: 'Базы данных',
               description: 'Реляционная модель данных, SQL, нормализация, транзакции и индексы; проектирование и администрирование баз данных.' },
  '10.ИБ':   { name: 'Информационная безопасность',
               description: 'Угрозы информационной безопасности, криптографические методы защиты и практика защиты веб-приложений.' },
  '09.МА':   { name: 'Микросервисные архитектуры',
               description: 'Проектирование распределённых систем на микросервисах: декомпозиция домена, Saga, service mesh и наблюдаемость.' },
  '09.DEV':  { name: 'DevOps и CI/CD',
               description: 'Непрерывная интеграция и доставка: пайплайны CI/CD, контейнеризация и деплой в Kubernetes.' },
  '09.ОС':   { name: 'Операционные системы',
               description: 'Устройство операционных систем: процессы и потоки, планирование, память, файловые системы и синхронизация.' },
  '09.Web':  { name: 'Web-программирование',
               description: 'Клиент-серверная разработка веб-приложений: HTTP, REST API, фронтенд-фреймворки и развёртывание.' },
  '09.Тест': { name: 'Тестирование программного обеспечения',
               description: 'Уровни и виды тестирования, пирамида тестов, модульные и сквозные тесты, автоматизация в CI.' },
  '02.Алг':  { name: 'Алгоритмы и структуры данных',
               description: 'Асимптотический анализ, сортировки и поиск, графовые алгоритмы и базовые структуры данных.' },
  '09.МЛ':   { name: 'Машинное обучение',
               description: 'Классические задачи машинного обучения: регрессия, классификация, метрики качества и нейронные сети.' }
};

const LESSONS = {
  '09.ПАС':  [['lecture', 'Введение в архитектуру ПО', 1], ['practice', 'Проектирование микросервисов', 2], ['lab', 'Разработка API Gateway', 3]],
  '09.БД':   [['lecture', 'Реляционная модель данных', 1], ['practice', 'SQL: сложные запросы', 2], ['lab', 'Проектирование и нормализация БД', 3]],
  '10.ИБ':   [['lecture', 'Основы криптографии', 1], ['practice', 'Анализ уязвимостей веб-приложений', 2], ['lab', 'Настройка межсетевого экрана', 3]],
  '09.МА':   [['lecture', 'Паттерны микросервисов', 1], ['practice', 'Docker и контейнеризация', 2], ['lab', 'Service Mesh на практике', 3]],
  '09.DEV':  [['lecture', 'Введение в CI/CD', 1], ['practice', 'Пайплайн сборки в GitHub Actions', 2], ['lab', 'Деплой в Kubernetes', 3]],
  '09.ОС':   [['lecture', 'Процессы и потоки', 1], ['practice', 'Системные вызовы POSIX', 2], ['lab', 'Синхронизация потоков', 3]],
  '09.Web':  [['lecture', 'Архитектура веб-приложений', 1], ['practice', 'REST API на Python', 2], ['lab', 'Одностраничное приложение', 3]],
  '09.Тест': [['lecture', 'Виды и уровни тестирования', 1], ['practice', 'Модульные тесты на pytest', 2], ['lab', 'Автоматизация UI-тестов', 3]],
  '02.Алг':  [['lecture', 'Сложность алгоритмов', 1], ['practice', 'Сортировки и поиск', 2], ['lab', 'Графовые алгоритмы', 3]],
  '09.МЛ':   [['lecture', 'Задачи и типы машинного обучения', 1], ['practice', 'Регрессия и классификация', 2], ['lab', 'Нейронная сеть на PyTorch', 3]]
};

// ---------- group_profiles ----------
const groupDocs = GROUPS.map(g => {
  const sp = SPECIALTIES[g.spec];
  const groupCourses = sp.plan.map(p => ({
    code: p.code, name: COURSES[p.code].name, description: COURSES[p.code].description,
    semester: p.semester, enrollment: p.type
  }));
  const groupLessons = groupCourses.flatMap(c =>
    LESSONS[c.code].map(l => ({ course_code: c.code, lesson_type: l[0], title: l[1], order_number: l[2] }))
  );
  return {
    group: g.name,
    enrollment_year: 2000 + g.year,                      // = student_groups.enrollment_year
    course_number: 2026 - (2000 + g.year),               // согласован с годом поступления
    specialty: { code: g.spec, name: sp.name },
    department: sp.department,
    institute: sp.institute,
    students: [],
    courses: groupCourses,
    lessons: groupLessons
  };
});

// 1000 студентов по единой формуле
for (let i = 1; i <= 1000; i++) {
  const gid = ((i - 1) % 34) + 1;
  const kin = Math.floor((i - 1) / 34) + 1;
  const isMale = i % 2 === 1;
  const sn = SURNAME[(i * 7) % SURNAME.length];
  const snFull = isMale ? sn : sn + 'а';
  const fn = isMale ? MALE_NAME[(i * 3) % MALE_NAME.length] : FEMALE_NAME[(i * 3) % FEMALE_NAME.length];
  const pt = isMale ? MALE_PATR[(i * 7) % MALE_PATR.length] : FEMALE_PATR[(i * 7) % FEMALE_PATR.length];
  const rb = String(gid).padStart(2, '0') + String(kin).padStart(3, '0');
  const v = (i * 13) % 100;
  const status = v < 88 ? 'active' : (v < 95 ? 'academic_leave' : 'expelled');
  const email = translit(snFull) + '.' + translit(fn) + '.' + String(i).padStart(4, '0') + '@example.edu';
  groupDocs[gid - 1].students.push({
    record_book: rb,
    full_name: snFull + ' ' + fn + ' ' + pt,
    email: email,
    status: status
  });
}

db.group_profiles.insertMany(groupDocs);

// ---------- university_hierarchy ----------
db.university_hierarchy.insertOne({
  university: {
    name: 'Российский технологический университет',
    short_name: 'РТУ МИРЭА',
    city: 'Москва'
  },
  institutes: [
    {
      name: 'Институт перспективных технологий и индустриального программирования',
      short_name: 'ИПТИП',
      departments: [
        {
          name: 'Кафедра архитектуры программных систем',
          short_name: 'АПС',
          faculty: 'Факультет программной инженерии',
          specialties: [
            {
              code: '09.03.01',
              name: 'Информатика и вычислительная техника',
              groups: GROUPS.filter(g => g.spec === '09.03.01').map(g => ({ name: g.name, enrollment_year: 2000 + g.year, course_number: 2026 - (2000 + g.year) }))
            }
          ]
        },
        {
          name: 'Кафедра индустриального программирования',
          short_name: 'ИП',
          faculty: 'Факультет программной инженерии',
          specialties: [
            {
              code: '09.03.04',
              name: 'Программная инженерия',
              groups: GROUPS.filter(g => g.spec === '09.03.04').map(g => ({ name: g.name, enrollment_year: 2000 + g.year, course_number: 2026 - (2000 + g.year) }))
            }
          ]
        },
        {
          name: 'Кафедра информационной безопасности',
          short_name: 'ИБ',
          faculty: 'Факультет кибербезопасности',
          specialties: [
            {
              code: '10.03.01',
              name: 'Информационная безопасность',
              groups: GROUPS.filter(g => g.spec === '10.03.01').map(g => ({ name: g.name, enrollment_year: 2000 + g.year, course_number: 2026 - (2000 + g.year) }))
            }
          ]
        }
      ]
    },
    {
      name: 'Институт электронной техники',
      short_name: 'ИЭТ',
      departments: [
        {
          name: 'Кафедра вычислительной техники',
          short_name: 'ВТ',
          faculty: 'Факультет вычислительной техники',
          specialties: [
            {
              code: '09.03.02',
              name: 'Информационные системы и технологии',
              groups: GROUPS.filter(g => g.spec === '09.03.02').map(g => ({ name: g.name, enrollment_year: 2000 + g.year, course_number: 2026 - (2000 + g.year) }))
            }
          ]
        },
        {
          name: 'Кафедра прикладной информатики',
          short_name: 'ПрИнф',
          faculty: 'Факультет вычислительной техники',
          specialties: [
            {
              code: '09.03.03',
              name: 'Прикладная информатика',
              groups: GROUPS.filter(g => g.spec === '09.03.03').map(g => ({ name: g.name, enrollment_year: 2000 + g.year, course_number: 2026 - (2000 + g.year) }))
            }
          ]
        },
        {
          name: 'Кафедра математического обеспечения',
          short_name: 'МО',
          faculty: 'Факультет вычислительной техники',
          specialties: [
            {
              code: '02.03.03',
              name: 'Математическое обеспечение и администрирование информационных систем',
              groups: GROUPS.filter(g => g.spec === '02.03.03').map(g => ({ name: g.name, enrollment_year: 2000 + g.year, course_number: 2026 - (2000 + g.year) }))
            }
          ]
        }
      ]
    }
  ]
});

// ---------- course_relations: связи дисциплин (= PostgreSQL course_relations) ----------
// prerequisite: source предшествует target; continuation: target — продолжение source;
// related: связанные дисциплины
db.course_relations.insertMany([
  { source_course_code: '02.Алг',  target_course_code: '09.БД',   relation_type: 'prerequisite' },  // Алгоритмы -> Базы данных
  { source_course_code: '09.БД',   target_course_code: '09.ПАС',  relation_type: 'prerequisite' },  // Базы данных -> ПАС
  { source_course_code: '09.ОС',   target_course_code: '10.ИБ',   relation_type: 'prerequisite' },  // ОС -> Информационная безопасность
  { source_course_code: '02.Алг',  target_course_code: '09.МЛ',   relation_type: 'prerequisite' },  // Алгоритмы -> Машинное обучение
  { source_course_code: '09.ПАС',  target_course_code: '09.МА',   relation_type: 'continuation' },  // МА — продолжение ПАС
  { source_course_code: '09.Web',  target_course_code: '09.Тест', relation_type: 'continuation' },  // Тест — продолжение Web
  { source_course_code: '09.МА',   target_course_code: '09.DEV',  relation_type: 'related' },       // МА <-> DevOps
  { source_course_code: '09.БД',   target_course_code: '09.Web',  relation_type: 'related' }        // БД <-> Web
]);

print('group_profiles: ' + db.group_profiles.countDocuments() + ' документов, студентов: ' +
      db.group_profiles.aggregate([{ $project: { n: { $size: '$students' } } }, { $group: { _id: null, total: { $sum: '$n' } } }]).toArray()[0].total);
print('university_hierarchy: ' + db.university_hierarchy.countDocuments());
print('course_relations: ' + db.course_relations.countDocuments() + ' связей');
