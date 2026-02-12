import os
from flask import Flask, request, jsonify, send_from_directory
import requests
from google.cloud import firestore

app = Flask(__name__)
db = firestore.Client()

# CONFIGURATION (Store these in Google Secret Manager, not code)
MAILGUN_DOMAIN = os.environ.get("MAILGUN_DOMAIN")
MAILGUN_API_KEY = os.environ.get("MAILGUN_API_KEY")

# Add this route to handle the root URL
@app.route('/')
def home():
    return "Hello from Flask inside Docker!", 200

@app.route('/app')
def serve_app():
    return send_from_directory('public', 'index.html')

@app.route('/send', methods=['POST'])
def send_email():
    """
    Replaces SMTP Sending.
    Accepts JSON payload from your frontend and relays via API.
    """
    data = request.json
    
    # 1. Send via Relay (Bypasses Port 25 Block)
    response = requests.post(
        f"https://api.mailgun.net/v3/{MAILGUN_DOMAIN}/messages",
        auth=("api", MAILGUN_API_KEY),
        data={"from": f"Admin <mail@{MAILGUN_DOMAIN}>",
              "to": data['to'],
              "subject": data['subject'],
              "text": data['body']}
    )
    
    return jsonify({"status": "sent", "provider_response": response.status_code})

@app.route('/incoming', methods=['POST'])
def receive_email():
    """
    Replaces IMAP/POP3.
    Receives parsed email JSON via Webhook from Mailgun/SendGrid.
    """
    # 1. Parse the incoming webhook data
    sender = request.form.get('sender')
    subject = request.form.get('subject')
    body_plain = request.form.get('body-plain')

    # 2. Store in Firestore (Replaces Maildir storage)
    doc_ref = db.collection('inbox').document()
    doc_ref.set({
        'from': sender,
        'subject': subject,
        'body': body_plain,
        'received_at': firestore.SERVER_TIMESTAMP
    })

    return "Email Received and Stored", 200

if __name__ == "__main__":
    # Cloud Run injects the PORT environment variable
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)