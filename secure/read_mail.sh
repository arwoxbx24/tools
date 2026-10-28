#!/bin/bash

ENV_FILE="/root/workspaces/secrets/services/timeweb.env"

python3 - "$@" << 'PYTHON_SCRIPT'
import os
import sys
import re
import ssl
import imaplib
import email
from email.header import decode_header

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

def get_imap_host(smtp_host):
    """Replace smtp prefix with imap"""
    if smtp_host.startswith('smtp.'):
        return 'imap.' + smtp_host[5:]
    return smtp_host.replace('smtp', 'imap', 1)

def decode_mime_words(text):
    """Decode MIME encoded words"""
    if not text:
        return ""
    decoded_parts = decode_header(text)
    result = []
    for part, encoding in decoded_parts:
        if isinstance(part, bytes):
            try:
                result.append(part.decode(encoding or 'utf-8', errors='replace'))
            except:
                result.append(part.decode('utf-8', errors='replace'))
        else:
            result.append(part)
    return ''.join(result)

def get_plain_text(msg):
    """Extract plain text from email"""
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_type() == 'text/plain':
                try:
                    charset = part.get_content_charset() or 'utf-8'
                    return part.get_payload(decode=True).decode(charset, errors='replace')
                except:
                    return ""
    else:
        try:
            charset = msg.get_content_charset() or 'utf-8'
            return msg.get_payload(decode=True).decode(charset, errors='replace')
        except:
            return ""
    return ""

def main():
    unseen_mode = False
    count = 5
    folder = 'INBOX'
    list_mode = False
    
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == '--unseen':
            unseen_mode = True
            i += 1
        elif args[i] == '--list':
            list_mode = True
            i += 1
        elif args[i] == '--folder' and i + 1 < len(args):
            folder = args[i + 1]
            i += 2
        elif args[i].lstrip('-').isdigit():
            count = int(args[i])
            i += 1
        else:
            i += 1
    
    env_file = os.environ.get('ENV_FILE', '/root/workspaces/secrets/services/timeweb.env')
    env_vars = parse_env_file(env_file)
    
    smtp_host = env_vars.get('SMTP_HOST')
    smtp_port = env_vars.get('SMTP_PORT')
    smtp_user = env_vars.get('SMTP_USER')
    smtp_pass = env_vars.get('SMTP_PASS')
    
    if not all([smtp_user, smtp_pass]):
        print("Missing SMTP configuration", file=sys.stderr)
        sys.exit(1)
    
    # Get IMAP host from SMTP host or use IMAP_HOST directly
    if env_vars.get('IMAP_HOST'):
        imap_host = env_vars.get('IMAP_HOST')
    elif smtp_host:
        imap_host = get_imap_host(smtp_host)
    else:
        print("No IMAP or SMTP host found", file=sys.stderr)
        sys.exit(1)
    
    try:
        # Connect to IMAP server
        context = ssl.create_default_context()
        with imaplib.IMAP4_SSL(imap_host, 993, ssl_context=context, timeout=30) as server:
            server.login(smtp_user, smtp_pass)
            
            if list_mode:
                status, folders = server.list()
                if status == 'OK':
                    for folder in folders:
                        decoded = decode_mime_words(folder.decode('utf-8', errors='replace'))
                        print(decoded)
                sys.exit(0)
            
            # Select folder
            if '.' in folder or ' ' in folder:
                server.select('"' + folder + '"')
            else:
                server.select(folder)
            
            # Search for messages
            if unseen_mode:
                status, data = server.search(None, 'UNSEEN')
            else:
                status, data = server.search(None, 'ALL')
            
            if status != 'OK':
                print("Failed to search messages", file=sys.stderr)
                sys.exit(1)
            
            msg_ids = data[0].split()
            if not msg_ids:
                print("No messages found")
                sys.exit(0)
            
            # Get last N messages
            msg_ids = msg_ids[-count:]
            
            for msg_id in reversed(msg_ids):
                status, msg_data = server.fetch(msg_id, '(RFC822)')
                if status != 'OK':
                    continue
                
                raw_email = msg_data[0][1]
                msg = email.message_from_bytes(raw_email)
                
                # Decode date
                date_raw = msg.get('Date', '')
                date_str = decode_mime_words(date_raw) if date_raw else ''
                
                # Decode sender
                from_raw = msg.get('From', '')
                from_str = decode_mime_words(from_raw) if from_raw else ''
                
                # Decode subject
                subject_raw = msg.get('Subject', '')
                subject_str = decode_mime_words(subject_raw) if subject_raw else ''
                
                # Get plain text content
                plain_text = get_plain_text(msg)
                preview = plain_text[:200]
                
                print(f"{date_str} | {from_str} | {subject_str} | {preview}")
            
            sys.exit(0)
            
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
PYTHON_SCRIPT
