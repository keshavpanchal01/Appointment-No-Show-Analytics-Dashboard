select * from appointments
limit 10
;

alter table appointments
	change column Hipertension hypertension int,
    change column Handcap disability_count int,
    change column `No-show` no_show varchar(3)
    ;
    
select disability_count, count(*)
from appointments
group by disability_count
;

select ScheduledDay, AppointmentDay
from appointments
limit 10
;

alter table appointments
	add column ScheduledDayc datetime,
    add column AppointmentDayc date
    ;
    
update appointments
set ScheduledDayc = str_to_date(replace(replace(ScheduledDay, 'T', ' '),'Z',' '), '%Y-%m-%d %H:%i:%s'),
AppointmentDayc = STR_TO_DATE(REPLACE(REPLACE(AppointmentDay, 'T', ' '), 'Z', ''), '%Y-%m-%d %H:%i:%s');

ALTER TABLE appointments
DROP COLUMN ScheduledDay,
DROP COLUMN AppointmentDay;

ALTER TABLE appointments
CHANGE COLUMN ScheduledDayc ScheduledDay datetime,
CHANGE COLUMN AppointmentDayc AppointmentDay date;

SELECT
    MIN(AGE),
    MAX(AGE)
FROM  appointments;

DELETE FROM  appointments
WHERE AGE = -1;

ALTER TABLE  appointments ADD COLUMN lead_time_days INT;

UPDATE  appointments
SET lead_time_days = DATEDIFF(AppointmentDay, DATE(ScheduledDay));

SELECT
    MIN(lead_time_days),
    MAX(lead_time_days)
FROM  appointments;

SELECT *
FROM  appointments
WHERE lead_time_days < 0;

DELETE FROM   appointments
WHERE lead_time_days < 0;

SELECT
    no_show,
    COUNT(*) AS total_appointments,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM  appointments), 2) AS pct_of_total
FROM  appointments
GROUP BY no_show;

SELECT
    DAYNAME(AppointmentDay) AS appointment_day,
    COUNT(*) AS total_appointments,
    SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) AS no_shows,
    ROUND(SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) * 100 / COUNT(*), 2) AS rate_of_no_shows
FROM  appointments
GROUP BY DAYNAME(AppointmentDay)
ORDER BY rate_of_no_shows DESC;

SELECT
    CASE
        WHEN lead_time_days = 0 THEN 'Same Day'
        WHEN lead_time_days BETWEEN 1 AND 3 THEN 'Short (1-3 Days)'
        WHEN lead_time_days BETWEEN 4 AND 7 THEN 'Within a week'
        ELSE 'Long Lead (8+ days)'
    END AS lead_time_bucket,
    COUNT(*) AS total_appointments,
    ROUND(SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) * 100 / COUNT(*), 2) AS no_show_rate
FROM  appointments
GROUP BY lead_time_bucket
ORDER BY no_show_rate DESC;

SELECT
    CASE
        WHEN Age BETWEEN 0 AND 12 THEN 'Child'
        WHEN Age BETWEEN 13 AND 19 THEN 'Teen'
        WHEN Age BETWEEN 20 AND 39 THEN 'Young Adult'
        WHEN Age BETWEEN 40 AND 59 THEN 'Adult'
        ELSE 'Senior'
    END AS age_group,
    COUNT(*) AS total_appointments,
    ROUND(
        SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) * 100 / COUNT(*),
        2
    ) AS no_show_rate
FROM  appointments
GROUP BY age_group
ORDER BY no_show_rate DESC;

SELECT
    CASE
        WHEN sms_received = 1 THEN 'Received SMS'
        ELSE 'No SMS'
    END AS sms_status,
    COUNT(*) AS total_appointments,
    ROUND(
        SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) * 100 / COUNT(*),
        2
    ) AS no_show_rate
FROM  appointments
GROUP BY sms_status;

WITH neighbourhood_stats AS (
    SELECT Neighbourhood, COUNT(*) AS total_appointments,
           ROUND(SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) * 100 / COUNT(*), 2) AS no_show_rate
    FROM  appointments
    GROUP BY Neighbourhood
    HAVING COUNT(*) >= 100
)
SELECT *, RANK() OVER (ORDER BY no_show_rate DESC) AS risk_rank
FROM neighbourhood_stats
ORDER BY no_show_rate DESC;


SELECT
    patientid,
    appointmentid,
    appointmentday,
    no_show,
    COUNT(*) OVER (
        PARTITION BY PatientID
        ORDER BY AppointmentDay
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prior_appointments,
    SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) OVER (
        PARTITION BY PatientID
        ORDER BY AppointmentDay
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prior_no_shows
FROM  appointments
ORDER BY patientid, appointmentday;


CREATE VIEW v_appointment_risk AS
WITH patient_history AS (
    SELECT
        PatientId,
        AppointmentID,
        AppointmentDay,
        Neighbourhood,
        lead_time_days,
        sms_received,
        Scholarship,
        no_show,
        COUNT(*) OVER (
            PARTITION BY PatientId
            ORDER BY AppointmentDay
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prior_appointments,
        SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) OVER (
            PARTITION BY PatientId
            ORDER BY AppointmentDay
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prior_no_shows
		from appointments)

SELECT
    PatientId,
    AppointmentID,
    AppointmentDay,
    Neighbourhood,
    lead_time_days,
    prior_appointments,
    prior_no_shows,
    ROUND(prior_no_shows / NULLIF(prior_appointments, 0), 2) AS prior_no_show_rate,
    CASE
        WHEN prior_appointments = 0 THEN 'New Patient - Monitor'
        WHEN (prior_no_shows / NULLIF(prior_appointments, 0)) >= 0.5
             OR lead_time_days >= 8 THEN 'High Risk'
        WHEN (prior_no_shows / NULLIF(prior_appointments, 0)) >= 0.2
             OR lead_time_days BETWEEN 4 AND 7 THEN 'Medium Risk'
        ELSE 'Low Risk'
    END AS risk_tier
FROM patient_history;

SELECT
*
FROM v_appointment_risk
WHERE risk_tier = 'High Risk'
ORDER BY AppointmentDay
Limit 50;

select * from appointments;

select * from v_appointment_risk;
