
import snowflake.connector
import time
import os
import logging

# Path to your large CSV file
schema_name = 'INVENC'


database= "LMAL_DB"
# Connect to Snowflake
try:
    connection = snowflake.connector.connect(
        user='baurice',
        password="yZ",
        account="blyzbv",
        warehouse="COMPUTE_WH",
        database=database,
        role="ACCOUNTADMIN"
    )

    cursor = connection.cursor()


    stage_name = 'TEST'
    validation_mode = 'ABORT_TRANSACTION'

    # Use the PUT command to stage the parquet file in Snowflake (adjust the stage name and file format)
    cursor.execute(f"USE SCHEMA {schema_name}")


    print("Start put")
    folder_path = 'C:/repository/snowflake-triaL/*'
    start_time = time.time()
    cursor.execute(f"PUT file://{folder_path} @{stage_name} SOURCE_COMPRESSION = AUTO_DETECT")
    time_run= time.time() - start_time
    print(f'Time to put data into stage  is --- {time_run} seconds ---')

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
