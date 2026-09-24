-- Door lines with calculated unit/line cost and sell, in schedule order. $1 job id
SELECT * FROM v_job_door_lines WHERE job_id = $1::uuid ORDER BY sort_order;
