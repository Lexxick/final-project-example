---
layout: default
---

## Links

| | |
| --- | --- |
| Application | <https://web.example.com> |
| Monitoring (Grafana) | <https://monitoring.example.com> |
| Repository | <https://github.com/Lexxick/final-project-example> |

## Architecture

<pre class="mermaid">
flowchart TB
    dev([Developer]) -- git push / PR --> gh[GitHub]
    gh -- OIDC, no keys --> actions[GitHub Actions]
    users([Browser]) -- HTTPS --> cf[Cloudflare]

    subgraph aws [AWS ap-southeast-1 · account 507861383583]
        ecr[(ECR<br/>devops-bootcamp/final-project-syedazam)]
        ssm[[Systems Manager<br/>Session Manager · Run Command · Parameter Store]]
        s3[(S3<br/>terraform state · ansible transfers)]
        subgraph vpc [devops-vpc 10.0.0.0/24]
            igw[devops-igw]
            subgraph pub [devops-public-subnet 10.0.0.0/25]
                web[devops-web-server<br/>10.0.0.5 + EIP<br/>ship :80 · node_exporter :9100]
                ngw[devops-ngw]
            end
            subgraph priv [devops-private-subnet 10.0.0.128/25]
                ctl[devops-ansible-controller<br/>10.0.0.135]
                mon[devops-monitoring-server<br/>10.0.0.136<br/>prometheus · grafana · cloudflared]
            end
        end
    end

    actions -- build & push --> ecr
    actions -- SendCommand --> ssm
    ssm -- web.yml --> ctl
    ctl -- aws_ssm connection --> web
    ctl -- aws_ssm connection --> mon
    web -- pull image --> ecr
    cf -- proxied A record --> igw --> web
    mon -- scrape :9100 --> web
    mon -- outbound tunnel --> cf
    priv -.-> ngw -.-> igw
</pre>
<script type="module">
  import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";
  mermaid.initialize({ startOnLoad: true, theme: "neutral" });
</script>

Three Ubuntu 24.04 `t3.micro` instances in one VPC. The web server is the only machine with a public
address. The Ansible controller and the monitoring server sit in the private subnet and reach the
internet through the NAT gateway. Nothing listens on port 22 anywhere: every interactive or automated
login goes through AWS Systems Manager, and Grafana is published through a Cloudflare tunnel instead
of an open port.

## Phase 1 – Infrastructure (Terraform)

Everything is built from `terraform-aws-modules` registry modules with the AWS provider `~> 6.0`.
State lives in S3 (`devops-bootcamp-terraform-syedazam-507861383583`) with the native S3 lock file.

| File | Owns |
| --- | --- |
| `versions.tf` | Terraform / provider constraints and the S3 backend |
| `providers.tf` | Region and `default_tags` (`Project`, `Owner`, `ManagedBy`) |
| `variables.tf`, `terraform.tfvars` | Region, CIDRs, private IPs, owner, GitHub repository |
| `network.tf` | `vpc` module: VPC, one public and one private subnet, IGW, single NAT gateway, route tables |
| `security.tf` | `security-group` module: `devops-public-sg` (80 from anywhere, 9100 from the monitoring server) and `devops-private-sg` (no inbound) |
| `iam.tf` | `iam` module: one role per server, the GitHub OIDC provider and the GitHub Actions role |
| `registry.tf` | `ecr` module: the application repository, scan on push, keep the last 10 images |
| `storage.tf` | `s3-bucket` module: transfer bucket for the Ansible SSM connection, objects expire after a day |
| `ec2.tf`, `templates/controller.sh.tftpl` | `ec2-instance` module ×3 and the controller bootstrap script |
| `outputs.tf` | Public IP, instance IDs, ECR URL, CI role ARN, the Session Manager command |

### IAM

| Role | Trust | Permissions |
| --- | --- | --- |
| `devops-web-role` | EC2 | `AmazonSSMManagedInstanceCore`; pull from the one ECR repository |
| `devops-controller-role` | EC2 | `AmazonSSMManagedInstanceCore`; `ssm:StartSession` on instances tagged `Project=devops-bootcamp`; `ec2:DescribeInstances` for the dynamic inventory; read `/devops-bootcamp/*` parameters; read/write the transfer bucket |
| `devops-monitoring-role` | EC2 | `AmazonSSMManagedInstanceCore` only |
| `devops-github-actions-role` | GitHub OIDC, `repo:Lexxick@234321683/final-project-example@1370915813:*` | `ReadOnlyAccess` for `terraform plan`; push to the ECR repository; `ssm:SendCommand` on instances tagged `Role=controller`; write the state lock file |

Every policy is scoped to the resource it is for; the only `*` resources are actions that do not
support resource-level permissions (`ecr:GetAuthorizationToken`, `ec2:DescribeInstances`,
`ssm:GetCommandInvocation`).

### Why no port 22

The SSM agent ships with the Ubuntu AMI and only needs outbound HTTPS. With the instance profile
above, `aws ssm start-session` gives an audited shell without a key pair, a bastion, or an inbound
rule. The same channel carries Ansible (Phase 2) and the deploy trigger from CI (CI/CD), so the
security groups never need to change.

## Phase 2 – Configuration (Ansible)

### Controller bootstrap

`terraform/templates/controller.sh.tftpl` runs once as user data on the controller: it installs the
Session Manager plugin, clones this repository to `/home/ubuntu/final-project-example`, creates a
virtualenv in `/opt/ansible` from `ansible/requirements.txt` (ansible-core 2.21, boto3) and installs
the Galaxy dependencies from `ansible/requirements.yml` (`geerlingguy.docker`, `amazon.aws`,
`community.docker`). Nothing else is ever installed by hand.

### Dynamic inventory and transport

`ansible/inventory/devops.aws_ec2.yaml` asks EC2 for running instances tagged
`Project=devops-bootcamp` and groups them by their `Role` tag, so the groups `web` and `monitoring`
exist without any static host list. `inventory/group_vars/all.yaml` switches the connection plugin to
`amazon.aws.aws_ssm`: modules run over a Session Manager session and files travel through the
transfer bucket. The controller role is the only identity that can open those sessions.

### Playbooks

| Playbook | Hosts | Does |
| --- | --- | --- |
| `site.yml` | all | Imports the three playbooks below, in order |
| `playbooks/docker.yml` | `web`, `monitoring` | Docker Engine and the Compose plugin via `geerlingguy.docker` |
| `playbooks/web.yml` | `web` | ECR credential helper for root, then imports `deploy.yml` |
| `playbooks/deploy.yml` | `web` | Renders `compose.yaml` (ship image + node_exporter), `docker compose up` with `pull: always`, waits for HTTP 200 |
| `playbooks/monitoring.yml` | `monitoring` | Grafana provisioning, Prometheus config, secrets file from Parameter Store, `docker compose up` |

Group variables carry the values that differ per environment: the ECR repository and image tag for
`web`, the domain, the web server's private IP and the two parameter names for `monitoring`.

### Idempotency

Every task uses a declarative module (`apt`, `file`, `copy`, `template`, `docker_compose_v2`,
`uri`) and no `command` or `shell`. A second run of `site.yml` reports `changed=0` on every host.
Deploying a new image is the one intentional change: CI passes `-e image_tag=sha-…` and only the
`ship` service is recreated.

## Phase 3 – Monitoring and access

```
web server                     monitoring server                     Cloudflare
node_exporter :9100  <-scrape-  prometheus :9090 (localhost only)
                                grafana :3000 (no host port)  <---  cloudflared  ==tunnel==>  monitoring.example.com
```

- `node_exporter` runs on the web server with `network_mode: host`, `pid: host` and the root
  filesystem mounted read-only, so CPU, memory, disk and uptime are the host's, not the container's.
- Prometheus scrapes it every 15 s over the private network; the only inbound rule for 9100 is from
  `10.0.0.136/32`.
- Grafana is provisioned from files: the Prometheus datasource and the "Web Server" dashboard exist
  on first start, no clicking. The admin password comes from Parameter Store.
- Grafana publishes no port at all. `cloudflared` opens an outbound tunnel and Cloudflare routes
  `monitoring.example.com` to `http://grafana:3000` on the Compose network. The monitoring server keeps
  no public IP and no inbound rules.
- The web server sits behind a proxied A record with SSL mode *Flexible*: browsers get TLS from
  Cloudflare, the origin speaks plain HTTP on port 80.

## CI/CD (GitHub Actions)

All three workflows authenticate to AWS with OIDC – the repository holds no access keys, only the
`AWS_ROLE_ARN` variable.

| Workflow | Trigger | Steps |
| --- | --- | --- |
| `terraform.yml` | pull request touching `terraform/**` | `fmt -check`, `init`, `validate`, `plan -detailed-exitcode`; the plan is posted (and updated) as a PR comment; the job fails on formatting or plan errors |
| `build-and-deploy.yml` | push to `main` touching `app/**`, or manual | Build the image with Buildx, push `sha-<short>` and `latest` to ECR, then `ssm send-command` runs `playbooks/web.yml -e image_tag=sha-…` on the controller and fails unless the command status is `Success` |
| `pages.yml` | push to `main` touching `docs/**`, or manual | Jekyll build of `docs/` and deploy to GitHub Pages |

The deploy job never talks to the web server. It only tells the controller to run the playbook, so
the same code path is used whether a deploy comes from CI or from a shell on the controller.

## Runbook

### 0. Prerequisites

- AWS CLI v2 authenticated to account `507861383583`, region `ap-southeast-1`.
- Terraform ≥ 1.11, the Session Manager plugin for the AWS CLI.
- A Cloudflare zone for your domain (replace `example.com` throughout).

### 1. Repository and Pages

Push this repository to `github.com/Lexxick/final-project-example` (public). In **Settings →
Pages** set *Source* to **GitHub Actions**. The controller clones the repository at boot, so this
must exist before `terraform apply`.

Repositories created after July 2026 present an immutable OIDC subject that carries the owner and
repository IDs. Put it in `terraform/terraform.tfvars` as `github_oidc_subject`:

```bash
gh api repos/Lexxick/final-project-example --jq '"\(.owner.login)@\(.owner.id)/\(.name)@\(.id)"'
```

### 2. State bucket

```bash
aws s3api create-bucket --bucket devops-bootcamp-terraform-syedazam-507861383583 \
  --region ap-southeast-1 --create-bucket-configuration LocationConstraint=ap-southeast-1
aws s3api put-bucket-versioning --bucket devops-bootcamp-terraform-syedazam-507861383583 \
  --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket devops-bootcamp-terraform-syedazam-507861383583 \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

### 3. Apply

```bash
cd terraform
terraform init
terraform plan
terraform apply
terraform output
```

Keep `web_public_ip` and `github_actions_role_arn` for the next steps.

### 4. Repository variable

**Settings → Secrets and variables → Actions → Variables**: add `AWS_ROLE_ARN` with the value of
`github_actions_role_arn`. Until it is set, the build workflow skips itself.

### 5. Cloudflare

1. **DNS**: add an `A` record `web` → `web_public_ip`, proxy status *Proxied*.
2. **SSL/TLS → Overview**: set the encryption mode to *Flexible*.
3. **Zero Trust → Networks → Tunnels → Create a tunnel** (Cloudflared): name it `devops-bootcamp`,
   copy the token from the install command (the long string after `--token`).
4. In the tunnel's **Public Hostname** tab add `monitoring.example.com` → service type **HTTP**,
   URL `grafana:3000`.

### 6. Parameter Store

```bash
aws ssm put-parameter --name /devops-bootcamp/tunnel-token \
  --type SecureString --value '<tunnel token>'
aws ssm put-parameter --name /devops-bootcamp/grafana-admin-password \
  --type SecureString --value '<a strong password>'
```

### 7. Docker on the fleet

Open a shell on the controller and install Docker on both managed hosts:

```bash
aws ssm start-session --target "$(cd terraform && terraform output -raw controller_instance_id)"
sudo -iu ubuntu
cd ~/final-project-example/ansible
ansible-inventory --graph          # expect @web and @monitoring
ansible-playbook playbooks/docker.yml
```

### 8. First image and deploy

**Actions → Build and deploy → Run workflow** on `main`. The build job pushes the image to ECR; the
deploy job runs `playbooks/web.yml` on the controller and the ship is live on `web_public_ip`.

### 9. Full convergence

Back on the controller:

```bash
ansible-playbook site.yml
```

This brings the monitoring stack up and, because the web server is already deployed, reports no
changes for it. Run it a second time to see `changed=0` everywhere.

### 10. Verify

- <https://web.example.com> shows the ship; `curl -I http://<web_public_ip>` returns `200`.
- <https://monitoring.example.com> shows the Grafana login; the *Web Server* dashboard has data.
- On the monitoring server, `curl -s localhost:9090/api/v1/targets` lists `web-server` as `up`.
- Open a pull request that edits any `.tf` file: the plan appears as a comment.

### 11. Teardown

```bash
cd terraform && terraform destroy
aws ssm delete-parameters --names /devops-bootcamp/tunnel-token /devops-bootcamp/grafana-admin-password
aws s3 rm s3://devops-bootcamp-terraform-syedazam-507861383583 --recursive
aws s3api delete-bucket --bucket devops-bootcamp-terraform-syedazam-507861383583
```

Then delete the tunnel and the DNS records in Cloudflare.

## Screenshots

**The application** – `web.example.com` behind the proxied A record.

![The ship](images/ship.png)

**Grafana** – the provisioned *Web Server* dashboard fed by `node_exporter`.

![Web Server dashboard](images/grafana.png)

**Terraform plan on a pull request** – fmt, validate and plan posted by `terraform.yml`.

![Plan comment](images/plan-comment.png)

**Build and deploy** – image built, pushed to ECR and deployed through SSM Run Command.

![Build and deploy run](images/deploy-run.png)

**Session Manager** – a shell on the controller after the second `site.yml` run, `changed=0`.

![Controller session](images/session.png)
