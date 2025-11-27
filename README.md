# spezistudyplatform

<!-- markdown-link-check-disable-next-line -->
[Live Deployment](https://${SPEZI_DOMAIN})

## Prerequisites:
* kubeseal (`brew install kubeseal`)
* Google Cloud SDK/CLI (`brew install google-cloud-sdk`)

## Optional/Nice-to-have:
* [Optional] K9S (`brew install k9s`), highly recommended to manage the cluster via CLI with a nice TUI.

Note: The Ansible playbooks use the `kubernetes.core.k8s` module. Install control-node Python deps with:

```bash
python -m pip install -r ansible/requirements.txt
```

## Integration Test

After bootstrapping either the local KIND or production environment you can
verify the oauth2-proxy/Keycloak flow end-to-end with:

```bash
python tools/run_integration_tests.py --base-url https://spezi.127.0.0.1.nip.io
```

Override `--username/--password` if you customised the test user credentials.
Pass `--insecure` for nip.io/self-signed certificates.
The script also ensures the default unauthorized test user (testuser2/password456) cannot access the whoami endpoint. Override --unauthorized-username/--unauthorized-password if you changed those accounts.
The test harness also exercises an invalid/nonexistent account via --invalid-username/--invalid-password flags.
