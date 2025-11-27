#!/usr/bin/env python3
"""End-to-end checks for frontend access through oauth2-proxy."""

from __future__ import annotations

import argparse
import http.cookiejar
import json
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from html.parser import HTMLParser
from typing import Callable, Iterable, Tuple

DEFAULT_HEADERS = {
    "User-Agent": "SpeziIntegrationTester/1.0",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
}

Credentials = Tuple[str, str]


class LoginFormParser(HTMLParser):
    """Extracts the first login form and its inputs."""

    def __init__(self):
        super().__init__()
        self.action: str | None = None
        self.method: str = "post"
        self._parsing_form = False
        self._form_captured = False
        self.fields: dict[str, str] = {}

    def handle_starttag(self, tag: str, attrs):
        if tag.lower() == "form" and not self._form_captured:
            self._parsing_form = True
            self._form_captured = True
            attr_map = {k.lower(): v for k, v in attrs}
            self.action = attr_map.get("action", "")
            self.method = attr_map.get("method", "post").lower()
        elif tag.lower() == "input" and self._parsing_form:
            attr_map = {k.lower(): v for k, v in attrs}
            name = attr_map.get("name")
            if name:
                self.fields[name] = attr_map.get("value", "")

    def handle_endtag(self, tag: str):
        if tag.lower() == "form" and self._parsing_form:
            self._parsing_form = False


@dataclass
class Response:
    body: str
    url: str
    status: int


@dataclass(frozen=True)
class IntegrationCheck:
    name: str
    run: Callable[[], None]


@dataclass(frozen=True)
class IntegrationFailure:
    check: str
    error: str


class HTTPSession:
    """Minimal HTTP session with cookie handling for integration checks."""

    def __init__(self, *, verify_ssl: bool, timeout: int):
        cookie_jar = http.cookiejar.CookieJar()
        handlers = [urllib.request.HTTPCookieProcessor(cookie_jar)]
        if verify_ssl:
            handlers.extend([urllib.request.HTTPHandler(), urllib.request.HTTPSHandler()])
        else:
            handlers.extend(
                [
                    urllib.request.HTTPHandler(),
                    urllib.request.HTTPSHandler(context=ssl._create_unverified_context()),
                ]
            )
        self._opener = urllib.request.build_opener(*handlers)
        self._timeout = timeout

    def request(
        self,
        url: str,
        *,
        data: bytes | None = None,
        headers: dict[str, str] | None = None,
    ) -> Response:
        hdrs = dict(DEFAULT_HEADERS)
        if headers:
            hdrs.update(headers)
        req = urllib.request.Request(url, data=data, headers=hdrs)
        with self._opener.open(req, timeout=self._timeout) as resp:
            payload = resp.read().decode("utf-8", errors="replace")
            return Response(payload, resp.geturl(), resp.getcode())


class IntegrationTestRunner:
    def __init__(
        self,
        *,
        base_url: str,
        allowed_user: Credentials,
        denied_user: Credentials,
        invalid_user: Credentials,
        verify_ssl: bool,
        timeout: int,
        whoami_path: str,
        keycloak_base_url: str | None = None,
        keycloak_realm: str = "spezistudyplatform",
        argocd_base_url: str | None = None,
        argocd_health_path: str = "/healthz",
        extra_checks: Iterable[IntegrationCheck] | None = None,
        only_checks: Iterable[str] | None = None,
        skip_checks: Iterable[str] | None = None,
    ):
        self.base_url = base_url.rstrip("/")
        self.allowed_user = allowed_user
        self.denied_user = denied_user
        self.invalid_user = invalid_user
        self.verify_ssl = verify_ssl
        self.timeout = timeout
        self.whoami_path = whoami_path
        self.keycloak_base_url = keycloak_base_url.rstrip("/") if keycloak_base_url else None
        self.keycloak_realm = keycloak_realm
        self.argocd_base_url = argocd_base_url.rstrip("/") if argocd_base_url else None
        self.argocd_health_path = argocd_health_path
        self._checks: list[IntegrationCheck] = []
        self._allowed_whoami: Response | None = None
        self._only_checks = {name.strip() for name in (only_checks or []) if name and name.strip()} or None
        self._skip_checks = {name.strip() for name in (skip_checks or []) if name and name.strip()}
        self._register_checks(extra_checks or [])
        self._checks = [check for check in self._checks if self._is_check_enabled(check.name)]

    def _register_checks(self, extra_checks: Iterable[IntegrationCheck]) -> None:
        self._checks.extend(
            [
                IntegrationCheck("authorized-user", self._check_allowed_user),
                IntegrationCheck("unauthorized-user", self._check_denied_user),
                IntegrationCheck("invalid-credentials", self._check_invalid_credentials),
            ]
        )
        self._checks.append(IntegrationCheck("oauth2-proxy-headers", self._check_oauth2_proxy_headers))
        if self.keycloak_base_url:
            self._checks.insert(
                0, IntegrationCheck("keycloak-openid-config", self._check_keycloak_openid_configuration)
            )
        if self.argocd_base_url:
            self._checks.append(IntegrationCheck("argocd-login", self._check_argocd_login_entrypoint))
            self._checks.append(IntegrationCheck("argocd-health", self._check_argocd_health))
        self._checks.extend(extra_checks)

    def _is_check_enabled(self, name: str) -> bool:
        if self._only_checks is not None and name not in self._only_checks:
            return False
        if name in self._skip_checks:
            return False
        return True

    def run(self) -> bool:
        if not self._checks:
            raise RuntimeError("No integration checks selected. Adjust --only-check/--skip-check options.")
        print(f"Starting integration checks against {self.base_url} ...")
        print("Selected checks: " + ", ".join(check.name for check in self._checks))
        failures: list[IntegrationFailure] = []
        for check in self._checks:
            print(f"Running {check.name} ...")
            try:
                check.run()
                print(f"Check {check.name} passed.")
            except Exception as exc:  # noqa: BLE001
                failures.append(IntegrationFailure(check=check.name, error=str(exc)))
                print(f"Check {check.name} failed: {exc}")
        if failures:
            failure_summary = "\n".join(f"- {failure.check}: {failure.error}" for failure in failures)
            raise RuntimeError(f"{len(failures)} integration check(s) failed:\n{failure_summary}")
        print("All integration checks passed.")
        return True

    def _new_session(self) -> HTTPSession:
        return HTTPSession(verify_ssl=self.verify_ssl, timeout=self.timeout)

    def _exercise_flow(self, credentials: Credentials, *, login_should_fail: bool = False) -> Response:
        session = self._new_session()
        entry_resp = self._fetch_page(session, self.base_url)
        if self._whoami_ready(entry_resp.body):
            return self._fetch_page(session, self._whoami_url())
        if not self._looks_like_login(entry_resp.body):
            raise RuntimeError("Did not find Keycloak login form when contacting the frontend.")
        print("Logging in via Keycloak...")
        login_resp = self._perform_login(session, entry_resp.body, entry_resp.url, credentials)
        if login_should_fail:
            return login_resp
        if login_resp.status >= 400:
            return login_resp
        return self._fetch_page(session, self._whoami_url())

    def _fetch_page(self, session: HTTPSession, url: str) -> Response:
        try:
            resp = session.request(url)
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"Request to {url} failed with HTTP {exc.code}: {body[:200]}") from exc
        except urllib.error.URLError as exc:
            raise RuntimeError(f"Request to {url} failed: {exc.reason}") from exc
        print(f"Fetched {resp.url} (HTTP {resp.status})")
        return resp

    def _perform_login(
        self,
        session: HTTPSession,
        login_page: str,
        login_url: str,
        credentials: Credentials,
    ) -> Response:
        parser = LoginFormParser()
        parser.feed(login_page)
        if parser.action is None:
            raise RuntimeError("Unable to locate login form action in Keycloak response.")
        form_data = dict(parser.fields)
        form_data["username"] = credentials[0]
        form_data["password"] = credentials[1]
        payload = urllib.parse.urlencode(form_data).encode()
        post_url = urllib.parse.urljoin(login_url, parser.action or "")
        try:
            resp = session.request(
                post_url,
                data=payload,
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            )
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            print(f"Login request received HTTP {exc.code}")
            return Response(body, exc.geturl(), exc.code)
        print(f"Submitted credentials to {post_url} (HTTP {resp.status})")
        return resp

    def _looks_like_login(self, html: str) -> bool:
        return "kc-form-login" in html or 'name="username"' in html

    def _whoami_url(self) -> str:
        return urllib.parse.urljoin(self.base_url + "/", self.whoami_path.lstrip("/"))

    def _whoami_ready(self, html: str) -> bool:
        return "Hostname" in html and "RemoteAddr" in html

    def _assert_allowed(self, response: Response) -> None:
        if response.status != 200 or not self._whoami_ready(response.body):
            raise RuntimeError(
                f"Authorized user failed to access whoami (status={response.status})."
            )

    def _assert_denied(self, response: Response) -> None:
        if response.status in {401, 403}:
            return
        if self._whoami_ready(response.body):
            raise RuntimeError("Unauthorized user unexpectedly accessed whoami endpoint.")
        if any(token in response.body for token in ["403", "Forbidden", "unauthorized"]):
            return
        raise RuntimeError(
            f"Unauthorized user received unexpected response (status={response.status})."
        )

    def _assert_invalid(self, response: Response) -> None:
        if response.status in {400, 401, 403}:
            return
        if any(
            token.lower() in response.body.lower()
            for token in ["invalid username", "invalid user", "invalid_login", "account is not enabled"]
        ):
            return
        raise RuntimeError(
            f"Invalid credentials produced unexpected response (status={response.status})."
        )

    def _check_allowed_user(self) -> None:
        allowed_resp = self._get_allowed_whoami()
        self._assert_allowed(allowed_resp)
        print("Authorized user successfully reached whoami endpoint.")

    def _check_denied_user(self) -> None:
        denied_resp = self._exercise_flow(self.denied_user)
        self._assert_denied(denied_resp)
        print("Unauthorized user was denied access as expected.")

    def _check_invalid_credentials(self) -> None:
        invalid_resp = self._exercise_flow(self.invalid_user, login_should_fail=True)
        self._assert_invalid(invalid_resp)
        print("Invalid credentials correctly rejected.")

    def _check_oauth2_proxy_headers(self) -> None:
        resp = self._get_allowed_whoami()
        body_lower = resp.body.lower()
        username = self.allowed_user[0].lower()
        header_prefixes = [
            "x-auth-request-user:",
            "x-auth-request-email:",
            "x-forwarded-preferred-username:",
            "x-forwarded-user:",
        ]
        if not any(prefix in body_lower for prefix in header_prefixes):
            raise RuntimeError("whoami response did not include forwarded auth headers from oauth2-proxy.")
        if username and username not in body_lower:
            raise RuntimeError("whoami response did not include the authenticated username.")
        print("OAuth2-proxy forwarded auth headers detected.")

    def _check_keycloak_openid_configuration(self) -> None:
        if not self.keycloak_base_url:
            return
        url = f"{self.keycloak_base_url}/realms/{self.keycloak_realm}/.well-known/openid-configuration"
        session = self._new_session()
        resp = self._fetch_page(session, url)
        if resp.status != 200:
            raise RuntimeError(f"Keycloak OIDC discovery returned HTTP {resp.status}")
        try:
            payload = json.loads(resp.body)
        except json.JSONDecodeError as exc:
            raise RuntimeError("Keycloak OIDC discovery response is not valid JSON.") from exc
        required_keys = ["issuer", "authorization_endpoint", "token_endpoint"]
        missing = [key for key in required_keys if key not in payload]
        if missing:
            raise RuntimeError(f"Keycloak discovery document missing keys: {', '.join(missing)}")
        if self.keycloak_realm not in payload.get("issuer", ""):
            raise RuntimeError("Keycloak discovery document issuer does not reference expected realm.")
        print("Keycloak OIDC discovery document is healthy.")

    def _check_argocd_health(self) -> None:
        if not self.argocd_base_url:
            return
        health_url = urllib.parse.urljoin(self.argocd_base_url + "/", self.argocd_health_path.lstrip("/"))
        session = self._new_session()
        resp = self._fetch_page(session, health_url)
        if resp.status != 200:
            raise RuntimeError(f"Argo CD health endpoint returned HTTP {resp.status}")
        if "healthy" not in resp.body.lower() and "ok" not in resp.body.lower():
            raise RuntimeError("Argo CD health endpoint did not report a healthy status.")
        print("Argo CD health endpoint returned healthy response.")

    def _check_argocd_login_entrypoint(self) -> None:
        if not self.argocd_base_url:
            return
        session = self._new_session()
        resp = self._fetch_page(session, self.argocd_base_url)
        if resp.status not in {200, 302, 303}:
            raise RuntimeError(f"Argo CD login entrypoint returned unexpected HTTP {resp.status}")
        body_lower = resp.body.lower()
        if "argo cd" in body_lower or "argo-cd" in body_lower:
            print("Argo CD login page is reachable.")
            return
        if self.keycloak_base_url and self._looks_like_login(resp.body) and self.keycloak_base_url in resp.url:
            print("Argo CD is gated by Keycloak and redirects to login.")
            return
        if self._looks_like_login(resp.body):
            print("Argo CD requires authentication and shows a login form.")
            return
        raise RuntimeError("Argo CD login entrypoint did not appear to be gated by authentication.")

    def _get_allowed_whoami(self) -> Response:
        if self._allowed_whoami is None:
            self._allowed_whoami = self._exercise_flow(self.allowed_user)
        return self._allowed_whoami


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Basic integration test for the Spezi frontend/whoami stack.")
    parser.add_argument(
        "--base-url",
        default="https://spezi.127.0.0.1.nip.io",
        help="Root URL for the ingress/Traefik endpoint (default: %(default)s)",
    )
    parser.add_argument(
        "--username",
        default="testuser",
        help="Username for the authorized Keycloak account.",
    )
    parser.add_argument(
        "--password",
        default="password123",
        help="Password for the authorized Keycloak account.",
    )
    parser.add_argument(
        "--unauthorized-username",
        default="testuser2",
        help="Username that should be denied access to the whoami endpoint.",
    )
    parser.add_argument(
        "--unauthorized-password",
        default="password456",
        help="Password for the unauthorized Keycloak account.",
    )
    parser.add_argument(
        "--invalid-username",
        default="nouser",
        help="Username that should not exist (invalid credentials test).",
    )
    parser.add_argument(
        "--invalid-password",
        default="wrongpassword",
        help="Password for the invalid credentials test.",
    )
    parser.add_argument(
        "--whoami-path",
        default="/",
        help="Path that should return the whoami response once authenticated (default: %(default)s).",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=30,
        help="Network timeout in seconds for each HTTP request (default: %(default)s).",
    )
    parser.add_argument(
        "--insecure",
        action="store_true",
        help="Disable TLS certificate verification (useful for nip.io/self-signed certs).",
    )
    parser.add_argument(
        "--keycloak-base-url",
        default=None,
        help="Base URL for Keycloak (e.g., https://keycloak.127.0.0.1.nip.io/auth). If omitted, Keycloak health checks are skipped.",
    )
    parser.add_argument(
        "--keycloak-realm",
        default="spezistudyplatform",
        help="Keycloak realm name used for OIDC discovery (default: %(default)s).",
    )
    parser.add_argument(
        "--argocd-base-url",
        default=None,
        help="Base URL for Argo CD (e.g., https://argocd.127.0.0.1.nip.io). If omitted, Argo CD health checks are skipped.",
    )
    parser.add_argument(
        "--argocd-health-path",
        default="/healthz",
        help="Path for Argo CD health endpoint (default: %(default)s).",
    )
    parser.add_argument(
        "--only-check",
        dest="only_checks",
        action="append",
        help="Limit execution to the specified check name (repeatable).",
    )
    parser.add_argument(
        "--skip-check",
        dest="skip_checks",
        action="append",
        help="Skip the specified check name (repeatable).",
    )
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv or sys.argv[1:])
    runner = IntegrationTestRunner(
        base_url=args.base_url,
        allowed_user=(args.username, args.password),
        denied_user=(args.unauthorized_username, args.unauthorized_password),
        invalid_user=(args.invalid_username, args.invalid_password),
        verify_ssl=not args.insecure,
        timeout=args.timeout,
        whoami_path=args.whoami_path,
        keycloak_base_url=args.keycloak_base_url,
        keycloak_realm=args.keycloak_realm,
        argocd_base_url=args.argocd_base_url,
        argocd_health_path=args.argocd_health_path,
        only_checks=args.only_checks,
        skip_checks=args.skip_checks,
    )
    try:
        runner.run()
    except Exception as exc:  # noqa: BLE001
        print(f"Integration test failed: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
