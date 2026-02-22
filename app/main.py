from flask import Flask, render_template, request
import sqlite3
import core
import schema  # Runs the DB setup immediately
import socket  # Required for SRE Node Identification

app = Flask(__name__)

@app.route("/", methods=["GET", "POST"])
def home():
    estimated_annual = 0
    # UPDATED: Your full name for the portfolio
    current_user = "Praveen Kumar Illa"
    reason_text = ""
    
    # Identify which specific container/node is serving the request
    node_id = socket.gethostname() 

    if request.method == "POST":
        try:
            monthly_input = float(request.form.get("monthly_amount", 0))
            reason_text = request.form.get("reason_goal", "")
            estimated_annual = core.calculate_savings(monthly_input)

            # Save to DB
            connection = sqlite3.connect("finance.db")
            cursor = connection.cursor()
            cursor.execute(
                "INSERT INTO users_data (user_name, estimated_annual, reason_text) VALUES (?, ?, ?)", 
                (current_user, estimated_annual, reason_text)
            )
            connection.commit()
            connection.close()
        except Exception as e:
            print(f"Error during POST: {e}")

    # Read History (Latest entries first)
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
    # Host 0.0.0.0 is critical for Docker/ALB routing
    app.run(debug=False, host="0.0.0.0", port=5000)