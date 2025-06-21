# FlaskApp Provisioning with Vagrant

This project provides a complete setup for deploying a Flask web application using **Vagrant** and a custom **provisioning script**.

It installs and configures:

- Nginx as a reverse proxy  
- Gunicorn to serve the Flask app  
- MySQL for data storage  
- UFW and Fail2Ban for server security  
- A sample CRUD interface to manage users

## Features

- Automated provisioning with `provision.sh`
- Flask virtual environment setup with dependencies
- MySQL database + user + sample data
- systemd service for Flask app
- Preconfigured firewall rules and security headers

## Usage

Make sure you have **Vagrant** and **VirtualBox** installed.

Then run the following command in the project folder:
vagrant up

Once it's ready, open your browser and go to:
http://localhost:8080

## Documentation
See the accompanying PDF for a detailed explanation of each step, including service configuration, security considerations, and architecture overview.