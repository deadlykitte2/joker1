#!/usr/bin/env python3
"""
MikroTik API Connection Test Script
Tests both legacy API and API-SSL connections
"""

import socket
import ssl
import hashlib
import binascii
import sys

def encode_length(length):
    """Encode length for MikroTik API protocol"""
    if length < 0x80:
        return bytes([length])
    elif length < 0x4000:
        length |= 0x8000
        return bytes([length >> 8, length & 0xFF])
    elif length < 0x200000:
        length |= 0xC00000
        return bytes([length >> 16, (length >> 8) & 0xFF, length & 0xFF])
    elif length < 0x10000000:
        length |= 0xE0000000
        return bytes([length >> 24, (length >> 16) & 0xFF, (length >> 8) & 0xFF, length & 0xFF])
    else:
        return bytes([0xF0, length >> 24, (length >> 16) & 0xFF, (length >> 8) & 0xFF, length & 0xFF])

def decode_length(sock):
    """Decode length from MikroTik API protocol"""
    c = sock.recv(1)
    if not c:
        return 0
    
    c = ord(c)
    if (c & 0x80) == 0x00:
        return c
    elif (c & 0xC0) == 0x80:
        return ((c & ~0xC0) << 8) + ord(sock.recv(1))
    elif (c & 0xE0) == 0xC0:
        return ((c & ~0xE0) << 16) + (ord(sock.recv(1)) << 8) + ord(sock.recv(1))
    elif (c & 0xF0) == 0xE0:
        return ((c & ~0xF0) << 24) + (ord(sock.recv(1)) << 16) + (ord(sock.recv(1)) << 8) + ord(sock.recv(1))
    elif (c & 0xF8) == 0xF0:
        return (ord(sock.recv(1)) << 24) + (ord(sock.recv(1)) << 16) + (ord(sock.recv(1)) << 8) + ord(sock.recv(1))

def send_sentence(sock, words):
    """Send a sentence to MikroTik API"""
    for word in words:
        word_bytes = word.encode('utf-8')
        sock.send(encode_length(len(word_bytes)) + word_bytes)
    sock.send(encode_length(0))

def recv_sentence(sock):
    """Receive a sentence from MikroTik API"""
    sentence = []
    while True:
        length = decode_length(sock)
        if length == 0:
            break
        word = sock.recv(length).decode('utf-8')
        sentence.append(word)
    return sentence

def test_api_connection(host, port, username, password, use_ssl=False):
    """Test MikroTik API connection"""
    print(f"\n🔍 Testing {'API-SSL' if use_ssl else 'API'} connection to {host}:{port}")
    
    try:
        # Create socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(10)
        
        if use_ssl:
            # Wrap with SSL for API-SSL
            context = ssl.create_default_context()
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
            sock = context.wrap_socket(sock, server_hostname=host)
        
        # Connect
        print(f"📡 Connecting to {host}:{port}...")
        sock.connect((host, port))
        print("✅ TCP connection established")
        
        # Try to receive initial response
        try:
            response = recv_sentence(sock)
            print(f"📥 Initial response: {response}")
        except:
            print("⚠️ No initial response (might be normal)")
        
        # Send login command
        print(f"🔐 Attempting login as '{username}'...")
        send_sentence(sock, ['/login', f'=name={username}', f'=password={password}'])
        
        # Receive login response
        response = recv_sentence(sock)
        print(f"📥 Login response: {response}")
        
        if '!done' in response:
            print("✅ Login successful!")
            
            # Test a simple command
            print("🧪 Testing /system/resource/print command...")
            send_sentence(sock, ['/system/resource/print'])
            
            response = recv_sentence(sock)
            print(f"📥 Resource response: {response[:3]}...")  # Show first few items
            
            # Check if we got system resource data
            if any('uptime=' in item or 'version=' in item or 'cpu=' in item for item in response):
                print("✅ API command executed successfully!")
                print(f"🔍 MikroTik Details:")
                for item in response:
                    if item.startswith('=version='):
                        print(f"   Version: {item[9:]}")
                    elif item.startswith('=board-name='):
                        print(f"   Board: {item[12:]}")
                    elif item.startswith('=uptime='):
                        print(f"   Uptime: {item[8:]}")
                    elif item.startswith('=cpu-load='):
                        print(f"   CPU Load: {item[10:]}%")
                return True
            else:
                print("❌ API command failed - no system data received")
                return False
        else:
            print("❌ Login failed")
            return False
            
    except socket.timeout:
        print("❌ Connection timeout - port might be blocked or service not running")
        return False
    except ConnectionRefusedError:
        print("❌ Connection refused - port is not open or service not listening")
        return False
    except Exception as e:
        print(f"❌ Error: {e}")
        return False
    finally:
        try:
            sock.close()
        except:
            pass

def main():
    if len(sys.argv) != 5:
        print("Usage: python3 test-api-connection.py <host> <api_port> <username> <password>")
        print("Example: python3 test-api-connection.py 16.28.86.103 9520 admin mypassword")
        sys.exit(1)
    
    host = sys.argv[1]
    api_port = int(sys.argv[2])
    username = sys.argv[3]
    password = sys.argv[4]
    
    api_ssl_port = api_port + 1  # Assume API-SSL is API port + 1
    
    print("🚀 MikroTik API Connection Test")
    print(f"🎯 Target: {host}")
    print(f"👤 Username: {username}")
    print(f"🔑 Password: {'*' * len(password)}")
    
    # Test regular API
    api_success = test_api_connection(host, api_port, username, password, use_ssl=False)
    
    # Test API-SSL
    api_ssl_success = test_api_connection(host, api_ssl_port, username, password, use_ssl=True)
    
    print("\n📊 Summary:")
    print(f"API ({api_port}): {'✅ Working' if api_success else '❌ Failed'}")
    print(f"API-SSL ({api_ssl_port}): {'✅ Working' if api_ssl_success else '❌ Failed'}")
    
    if not api_success and not api_ssl_success:
        print("\n🔧 Troubleshooting steps:")
        print("1. Check if NAT rules are set up on VPS")
        print("2. Verify MikroTik API services are enabled")
        print("3. Check firewall rules on both VPS and MikroTik")
        print("4. Verify VPN connection is established")

if __name__ == "__main__":
    main()
