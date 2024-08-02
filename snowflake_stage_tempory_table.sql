CREATE OR REPLACE TABLE device (
deviceID string,
serialnumber string,
firmwareversion string,
producttypenumber string,
imei number(38,0),
mac string,
mac2 string,
mac3 string,
mac4 string,
otpinfo string,
param_chipid string,
param_flashid string,
workflowid string,
processedtime timestamp_ntz

);


CREATE or replace TABLE limits (
  limitsID STRING,
  name STRING,
  type STRING,
  unit STRING,
  lower STRING,
  upper STRING,
  workflowID STRING,
  processedtime timestamp_ntz
);


CREATE or replace TABLE steplist (
  stepListID STRING,
  stepKeyName STRING,
  id1 INT,
  workflowID STRING,
  processedtime timestamp_ntz
);



CREATE or replace TABLE substep (
  subStepID STRING,
  testID STRING,
  stepListId STRING,
  testStepID STRING,
  limitsID STRING,
  arrayIndex INT,
  subStepIndex INT,
  id2 INT,
  meas STRING,
  subStepResult INT,
  elapsed INT,
  workflowId STRING,
  processedtime timestamp_ntz,
  startDate DATE
);



CREATE or replace TABLE test (
  testID STRING,
  deviceID STRING,
  testPackageID STRING,
  testBenchID STRING,
  startDateTime timestamp_ntz,
  manufacturer STRING,
  testDuration INT,
  failedTestStep STRING,
  operator STRING,
  testResult INT,
  errorCode STRING,
  runMode STRING,
  prodCenter STRING,
  workflowID STRING,
  processedtime timestamp_ntz,
  startDate DATE
);


CREATE or replace TABLE testbench (
  testBenchID STRING,
  computerName STRING,
  workflowID STRING,
  processedtime timestamp_ntz
);


CREATE or replace TABLE testpackage (
  testPackageID STRING,
  testPackageMD5 STRING,
  testSequenceName STRING,
  testSequenceMD5 STRING,
  testPackageName STRING,
  testVariablesName STRING,
  testVariablesMD5 STRING,
  testLimitsName STRING,
  testLimitsMD5 STRING,
  testEquipmentName STRING,
  testEquipmentMD5 STRING,
  testProgramVersion STRING,
  testSequenceVersion STRING,
  testHandlerLibrary STRING,
  testHandlerLibraryMD5 STRING,
  calibrationConfig STRING,
  calibrationConfigMD5 STRING,
  stationConfig STRING,
  stationConfigMD5 STRING,
  koboltFrameworkVersion STRING,
  workflowID STRING,
  processedtime TIMESTAMP_NTZ
);

CREATE or replace TABLE teststep (
  testStepID STRING,
  testID STRING,
  stepListId STRING,
  stepIndex INT,
  stepTime INT,
  elapsed INT,
  testStepResult INT,
  workflowId STRING,
  processedtime timestamp_ntz,
  startDate DATE
);

-- TEMPORARY FROM HERE

create OR REPLACE temporary TABLE temp_device (
deviceid string,
serialnumber string,
firmwareversion string,
producttypenumber string,
imei number(38,0),
mac string,
mac2 string,
mac3 string,
mac4 string,
otpinfo string,
param_chipid string,
param_flashid string,
workflowid string,
processedtime STRING

);


CREATE OR REPLACE temporary TABLE temp_limits (
  limitsID STRING,
  name STRING,
  type STRING,
  unit STRING,
  lower STRING,
  upper STRING,
  workflowID STRING,
  processedtime string
);


CREATE OR REPLACE temporary TABLE temp_steplist (
  stepListID STRING,
  stepKeyName STRING,
  id1 INT,
  workflowID STRING,
  processedtime string
);



CREATE OR REPLACE temporary TABLE temp_substep (
  subStepID STRING,
  testID STRING,
  stepListId STRING,
  testStepID STRING,
  limitsID STRING,
  arrayIndex INT,
  subStepIndex INT,
  id2 INT,
  meas STRING,
  subStepResult INT,
  elapsed INT,
  workflowId STRING,
  processedtime string,
  startDate DATE
);



CREATE OR REPLACE temporary TABLE temp_test (
  testID STRING,
  deviceID STRING,
  testPackageID STRING,
  testBenchID STRING,
  startDateTime string,
  manufacturer STRING,
  testDuration INT,
  failedTestStep STRING,
  operator STRING,
  testResult INT,
  errorCode STRING,
  runMode STRING,
  prodCenter STRING,
  workflowID STRING,
  processedtime string,
  startDate DATE
);


CREATE temporary TABLE temp_testbench (
  testBenchID STRING,
  computerName STRING,
  workflowID STRING,
  processedtime string
);


CREATE temporary TABLE temp_testpackage (
  testPackageID STRING,
  testPackageMD5 STRING,
  testSequenceName STRING,
  testSequenceMD5 STRING,
  testPackageName STRING,
  testVariablesName STRING,
  testVariablesMD5 STRING,
  testLimitsName STRING,
  testLimitsMD5 STRING,
  testEquipmentName STRING,
  testEquipmentMD5 STRING,
  testProgramVersion STRING,
  testSequenceVersion STRING,
  testHandlerLibrary STRING,
  testHandlerLibraryMD5 STRING,
  calibrationConfig STRING,
  calibrationConfigMD5 STRING,
  stationConfig STRING,
  stationConfigMD5 STRING,
  koboltFrameworkVersion STRING,
  workflowID STRING,
  processedtime STRING
);

CREATE temporary TABLE temp_teststep (
  testStepID STRING,
  testID STRING,
  stepListId STRING,
  stepIndex INT,
  stepTime INT,
  elapsed INT,
  testStepResult INT,
  workflowId STRING,
  processedtime STRING,
  startDate DATE
);


--FINISHED WITH TEMPORARY
--COPYING INTO TABLES

INSERT INTO device
SELECT 
deviceid,
serialnumber,
firmwareversion,
producttypenumber,
imei,
mac,
mac2,
mac3,
mac4,
otpinfo,
param_chipid,
param_flashid,
workflowid,
TO_TIMESTAMP_NTZ(REPLACE(processedtime, ' UTC', ''), 'YYYY-MM-DD HH24:MI:SS.FF6')
FROM temp_device;

INSERT INTO limits
SELECT 
    limitsID,
name,
type,
unit,
lower,
upper,
workflowID,
    TO_TIMESTAMP_NTZ(REPLACE(processedtime, ' UTC', ''), 'YYYY-MM-DD HH24:MI:SS.FF6')
FROM temp_limits;

INSERT INTO steplist
SELECT 
  stepListID,
  stepKeyName,
  id1,
  workflowID,
    TO_TIMESTAMP_NTZ(REPLACE(processedtime, ' UTC', ''), 'YYYY-MM-DD HH24:MI:SS.FF6')
FROM temp_steplist;

INSERT INTO substep
SELECT 
subStepID,
testID,
stepListId,
testStepID,
limitsID,
arrayIndex,
subStepIndex,
id2,
meas,
subStepResult,
elapsed,
workflowId,
TO_TIMESTAMP_NTZ(REPLACE(processedtime, ' UTC', ''), 'YYYY-MM-DD HH24:MI:SS.FF6'),
startDate    
FROM temp_substep;

INSERT INTO test
SELECT 
testID,
deviceID,
testPackageID,
testBenchID,
TO_TIMESTAMP_NTZ(REPLACE(startdatetime, ' UTC', ''), 'YYYY-MM-DD HH24:MI:SS.FF6'),
manufacturer,
testDuration,
failedTestStep,
operator,
testResult,
errorCode,
runMode,
prodCenter,
workflowID,
TO_TIMESTAMP_NTZ(REPLACE(processedtime, ' UTC', ''), 'YYYY-MM-DD HH24:MI:SS.FF6'),
startDate
FROM temp_test;

INSERT INTO testbench
SELECT 
  testBenchID STRING,
  computerName STRING,
  workflowID STRING,
  TO_TIMESTAMP_NTZ(REPLACE(processedtime, ' UTC', ''), 'YYYY-MM-DD HH24:MI:SS.FF6')
FROM temp_testbench;

INSERT INTO testpackage
SELECT 
    testPackageID,
    testPackageMD5,
    testSequenceName,
    testSequenceMD5,
    testPackageName,
    testVariablesName,
    testVariablesMD5,
    testLimitsName,
    testLimitsMD5,
    testEquipmentName,
    testEquipmentMD5,
    testProgramVersion,
    testSequenceVersion,
    testHandlerLibrary,
    testHandlerLibraryMD5,
    calibrationConfig,
    calibrationConfigMD5,
    stationConfig,
    stationConfigMD5,
    koboltFrameworkVersion,
    workflowID,
    TO_TIMESTAMP_NTZ(REPLACE(processedtime, ' UTC', ''), 'YYYY-MM-DD HH24:MI:SS.FF6')
FROM temp_testpackage;

INSERT INTO teststep
SELECT 
testStepID,
testID,
stepListId,
stepIndex,
stepTime,
elapsed,
testStepResult,
workflowId,
TO_TIMESTAMP_NTZ(REPLACE(processedtime, ' UTC', ''), 'YYYY-MM-DD HH24:MI:SS.FF6'),
startDate

FROM temp_teststep;
LMAL_DB.INVENTEC.DEVICELMAL_DB.INVENTEC.STEPLISTLMAL_DB.INVENTEC.TEST

-- END OF INSERTS FROM TEMP TO TABLE
-- BEGINNING OF INSERT FROM FILE TO TEMP


COPY INTO temp_device
FROM @test/device_data.csv.gz
FILE_FORMAT = (
    TYPE = 'CSV',
    PARSE_HEADER = TRUE,
    FIELD_OPTIONALLY_ENCLOSED_BY = '"',
    FIELD_DELIMITER = ',',
    RECORD_DELIMITER = '\n',
    NULL_IF = ('', 'NULL') -- Adjust if you have specific representations of NULLs
)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;


COPY INTO temp_limits
FROM @test/limits-data.csv.gz
FILE_FORMAT = (
    TYPE = 'CSV',
    PARSE_HEADER = TRUE,
    FIELD_OPTIONALLY_ENCLOSED_BY = '"',
    FIELD_DELIMITER = ',',
    RECORD_DELIMITER = '\n',
    NULL_IF = ('', 'NULL') -- Adjust if you have specific representations of NULLs
)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;


COPY INTO temp_steplist
FROM @test/steplist-data.csv.gz
FILE_FORMAT = (
    TYPE = 'CSV',
    PARSE_HEADER = TRUE,
    FIELD_OPTIONALLY_ENCLOSED_BY = '"',
    FIELD_DELIMITER = ',',
    RECORD_DELIMITER = '\n',
    NULL_IF = ('', 'NULL') -- Adjust if you have specific representations of NULLs
)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

COPY INTO temp_substep
FROM @test/substep24pt1-data.csv.gz
FILE_FORMAT = (
    TYPE = 'CSV',
    PARSE_HEADER = TRUE,
    FIELD_OPTIONALLY_ENCLOSED_BY = '"',
    FIELD_DELIMITER = ',',
    RECORD_DELIMITER = '\n',
    NULL_IF = ('', 'NULL') -- Adjust if you have specific representations of NULLs
)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;


COPY INTO temp_test
FROM @test/test-data.csv.gz
FILE_FORMAT = (
    TYPE = 'CSV',
    PARSE_HEADER = TRUE,
    FIELD_OPTIONALLY_ENCLOSED_BY = '"',
    FIELD_DELIMITER = ',',
    RECORD_DELIMITER = '\n',
    NULL_IF = ('', 'NULL') -- Adjust if you have specific representations of NULLs
)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

COPY INTO temp_testbench
FROM @test/testbench-data.csv.gz
FILE_FORMAT = (
    TYPE = 'CSV',
    PARSE_HEADER = TRUE,
    FIELD_OPTIONALLY_ENCLOSED_BY = '"',
    FIELD_DELIMITER = ',',
    RECORD_DELIMITER = '\n',
    NULL_IF = ('', 'NULL') -- Adjust if you have specific representations of NULLs
)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

COPY INTO temp_testpackage
FROM @test/testpackage-data.csv.gz
FILE_FORMAT = (
    TYPE = 'CSV',
    PARSE_HEADER = TRUE,
    FIELD_OPTIONALLY_ENCLOSED_BY = '"',
    FIELD_DELIMITER = ',',
    RECORD_DELIMITER = '\n',
    NULL_IF = ('', 'NULL') -- Adjust if you have specific representations of NULLs
)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

COPY INTO temp_teststep
FROM @test/teststep-data.csv.gz
FILE_FORMAT = (
    TYPE = 'CSV',
    PARSE_HEADER = TRUE,
    FIELD_OPTIONALLY_ENCLOSED_BY = '"',
    FIELD_DELIMITER = ',',
    RECORD_DELIMITER = '\n',
    NULL_IF = ('', 'NULL') -- Adjust if you have specific representations of NULLs
)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;





