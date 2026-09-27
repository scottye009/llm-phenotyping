-- Helps DISTINCT / returning person_id quickly
CREATE INDEX IF NOT EXISTS idx_meas_person ON measurement(person_id);

-- Helps the numeric filter narrow rows early
CREATE INDEX IF NOT EXISTS idx_meas_value ON measurement(value_as_number);

