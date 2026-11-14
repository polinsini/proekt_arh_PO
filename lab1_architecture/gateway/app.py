import os
from datetime import datetime, timedelta, timezone, date
import secrets
import httpx
import jwt
from fastapi import FastAPI, HTTPException, Header, Depends, Query
from pydantic import BaseModel
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

app = FastAPI(title="University API Gateway", version="1.0")
security = HTTPBearer(
    scheme_name="JWT",
    description="Введите JWT-токен, полученный через /auth/login",
    auto_error=False
)
SECRET = os.environ["JWT_SECRET"]
INTERNAL_TOKEN = os.environ["INTERNAL_TOKEN"]
LAB1_URL = os.getenv("LAB1_URL", "http://lab1:8001")

class Credentials(BaseModel):
    username: str
    password: str

@app.get('/health')
def health():
    return {'status': 'ok'}

@app.post('/auth/login')
def login(creds: Credentials):
    if not (secrets.compare_digest(creds.username, os.getenv('DEMO_USER','student'))
            and secrets.compare_digest(creds.password, os.environ['DEMO_PASSWORD'])):
        raise HTTPException(401, 'Invalid credentials')
    now = datetime.now(timezone.utc)
    token = jwt.encode({'sub': creds.username, 'iat': now, 'exp': now + timedelta(hours=1)}, SECRET, algorithm='HS256')
    return {'access_token': token, 'token_type':'bearer', 'expires_in':3600}

def require_token(
    credentials: HTTPAuthorizationCredentials | None = Depends(security)
):
    if credentials is None:
        raise HTTPException(401, "Bearer token required")

    try:
        return jwt.decode(
            credentials.credentials,
            SECRET,
            algorithms=["HS256"],
            options={"require": ["sub", "exp"]}
        )
    except jwt.PyJWTError:
        raise HTTPException(401, "Invalid or expired JWT")

@app.get('/api/lab1/low-attendance')
async def lab1(
    term: str = Query(
        min_length=1,
        max_length=200,
        description="Термин или фраза для поиска в лекциях",
        examples=["архитектура"]
    ),
    date_from: date = Query(
        description="Начало периода обучения (ГГГГ-ММ-ДД)",
        examples=["2026-09-21"]
    ),
    date_to: date = Query(
        description="Конец периода обучения (ГГГГ-ММ-ДД)",
        examples=["2026-09-27"]
    ),
    _user=Depends(require_token)
):
    try:
        async with httpx.AsyncClient(timeout=25) as client:
            r = await client.get(LAB1_URL + '/report', params={'term':term,'date_from':date_from,'date_to':date_to}, headers={'X-Internal-Token':INTERNAL_TOKEN})
            return_data = r.json()
            if r.status_code >= 400:
                raise HTTPException(r.status_code, return_data.get('detail', return_data))
            return return_data
    except (httpx.RequestError, ValueError):
        raise HTTPException(502, 'Lab1 service unavailable')
