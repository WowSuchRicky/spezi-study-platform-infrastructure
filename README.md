# spezistudyplatform

<!-- markdown-link-check-disable-next-line -->
[Live Deployment](https://${SPEZI_DOMAIN})

## Prerequisites:
* kubeseal (`brew install kubeseal`)
* Google Cloud SDK/CLI (`brew install google-cloud-sdk`)

## Optional/Nice-to-have:
* [Optional] K9S (`brew install k9s`), highly recommended to maanage the cluster via CLI with a nice TUI.

Note: The Ansible playbooks use the `kubernetes.core.k8s` module. Install control-node Python deps with:

```bash
python -m pip install -r ansible/requirements.txt
```
