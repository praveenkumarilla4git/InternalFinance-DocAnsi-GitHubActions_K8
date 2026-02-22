import sqlite3

# Creates DB in the current working directory
connection = sqlite3.connect("finance.db")
cursor = connection.cursor()

# Create table if it doesn't exist
cursor.execute("""
    CREATE TABLE IF NOT EXISTS users_data (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_name TEXT,
        estimated_annual REAL,
        reason_text TEXT,
        db_data TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
""")
connection.commit()
connection.close()