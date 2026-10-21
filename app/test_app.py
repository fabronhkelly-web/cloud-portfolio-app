"""Unit tests. They run in the pipeline before any image is built."""
import os

os.environ.pop("DB_HOST", None)  # force the in-memory store

from app import app  # noqa: E402


def client():
    app.config["TESTING"] = True
    return app.test_client()


def test_health():
    resp = client().get("/health")
    assert resp.status_code == 200
    assert resp.data == b"OK"


def test_ready_without_database():
    resp = client().get("/ready")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ready"


def test_add_and_update_job():
    c = client()
    c.post("/jobs", data={"company": "Acme", "role": "Cloud Engineer"})
    jobs = c.get("/api/jobs").get_json()
    assert jobs[0]["company"] == "Acme"
    assert jobs[0]["status"] == "Applied"

    c.post(f"/jobs/{jobs[0]['id']}/status", data={"status": "Interviewing"})
    assert c.get("/api/jobs").get_json()[0]["status"] == "Interviewing"


def test_rejects_unknown_status():
    c = client()
    c.post("/jobs", data={"company": "Globex", "role": "SRE"})
    job_id = c.get("/api/jobs").get_json()[0]["id"]
    c.post(f"/jobs/{job_id}/status", data={"status": "Hacked"})
    assert c.get("/api/jobs").get_json()[0]["status"] == "Applied"


def test_home_page_renders():
    resp = client().get("/")
    assert resp.status_code == 200
    assert b"Job Application Tracker" in resp.data
