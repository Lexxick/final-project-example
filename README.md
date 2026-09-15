# final-project-example

Capstone for the DevOps bootcamp: a personal ship microsite built into a container, deployed to AWS
with Terraform and Ansible, monitored with Prometheus and Grafana, and shipped by GitHub Actions.
Every login and deploy goes through AWS Systems Manager – no SSH, no access keys in CI.

- Application: <https://web.doubleadigital.my>
- Monitoring: <https://monitoring.doubleadigital.my>
- Documentation and runbook: <https://lexxick.github.io/final-project-example/>

## Architecture

Three Ubuntu 24.04 `t3.micro` instances in one VPC (`10.0.0.0/24`, `ap-southeast-1a`):

| Host | Subnet | Runs |
| --- | --- | --- |
| `devops-web-server` | public, Elastic IP | the ship container on `:80`, `node_exporter` on `:9100` |
| `devops-ansible-controller` | private | Ansible; reaches the other hosts over SSM |
| `devops-monitoring-server` | private | Prometheus, Grafana, `cloudflared` (outbound tunnel, no open port) |

Only the web server has a public address. Nothing listens on port 22: Session Manager gives the
shell, carries the Ansible connection and receives the deploy trigger from CI.

## Two layers

| Layer | Owns | Lifecycle |
| --- | --- | --- |
| **Foundation** | state bucket, ECR repository and its images, the web Elastic IP (`terraform/bootstrap/`), Cloudflare DNS and tunnel, the two Parameter Store secrets, the `AWS_ROLE_ARN` variable | created once, never destroyed with the stack |
| **Stack** | VPC, subnets, NAT, security groups, IAM roles and the OIDC provider, the three servers (`terraform/`) | `apply` and `destroy` at will; converges itself at boot |

Everything external points at the foundation – DNS at the Elastic IP, CI at the repository name –
so rebuilding the stack changes nothing outside AWS.

## How it works

- **Terraform** builds everything from `terraform-aws-modules` registry modules, state in S3; the
  foundation and the stack are two configurations with two state keys.
- **The controller** installs Ansible from its user data, clones this repository and runs
  `site.yml` – one `terraform apply` brings the whole stack up.
- **Ansible** finds the hosts through the `aws_ec2` inventory (grouped by the `Role` tag) and talks
  to them over the `aws_ssm` connection. Declarative modules only; a second `site.yml` is `changed=0`.
- **Monitoring**: `node_exporter` on the web server, scraped by Prometheus over the private network;
  Grafana is provisioned from files and published through a Cloudflare tunnel.
- **CI/CD** authenticates with OIDC. A pull request touching `terraform/` gets a plan comment; a push
  to `app/` builds the image, pushes `sha-<short>` and `latest` to ECR, and runs `web.yml` on the
  controller through SSM Run Command.

## Layout

```
app/                      Ship microsite (Vite + Three.js), tests, Dockerfile (node build → nginx)
terraform/                VPC, security groups, IAM, EC2 (ec2.tf + templates/controller.sh.tftpl),
                          transfer bucket; registry.tf reads the ECR repository owned by bootstrap/
terraform/bootstrap/      Foundation: ECR repository and the web Elastic IP, own state key
ansible/                  ansible.cfg, requirements, inventory/ (aws_ec2 + group_vars), site.yml,
                          playbooks/ (docker, web, deploy, monitoring + templates and Grafana files)
.github/workflows/        terraform.yml (plan on PR), build-and-deploy.yml, pages.yml
docs/                     Project site (Jekyll): design notes, runbook, screenshots
```

## Bringing it up

Full details in the [runbook](https://lexxick.github.io/final-project-example/#runbook).

### Foundation – once

1. Push the repository; set the Pages source to *GitHub Actions* (the controller clones `main` at boot).
2. State bucket:
   ```bash
   aws s3api create-bucket --bucket devops-bootcamp-terraform-syedazam-507861383583 \
     --region ap-southeast-1 --create-bucket-configuration LocationConstraint=ap-southeast-1
   aws s3api put-bucket-versioning --bucket devops-bootcamp-terraform-syedazam-507861383583 \
     --versioning-configuration Status=Enabled
   aws s3api put-public-access-block --bucket devops-bootcamp-terraform-syedazam-507861383583 \
     --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
   ```
3. Registry and Elastic IP:
   ```bash
   terraform -chdir=terraform/bootstrap init
   terraform -chdir=terraform/bootstrap apply
   ```
4. First image (the controller deploys `latest` at boot; CI pushes every later one):
   ```bash
   image="$(terraform -chdir=terraform/bootstrap output -raw repository_url):latest"
   aws ecr get-login-password | docker login --username AWS --password-stdin "${image%%/*}"
   docker build -t "$image" app/
   docker push "$image"
   ```
5. Cloudflare: `A` record `web` → the bootstrap `web_public_ip` output (proxied, SSL *Flexible*), a
   tunnel (Zero Trust, public hostname `monitoring.<domain>` → `grafana:3000`), and the two secrets
   read at boot:
   ```bash
   aws ssm put-parameter --name /devops-bootcamp/tunnel-token --type SecureString --value '<tunnel token>'
   aws ssm put-parameter --name /devops-bootcamp/grafana-admin-password --type SecureString --value '<password>'
   ```
   Also add the `AWS_ROLE_ARN` repository variable, `arn:aws:iam::507861383583:role/devops-github-actions-role`
   (the name is fixed, so once).

### Stack – any time

```bash
terraform -chdir=terraform init
terraform -chdir=terraform apply
aws ssm start-session --target "$(terraform -chdir=terraform output -raw controller_instance_id)"
sudo tail -f /var/log/cloud-init-output.log        # ends with the PLAY RECAP
```

The controller runs `site.yml` on its own, about ten minutes from `apply` to the recap.
Verify: `https://web.<domain>` shows the ship, `https://monitoring.<domain>` shows the Grafana login,
`curl -s localhost:9090/api/v1/targets` on the monitoring server lists `web-server` as `up`.

Teardown is `terraform -chdir=terraform destroy`; the foundation stays, so the next `apply` comes
back with the last image, the same address, tunnel and secrets – nothing to redo by hand. The OIDC
provider and the CI role are part of the stack, so the first pull-request plan after a teardown fails
at *Configure AWS credentials* until the stack is applied again.

## Credentials

Nothing secret is committed. The tunnel token and the Grafana admin password are SecureString
parameters that `monitoring.yml` reads at run time into a root-only `.env` on the monitoring server.
The Grafana login (`admin` and that password) is shared with reviewers separately. CI holds no
credentials: the GitHub Actions role trusts the repository's OIDC subject and nothing else.

## Screenshots

**The application** – `web.doubleadigital.my` behind the proxied A record.

![The ship](docs/images/ship.png)

**Grafana** – the provisioned *Web Server* dashboard fed by `node_exporter`.

![Web Server dashboard](docs/images/grafana.png)

**Terraform plan on a pull request** – fmt, validate and plan posted by `terraform.yml`.

![Plan comment](docs/images/plan-comment.png)

**Build and deploy** – image built, pushed to ECR and deployed through SSM Run Command.

![Build and deploy run](docs/images/deploy-run.png)

**Session Manager** – a shell on the controller after the second `site.yml` run, `changed=0`.

![Controller session](docs/images/session.png)

## Licence

MIT – see [LICENSE](LICENSE).
