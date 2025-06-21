#!/bin/bash

echo "Updating the OS..."
sudo apt update -y && sudo apt upgrade -y 

echo "Installing Python, Pip, Nginx, MySql, fail2ban, ufw..."
sudo apt install -y python3 python3-pip python3-venv nginx mysql-server fail2ban ufw 

echo "Creating App folder" 
sudo mkdir -p /var/www/flaskapp
sudo chown -R www-data:www-data /var/www/flaskapp
cd /var/www/flaskapp

echo "Setting up virtual environment" 
sudo -u www-data python3 -m venv venv 
sudo -u www-data /var/www/flaskapp/venv/bin/pip install --upgrade pip 
sudo -u www-data /var/www/flaskapp/venv/bin/pip install flask gunicorn python-dotenv mysql-connector-python

echo "Creating Flask App"
sudo tee app.py > /dev/null <<'EOF'
from flask import Flask, request, render_template_string, redirect, url_for
from dotenv import load_dotenv
import os
import mysql.connector

load_dotenv()

app = Flask(__name__)

def get_db_connection():
    return mysql.connector.connect(
        host=os.getenv("DB_HOST", "localhost"),
        user=os.getenv("DB_USER", "flaskuser"),
        password=os.getenv("DB_PASSWORD", "admin"),
        database=os.getenv("DB_NAME", "flaskdb")
    )

@app.route("/")
def home():
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM users")
        users = cursor.fetchall()
        cursor.close()
        conn.close()
        return render_template_string('''
            <h1>User List</h1>
            <a href="{{ url_for('add_user') }}">Add New User</a>
            <ul>
            {% for user in users %}
                <li>
                    {{ user.name }} ({{ user.email }})
                    <a href="{{ url_for('user_detail', user_id=user.id) }}">Details</a> |
                    <a href="{{ url_for('delete_user', user_id=user.id) }}" style="color: red;">Delete</a>
                </li>
            {% endfor %}
            </ul>
        ''', users=users)
    except Exception as e:
        return f"Database error: {str(e)}", 500

@app.route("/user/<int:user_id>")
def user_detail(user_id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
        user = cursor.fetchone()
        cursor.close()
        conn.close()
        if user:
            return render_template_string('''
                <h1>User Details</h1>
                <p>Name: {{ user.name }}</p>
                <p>Email: {{ user.email }}</p>
                <a href="{{ url_for('home') }}">Back to List</a>
            ''', user=user)
        return "User not found", 404
    except Exception as e:
        return f"Database error: {str(e)}", 500

@app.route("/add", methods=["GET", "POST"])
def add_user():
    if request.method == "POST":
        try:
            name = request.form["name"]
            email = request.form["email"]
            conn = get_db_connection()
            cursor = conn.cursor()
            cursor.execute("INSERT INTO users (name, email) VALUES (%s, %s)", (name, email))
            conn.commit()
            cursor.close()
            conn.close()
            return redirect(url_for('home'))
        except Exception as e:
            return f"Database error: {str(e)}", 500
    return render_template_string('''
        <h1>Add New User</h1>
        <form method="POST">
            <label for="name">Name</label>
            <input type="text" name="name" required><br><br>
            <label for="email">Email</label>
            <input type="email" name="email" required><br><br>
            <input type="submit" value="Add User">
        </form>
        <a href="{{ url_for('home') }}">Back to List</a>
    ''')

@app.route("/delete/<int:user_id>")
def delete_user(user_id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("DELETE FROM users WHERE id = %s", (user_id,))
        conn.commit()
        cursor.close()
        conn.close()
        return redirect(url_for('home'))
    except Exception as e:
        return f"Database error: {str(e)}", 500

@app.route("/health")
def health():
    return "OK", 200

if __name__ == "__main__":
    app.run(debug=True)
EOF

echo "Creating .env file..."
sudo tee .env > /dev/null <<EOF
DB_HOST=localhost
DB_USER=flaskuser
DB_PASSWORD=admin
DB_NAME=flaskdb
ROOT_PASSWORD=admin
EOF

echo "Creating Gunicorn Script..." 
sudo tee start.sh > /dev/null <<'EOF'
#!/bin/bash
cd /var/www/flaskapp
source venv/bin/activate
set -o allexport
source .env
set +o allexport
exec gunicorn --workers 3 --bind 127.0.0.1:8000 app:app --access-logfile /var/www/flaskapp/gunicorn_access.log --error-logfile /var/www/flaskapp/gunicorn_error.log
EOF

echo "Setting permissions..."
sudo chown -R www-data:www-data /var/www/flaskapp
sudo chmod +x /var/www/flaskapp/start.sh
sudo chmod 600 /var/www/flaskapp/.env

echo "Configuring Nginx..." 
sudo tee /etc/nginx/sites-available/flaskapp > /dev/null <<EOF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        client_max_body_size 10M;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Frame-Options SAMEORIGIN;
}
EOF

sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/flaskapp /etc/nginx/sites-enabled/

echo "Testing Nginx configuration..."
sudo nginx -t

echo "Configuring MySQL..."
echo "Loading environment variables..."
set -o allexport
source /var/www/flaskapp/.env
set +o allexport
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $ROOT_PASSWORD"
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $ROOT_PASSWORD"

sudo systemctl start mysql
sudo systemctl enable mysql
sleep 2

sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$ROOT_PASSWORD';" 
sudo mysql -u root -p$ROOT_PASSWORD -e "DELETE FROM mysql.user WHERE User='';"
sudo mysql -u root -p$ROOT_PASSWORD -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test_%';"
sudo mysql -u root -p$ROOT_PASSWORD -e "FLUSH PRIVILEGES;"

echo "Setting up database and user..."
sudo mysql -u root -p$ROOT_PASSWORD <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "Creating users table and sample data..."
sudo mysql -u root -p$ROOT_PASSWORD $DB_NAME <<EOF
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE
);

INSERT IGNORE INTO users (name, email) VALUES
('user1', 'user1@test.com'),
('user2', 'user2@example.com');
EOF

echo "Creating systemd service..." 
sudo tee /etc/systemd/system/flaskapp.service > /dev/null <<EOF
[Unit]
Description=Flask App with Gunicorn
After=network.target mysql.service
Requires=mysql.service

[Service]
Type=exec
User=www-data
Group=www-data
WorkingDirectory=/var/www/flaskapp
ExecStart=/bin/bash /var/www/flaskapp/start.sh
Restart=always
RestartSec=5
Environment=PATH=/var/www/flaskapp/venv/bin:/usr/bin:/bin
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF


sudo touch /var/www/flaskapp/gunicorn_access.log /var/www/flaskapp/gunicorn_error.log
sudo chown www-data:www-data /var/www/flaskapp/gunicorn_access.log /var/www/flaskapp/gunicorn_error.log
sudo chmod 664 /var/www/flaskapp/gunicorn_access.log /var/www/flaskapp/gunicorn_error.log

echo "Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable flaskapp.service
sudo systemctl start flaskapp.service

sleep 5

sudo systemctl restart nginx

echo "Configuring fail2ban..." 
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

echo "Configuring UFW..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable


echo "Services status"
echo "MySQL:"
sudo systemctl status mysql --no-pager -l
echo ""
echo "Flask App:"
sudo systemctl status flaskapp.service --no-pager -l
echo ""
echo "Nginx:"
sudo systemctl status nginx --no-pager -l
echo ""