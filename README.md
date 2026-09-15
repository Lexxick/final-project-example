# final-project-example

Capstone for the DevOps bootcamp: a personal ship microsite built into a container, deployed to AWS
with Terraform and Ansible, monitored with Prometheus and Grafana, and shipped by GitHub Actions.
Every login and deploy goes through AWS Systems Manager – no SSH, no access keys in CI.

- Application: <https://web.example.com>
- Monitoring: <https://monitoring.example.com>
- Documentation: <https://lexxick.github.io/final-project-example/>

## Layout

```
app/          Ship microsite (Vite + Three.js) and its Dockerfile
terraform/    VPC, security groups, IAM, ECR, S3 and the three EC2 instances (registry modules only)
ansible/      Dynamic EC2 inventory, aws_ssm connection, playbooks for Docker, the app and monitoring
.github/      Workflows: Terraform plan on PRs, build-and-deploy on push, GitHub Pages
docs/         The project site (GitHub Pages, Jekyll)
```

## Quick start

The full runbook is in [docs/index.md](docs/index.md). In short:

1. Push the repository and set the Pages source to *GitHub Actions*.
2. Create the state bucket, then `terraform apply` from `terraform/`.
3. Add the `AWS_ROLE_ARN` repository variable from the `github_actions_role_arn` output.
4. Configure Cloudflare (proxied `web` A record, tunnel for `monitoring`) and put the two
   Parameter Store secrets.
5. From the controller run `playbooks/docker.yml`, dispatch *Build and deploy*, then `site.yml`.

## Values to change

| Value | Where |
| --- | --- |
| `syedazam` (state bucket, transfer bucket, ECR path, `Owner` tag, callsign) | `terraform/terraform.tfvars`, `terraform/versions.tf`, `ansible/inventory/group_vars/all.yaml`, `ansible/inventory/group_vars/web.yaml`, `.github/workflows/build-and-deploy.yml` |
| `Lexxick/final-project-example` (OIDC trust, controller clone URL) | `terraform/terraform.tfvars` |
| `example.com` | `ansible/inventory/group_vars/monitoring.yaml`, `docs/index.md`, this file |
| Account ID `507861383583` | `ansible/inventory/group_vars/web.yaml` |

## Licence

MIT – see [LICENSE](LICENSE).
