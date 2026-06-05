# Documentation Roadmap

This folder mirrors the Linear roadmap in repository-native Markdown so agents can work from GitHub context without needing Linear open in another pane.

## Reading order

1. [`00-architecture.md`](00-architecture.md)
2. [`01-cloud-to-local-mapping.md`](01-cloud-to-local-mapping.md)
3. [`02-reverse-proxy.md`](02-reverse-proxy.md)
4. [`03-opentofu.md`](03-opentofu.md)
5. [`04-registry.md`](04-registry.md)
6. [`05-secrets.md`](05-secrets.md)
7. [`06-observability.md`](06-observability.md)
8. [`07-deploy-pipeline.md`](07-deploy-pipeline.md)
9. [`08-backup-restore.md`](08-backup-restore.md)
10. [`09-private-access.md`](09-private-access.md)
11. [`10-scheduler-branch.md`](10-scheduler-branch.md)

## Linear mirror

- [`linear/README.md`](linear/README.md)
- [`linear/phase-00-project-scaffold.md`](linear/phase-00-project-scaffold.md)
- [`linear/phase-01-compose-parity.md`](linear/phase-01-compose-parity.md)
- [`linear/phase-02-reverse-proxy.md`](linear/phase-02-reverse-proxy.md)
- [`linear/phase-03-opentofu.md`](linear/phase-03-opentofu.md)
- [`linear/phase-04-local-registry.md`](linear/phase-04-local-registry.md)
- [`linear/phase-05-secrets.md`](linear/phase-05-secrets.md)
- [`linear/phase-06-observability.md`](linear/phase-06-observability.md)
- [`linear/phase-07-self-hosted-cicd.md`](linear/phase-07-self-hosted-cicd.md)
- [`linear/phase-08-backup-restore.md`](linear/phase-08-backup-restore.md)
- [`linear/phase-09-private-access.md`](linear/phase-09-private-access.md)
- [`linear/phase-10-scheduler-branch.md`](linear/phase-10-scheduler-branch.md)

## Repo contract

Every phase document should answer:

- What AWS-managed concept does this replace?
- What open-source/containerized primitive teaches the same idea?
- What files should change?
- What commands prove it works?
- What should agents avoid?

Keep this repo boring in the best way: small changes, visible systems, repeatable checks.
