import snowflake.connector
import time
import os
import logging
# Path to your large CSV file
schema_name = 'AUTORESUM_1'

stage_name = 'STG_complete'
database= "INVENC"
# Connect to Snowflake
try:
    connection = snowflake.connector.connect(
        user='baurice',
        password="yZNZ",
        account="blyzbvg",
        warehouse="COMPUTE_WH",
        database=database,
        role="ACCOUNTADMIN"
    )
    cursor = connection.cursor()
    start_time = time.time()
    copy_into_generic = f""" COPY INTO GENERICINFO_TABLE
                FROM @{stage_name}
                FILE_FORMAT = (TYPE = 'PARQUET')
                MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
                PATTERN = '.*genericinfo.parquet*'
                ; """
    copy_into_limit =  f""" COPY INTO LIMITS_TABLE
                FROM @{stage_name}
                FILE_FORMAT = (TYPE = 'PARQUET')
                MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
                PATTERN = '.*limits.*'
                ; """

    start_time = time.time()
    cursor.execute(u"begin")

    cursor.execute(copy_into_limit)

    connection.commit()
    time_run= round(time.time() - start_time,2)
    logging.info(f'Time to copy data into limit table  is --- {time_run} seconds ---')
    start_time = time.time()
    cursor.execute(u"begin")

    cursor.execute(copy_into_generic)

    connection.commit()
    time_run= round(time.time() - start_time,2)
    logging.info(f'Time to copy data into generic table  is --- {time_run} seconds ---')
except (Exception) as error:
    if(connection):
        print(f"Failed to insert record into into the database {database} in schema {schema_name} error {error}")
        # Rollback transaction in case of error
        connection.rollback()
        print(f"An error occurred: {error}")
finally:
    # closing database connection.
    if(connection):
        cursor.close()
        connection.close()
        print("Snowflake connection is closed")
