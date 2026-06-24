# Azure Hub-and-Spoke Network — IaC with Bicep & GitHub Actions CI/CD

> **A real-world infrastructure deployment showcase**
> Co-authored by **Sufideen Mawara** · [github.com/sufideen](https://github.com/sufideen)

---

## What This Project Demonstrates

This repository shows how to design, codify, and deploy a production-grade Azure network architecture using **Infrastructure as Code (IaC)**. Everything you see in Azure was created from code — no clicking through the portal.

| Skill Area | What You Will See |
|---|---|
| Azure Networking | Hub-and-spoke VNet topology with peering |
| Security | NSGs with least-privilege rules, WAF v2, Bastion-only RDP |
| IaC | Modular Azure Bicep templates |
| CI/CD | GitHub Actions pipeline with OIDC (passwordless auth) |
| Environments | Dev / Test / Prod with independent deployment gates |

---

## Architecture Overview

```
                          ┌─────────────────────────────┐
                          │         HUB VNet             │
                          │       10.0.0.0/16            │
                          │                              │
                          │  ┌──────────────────────┐   │
                          │  │  AppGatewaySubnet     │   │
         Internet ───────────│  App Gateway WAF v2   │   │
                          │  │  OWASP 3.2 + BotMgr  │   │
                          │  └──────────────────────┘   │
                          │  ┌──────────────────────┐   │
                          │  │  AzureBastionSubnet   │   │
                          │  │  (RDP/SSH gateway)    │   │
                          │  └──────────────────────┘   │
                          │  GatewaySubnet               │
                          │  AzureFirewallSubnet          │
                          └────────────┬─────────────────┘
                                       │ VNet Peering (bidirectional)
                          ┌────────────▼─────────────────┐
                          │        SPOKE VNet             │
                          │    dev:  10.1.0.0/16         │
                          │    test: 10.2.0.0/16         │
                          │    prod: 10.3.0.0/16         │
                          │                              │
                          │  WebSubnet   (.1/24) ◄─── HTTPS from App GW only
                          │  AppSubnet   (.2/24) ◄─── HTTP from Web only
                          │  DataSubnet  (.3/24) ◄─── SQL from App only
                          │  AdminSubnet (.4/24) ◄─── RDP from Bastion only
                          └──────────────────────────────┘
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
│       └── deploy-infrastructure.yml   # CI/CD pipeline
├── infrastructure/
│   ├── main.bicep                      # Subscription-scoped orchestrator
│   ├── modules/
│   │   ├── hub-network.bicep           # Hub VNet + subnets
│   │   ├── spoke-network.bicep         # Spoke VNet + subnets
│   │   ├── nsg.bicep                   # 4 Network Security Groups
│   │   ├── app-gateway.bicep           # App Gateway WAF v2
│   │   ├── storage.bicep               # Storage account (LRS dev/test, GRS prod)
│   │   ├── vnet-peering.bicep          # Bidirectional peering orchestrator
│   │   └── vnet-peering-single.bicep   # Single-direction peering primitive
│   ├── parameters/
│   │   ├── dev.bicepparam
│   │   ├── test.bicepparam
│   │   └── prod.bicepparam
│   └── scripts/
│       └── bootstrap-oidc.sh           # One-time OIDC setup script
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

    ┌─────────┐    Trigger: dispatch environment=test
    │  Deploy │
    │  test   │
    └─────────┘

    ┌─────────┐    Trigger: dispatch environment=prod
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

---

## Cost Estimate

Approximate monthly costs in East US. The App Gateway WAF v2 is the dominant line item.

| Resource | dev / test (each) | prod |
|---|---|---|
| App Gateway WAF v2 (1 capacity unit) | ~$180/month | ~$360/month (2 CU) |
| Public IP — Standard | ~$4/month | ~$4/month |
| Storage account — LRS | <$1/month | ~$2/month (GRS) |
| VNet / NSG / Peering | Free | Free |
| **Environment total** | **~$185/month** | **~$366/month** |
| **All 3 environments** | | **~$736/month** |

> To reduce dev/test costs: switch App Gateway SKU to `Standard_v2` (no WAF) in those environments, or schedule automated shutdown during off-hours.

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

---

## Phase 2 Roadmap

- [ ] Add SSL certificate from Azure Key Vault and enable HTTPS listener on App Gateway
- [ ] Enable HTTP → HTTPS redirect rule
- [ ] Add Azure Firewall in the hub for egress filtering
- [ ] Add Azure Bastion Standard SKU with native client support
- [ ] Configure Azure Monitor / Network Watcher diagnostics
- [ ] Add cost management alerts per environment

---

## About the Co-Author

**Sufideen Mawara** is a cloud and infrastructure engineer specialising in Azure architecture, Infrastructure as Code, and DevSecOps. This project is a complete end-to-end example of how enterprise-grade infrastructure is designed, secured, and automated — from a blank subscription to nine fully deployed resource groups across three environments, driven entirely by code and a CI/CD pipeline.

Available for cloud consulting, architecture reviews, and IaC delivery engagements.

- **GitHub:** [github.com/sufideen](https://github.com/sufideen)
- **LinkedIn:** [linkedin.com/in/sufideen](https://linkedin.com/in/sufideen)

---

## For VAK Learners

This project was built to be learned from, not just cloned.

**Visual learners** — start with the architecture diagram above. Then open the Azure Portal and explore the deployed resource groups. See how the diagram maps to real resources.

**Auditory / reading learners** — work through the Bicep module files in dependency order: `nsg.bicep` → `hub-network.bicep` → `spoke-network.bicep` → `vnet-peering.bicep` → `app-gateway.bicep` → `storage.bicep` → `main.bicep`. Read each parameter and variable name aloud — good naming is documentation.

**Kinesthetic learners** — fork the repo, follow the deploy steps, then try making a change: add a new NSG rule, change a CIDR, rename a subnet. Submit a pull request and watch the Validate job run the `what-if` diff before anything touches Azure.

---

*Built with Azure Bicep · GitHub Actions · OIDC · Azure Networking*
