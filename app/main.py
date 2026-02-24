from flask import Flask, render_template, request
import sqlite3
import core
import schema  # DB initialization
import socket

app = Flask(__name__)

@app.route("/health")
def health_check():
    try:
        connection = sqlite3.connect("finance.db")
        connection.execute("SELECT 1")
        connection.close()
        return {"status": "healthy", "node": socket.gethostname()}, 200
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}, 500

@app.route("/", methods=["GET", "POST"])
def home():
    estimated_annual = 0
    current_user = "Praveen Kumar Illa"
    reason_text = ""
    node_id = socket.gethostname() 

    if request.method == "POST":
        try:
            monthly_input = float(request.form.get("monthly_amount", 0))
            reason_text = request.form.get("reason_goal", "")
            estimated_annual = core.calculate_savings(monthly_input)

            connection = sqlite3.connect("finance.db")
            cursor = connection.cursor()
            cursor.execute(
                "INSERT INTO users_data (user_name, estimated_annual, reason_text) VALUES (?, ?, ?)", 
                (current_user, estimated_annual, reason_text)
            )
            connection.commit()
            connection.close()
        except Exception as e:
            print(f"Error: {e}")

    connection = sqlite3.connect("finance.db")
    cursor = connection.cursor()
    cursor.execute("SELECT * FROM users_data ORDER BY id DESC")
    db_data = cursor.fetchall()
    connection.close()

    return render_template("index.html", 
                           user_name=current_user, 
                           money=estimated_annual, 
                           reason=reason_text,
                           history=db_data,
                           server_id=node_id)

if __name__ == "__main__":
    app.run(debug=False, host="0.0.0.0", port=5000)