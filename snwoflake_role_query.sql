select current_role();

create user TestUser
password = 'Test@12345'
comment = 'This is the test user'
MUST_CHANGE_PASSWORD = False;

CREATE ROLE BASIC_ROLE;

GRANT ROLE BASIC_ROLE to USER TestUSER;

GRANT USAGE ON WAREHOUSE COMPUTE_WH to ROLE BASIC_ROLE;

GRANT USAGE on database WS to role BASIC_ROLE;
grant USAGE on Schema ws.ws_m10050_ltx_03_04 to role basic_role;

grant select on table ws.ws_m10050_ltx_03_04.ws_results to role basic_role;
