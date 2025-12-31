# Secure Server Provisioning: The "Scorched Earth" Protocol

## Overview

This project is an Ansible automation suite designed to provision Ubuntu servers with an extremely high security posture. It moves away from static keys managed on disk and instead adopts a modern, identity-based access model.

It is designed for a **"One-Shot" deployment lifecycle**. It configures identity, enforces strict Multi-Factor Authentication (MFA), and then aggressively removes its own entry mechanism—sealing the server against traditional attack vectors.

### Key Features
* **GitHub as Identity Provider:** SSH public keys are fetched dynamically from GitHub, allowing access control to be managed via Git (Infrastructure as Code).
* **Mandatory 2FA (Google Authenticator):** Every user, including administrators, must use a time-based one-time password (TOTP).
* **Role-Based Access Control (RBAC):** Users are defined in YAML as either standard users or full administrators (sudo).
* **Passwordless Sudo:** Administrators authenticate via strong keys+2FA at the door, allowing seamless sudo access inside without weaker system passwords.
* **"Scorched Earth" Sealing:** The initial bootstrap credentials used by Ansible are irrevocably destroyed at the end of the run.

---

## Security Architecture

Our security model relies on multiple, independent layers of defense. An attacker must compromise a user's physical laptop (private key) **AND** their mobile device (unlocked phone with 2FA app) to gain access.

### The Defense-in-Depth Model

```mermaid
graph TD
    A[Attacker] -->|Attempt SSH| B(Layer 1: SSH Daemon);
    B -- Public Key Challenge --> C{Has Private Key?};
    C -->|No| D[Reject Connection];
    C -->|Yes| E(Layer 2: PAM Stack);
    E -->|Request 2FA Code| F{Valid Google Auth Code?};
    F -->|No| G[Reject Connection];
    F -->|Yes| H[Shell Access Granted];
    H --> I{User Role?};
    I -->|Standard| J[Restricted Shell];
    I -->|Admin| K[Sudo Access NOPASSWD];

    style B fill:#f9f,stroke:#333,stroke-width:2px,color:#000
    style E fill:#ccf,stroke:#333,stroke-width:2px,color:#000
    style K fill:#cfc,stroke:#333,stroke-width:2px,color:#000

```

### The "Scorched Earth" Lifecycle

This is the defining feature of this deployment. We use a temporary "Bootstrap Key" (e.g., an AWS `.pem` file) for the initial configuration. Once the new, secure GitHub-based users are verified to be working, the bootstrap key is deleted from the server.

**Once the playbook completes, the original access method is gone forever.**

```mermaid
sequenceDiagram
    participant Operator as Ansible Operator
    participant Server as Target Server
    participant GitHub as GitHub Config Repo
    participant NewAdmin as New Admin User

    Note over Operator,Server: PHASE 1: BOOTSTRAP
    Operator->>Server: SSH connect using Bootstrap Key (.pem)
    Server-->>Operator: Access Granted (Temp)
    
    Note over Operator,Server: PHASE 2: CONFIGURE
    Operator->>GitHub: Fetch users.yml
    Operator->>Server: Create Users & Install Security Scripts
    Operator->>Server: Enforce 2FA in PAM/SSHD

    Note over Operator,Server: PHASE 3: VERIFY & SEAL
    Operator->>Server: VERIFY: Do new users exist?
    Server-->>Operator: Yes.
    critical SCORCHED EARTH EVENT
        Operator->>Server: DELETE Bootstrap Key (authorized_keys)
    end
    Operator->>Server: Disconnect.

    Note over Server,NewAdmin: PHASE 4: OPERATIONS
    Operator-xServer: SSH connect using Bootstrap Key (.pem)
    Server--xOperator: PERMISSION DENIED (Publickey)
    NewAdmin->>Server: Login via GitHub Key + 2FA
    Server->>NewAdmin: Access Granted.

```

---

## Prerequisites

1. **Ansible Host:** A machine with Ansible installed (e.g., your laptop).
2. **Target Server:** A fresh Ubuntu 22.04/24.04 server.
3. **Bootstrap Credentials:** The initial SSH private key provided by your cloud provider (e.g., `aws-key.pem`) and the default user (e.g., `ubuntu`).
4. **GitHub Configuration Repo:** A public (or accessible via token) repository containing your `users.yml`.

---

## Configuration

### 1. Define Users (`users.yml`)

Create a YAML file in your GitHub repository to define who gets access and their role.

* `role: admin` gets `sudo` access.
* Other roles get standard shell access.

```yaml
---
- username: cmull-code
  role: admin
  
- username: alice-dev
  role: developer

- username: bob-audit
  role: auditor

```

### 2. Configure Inventory (`inventory.ini`)

Define the IP address of your target server(s) and the bootstrap user.

```ini
[targets]
192.0.2.10  # <-- Replace with Server IP

[targets:vars]
ansible_user=ubuntu
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
ansible_ssh_private_key_file=/path/to/initial/bootstrap.pem  # <-- Replace the bootstrapping pem path (useless after provisioning)


```

### 3. Update Playbook Variables (`deploy_server.yml`)

Edit the `vars` section to point to your GitHub repository.

```yaml
  vars:
    admin_user: "ubuntu" # The bootstrap user to be locked out
    user_list_url: "https://raw.githubusercontent.com/YOUR_GITHUB_USER/YOUR_REPO/main/users.yml"

```

---

## Usage (Running the Playbook)

### ⚠️ Critical Warning

This playbook is designed to run **EXACTLY ONCE** against a fresh server. It will delete the credentials you use to run it. Do not run this on an already-configured production server unless you intend to lock yourself out of the bootstrap account.

### Execution

(Remember we use an initial .pem bootstrap key, in my examples I use AWS but depending on company provisioning setup for new servers this could change. If we had a batch of 100 servers provisioned we would inject the initial pem to work with ubuntu. Because this is deleted after run it takes away risk of this .pem being abused on servers that then go on to run critial services)

1. **Run the playbook:**
```bash
ansible-playbook -i inventory.ini playbooks/deploy_server.yml \
  -u ubuntu \
  --ssh-common-args='-o StrictHostKeyChecking=no'
```



**What happens next:**

* Ansible installs necessary packages.
* It creates the users defined in your YAML.
* It configures SSHD and PAM for mandatory 2FA.
* It grants passwordless sudo to admins.
* **Final Step:** It deletes the `authorized_keys` file for the `ubuntu` user, sealing the server.

---

## User Onboarding: The 2FA Flow

This is the experience for a new user listed in `users.yml` logging in for the very first time.

### The First Login (Enrollment)

The system detects that the user has not set up 2FA yet. A special "trap" script intercepts the login session and forces enrollment before a shell is granted.

1. The user SSHes in normally: `ssh username@server-ip`
2. Their SSH key is accepted.
3. The terminal clears, and a large QR code is displayed.
4. The user scans this with Google Authenticator (or Authy, etc.).
5. The user enters the 6-digit code displayed on their phone into the terminal.
6. **Success:** The connection closes. Enrollment is complete.

### Subsequent Logins (Enforcement)

For every future login, the user must provide both their key and the current code.

1. User runs: `ssh username@server-ip`
2. SSH Key is accepted silently.
3. Server prompts: `Verification code:`
4. User enters current 6-digit code from app.
5. Access granted.


## Administrative Operations

Since the servers enforce mandatory interactive 2FA, standard automation tools cannot connect directly. Administrators must use **SSH Multiplexing** to authenticate once and tunnel automation commands through an open socket.

### 1. Setup (One-Time)
Add these aliases to your local shell configuration (`~/.zshrc` or `~/.bashrc`) to streamline the workflow:

```bash
# Open a persistent background connection (The "Open Door")
alias admin-connect="ssh -M -S /tmp/ansible_mux -fnNT"

# Close the background connection
alias admin-disconnect="ssh -S /tmp/ansible_mux -O exit"

```

*Reload your shell: `source ~/.zshrc*`

### 2. Emergency Access (Inject OTP)

If a user loses their phone, you can inject a single-use 8-digit scratch code into their account.

**How it works:**
The Ansible script generates a random code locally, appends it to the user's secret file on the server, and prints the code to your terminal screen. You then copy-paste this code to the user.

```mermaid
sequenceDiagram
    participant Admin
    participant Ansible
    participant Server
    participant User

    Note over Admin,Server: PHASE 1: GENERATION
    Admin->>Server: Open Connection (admin-connect) + Type 2FA
    Admin->>Ansible: Run 'inject_otp.yml'
    Ansible->>Server: Generate & Append Code (e.g. 88229911)
    Server-->>Ansible: Success
    Ansible->>Admin: PRINT TO SCREEN: "Emergency Code: 88229911"
    
    Note over Admin,User: PHASE 2: HANDOFF
    Admin->>User: Sends code via secure channel (Signal/Slack)
    
    Note over User,Server: PHASE 3: ACCESS & BURN
    User->>Server: SSH Connect
    Server->>User: Prompt "Verification code:"
    User->>Server: Enters "88229911"
    Server->>Server: Validates & DELETES code instantly
    Server->>User: Access Granted

```

**Execution:**

```bash
# 1. Connect (Type your 2FA code)
admin-connect cmull-code@<SERVER_IP>

# 2. Run Playbook
ansible-playbook -i inventory.ini playbooks/inject_otp.yml \
  -u cmull-code \ #admin user
  -e "username=alice-dev" \
  --ssh-common-args='-o StrictHostKeyChecking=no -o ControlPath=/tmp/ansible_mux'

# 3. Disconnect
admin-disconnect cmull-code@<SERVER_IP>

```



### Chris thought/feelings
So, I decided to go with the "scorched earth" model, where we provision and seal access behind us. This was because I wanted to adhere strictly to the task's wording: "Login is only allowed via SSH key and one-time password (OTP) using Google Authenticator."

IMO, I would prefer to have a way for admins to bypass this for administration purposes, as it limits our ability to run Ansible on the servers thereafter since the OTP is interactive (there might be a way to pass this, but it's outside the scope for now). However, for now, it's nice to be able to provision admin permissions as per the access_list.yml file (a pull request would require approvals, ensuring a "four-eyes" principle on user/admin additions).

I worked with what I had and utilized GitHub as a way to sync SSH keys to our server(s). In a trading environment, we would probably want some on-prem HA key server so we aren't reliant on GitHub's availability and have more resilience. (Also I would image working with systems teams we could hook into how they do user creation/home dir creation on servers LDAP or the likes)

Using GitHub as a source of truth is nice. Although I have not implemented it, we could, of course, utilize GitHub Actions—for example, so that when the inventory file is updated, the Ansible playbook runs on fresh servers. It would also be a good way to make sure the access_list.yml is kept up-to-date on the servers. This would then mean bootstrap key would be kept as a github variable or perhaps in AWS secret manager and retrieved on pipeline run.

```

```