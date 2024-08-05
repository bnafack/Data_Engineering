--1--
WITH filtered_device_data AS (
    SELECT
        d.deviceID,
        d.productTypeNumber,
        d.firmwareVersion,
        COUNT(t.testID) AS total_tests,
        AVG(t.testDuration) AS avg_test_duration,
        MAX(t.testDuration) AS max_test_duration,
        MIN(t.testDuration) AS min_test_duration
    FROM
        device d
    JOIN
        test t ON d.deviceID = t.deviceID
    WHERE
        d.productTypeNumber like 'LARA%'
        AND t.startDate > '2024-07-14'
    GROUP BY
        d.deviceID,
        d.productTypeNumber,
        d.firmwareVersion
)
SELECT * FROM filtered_device_data;

--- 2 ----

WITH filtered_device_data AS (
    SELECT
        d.deviceID,
        d.productTypeNumber,
        d.firmwareVersion,
        COUNT(t.testID) AS total_tests,
        AVG(t.testDuration) AS avg_test_duration,
        MAX(t.testDuration) AS max_test_duration,
        MIN(t.testDuration) AS min_test_duration
    FROM
        device d
    JOIN
        test t ON d.deviceID = t.deviceID
    WHERE
        d.productTypeNumber like 'LEXI%'
        AND t.startDate > '2024-07-14'
    GROUP BY
        d.deviceID,
        d.productTypeNumber,
        d.firmwareVersion
)
SELECT * FROM filtered_device_data;

---
select distinct producttypenumber, count(*)
from device
group by producttypenumber;


--- 3 ---
-- Step 2: Aggregating step data to calculate average step time and result count
WITH aggregated_step_data AS (
    SELECT
        s.testID,
        AVG(s.stepTime) AS avg_step_time,
        COUNT(CASE WHEN s.testStepResult = 1 THEN 1 ELSE NULL END) AS successful_steps,
        COUNT(CASE WHEN s.testStepResult = 0 THEN 1 ELSE NULL END) AS failed_steps
    FROM
        teststep s
    GROUP BY
        s.testID
)
SELECT * FROM aggregated_step_data;

------- 4 ---

WITH filtered_device_data AS (
    SELECT
        d.deviceID,
        d.productTypeNumber,
        d.firmwareVersion,
        COUNT(t.testID) AS total_tests,
        AVG(t.testDuration) AS avg_test_duration,
        MAX(t.testDuration) AS max_test_duration,
        MIN(t.testDuration) AS min_test_duration
    FROM
        device d
    JOIN
        test t ON d.deviceID = t.deviceID
    WHERE
     d.productTypeNumber = 'LARA-R6401D-01B-00' and -- add for new record
        t.startDate between '2024-07-18' and '2024-07-24'
    GROUP BY
        d.deviceID,
        d.productTypeNumber,
        d.firmwareVersion
),
aggregated_step_data AS (
    SELECT
        s.testID,
        AVG(s.stepTime) AS avg_step_time,
        COUNT(CASE WHEN s.testStepResult = 1 THEN 1 ELSE NULL END) AS successful_steps,
        COUNT(CASE WHEN s.testStepResult = 0 THEN 1 ELSE NULL END) AS failed_steps
    FROM
        teststep s
    GROUP BY
        s.testID
)
SELECT
    f.deviceID,
    f.productTypeNumber,
    f.firmwareVersion,
    f.total_tests,
    f.avg_test_duration,
    f.max_test_duration,
    f.min_test_duration,
    a.avg_step_time,
    a.successful_steps,
    a.failed_steps
FROM
    filtered_device_data f
JOIN
    test t ON f.deviceID = t.deviceID
JOIN
    aggregated_step_data a ON t.testID = a.testID;


-------5 ---


-- Benchmark Query for Snowflake and Athena
-- Complex query with multiple joins, subqueries, window functions, and aggregations
 
-- Step 1: Filtering and aggregating device data with window functions
-- Subquery for benchmarking device aggregates
WITH device_aggregates AS (
    SELECT
        d.deviceID,
        d.productTypeNumber,
        d.firmwareVersion,
        COUNT(t.testID) AS total_tests,
        AVG(t.testDuration) AS avg_test_duration,
        MAX(t.testDuration) AS max_test_duration,
        MIN(t.testDuration) AS min_test_duration,
        ROW_NUMBER() OVER (PARTITION BY d.productTypeNumber ORDER BY d.deviceID) AS device_rank
    FROM
        device d
    JOIN
        test t ON d.deviceID = t.deviceID
    WHERE
        d.productTypeNumber = 'LARA-R6801-00B-01'
        AND t.startDate between '2024-07-18' and '2024-07-24'
    GROUP BY
        d.deviceID,
        d.productTypeNumber,
        d.firmwareVersion
)
SELECT
    *
FROM
    device_aggregates
ORDER BY
    device_rank;


--- 6 ---
-- Subquery for benchmarking step aggregates
WITH step_aggregates AS (
    SELECT
        s.testID,
        AVG(s.stepTime) AS avg_step_time,
        COUNT(CASE WHEN s.testStepResult = 1 THEN 1 ELSE NULL END) AS successful_steps,
        COUNT(CASE WHEN s.testStepResult = 0 THEN 1 ELSE NULL END) AS failed_steps,
        SUM(s.elapsed) AS total_elapsed_time
    FROM
        teststep s
    GROUP BY
        s.testID
),
step_ranks AS (
    SELECT
        s.testID,
        s.elapsed,
        RANK() OVER (PARTITION BY s.testID ORDER BY s.elapsed DESC) AS step_rank
    FROM
        teststep s
    where s.startDate between '2024-07-18' and '2024-07-24'
)
SELECT
    sa.*,
    sr.step_rank
FROM
    step_aggregates sa
JOIN
    step_ranks sr ON sa.testID = sr.testID
ORDER BY
    sr.step_rank;

--- 7---
select *
from substep
where startdate='2024-07-24';


----- 8 ---
select *
from device d join test t on d.deviceid=t.deviceid join teststep ts on t.testid=ts.testid join substep ss on ts.teststepid=ss.teststepid join testpackage tp on t.TESTPACKAGEID = tp.TESTPACKAGEID 
where d.producttypenumber like 'LARA%' and t.startdate='2024-07-24';

--- 9 ---- 


select d.imei, t.startdatetime, tsb.computername, sum(ts.steptime), avg(ss.elapsed)
from device d join test t on d.deviceid=t.deviceid join teststep ts on t.testid=ts.testid join substep ss on ts.teststepid=ss.teststepid join testbench tsb on t.testbenchid=tsb.testbenchid join testpackage tp on t.TESTPACKAGEID = tp.TESTPACKAGEID join limits on limits.limitsid = ss.limitsid
where d.producttypenumber like 'LARA%' and t.startdate='2024-07-24'
group by d.imei, t.startdatetime, tsb.computername;


