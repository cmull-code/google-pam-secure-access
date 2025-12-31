#!/bin/bash
# /usr/local/bin/login_wrapper.sh

# 1. ENROLLMENT CHECK
# We check for the secret file. If missing, we FORCE setup.
SECRET_FILE="${HOME}/.google_authenticator"

if [ ! -f "$SECRET_FILE" ]; then
    echo "=== MANDATORY 2FA SETUP ==="
    echo "You must configure Two-Factor Authentication before accessing this server."
    
    # Run the setup wizard
    # -t (TOTP), -d (No reuse), -f (Force), -r 3 -R 30 (Rate limit), -w 3 (Window)
    google-authenticator -t -d -f -r 3 -R 30 -w 3
    
    if [ $? -ne 0 ]; then
        echo "Setup failed or cancelled. Disconnecting."
        exit 1
    fi
    
    echo "Setup complete. Connection closing. Please reconnect using your code."
    # xit here to force them to re-auth with the new code 
    exit 0
fi

#EXECUTION PASS-THROUGH
# If we are here, 2FA is set up. Now we let them run either cmd or get shell

if [ -n "$SSH_ORIGINAL_COMMAND" ]; then
    eval "$SSH_ORIGINAL_COMMAND"
else
    exec "$SHELL" -l
fi