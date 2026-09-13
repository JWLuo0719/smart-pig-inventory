CREATE INDEX idx_job_status_finished ON inference_job (status, finished_at);
CREATE INDEX idx_job_retry_requested ON inference_job (retry_requested_at);
CREATE INDEX idx_session_confirmed_at ON inventory_session (confirmed_at);
