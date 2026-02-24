from flask import Flask, render_template, request
import sqlite3
import core
import schema  # Runs the DB setup immediately
import socket  # Required for SRE Node Identification

app = Flask(__name__)

# --- SRE HEALTH CHECK ENDPOINT ---
# This allows the Application Load Balancer (ALB) to verify the app is running.
@app.route("/health")
def health_check():
    try:
        # Verify the database connection is active
        connection = sqlite3.connect("finance.db")
        connection.execute("SELECT 1")
        connection.close()
        # Return 200 OK if healthy
        return {"status": "healthy", "node": socket.gethostname()}, 200
    except Exception as e:
        # Return 500 Internal Server Error if something is wrong
        # This will trigger the ALB to mark the node as 'Unhealthy'
        return {"status": "unhealthy", "error": str(e)}, 500

@app.route("/", methods=["GET", "POST"])
def home():
    estimated_annual = 0
    # UPDATED: Your full name for the portfolio
    current_user = "Praveen Kumar Illa"
    reason_text = ""
    
    # Identify which specific container/node is serving the request
    # This is critical for demonstrating Load Balancing in action
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
    # Host 0.0.0.0 is critical for Docker/ALB routing so it listens on all interfaces.
    # Port 5000 matches your Dockerfile and Terraform Target Group settings.
    app.run(debug=False, host="0.0.0.0", port=5000)