"""Job Application Tracker - a small Flask app used to demonstrate cloud infrastructure.

Runs two ways:
  * Locally with no database (DB_HOST unset): keeps jobs in memory.
  * On AWS ECS Fargate: connects to RDS Postgres. The password is injected by ECS
    from AWS Secrets Manager, never stored in code.
"""
import logging
import os
import threading

from flask import Flask, jsonify, redirect, render_template, request, url_for

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("app")

app = Flask(__name__)

STATUSES = ["Applied", "Interviewing", "Offer", "Rejected"]
APP_ENV = os.environ.get("APP_ENV", "local")
DB_HOST = os.environ.get("DB_HOST")


class MemoryStore:
    """Used when no database is configured (local development and tests)."""

    def __init__(self):
        self._jobs = []
        self._next_id = 1
        self._lock = threading.Lock()

    def list(self):
        return sorted(self._jobs, key=lambda j: j["id"], reverse=True)

    def add(self, company, role):
        with self._lock:
            self._jobs.append({"id": self._next_id, "company": company, "role": role, "status": "Applied"})
            self._next_id += 1

    def set_status(self, job_id, status):
        for job in self._jobs:
            if job["id"] == job_id:
                job["status"] = status

    def ping(self):
        return True


class PostgresStore:
    """Stores jobs in RDS Postgres."""

    def __init__(self):
        import psycopg  # imported here so local runs don't need a database driver

        self._psycopg = psycopg
        self._params = dict(
            host=DB_HOST,
            port=int(os.environ.get("DB_PORT", "5432")),
            dbname=os.environ.get("DB_NAME", "jobs"),
            user=os.environ.get("DB_USER"),
            password=os.environ.get("DB_PASSWORD"),
            connect_timeout=5,
            sslmode=os.environ.get("DB_SSLMODE", "require"),
        )
        self._ready = False

    def _conn(self):
        conn = self._psycopg.connect(**self._params)
        if not self._ready:
            with conn.cursor() as cur:
                cur.execute(
                    """CREATE TABLE IF NOT EXISTS jobs (
                           id SERIAL PRIMARY KEY,
                           company TEXT NOT NULL,
                           role TEXT NOT NULL,
                           status TEXT NOT NULL DEFAULT 'Applied',
                           created_at TIMESTAMPTZ NOT NULL DEFAULT now())"""
                )
            conn.commit()
            self._ready = True
        return conn

    def list(self):
        with self._conn() as conn, conn.cursor() as cur:
            cur.execute("SELECT id, company, role, status FROM jobs ORDER BY id DESC")
            return [dict(id=r[0], company=r[1], role=r[2], status=r[3]) for r in cur.fetchall()]

    def add(self, company, role):
        with self._conn() as conn, conn.cursor() as cur:
            cur.execute("INSERT INTO jobs (company, role) VALUES (%s, %s)", (company, role))

    def set_status(self, job_id, status):
        with self._conn() as conn, conn.cursor() as cur:
            cur.execute("UPDATE jobs SET status = %s WHERE id = %s", (status, job_id))

    def ping(self):
        with self._conn() as conn, conn.cursor() as cur:
            cur.execute("SELECT 1")
            return True


store = PostgresStore() if DB_HOST else MemoryStore()
log.info("Starting in %s mode with %s", APP_ENV, type(store).__name__)


@app.get("/")
def index():
    return render_template("index.html", jobs=store.list(), statuses=STATUSES, env=APP_ENV)


@app.post("/jobs")
def add_job():
    company = request.form.get("company", "").strip()[:100]
    role = request.form.get("role", "").strip()[:100]
    if company and role:
        store.add(company, role)
    return redirect(url_for("index"))


@app.post("/jobs/<int:job_id>/status")
def update_status(job_id):
    status = request.form.get("status")
    if status in STATUSES:
        store.set_status(job_id, status)
    return redirect(url_for("index"))


@app.get("/api/jobs")
def api_jobs():
    return jsonify(store.list())


@app.get("/health")
def health():
    """Liveness check used by the load balancer. Does not touch the database,
    so a database blip doesn't make every container look dead."""
    return "OK", 200


@app.get("/ready")
def ready():
    """Readiness check: confirms the app can reach its database."""
    try:
        store.ping()
        return jsonify(status="ready", store=type(store).__name__), 200
    except Exception as exc:  # noqa: BLE001
        log.error("Readiness check failed: %s", exc)
        return jsonify(status="not ready"), 503


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
