import os
from datetime import date
from fastapi import FastAPI, Header, HTTPException, Query
import httpx
import psycopg
from psycopg.rows import dict_row
import redis

app = FastAPI(title='Lab1: lowest lecture attendance')
ES_URL = os.getenv('ES_URL', 'http://practice01-elasticsearch:9200')
PG_DSN = os.environ['PG_DSN']
REDIS_URL = os.getenv('REDIS_URL', '')
INTERNAL_TOKEN = os.environ['INTERNAL_TOKEN']

# ES supplies full-text matching; PG remains authoritative for attendance and students.
# A matching course MUST have a lecture hit, not just an arbitrary practical/lab hit.
SQL = '''
WITH matches AS (
    SELECT l.lesson_id, l.course_id
    FROM lessons l
    WHERE l.lesson_id = ANY(%(lesson_ids)s::int[]) AND l.lesson_type = 'lecture'
), eligible AS (
    SELECT st.student_id, st.record_book_number, st.full_name, st.email,
           st.status AS student_status, st.group_id, grp.group_number,
           grp.course_number, sp.code AS specialty_code, sp.name AS specialty_name,
           d.name AS department_name, f.name AS faculty_name,
           i.name AS institute_name, u.name AS university_name,
           sch.schedule_id, sch.lesson_date
    FROM matches m
    JOIN schedule sch ON sch.lesson_id = m.lesson_id
    JOIN student_groups grp ON grp.group_id = sch.group_id
    JOIN students st ON st.group_id = grp.group_id
    JOIN student_courses sc ON sc.student_id = st.student_id AND sc.course_id = m.course_id
    JOIN specialties sp ON sp.specialty_id = grp.specialty_id
    JOIN departments d ON d.department_id = sp.department_id
    JOIN faculties f ON f.faculty_id = d.faculty_id
    JOIN institutes i ON i.institute_id = f.institute_id
    JOIN universities u ON u.university_id = i.university_id
    WHERE sch.lesson_date BETWEEN %(date_from)s AND %(date_to)s
), counted AS (
    SELECT e.*, a.status AS attendance_status
    FROM eligible e
    LEFT JOIN attendance a
      ON a.student_id = e.student_id AND a.schedule_id = e.schedule_id
      AND a.week_start_date = date_trunc('week', e.lesson_date)::date
      AND a.week_start_date BETWEEN date_trunc('week', %(date_from)s::date)::date
                                 AND date_trunc('week', %(date_to)s::date)::date
)
SELECT student_id, record_book_number, full_name, email, student_status,
       group_id, group_number, course_number, specialty_code, specialty_name,
       department_name, faculty_name, institute_name, university_name,
       COUNT(DISTINCT schedule_id) FILTER (
        WHERE attendance_status IN ('attended', 'missed')
       ) AS scheduled_lectures,
       COUNT(DISTINCT schedule_id) FILTER (WHERE attendance_status = 'attended') AS attended_lectures,
        ROUND(
            100.0 * COUNT(DISTINCT schedule_id) FILTER (
                WHERE attendance_status = 'attended'
            )
            / NULLIF(
                COUNT(DISTINCT schedule_id) FILTER (
                    WHERE attendance_status IN ('attended', 'missed')
                ),
                0
            ),
            2
        ) AS attendance_percent
FROM counted
GROUP BY student_id, record_book_number, full_name, email, student_status,
         group_id, group_number, course_number, specialty_code, specialty_name,
         department_name, faculty_name, institute_name, university_name
HAVING COUNT(DISTINCT schedule_id) FILTER (
    WHERE attendance_status IN ('attended', 'missed')
) > 0
ORDER BY attendance_percent ASC, scheduled_lectures DESC, full_name ASC
LIMIT 10
'''

@app.get('/health')
def health():
    return {'status': 'ok'}

@app.get('/report')
async def report(term: str=Query(min_length=1, max_length=200), date_from: date=Query(), date_to: date=Query(), x_internal_token: str|None=Header(None)):
    import secrets
    if not x_internal_token or not secrets.compare_digest(x_internal_token, INTERNAL_TOKEN):
        raise HTTPException(403, 'Forbidden')
    if date_from > date_to:
        raise HTTPException(422, 'date_from must be <= date_to')
    # Search only lecture documents. Source index from rebuild_all.sh.
    es_query = {
        'size': 1000, '_source':['lesson_id','title','course_code','course_name','lesson_type'],
        'query': {'multi_match': {'query':term,'fields':['title^3','description^2','content_text','tags'], 'type':'phrase'}}
    }
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            er = await client.post(f'{ES_URL}/lab3_learning_content/_search',json=es_query)
            er.raise_for_status()
            response = er.json()
        hits = response['hits']['hits']
        lesson_ids = sorted({int(h['_source']['lesson_id']) for h in hits if h.get('_source',{}).get('lesson_type') == 'lecture' and h.get('_source',{}).get('lesson_id') is not None})
        if not lesson_ids:
            return {'term':term,'period':{'from':str(date_from),'to':str(date_to)}, 'matched_lectures':[], 'total_students':0, 'students':[], 'steps':{'elasticsearch_hits':0,'postgresql_rows':0}}
        with psycopg.connect(PG_DSN, row_factory=dict_row) as conn:
            with conn.cursor() as cur:
                cur.execute(SQL, {'lesson_ids':lesson_ids,'date_from':date_from,'date_to':date_to})
                rows = cur.fetchall()
        # Redis cache is OPTIONAL read-through enrichment: only if actual key is hash.
        # Do not trust Redis instead of PostgreSQL for source-of-truth student attributes.
        cache_hits = 0
        if REDIS_URL:
            try:
                r = redis.from_url(REDIS_URL, decode_responses=True, socket_timeout=1)
                for student in rows:
                    key=f'lab3:student:{student["record_book_number"]}'
                    if r.exists(key):
                        cache_hits += 1
            except redis.RedisError:
                pass
        for row in rows:
            row['attendance_percent'] = float(row['attendance_percent']) if row['attendance_percent'] is not None else None
        return {'term':term,'period':{'from':str(date_from),'to':str(date_to)},
                'matched_lectures':[h['_source'] for h in hits if h.get('_source',{}).get('lesson_type') == 'lecture'],
                'total_students':len(rows),'students':rows,
                'steps':{'elasticsearch_hits':len(hits),'postgresql_rows':len(rows),'redis_existing_student_keys':cache_hits}}
    except httpx.HTTPError:
        raise HTTPException(502, 'Elasticsearch request failed')
    except psycopg.Error:
        raise HTTPException(502, 'PostgreSQL request failed')
