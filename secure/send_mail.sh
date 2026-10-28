#!/bin/bash

ENV_FILE="/root/workspaces/secrets/services/timeweb.env"

python3 - "$@" << 'PYTHON_SCRIPT'
import os
import sys
import re
import ssl
import time
import imaplib
from email.message import EmailMessage
from email.utils import formatdate, make_msgid

def parse_env_file(filepath):
    """Parse env file, only lines matching ^[A-Za-z_][A-Za-z0-9_]*="""
    env_vars = {}
    try:
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', line):
                    key, _, value = line.partition('=')
                    env_vars[key] = value
    except FileNotFoundError:
        pass
    return env_vars

def main():
    if len(sys.argv) < 4:
        print("Usage: append_sent.sh <кому> <тема> <файл-с-текстом>", file=sys.stderr)
        sys.exit(1)
    
    to_addr = sys.argv[1]
    subject = sys.argv[2]
    content_file = sys.argv[3]
    
    env_file = os.environ.get('ENV_FILE', '/root/workspaces/secrets/services/timeweb.env')
    env_vars = parse_env_file(env_file)
    
    smtp_user = env_vars.get('SMTP_USER')
    smtp_pass = env_vars.get('SMTP_PASS')
    
    if not all([smtp_user, smtp_pass]):
        print("Missing SMTP configuration", file=sys.stderr)
        sys.exit(1)
    
    try:
        with open(content_file, 'r') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Content file not found: {content_file}", file=sys.stderr)
        sys.exit(1)
    
    msg = EmailMessage()
    msg['From'] = smtp_user
    msg['To'] = to_addr
    msg['Subject'] = subject
    msg['Date'] = formatdate()
    msg['Message-ID'] = make_msgid()
    msg.set_content(content)
    
    try:
        imap_host = env_vars.get('IMAP_HOST')
        if not imap_host:
            smtp_host = env_vars.get('SMTP_HOST')
            if smtp_host:
                imap_host = smtp_host.replace('smtp.', 'imap.') if 'smtp.' in smtp_host else smtp_host
            else:
                print("Missing IMAP_HOST configuration", file=sys.stderr)
                sys.exit(1)
        
        context_imap = ssl.create_default_context()
        with imaplib.IMAP4_SSL(imap_host, 993, ssl_context=context_imap, timeout=30) as imap:
            status, _ = imap.login(smtp_user, smtp_pass)
            
            if os.environ.get('MAIL_DEBUG') == '1':
                list_status, folders = imap.list()
                if list_status == 'OK':
                    for folder in folders:
                        folder_str = folder.decode('utf-8') if isinstance(folder, bytes) else folder
                        print(f"IMAP-FOLDER: {folder_str}", file=sys.stderr)
            
            sent_folder = None
            if status == 'OK':
                # First, look for RFC 6154 \Sent attribute
                for folder in folders:
                    folder_str = folder.decode('utf-8') if isinstance(folder, bytes) else folder
                    if '\\Sent' in folder_str or '\\Sent' in folder_str.replace(' ', '').lower():
                        # Extract folder name (last token, usually in quotes or after delimiter)
                        parts = folder_str.split()
                        if len(parts) >= 3:
                            # Folder name is typically the last part
                            folder_name = parts[-1]
                            # Remove quotes if present
                            if folder_name.startswith('"') and folder_name.endswith('"'):
                                folder_name = folder_name[1:-1]
                            sent_folder = folder_name
                            break
                
                # Fallback: search by name
                if not sent_folder:
                    for folder in folders:
                        folder_str = folder.decode('utf-8') if isinstance(folder, bytes) else folder
                        if any(x in folder_str for x in ['Sent', 'INBOX.Sent', 'Отправ']):
                            parts = folder_str.split()
                            if len(parts) >= 3:
                                folder_name = parts[-1]
                                if folder_name.startswith('"') and folder_name.endswith('"'):
                                    folder_name = folder_name[1:-1]
                                sent_folder = folder_name
                                break
                
                # If still not found, create "Sent" folder
                if not sent_folder:
                    try:
                        imap.create("Sent")
                        sent_folder = "Sent"
                    except Exception:
                        print("WARN-SENT-COPY-FAILED: Could not create Sent folder", file=sys.stderr)
                        sent_folder = None
            
            if sent_folder:
                # Quote folder name if it contains space or dot
                folder_to_use = sent_folder
                if ' ' in sent_folder or '.' in sent_folder:
                    folder_to_use = '"' + sent_folder.replace('\\', '\\\\').replace('"', '\\"') + '"'
                
                imap.append(folder_to_use, '\\Seen', imaplib.Time2Internaldate(time.time()), msg.as_bytes())
                print(f"APPENDED-TO: {sent_folder}")
                sys.exit(0)
            else:
                print("WARN-SENT-COPY-FAILED: Sent folder not found", file=sys.stderr)
                sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
PYTHON_SCRIPT
