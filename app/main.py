from flask import Flask, render_template, request
import sqlite3
import core
import schema  # Runs the DB setup immediately

app = Flask(__name__)

@app.route("/", methods=["GET", "POST"])
def home():
    estimated_annual = 0
    current_user = "Praveen"
    reason_text = ""
    
    if request.method == "POST":
        monthly_input = float(request.form.get("monthly_amount"))
        reason_text = request.form.get("reason_goal")
        estimated_annual = core.calculate_savings(monthly_input)

        # Save to DB
        connection = sqlite3.connect("finance.db")
        cursor = connection.cursor()
        cursor.execute("INSERT INTO users_data (user_name, estimated_annual, reason_text) VALUES (?, ?, ?)", 
                       (current_user, estimated_annual, reason_text))
        connection.commit()
        connection.close()

    # Read History
    connection = sqlite3.connect("finance.db")
    cursor = connection.cursor()
    cursor.execute("SELECT * FROM users_data")
    db_data = cursor.fetchall()
    connection.close()

    return render_template("index.html", 
                           user_name=current_user, 
                           money=estimated_annual, 
                           reason=reason_text,
                           history=db_data)

if __name__ == "__main__":
    # HOST 0.0.0.0 IS REQUIRED FOR DOCKER/CLOUD ACCESS
    app.run(debug=True, host="0.0.0.0", port=5000)