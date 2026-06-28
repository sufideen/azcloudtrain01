# Azure Hub-and-Spoke Network — IaC with Bicep & GitHub Actions CI/CD

[![Deploy Hub-Spoke Infrastructure](https://github.com/sufideen/azcloudtrain01/actions/workflows/deploy-infrastructure.yml/badge.svg)](https://github.com/sufideen/azcloudtrain01/actions/workflows/deploy-infrastructure.yml)

> **A real-world infrastructure deployment showcase**
> Co-authored by **Sufyan Gabisi aka sufideen** · [github.com/sufideen](https://github.com/sufideen)

---

## Documentation

| Guide | Description |
|---|---|
| [Setup Guide](docs/setup-guide.md) | Install all tools on macOS, Ubuntu, or Windows — Azure CLI, Bicep, VS Code, Git, GitHub CLI |
| [OIDC Setup](docs/oidc-setup.md) | Configure passwordless Azure authentication for GitHub Actions |
| [Rebuild Dev Environment](docs/rebuild-dev.md) | Deploy or rebuild the `dev` environment via GitHub Actions or Azure CLI |
| [Architecture](infrastructure/docs/architecture.md) | Network diagrams, subnet design, NSG rules |
| [Cost Estimate](infrastructure/docs/cost-estimate.md) | Per-environment cost breakdown and optimisation tips |

---

## What This Project Demonstrates

This repository shows how to design, codify, and deploy a production-grade Azure network architecture using **Infrastructure as Code (IaC)**. Everything you see in Azure was created from code — no clicking through the portal.

| Skill Area | What You Will See |
|---|---|
| Azure Networking | Hub-and-spoke VNet topology with peering, egress via Azure Firewall |
| Security | NSGs with least-privilege rules, WAF v2, Bastion-only RDP/SSH, Key Vault-backed SSL |
| IaC | Modular Azure Bicep templates (11 modules, subscription-scoped) |
| CI/CD | GitHub Actions pipeline with OIDC (passwordless auth), environment gates |
| Environments | Dev / Test / Prod with independent deployment gates and nightly dev teardown |

---

## Architecture Overview

```
                          ┌──────────────────────────────────────┐
                          │              HUB VNet                 │
                          │           10.0.0.0/16                 │
                          │                                       │
                          │  ┌──────────────────────────────┐    │
                          │  │  AppGatewaySubnet             │    │
         Internet ───────────│  App Gateway WAF v2           │    │
         (HTTPS/HTTP)     │  │  OWASP 3.2 · BotMgr · SQLi   │    │
                          │  │  HTTP → HTTPS 301 redirect    │    │
                          │  └──────────────────────────────┘    │
                          │  ┌──────────────────────────────┐    │
                          │  │  AzureFirewallSubnet          │    │
         Egress ◄─────────────  Azure Firewall Standard      │    │
         (filtered)       │  │  Threat Intel · Policy rules  │    │
                          │  └──────────────────────────────┘    │
                          │  ┌──────────────────────────────┐    │
                          │  │  AzureBastionSubnet           │    │
         Admin ◄──────────────  Bastion Standard SKU         │    │
         (SSH/RDP tunnel) │  │  Native client tunnelling     │    │
                          │  └──────────────────────────────┘    │
                          │  GatewaySubnet (VPN/ER ready)         │
                          └────────────┬──────────────────────────┘
                                       │ VNet Peering (bidirectional)
                          ┌────────────▼──────────────────────────┐
                          │           SPOKE VNet                   │
                          │    dev:  10.1.0.0/16                  │
                          │    test: 10.2.0.0/16                  │
                          │    prod: 10.3.0.0/16                  │
                          │                                       │
                          │  WebSubnet   (.1/24) ◄─── HTTPS from App GW only
                          │  AppSubnet   (.2/24) ◄─── HTTP from Web only
                          │  DataSubnet  (.3/24) ◄─── SQL from App only
                          │  AdminSubnet (.4/24) ◄─── RDP/SSH from Bastion only
                          └───────────────────────────────────────┘
```

### Network Security Rules — Least Privilege

| NSG | Allows Inbound | Denies |
|---|---|---|
| nsg-web | HTTPS/HTTP from App Gateway subnet, GatewayManager probes | Everything else |
| nsg-app | Port 80/443/8080 from WebSubnet only | Everything else |
| nsg-data | SQL (1433/5432) from AppSubnet, RDP from AdminSubnet | Everything else |
| nsg-admin | RDP/SSH from BastionSubnet only | Everything else |

---

## Repository Structure

```
azcloudtrain01/
├── .github/
│   └── workflows/
│       ├── deploy-infrastructure.yml     # CI/CD pipeline (Validate → dev → test → prod)
│       └── teardown-infrastructure.yml   # Nightly dev teardown + manual env teardown
├── infrastructure/
│   ├── main.bicep                        # Subscription-scoped orchestrator
│   ├── modules/
│   │   ├── hub-network.bicep             # Hub VNet + subnets + Firewall + Bastion + Route Table
│   │   ├── spoke-network.bicep           # Spoke VNet + subnets
│   │   ├── nsg.bicep                     # 4 Network Security Groups (least-privilege)
│   │   ├── app-gateway.bicep             # App Gateway WAF v2 (OWASP 3.2, BotMgr, HTTP→HTTPS)
│   │   ├── firewall.bicep                # Azure Firewall Standard + Policy
│   │   ├── bastion.bicep                 # Azure Bastion Standard (native client SSH/RDP)
│   │   ├── key-vault.bicep               # Key Vault (RBAC mode, SSL cert store)
│   │   ├── route-table.bicep             # UDR — default egress via Firewall
│   │   ├── storage.bicep                 # Storage account (LRS dev/test, GRS prod)
│   │   ├── vnet-peering.bicep            # Bidirectional peering orchestrator
│   │   └── vnet-peering-single.bicep     # Single-direction peering primitive
│   ├── parameters/
│   │   ├── dev.bicepparam
│   │   ├── test.bicepparam
│   │   └── prod.bicepparam
│   └── scripts/
│       ├── bootstrap-oidc.sh             # One-time OIDC setup
│       └── bootstrap-ssl.sh              # Generate + upload SSL cert to Key Vault
└── README.md
```

---

## The CI/CD Pipeline

The pipeline has four jobs. Each runs only when appropriate — there is no risk of accidentally deploying to prod when fixing a dev bug.

```
┌──────────────────┐
│  Validate Bicep  │  ← Runs on every push and pull request
│  • bicep lint    │
│  • what-if diff  │
└────────┬─────────┘
         │
    ┌────▼────┐    Trigger: push to master  OR  dispatch environment=dev
    │  Deploy │
    │   dev   │
    └─────────┘

    ┌─────────┐    Trigger: dispatch environment=test  (manual approval gate)
    │  Deploy │
    │  test   │
    └─────────┘

    ┌─────────┐    Trigger: dispatch environment=prod  (manual approval gate)
    │  Deploy │
    │  prod   │
    └─────────┘
```

Each environment is an independent dispatch — deploying test does not require dev to have just run, and deploying prod does not require test. Validation always runs first in every case.

### Why OIDC Instead of a Client Secret?

Traditional CI/CD pipelines store an Azure client secret in GitHub. That secret can be leaked, rotated incorrectly, or simply forgotten and left to expire. OIDC (OpenID Connect) eliminates the secret entirely — GitHub proves its identity to Azure using a short-lived signed token, and Azure issues a scoped access token just for that pipeline run.

```
GitHub Actions runner            Azure Active Directory
        │                                │
        │─── "I am run #11 ────────────►│
        │     on sufideen/azcloudtrain01 │── Checks federated credential:
        │     branch: master"            │   repo name ✓  branch ✓
        │                                │
        │◄─── Access token (60 min) ────│
        │                                │
        │─── Deploy to Azure ──────────►│
```

No secrets stored anywhere. No rotation schedule. Every run is independently auditable.

---

## What Gets Deployed Per Environment

Each environment is fully isolated — its own resource groups, VNets, address spaces, and storage replication policy.

| Resource | dev | test | prod |
|---|---|---|---|
| Spoke VNet CIDR | 10.1.0.0/16 | 10.2.0.0/16 | 10.3.0.0/16 |
| Storage replication | LRS | LRS | GRS |
| WAF mode | Detection | Detection | Prevention |
| App Gateway instances | 1 | 1 | 2 |
| Azure Firewall | Standard | Standard | Standard |
| Azure Bastion | Standard | Standard | Standard |
| Resource groups created | 3 | 3 | 3 |

### Azure Resource Groups Created (9 total)

```
rg-contoso-hub-dev        rg-contoso-hub-test        rg-contoso-hub-prod
rg-contoso-spoke-dev      rg-contoso-spoke-test      rg-contoso-spoke-prod
rg-contoso-storage-dev    rg-contoso-storage-test    rg-contoso-storage-prod
```

---

## Key Design Decisions Explained

### Modular Bicep over monolithic templates

Each resource type lives in its own module file. The orchestrator (`main.bicep`) wires them together by passing outputs from one module as inputs to another — for example, the NSG IDs output from `nsg.bicep` are passed into `spoke-network.bicep` to attach them to subnets. This means modules can be tested, versioned, and reused independently.

### Subscription-scoped deployment

The top-level Bicep deployment targets the Azure **subscription**, not a resource group. This lets Bicep create the resource groups themselves as part of the deployment — the entire environment, including its own containers, is self-contained and reproducible from a single `az deployment sub create` command.

### Conditional HTTPS — zero-downtime cert activation

The App Gateway supports both HTTP-only and HTTPS modes from the same template. HTTPS activates by setting `keyVaultCertSecretUri` in the parameter file — no template changes required. When the URI is empty the gateway serves HTTP; when set, port 443 opens, the SSL cert loads from Key Vault, and HTTP automatically issues a **301 Permanent redirect** to HTTPS. This decouples cert management from infrastructure deployment.

### Azure Firewall as default egress

All spoke traffic destined for the internet is routed through the hub Azure Firewall via a User-Defined Route (UDR) in `route-table.bicep`. The Firewall Policy runs in Standard tier with Threat Intelligence in Alert mode, providing a centralised enforcement point for egress filtering and logging.

### Standalone WAF Policy (not inline config)

Azure retired the `webApplicationFirewallConfiguration` inline block on Application Gateway in 2025. This project uses a standalone `ApplicationGatewayWebApplicationFirewallPolicies` resource attached via `firewallPolicy: { id: wafPolicy.id }`. As a separate resource, the WAF policy can be versioned independently, shared across multiple gateways, and updated without modifying the gateway itself.

### Idempotent deployments

Running the pipeline twice produces the same result. Azure Resource Manager compares desired state in the Bicep template against current state and only makes necessary changes. The `what-if` step in the Validate job previews exactly what would change before anything is touched in Azure.

---

## How to Deploy This Yourself

### Prerequisites

- Azure subscription with Contributor access
- GitHub account
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) + [Bicep CLI](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install)
- [GitHub CLI](https://cli.github.com/)

### Step 1 — Fork and clone

```bash
git clone https://github.com/sufideen/azcloudtrain01.git
cd azcloudtrain01
```

### Step 2 — Bootstrap OIDC authentication (one-time)

```bash
chmod +x infrastructure/scripts/bootstrap-oidc.sh
./infrastructure/scripts/bootstrap-oidc.sh \
  --subscription-id <your-subscription-id> \
  --github-repo <your-github-username>/azcloudtrain01
```

This script creates the Azure App Registration, assigns Contributor role at subscription scope, adds federated credentials for each environment and branch, and pushes `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` as GitHub secrets.

### Step 3 — Deploy dev

```bash
gh workflow run "Deploy Hub-Spoke Infrastructure" \
  --repo <your-github-username>/azcloudtrain01 \
  --ref master \
  --field environment=dev
```

### Step 4 — Deploy test and prod when ready

```bash
gh workflow run "Deploy Hub-Spoke Infrastructure" \
  --repo <your-github-username>/azcloudtrain01 \
  --ref master \
  --field environment=test

gh workflow run "Deploy Hub-Spoke Infrastructure" \
  --repo <your-github-username>/azcloudtrain01 \
  --ref master \
  --field environment=prod
```

### Step 5 — Enable HTTPS (optional, after initial deploy)

```bash
# Generate a self-signed cert and upload it to Key Vault
chmod +x infrastructure/scripts/bootstrap-ssl.sh
./infrastructure/scripts/bootstrap-ssl.sh \
  --environment dev \
  --keyvault-name <kv-name-from-output>

# Copy the output URI into infrastructure/parameters/dev.bicepparam:
# param keyVaultCertSecretUri = 'https://<kv>.vault.azure.net/secrets/<cert>'
# Re-run the pipeline — HTTPS activates automatically, HTTP redirects to HTTPS.
```

---

## Cost Estimate — UK South (uksouth)

> Azure Firewall is the dominant cost at ~£720/environment/month. Dev and test environments should be torn down outside working hours using the included teardown workflow.

| Resource | dev / test (each) | prod |
|---|---|---|
| App Gateway WAF v2 (1 CU) | ~£195/month | ~£390/month (2 CU) |
| Azure Firewall Standard | ~£720/month | ~£720/month |
| Azure Bastion Standard | ~£140/month | ~£140/month |
| Public IPs (×2) | ~£3/month | ~£3/month |
| Storage account | <£1/month (LRS) | ~£2/month (GRS) |
| VNet / NSG / Peering | Free | Free |
| **Environment total** | **~£1,058/month** | **~£1,255/month** |
| **All 3 environments 24/7** | | **~£3,371/month (~£40,452/year)** |
| **Dev + test off-hours only** | | **~£2,121/month — use the teardown workflow** |

### Automated cost control — teardown workflow

The repo includes `.github/workflows/teardown-infrastructure.yml` which:
- Runs **nightly at 22:00 UTC (Mon–Fri)** to delete the dev environment automatically
- Supports **manual dispatch** to tear down dev / test / prod / all on demand
- Requires typing `delete-prod` as a confirmation input before touching prod
- Redeploy any environment in ~5 minutes via the deploy pipeline

---

## Phase 2 — Completed ✅

All Phase 2 roadmap items have been designed, implemented in Bicep, and deployed through the CI/CD pipeline.

- [x] Add SSL certificate from Azure Key Vault and enable HTTPS listener on App Gateway
- [x] Enable HTTP → HTTPS redirect rule (301 Permanent — activates automatically when cert URI set)
- [x] Add Azure Firewall Standard in the hub for egress filtering
- [x] Add Azure Bastion Standard SKU with native client SSH/RDP tunnelling
- [x] Configure Azure Monitor / Log Analytics workspace diagnostics
- [x] Add cost management — automated nightly teardown workflow with budget guardrails

---

## Lessons Learned

**Azure API deprecations surface at deploy time, not at lint time.**
The `webApplicationFirewallConfiguration` inline block passed `az bicep build` without error but failed when ARM actually provisioned the resource. Azure had retired the property mid-project. Always run `what-if` before assuming lint means deployable.

**OIDC federated credential subjects are exact-match strings.**
The federated credential subject must exactly match `repo:org/repo:ref:refs/heads/master`. A mismatch produces `AADSTS700213 — No matching federated identity record found`, which reads like a permissions error but is actually a configuration mismatch. Check the subject string character by character.

**GitHub Actions job chaining and `if` conditions interact unexpectedly.**
When a job is skipped due to an `if` condition evaluating to false, any downstream jobs that `needs` it are also skipped — even if the downstream job has its own `if` condition that would evaluate to true. The solution: give each environment job `needs: validate` directly, rather than chaining dev → test → prod.

**Deployment naming conflicts block re-runs.**
Azure ARM deployments at subscription scope are named. Re-running with the same name while a previous run is still `Running` produces a `DeploymentActive` conflict. Using `${{ github.run_number }}` in the deployment name ensures each pipeline run gets a unique name.

**Azure Policy enforcement at management group scope blocks non-compliant locations.**
The `alz-allowed-locations` policy on the `ict` management group silently allowed `az bicep build` and `what-if` to pass, then blocked `az deployment sub create` with a policy violation. All resource deployments — including the workflow `--location` flag — must match the allowed location list. Always test against the target management group, not just the subscription.

---

## About the Author

**Sufyan Gabisi aka sufideen** is a cloud and infrastructure engineer specialising in Azure architecture, Infrastructure as Code, and DevSecOps. This project is a complete end-to-end example of how enterprise-grade infrastructure is designed, secured, and automated — from a blank subscription to nine fully deployed resource groups across three environments, driven entirely by code and a CI/CD pipeline.

Available for cloud consulting, architecture reviews, and IaC delivery engagements.

- **GitHub:** [github.com/sufideen](https://github.com/sufideen)
- **LinkedIn:** [linkedin.com/in/sufideen](https://linkedin.com/in/sufideen)

---

## For VAK Learners

This project was built to be learned from, not just cloned.

**Visual learners** — start with the architecture diagram above. Then open the Azure Portal and explore the deployed resource groups. See how the diagram maps to real resources.

**Auditory / reading learners** — work through the Bicep module files in dependency order: `nsg.bicep` → `hub-network.bicep` → `spoke-network.bicep` → `vnet-peering.bicep` → `app-gateway.bicep` → `firewall.bicep` → `bastion.bicep` → `key-vault.bicep` → `route-table.bicep` → `storage.bicep` → `main.bicep`. Read each parameter and variable name aloud — good naming is documentation.

**Kinesthetic learners** — fork the repo, follow the deploy steps, then try making a change: add a new NSG rule, change a CIDR, rename a subnet. Submit a pull request and watch the Validate job run the `what-if` diff before anything touches Azure.

---

*Built with Azure Bicep · GitHub Actions · OIDC · Azure Networking · Azure Firewall · Azure Bastion · Azure Key Vault*
