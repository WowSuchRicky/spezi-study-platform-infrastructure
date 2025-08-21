#!/usr/bin/env python3
"""Local Development Environment Connectivity Test"""

import requests
import sys
import subprocess
from bs4 import BeautifulSoup
import warnings
warnings.filterwarnings('ignore', message='Unverified HTTPS request')

class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    BOLD = '\033[1m'
    NC = '\033[0m'

def green(text): return f"{Colors.GREEN}{text}{Colors.NC}"
def red(text): return f"{Colors.RED}{text}{Colors.NC}"
def yellow(text): return f"{Colors.YELLOW}{text}{Colors.NC}"
def blue(text): return f"{Colors.BLUE}{text}{Colors.NC}"
def cyan(text): return f"{Colors.CYAN}{text}{Colors.NC}"
def bold(text): return f"{Colors.BOLD}{text}{Colors.NC}"

class Tester:
    def __init__(self):
        # Get the local IP address dynamically
        print("Getting local IP address...")
        local_ip = subprocess.check_output(
            "ifconfig | grep 'inet ' | grep -v 127.0.0.1 | head -1 | awk '{print $2}'",
            shell=True, text=True
        ).strip()
        self.base = f"https://{local_ip}.nip.io"
        print(f"Base URL: {self.base}")
        self.session = requests.Session()
        # Try CA cert, fallback to insecure
        print("Testing SSL configuration...")
        try:
            self.session.verify = 'local-dev.crt'
            print("Trying SSL cert verification...")
            self.session.get(f"{self.base}/auth/realms/master", timeout=5)
            print(green("✓ Using trusted SSL"))
        except Exception as e:
            print(f"SSL cert failed: {e}")
            self.session.verify = False
            print("Falling back to insecure SSL...")
            print(yellow("⚠ Using insecure SSL"))
    
    def test_services(self):
        """Test basic service connectivity"""
        print(f"\n{bold('=== Service Connectivity ===')}")
        services = [
            ("/auth/realms/master", "Keycloak"),
            ("/oauth2/ping", "OAuth2-Proxy"), 
            ("", "Frontend")
        ]
        
        for path, name in services:
            try:
                print(f"Testing {name} at {self.base}{path}...")
                r = self.session.get(f"{self.base}{path}", timeout=10, allow_redirects=False)
                if r.status_code < 400:
                    print(green(f"✓ {name}: HTTP {r.status_code}"))
                else:
                    print(red(f"✗ {name}: HTTP {r.status_code}"))
                    
                if r.status_code in [301, 302, 307, 308]:
                    location = r.headers.get('Location', 'No location header')
                    print(cyan(f"  → Redirects to: {location}"))
                if r.status_code >= 400:
                    print(red(f"  ✗ Error response"))
                    return False
            except Exception as e:
                print(red(f"✗ {name}: {e}"))
                return False
        return True
    
    def authenticate(self, username, password):
        """Try to authenticate and return (success, can_access_backend)"""
        print(f"Starting authentication for user: {username}")
        session = requests.Session()
        session.verify = self.session.verify
        
        print(blue(f"  → Step 1: Accessing frontend for user {username}"))
        try:
            # Get initial page (without following redirects to see what happens)
            r = session.get(self.base, allow_redirects=False, timeout=10)
            print(f"    Initial response: HTTP {r.status_code}")
            
            if r.status_code in [301, 302]:
                location = r.headers.get('Location', '')
                print(cyan(f"    Redirected to: {location}"))
                # Follow the redirect
                r = session.get(location, allow_redirects=True, timeout=10)
                print(f"    After redirect: HTTP {r.status_code}")
            
            # Already authenticated?
            if 'Hostname' in r.text and 'RemoteAddr' in r.text:
                print(green(f"    ✓ Already authenticated - found whoami content"))
                return True, True
            
            print(blue(f"  → Step 2: Looking for login form"))
            # Find login form
            soup = BeautifulSoup(r.text, 'html.parser')
            form = soup.find('form')
            if not form:
                print(red(f"    ✗ No login form found"))
                return False, False
            
            action = form.get('action')
            if action.startswith('/'):
                action = f"{self.base}{action}"
            print(f"    Form action: {action}")
            
            print(blue(f"  → Step 3: Submitting credentials"))
            # Submit credentials (don't follow redirects to see immediate response)
            r = session.post(action, data={'username': username, 'password': password}, 
                           allow_redirects=False, timeout=10)
            print(f"    Login POST response: HTTP {r.status_code}")
            
            if r.status_code in [301, 302]:
                location = r.headers.get('Location', '')
                print(cyan(f"    Login redirected to: {location}"))
                # Follow the redirect chain
                r = session.get(location, allow_redirects=True, timeout=10)
                print(f"    Final response: HTTP {r.status_code}")
            
            print(blue(f"  → Step 4: Checking final access"))
            # Check what we actually got
            if 'Hostname' in r.text and 'RemoteAddr' in r.text:
                print(green(f"    ✓ Successfully accessing whoami backend"))
                return True, True
            elif '403' in r.text or 'Forbidden' in r.text:
                print(green(f"    ✓ Authenticated but access denied (403)"))
                return True, False
            elif 'keycloak' in r.url.lower() or 'login' in r.text.lower():
                print(red(f"    ✗ Still on login page - auth failed or access denied"))
                return False, False
            else:
                print(yellow(f"    ? Unexpected response content (length: {len(r.text)})"))
                print(f"    Final URL: {r.url}")
                print(f"    Content preview: {r.text[:200]}...")
                return False, False
            
        except Exception as e:
            print(red(f"    ✗ Exception during authentication: {e}"))
            return False, False
    
    def test_auth(self):
        """Test authentication and authorization"""
        print(f"\n{bold('=== Authentication & Authorization ===')}")
        
        # Test authorized user
        auth_ok, can_access = self.authenticate("testuser", "password123")
        if auth_ok and can_access:
            print(green("✓ Authorized user (testuser) can access backend"))
            auth_test = True
        else:
            print(red("✗ Authorized user (testuser) cannot access backend"))
            auth_test = False
        
        # Test unauthorized user  
        unauth_ok, cant_access = self.authenticate("testuser2", "password456")
        if unauth_ok and not cant_access:
            print(green("✓ Unauthorized user (testuser2) correctly denied backend access"))
            unauth_test = True
        else:
            print(red("✗ Unauthorized user (testuser2) access control failed"))
            unauth_test = False
        
        return auth_test and unauth_test
    
    def run(self):
        """Run all tests"""
        print(bold("Local Development Environment Test"))
        print(bold("=" * 40))
        
        services_ok = self.test_services()
        auth_ok = self.test_auth()
        
        print(f"\n{bold('=== Summary ===')}")
        if services_ok and auth_ok:
            print(green("✓ All tests passed!"))
            print(f"Access: {self.base}")
            print("Auth: testuser/password123 | Unauth: testuser2/password456")
            return 0
        else:
            print(red("✗ Some tests failed"))
            return 1

if __name__ == "__main__":
    sys.exit(Tester().run())