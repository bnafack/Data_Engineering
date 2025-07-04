from flask import Flask, render_template_string, request, redirect, url_for, flash
import psycopg2
from psycopg2 import sql
from psycopg2 import errors # Import errors for specific exception handling
from collections import defaultdict

app = Flask(__name__)
app.secret_key = 'supersecretkey'  # For flash messages

# --- PostgreSQL connection config ---
PG_CONFIG = {
    'dbname': 'postgres',
    'user': 'postgres',
    'password': 'root',
    'host': 'localhost',
    'port': 5432,
}

def connect():
    """Establishes a connection to the PostgreSQL database."""
    return psycopg2.connect(**PG_CONFIG)

def grant_connect_on_database(cur, dbname, group):
    """Grants CONNECT privilege on a specific database to a role/group."""
    cur.execute(sql.SQL("GRANT CONNECT ON DATABASE {} TO {};")
                .format(sql.Identifier(dbname), sql.Identifier(group)))

# --- Helper functions ---

def list_databases(cur):
    """Lists all non-template databases."""
    # Exclude template databases
    cur.execute("""
        SELECT datname FROM pg_database
        WHERE datistemplate = false
        ORDER BY datname;
    """)
    return [row[0] for row in cur.fetchall()]

def list_users(cur):
    """Lists all roles that can log in (users)."""
    cur.execute("SELECT rolname FROM pg_roles WHERE rolcanlogin ORDER BY rolname;")
    return [row[0] for row in cur.fetchall()]

def list_groups(cur):
    """Lists all roles that cannot log in (groups)."""
    cur.execute("SELECT rolname FROM pg_roles WHERE NOT rolcanlogin ORDER BY rolname;")
    return [row[0] for row in cur.fetchall()]

def list_role_memberships(cur):
    """Lists all role memberships (who is a member of which role)."""
    cur.execute("""
        SELECT member.rolname AS member, role.rolname AS role
        FROM pg_auth_members m
        JOIN pg_roles member ON m.member = member.oid
        JOIN pg_roles role ON m.roleid = role.oid
        ORDER BY role.rolname, member.rolname;
    """)
    return cur.fetchall()

def list_permissions(cur, role_filter=None):
    """Lists table-level permissions, optionally filtered by a role."""
    query = """
        SELECT grantee, table_schema, table_name, privilege_type
        FROM information_schema.role_table_grants
        WHERE table_schema NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
    """
    params = []
    if role_filter:
        query += " AND grantee = %s "
        params.append(role_filter)
    query += " ORDER BY grantee, table_schema, table_name, privilege_type;"
    cur.execute(query, params)
    return cur.fetchall()

def get_all_roles(cur):
    """Lists all roles (users and groups)."""
    cur.execute("SELECT rolname FROM pg_roles ORDER BY rolname;")
    return [row[0] for row in cur.fetchall()]

def get_user_schemas(cur):
    """Lists all user-defined schemas."""
    cur.execute("""
        SELECT schema_name
        FROM information_schema.schemata
        WHERE schema_name NOT LIKE 'pg_%'
          AND schema_name NOT IN ('information_schema')
        ORDER BY schema_name;
    """)
    return [row[0] for row in cur.fetchall()]

def get_all_tables(cur):
    """Lists all user-defined tables."""
    cur.execute("""
        SELECT table_schema, table_name
        FROM information_schema.tables
        WHERE table_schema NOT LIKE 'pg_%'
          AND table_schema != 'information_schema'
          AND table_type = 'BASE TABLE'
        ORDER BY table_schema, table_name;
    """)
    return [(schema, table) for schema, table in cur.fetchall()]

def create_user(cur, username, password, default_db_name="postgres"):
    """
    Creates a new PostgreSQL user (ROLE) with a specified password.
    It allows the user to CONNECT to the specified default_db_name,
    but revokes CONNECT privileges on all other existing databases.
    It also revokes all privileges on the 'public' schema within the default database.

    Args:
        cur: A psycopg2 cursor object.
        username (str): The desired username for the new PostgreSQL role.
        password (str): The password for the new PostgreSQL role.
        default_db_name (str): The name of the database the user IS allowed to connect to.

    Returns:
        tuple: A tuple (bool, str) indicating success/failure and a message.
    """
    try:
        # 1. Create the user with LOGIN and PASSWORD
        # Using sql.Identifier for the username to prevent SQL injection
        # and %s for the password to pass it as a parameter.
        cur.execute(
            sql.SQL("CREATE ROLE {} WITH LOGIN PASSWORD %s").format(sql.Identifier(username)),
            [password]
        )
        print(f"Successfully created user: {username}")

        # 2. Revoke CONNECT on all existing non-template databases EXCEPT the default_db_name.
        # This is the most critical step to prevent unauthorized database access.
        cur.execute("SELECT datname FROM pg_database WHERE datistemplate = false;")
        databases = cur.fetchall()

        for (dbname,) in databases:
            # Only revoke CONNECT if the database is NOT the default_db_name
            if dbname != default_db_name:
                try:
                    cur.execute(
                        sql.SQL("REVOKE CONNECT ON DATABASE {} FROM {};").format(
                            sql.Identifier(dbname),
                            sql.Identifier(username)
                        )
                    )
                    print(f"Revoked CONNECT on database '{dbname}' from user '{username}'.")
                except Exception as e:
                    print(f"Warning: Could not revoke CONNECT on database '{dbname}' from user '{username}': {e}")
            else:
                print(f"User '{username}' is allowed to CONNECT to database '{default_db_name}'.")

        # 3. Revoke ALL privileges on the 'public' schema in the default database.
        # This ensures that even if the user connects to the default DB, they cannot
        # automatically access tables/objects in the public schema without explicit grants.
        cur.execute(
            sql.SQL("REVOKE ALL ON SCHEMA public FROM {};").format(
                sql.Identifier(username)
            )
        )
        print(f"Revoked ALL privileges on schema 'public' from user '{username}' in the current database ({default_db_name}).")


        # Commit the transaction to make changes permanent
        cur.connection.commit()
        return True, f"Created user '{username}' with CONNECT access only to '{default_db_name}' and no public schema access."

    except errors.DuplicateObject:
        # If the user already exists, rollback the transaction
        cur.connection.rollback()
        return False, f"Error: User '{username}' already exists."
    except Exception as e:
        # Catch any other database-related errors and rollback
        cur.connection.rollback()
        return False, f"An unexpected error occurred: {e}"

def delete_user(cur, username):
    """
    Deletes a PostgreSQL user (ROLE).

    Args:
        cur: A psycopg2 cursor object.
        username (str): The username of the PostgreSQL role to delete.

    Returns:
        tuple: A tuple (bool, str) indicating success/failure and a message.
    """
    try:
        # Use DROP ROLE to delete the user.
        # IF EXISTS prevents an error if the role does not exist.
        cur.execute(
            sql.SQL("DROP ROLE {}").format(sql.Identifier(username))
        )
        # Commit the transaction
        cur.connection.commit()
        return True, f"Successfully deleted user: {username}."
    except errors.UndefinedObject:
        # If the user does not exist, rollback
        cur.connection.rollback()
        return False, f"Error: User '{username}' does not exist."
    except Exception as e:
        # Catch any other database-related errors and rollback
        cur.connection.rollback()
        return False, f"An unexpected error occurred while deleting user '{username}': {e}"


def create_role(cur, role, login=False):
    """Creates a new PostgreSQL role (group or user without password)."""
    try:
        if login:
            cur.execute(sql.SQL("CREATE ROLE {} WITH LOGIN").format(sql.Identifier(role)))
        else:
            cur.execute(sql.SQL("CREATE ROLE {}").format(sql.Identifier(role)))
        return True, f"Created role: {role}"
    except psycopg2.errors.DuplicateObject:
        cur.connection.rollback()
        return False, f"Role '{role}' already exists."

def grant_role_to_user(cur, user, group):
    """Grants a role (group) to a user."""
    cur.execute(sql.SQL("GRANT {} TO {}").format(sql.Identifier(group), sql.Identifier(user)))

def revoke_role_from_user(cur, user, group):
    """Revokes a role (group) from a user."""
    cur.execute(sql.SQL("REVOKE {} FROM {}").format(sql.Identifier(group), sql.Identifier(user)))

def grant_permission(cur, role, schema, table, privilege):
    """Grants a specific privilege on a table to a role."""
    cur.execute(sql.SQL("GRANT {} ON {}.{} TO {}").format(
        sql.SQL(privilege),
        sql.Identifier(schema),
        sql.Identifier(table),
        sql.Identifier(role)
    ))

def revoke_permission(cur, role, schema, table, privilege):
    """Revokes a specific privilege on a table from a role."""
    cur.execute(sql.SQL("REVOKE {} ON {}.{} FROM {}").format(
        sql.SQL(privilege),
        sql.Identifier(schema),
        sql.Identifier(table),
        sql.Identifier(role)
    ))

def revoke_connect_on_database(cur, dbname, group):
    """Revokes CONNECT privilege on a specific database from a role/group."""
    cur.execute(sql.SQL("REVOKE CONNECT ON DATABASE {} FROM {};")
                .format(sql.Identifier(dbname), sql.Identifier(group)))


# --- Flask routes ---

@app.route('/', methods=['GET'])
def index():
    """Renders the main page with all PostgreSQL role and permission information."""
    selected_group = request.args.get('group')  # For filtering permissions by group/role

    with connect() as conn:
        with conn.cursor() as cur:
            databases = list_databases(cur)
            users = list_users(cur)
            groups = list_groups(cur)
            memberships = list_role_memberships(cur)
            all_roles = get_all_roles(cur)
            schemas = get_user_schemas(cur)
            tables = get_all_tables(cur)
            permissions = list_permissions(cur, role_filter=selected_group)

    # Group → Users
    group_members = defaultdict(list)
    # User → Groups
    user_groups = defaultdict(list)
    for member, group in memberships:
        group_members[group].append(member)
        user_groups[member].append(group)

    return render_template_string(
        TEMPLATE,
        databases=databases,
        users=users,
        groups=groups,
        memberships=memberships,
        permissions=permissions,
        group_members=group_members,
        user_groups=user_groups,
        all_roles=all_roles,
        schemas=schemas,
        tables=tables,
        selected_group=selected_group
    )

@app.route('/create_user', methods=['POST'])
def create_user_route():
    """Handles the creation of a new user."""
    username = request.form['username']
    password = request.form['password']
    # Default to 'postgres' database for connect access if not specified in form
    default_db_name = request.form.get('default_db_name', 'postgres')
    with connect() as conn:
        with conn.cursor() as cur:
            success, msg = create_user(cur, username, password, default_db_name)
        conn.commit() # Commit transaction after operation
    flash(msg)
    return redirect(url_for('index'))

@app.route('/delete_user', methods=['POST'])
def delete_user_route():
    """Handles the deletion of an existing user."""
    username = request.form['username']
    with connect() as conn:
        with conn.cursor() as cur:
            success, msg = delete_user(cur, username)
        conn.commit() # Commit transaction after operation
    flash(msg)
    return redirect(url_for('index'))

@app.route('/create_group', methods=['POST'])
def create_group_route():
    """Handles the creation of a new group (role without login)."""
    groupname = request.form['groupname']
    with connect() as conn:
        with conn.cursor() as cur:
            success, msg = create_role(cur, groupname, login=False)
        conn.commit()
    flash(msg)
    return redirect(url_for('index'))

@app.route('/assign_user_group', methods=['POST'])
def assign_user_group_route():
    """Assigns a user to a group."""
    user = request.form['user']
    group = request.form['group']
    with connect() as conn:
        with conn.cursor() as cur:
            grant_role_to_user(cur, user, group)
        conn.commit()
    flash(f"Granted group '{group}' to user '{user}'")
    return redirect(url_for('index'))

@app.route('/remove_user_from_group', methods=['POST'])
def remove_user_from_group_route():
    """Removes a user from a group."""
    user = request.form['user']
    group = request.form['group']
    with connect() as conn:
        with conn.cursor() as cur:
            revoke_role_from_user(cur, user, group)
        conn.commit()
    flash(f"Removed user '{user}' from group '{group}'")
    return redirect(url_for('index'))

@app.route('/grant_permission', methods=['POST'])
def grant_permission_route():
    """Grants table-level permissions."""
    role = request.form['role']
    schema_table = request.form['table']  # e.g. "public.mytable"
    privilege = request.form['privilege']
    schema, table = schema_table.split('.', 1)
    with connect() as conn:
        with conn.cursor() as cur:
            grant_permission(cur, role, schema, table, privilege)
        conn.commit()
    flash(f"Granted {privilege} on {schema}.{table} to {role}")
    return redirect(url_for('index'))

@app.route('/revoke_permission', methods=['POST'])
def revoke_permission_route():
    """Revokes table-level permissions."""
    role = request.form['role']
    schema_table = request.form['table']  # e.g. "public.mytable"
    privilege = request.form['privilege']
    schema, table = schema_table.split('.', 1)
    with connect() as conn:
        with conn.cursor() as cur:
            revoke_permission(cur, role, schema, table, privilege)
        conn.commit()
    flash(f"Revoked {privilege} on {schema}.{table} from {role}")
    return redirect(url_for('index'))

@app.route('/grant_connect', methods=['POST'])
def grant_connect_route():
    """Grants CONNECT privilege on a database."""
    role = request.form['role']
    database = request.form['database']
    with connect() as conn:
        with conn.cursor() as cur:
            grant_connect_on_database(cur, database, role)
        conn.commit()
    flash(f"Granted CONNECT on database '{database}' to role '{role}'")
    return redirect(url_for('index'))

@app.route('/revoke_connect', methods=['POST'])
def revoke_connect_route():
    """Revokes CONNECT privilege on a database."""
    role = request.form['role']
    database = request.form['database']
    with connect() as conn:
        with conn.cursor() as cur:
            revoke_connect_on_database(cur, database, role)
        conn.commit()
    flash(f"Revoked CONNECT on database '{database}' from role '{role}'")
    return redirect(url_for('index'))


# --- HTML Template ---
TEMPLATE = """
<!doctype html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PostgreSQL Role Manager</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        /* General Body and Container Styling */
        body {
            font-family: 'Inter', sans-serif;
            @apply bg-gradient-to-br from-blue-50 to-indigo-100 text-gray-800 p-6;
        }
        .container {
            @apply mx-auto max-w-4xl bg-white p-8 rounded-xl shadow-2xl px-10; /* Added px-10 for right shift */
        }

        /* Headings */
        h1 {
            @apply text-4xl font-extrabold text-blue-800 mb-6 text-center;
        }
        h2 {
            @apply text-3xl font-bold text-blue-700 mt-8 mb-4 border-b-2 border-blue-200 pb-2;
        }
        h3 {
            @apply text-2xl font-semibold text-indigo-700 mt-6 mb-3;
        }

        /* Horizontal Rule */
        hr {
            @apply border-t-2 border-gray-300 my-8;
        }

        /* Lists */
        ul {
            /* Removed Tailwind list-disc and pl-6 to use custom marker styling */
            list-style-type: disc;
            list-style-position: inside;
            margin-left: 1.5rem; /* Equivalent to pl-6 */
            @apply mb-6;
        }
        li {
            @apply mb-2 text-lg;
        }
        li::marker { /* Targeting the list bullet directly */
            color: #22c55e; /* Tailwind green-500 */
        }
        li strong {
            @apply text-blue-600;
        }

        /* Forms */
        form {
            @apply bg-white p-7 rounded-xl shadow-lg mb-8 border border-gray-200;
        }
        label {
            @apply block text-sm font-medium text-gray-700 mb-1 mt-3;
        }
        input[type="text"], input[type="password"], select {
            @apply border-2 border-gray-400 rounded-lg p-2.5 w-full max-w-sm focus:ring-blue-500 focus:border-blue-500 transition-all duration-200 shadow-sm; /* Increased border and added shadow */
        }
        button[type="submit"] {
            @apply bg-blue-600 text-white px-6 py-2.5 rounded-lg font-semibold hover:bg-blue-700 transition-all duration-200 shadow-md mt-4;
        }
        button[type="submit"].bg-red-600 { /* Specific style for delete button */
            @apply bg-red-600 hover:bg-red-700;
        }

        /* Tables */
        table {
            @apply w-full border-collapse rounded-xl overflow-hidden shadow-lg mb-8;
        }
        th, td {
            @apply border border-gray-200 px-5 py-3 text-left align-top;
        }
        th {
            @apply bg-blue-600 text-white font-bold uppercase tracking-wider;
        }
        tbody tr:nth-child(even) {
            @apply bg-gray-50;
        }
        tbody tr:hover {
            @apply bg-blue-50 transition-colors duration-150;
        }

        /* Flash Messages */
        .flash-messages {
            @apply bg-green-100 border border-green-400 text-green-700 px-5 py-3 rounded-lg relative mb-6 text-center text-lg font-medium;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="text-4xl font-bold">PostgreSQL Role & Permission Manager</h1>

        {% with messages = get_flashed_messages() %}
            {% if messages %}
                <div class="flash-messages">
                    <ul class="list-none p-0 m-0">
                        {% for message in messages %}
                            <li>{{ message }}</li>
                        {% endfor %}
                    </ul>
                </div>
            {% endif %}
        {% endwith %}

        <h2 class="text-2xl font-semibold">Databases</h2>
        <ul>
            {% for db in databases %}
                <li>{{ db }}</li>
            {% endfor %}
        </ul>

        <hr>

        <h2 class="text-2xl font-semibold">Users</h2>
        <ul>
            {% for u in users %}
                <li>
                    <strong class="text-lg">{{ u }}</strong>
                    {% if user_groups[u] %}
                        — Groups: {{ user_groups[u] | join(', ') }}
                    {% else %}
                        — No groups
                    {% endif %}
                </li>
            {% endfor %}
        </ul>

        <h3 class="text-xl font-semibold">Create User</h3>
        <form method="post" action="{{ url_for('create_user_route') }}">
            <label for="username_create">Username:</label>
            <input type="text" id="username_create" name="username" required>
            <label for="password_create">Password:</label>
            <input type="password" id="password_create" name="password" required>
            <label for="default_db_name_create">Default Connect DB:</label>
            <select id="default_db_name_create" name="default_db_name">
                {% for db in databases %}
                    <option value="{{ db }}" {% if db == 'postgres' %}selected{% endif %}>{{ db }}</option>
                {% endfor %}
            </select>
            <button type="submit">Create User</button>
        </form>

        <h3 class="text-xl font-semibold">Delete User</h3>
        <form method="post" action="{{ url_for('delete_user_route') }}">
            <label for="username_delete">Select User to Delete:</label>
            <select id="username_delete" name="username" required>
                {% for u in users %}
                    <option value="{{ u }}">{{ u }}</option>
                {% endfor %}
            </select>
            <button type="submit" class="bg-red-600">Delete User</button>
        </form>

        <hr>

        <h2 class="text-2xl font-semibold">Groups</h2>
        <ul>
            {% for g in groups %}
                <li>
                    <strong class="text-lg">{{ g }}</strong>
                    {% if group_members[g] %}
                        — Members: {{ group_members[g] | join(', ') }}
                    {% else %}
                        — No members
                    {% endif %}
                </li>
            {% endfor %}
        </ul>

        <h3 class="text-xl font-semibold">Create Group</h3>
        <form method="post" action="{{ url_for('create_group_route') }}">
            <label for="groupname_create">Group Name:</label>
            <input type="text" id="groupname_create" name="groupname" required>
            <button type="submit">Create Group</button>
        </form>

        <h3 class="text-xl font-semibold">Grant CONNECT on Database</h3>
        <form method="post" action="{{ url_for('grant_connect_route') }}">
            <label for="role_grant_connect">Role:</label>
            <select id="role_grant_connect" name="role" required>
                {% for role in all_roles %}
                    <option value="{{ role }}">{{ role }}</option>
                {% endfor %}
            </select>

            <label for="database_grant_connect">Database:</label>
            <select id="database_grant_connect" name="database" required>
                {% for db in databases %}
                    <option value="{{ db }}">{{ db }}</option>
                {% endfor %}
            </select>

            <button type="submit">Grant CONNECT</button>
        </form>

        <h3 class="text-xl font-semibold">Assign User to Group</h3>
        <form method="post" action="{{ url_for('assign_user_group_route') }}">
            <label for="user_assign">User:</label>
            <select id="user_assign" name="user" required>
                {% for u in users %}
                    <option value="{{ u }}">{{ u }}</option>
                {% endfor %}
            </select>
            <label for="group_assign">Group:</label>
            <select id="group_assign" name="group" required>
                {% for g in groups %}
                    <option value="{{ g }}">{{ g }}</option>
                {% endfor %}
            </select>
            <button type="submit">Assign</button>
        </form>

        <h3 class="text-xl font-semibold">Remove User from Group</h3>
        <form method="post" action="{{ url_for('remove_user_from_group_route') }}">
            <label for="user_remove">User:</label>
            <select id="user_remove" name="user" required>
                {% for u in users %}
                    <option value="{{ u }}">{{ u }}</option>
                {% endfor %}
            </select>
            <label for="group_remove">Group:</label>
            <select id="group_remove" name="group" required>
                {% for g in groups %}
                    <option value="{{ g }}">{{ g }}</option>
                {% endfor %}
            </select>
            <button type="submit">Remove</button>
        </form>

        <hr>

        <h2 class="text-2xl font-semibold">Permissions</h2>

        <form method="get" action="{{ url_for('index') }}" class="inline-block">
            <label for="filter_role">Filter by Role:</label>
            <select id="filter_role" name="group" onchange="this.form.submit()">
                <option value="">-- All --</option>
                {% for role in all_roles %}
                    <option value="{{ role }}" {% if selected_group == role %}selected{% endif %}>{{ role }}</option>
                {% endfor %}
            </select>
            <noscript><button type="submit">Filter</button></noscript>
        </form>

        <table>
            <thead>
                <tr>
                    <th>Role</th>
                    <th>Schema</th>
                    <th>Table</th>
                    <th>Privilege</th>
                </tr>
            </thead>
            <tbody>
                {% for grantee, schema, table, privilege in permissions %}
                    <tr>
                        <td>{{ grantee }}</td>
                        <td>{{ schema }}</td>
                        <td>{{ table }}</td>
                        <td>{{ privilege }}</td>
                    </tr>
                {% else %}
                    <tr><td colspan="4">No permissions found.</td></tr>
                {% endfor %}
            </tbody>
        </table>

        <h3 class="text-xl font-semibold">Grant Permission</h3>
        <form method="post" action="{{ url_for('grant_permission_route') }}">
            <label for="role_grant_perm">Role:</label>
            <select id="role_grant_perm" name="role" required>
                {% for role in all_roles %}
                    <option value="{{ role }}">{{ role }}</option>
                {% endfor %}
            </select>

            <label for="table_grant_perm">Table:</label>
            <select id="table_grant_perm" name="table" required>
                {% for schema, table in tables %}
                    <option value="{{ schema }}.{{ table }}">{{ schema }}.{{ table }}</option>
                {% endfor %}
            </select>

            <label for="privilege_grant_perm">Privilege:</label>
            <select id="privilege_grant_perm" name="privilege" required>
                <option value="SELECT">SELECT</option>
                <option value="INSERT">INSERT</option>
                <option value="UPDATE">UPDATE</option>
                <option value="DELETE">DELETE</option>
                <option value="TRUNCATE">TRUNCATE</option>
                <option value="REFERENCES">REFERENCES</option>
                <option value="TRIGGER">TRIGGER</option>
            </select>

            <button type="submit">Grant</button>
        </form>

        <h3 class="text-xl font-semibold">Revoke Permission</h3>
        <form method="post" action="{{ url_for('revoke_permission_route') }}">
            <label for="role_revoke_perm">Role:</label>
            <select id="role_revoke_perm" name="role" required>
                {% for role in all_roles %}
                    <option value="{{ role }}">{{ role }}</option>
                {% endfor %}
            </select>

            <label for="table_revoke_perm">Table:</label>
            <select id="table_revoke_perm" name="table" required>
                {% for schema, table in tables %}
                    <option value="{{ schema }}.{{ table }}">{{ schema }}.{{ table }}</option>
                {% endfor %}
            </select>

            <label for="privilege_revoke_perm">Privilege:</label>
            <select id="privilege_revoke_perm" name="privilege" required>
                <option value="SELECT">SELECT</option>
                <option value="INSERT">INSERT</option>
                <option value="UPDATE">UPDATE</option>
                <option value="DELETE">DELETE</option>
                <option value="TRUNCATE">TRUNCATE</option>
                <option value="REFERENCES">REFERENCES</option>
                <option value="TRIGGER">TRIGGER</option>
            </select>

            <button type="submit">Revoke</button>
        </form>

        <h3 class="text-xl font-semibold">Revoke CONNECT on Database</h3>
        <form method="post" action="{{ url_for('revoke_connect_route') }}">
            <label for="role_revoke_connect">Role:</label>
            <select id="role_revoke_connect" name="role" required>
                {% for role in all_roles %}
                    <option value="{{ role }}">{{ role }}</option>
                {% endfor %}
            </select>

            <label for="database_revoke_connect">Database:</label>
            <select id="database_revoke_connect" name="database" required>
                {% for db in databases %}
                    <option value="{{ db }}">{{ db }}</option>
                {% endfor %}
            </select>

            <button type="submit">Revoke CONNECT</button>
        </form>
    </div>
</body>
</html>
"""

if __name__ == '__main__':
    app.run(debug=True)
