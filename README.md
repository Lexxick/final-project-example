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
| `devops-ansible-controller` | private | Ansible with the dynamic EC2 inventory; reaches the other hosts over SSM |
| `devops-monitoring-server` | private | Prometheus, Grafana and `cloudflared` (outbound tunnel, no open port) |

The web server is the only machine with a public address. The other two reach the internet through
the NAT gateway. Nothing listens on port 22 anywhere: the SSM agent that ships with the Ubuntu AMI
gives an audited shell (`aws ssm start-session`), carries the Ansible connection, and receives the
deploy trigger from CI, so the security groups never need to change.

## How it works

**Infrastructure – Terraform.** Everything is built from `terraform-aws-modules` registry modules
with the AWS provider `~> 6.0`. State lives in S3 with the native lock file. Terraform creates the
network, the security groups, one IAM role per server plus the GitHub OIDC role, the ECR repository,
the Ansible transfer bucket and the three instances. The controller's user data installs Ansible in
a virtualenv, clones this repository, pulls the Galaxy dependencies and runs `site.yml`, so one
`terraform apply` brings up the whole stack. The ECR repository lives in `terraform/bootstrap/`, a
second configuration applied once, so images outlive `terraform destroy`.

**Configuration – Ansible.** The `amazon.aws.aws_ec2` inventory groups running instances by their
`Role` tag, so `web` and `monitoring` exist without a static host list. The `amazon.aws.aws_ssm`
connection runs modules over a Session Manager session and moves files through the transfer bucket.
Every task uses a declarative module (`apt`, `file`, `copy`, `template`, `docker_compose_v2`, `uri`),
never `command` or `shell`; a second run of `site.yml` reports `changed=0` on every host.

| Playbook | Hosts | Does |
| --- | --- | --- |
| `site.yml` | all | Imports the three playbooks below, in order |
| `playbooks/docker.yml` | `web`, `monitoring` | Docker Engine and the Compose plugin via `geerlingguy.docker` |
| `playbooks/web.yml` | `web` | ECR credential helper for root, then imports `deploy.yml` |
| `playbooks/deploy.yml` | `web` | Renders `compose.yaml` (ship + node_exporter), `docker compose up` with `pull: always`, waits for HTTP 200 |
| `playbooks/monitoring.yml` | `monitoring` | Grafana provisioning, Prometheus config, secrets from Parameter Store, `docker compose up` |

**Monitoring – Prometheus and Grafana.** `node_exporter` runs on the web server with the host network,
host PID namespace and the root filesystem mounted read-only, so the metrics are the host's, not the
container's. Prometheus scrapes it every 15 s over the private network (the only inbound rule for
`9100` is from the monitoring server). Grafana is provisioned from files – the Prometheus datasource
and the *Web Server* dashboard (target up, uptime, disk, CPU, memory) exist on first start – and
publishes no port at all: `cloudflared` opens an outbound tunnel and Cloudflare routes
`monitoring.doubleadigital.my` to `http://grafana:3000` on the Compose network.

**CI/CD – GitHub Actions.** All workflows authenticate to AWS with OIDC; the repository holds no
access keys, only the `AWS_ROLE_ARN` variable.

| Workflow | Trigger | Steps |
| --- | --- | --- |
| `terraform.yml` | pull request touching `terraform/**` | `fmt -check`, `init`, `validate`, `plan`; the plan is posted (and updated) as a PR comment; fails on formatting or plan errors |
| `build-and-deploy.yml` | push to `main` touching `app/**`, or manual | Build the image with Buildx (tests run inside the build stage), push `sha-<short>` and `latest` to ECR, then `ssm send-command` runs `playbooks/web.yml -e image_tag=sha-…` on the controller and fails unless the command status is `Success` |
| `pages.yml` | push to `main` touching `docs/**`, or manual | Jekyll build of `docs/` and deploy to GitHub Pages |

The deploy job never talks to the web server. It only tells the controller to run the playbook, so
the same code path is used whether a deploy comes from CI or from a shell on the controller.

## Layout

```
app/                          Ship microsite (Vite + Three.js), tests, Dockerfile (node build → nginx)
terraform/
  versions.tf providers.tf    Terraform / provider constraints, S3 backend, default tags
  variables.tf                Region, CIDRs, private IPs, owner, GitHub repository and OIDC subject
  network.tf                  VPC, public and private subnet, IGW, single NAT gateway
  security.tf                 devops-public-sg (80 from anywhere, 9100 from monitoring), devops-private-sg
  iam.tf                      Instance roles, GitHub OIDC provider and the GitHub Actions role
  registry.tf storage.tf      ECR repository (data source), Ansible transfer bucket
  bootstrap/                  Separate configuration owning the ECR repository (applied once, own state key)
  ec2.tf                      The three instances; templates/controller.sh.tftpl bootstraps the controller
  outputs.tf                  Public IP, instance IDs, ECR URL, CI role ARN, Session Manager command
ansible/
  ansible.cfg                 Inventory path, Galaxy paths, YAML result format
  requirements.txt/.yml       ansible-core + boto3; geerlingguy.docker, amazon.aws, community.docker
  inventory/devops.aws_ec2.yaml   Dynamic inventory: Project tag filter, groups from the Role tag
  inventory/group_vars/       aws_ssm connection (all), ECR repository and image tag (web),
                              domain, scrape target and parameter names (monitoring)
  site.yml                    docker.yml + web.yml + monitoring.yml
  playbooks/                  Playbooks, Jinja2 templates, Grafana provisioning files
.github/workflows/            terraform.yml, build-and-deploy.yml, pages.yml
docs/                         Project site (Jekyll): design notes, runbook, screenshots
```

## Bringing it up

Three layers, each a prerequisite of the next. The full runbook is on the
[project site](https://lexxick.github.io/final-project-example/).

| Step | What | Why first |
| --- | --- | --- |
| 1 | Push the repository, set the Pages source to *GitHub Actions* | the controller clones `main` at boot |
| 2 | Create the state bucket (`aws s3api`, three commands) | Terraform needs somewhere to keep state |
| 3 | `terraform -chdir=terraform/bootstrap apply` | the ECR repository, with its own state; never destroyed with the stack |
| 4 | `docker build` + `docker push` the first image | the controller deploys `latest` at boot; CI pushes every later one |
| 5 | Create the Cloudflare tunnel, put the two Parameter Store secrets | `monitoring.yml` reads them at boot |
| 6 | `terraform -chdir=terraform apply` | the stack; the controller then runs `site.yml` unattended (about ten minutes) |
| 7 | Add the proxied `web` A record and the `AWS_ROLE_ARN` repository variable from the outputs | HTTPS for the site; CI can assume the role |

After step 6 nothing is run by hand: `site.yml` waits for the other two instances to register with
Systems Manager, installs Docker, deploys the ship from ECR and starts the monitoring stack. A
second `site.yml` from the controller reports `changed=0`. Later changes flow through CI: a push to
`app/` builds, pushes and deploys; a pull request touching `terraform/` gets a plan comment.

Tearing down is `terraform -chdir=terraform destroy`; steps 2–5 stay, so the next `apply` brings
everything back with the last image, and the same tunnel and secrets.

Verify with `curl -I` on the web server, the Grafana login, `localhost:9090/api/v1/targets` on the
monitoring server, and a pull request that edits a `.tf` file to see the plan comment.

## Credentials

Nothing secret is committed. The Cloudflare tunnel token and the Grafana admin password are
SecureString parameters (`/devops-bootcamp/tunnel-token`, `/devops-bootcamp/grafana-admin-password`)
that `monitoring.yml` reads at run time and writes to a root-only `.env` on the monitoring server.
The Grafana login (`admin` and that password) is shared with reviewers separately, never in this
repository. CI holds no credentials at all: the GitHub Actions role trusts the repository's OIDC
subject and nothing else.

## Licence

MIT – see [LICENSE](LICENSE).
