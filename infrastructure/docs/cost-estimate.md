# Azure Cost Estimate — Hub-and-Spoke Architecture

Pricing based on **East US** region, June 2026. All figures are monthly estimates.
Use the [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/) to validate with current rates.

---

## Per-Environment Cost Breakdown

### App Gateway WAF v2
| Environment | SKU | Capacity Units | Est. Cost/month |
|---|---|---|---|
| dev | WAF_v2 | 1 CU | ~$145 |
| test | WAF_v2 | 1 CU | ~$145 |
| prod | WAF_v2 | 2 CU (HA) | ~$290 |

> Fixed rate ≈ $0.246/hr + $0.008/CU/hr. CU covers 2,500 connections/sec, 2.22 Mbps, 2,500 persistent connections.

### Virtual Networks & Peering
| Item | Rate | Est. Cost/month |
|---|---|---|
| VNet (hub + spoke) | Free | $0 |
| VNet Peering intra-region | $0.01/GB | ~$2–10 (low traffic) |

### NSGs
| Item | Cost |
|---|---|
| NSGs (4 per env) | **Free** |
| Flow logs (optional, diagnostic) | ~$5–10/month/env |

### Storage Accounts
| Environment | Replication | Cap | Est. Cost/month |
|---|---|---|---|
| dev | LRS | 100 GB | ~$5 |
| test | LRS | 100 GB | ~$5 |
| prod | GRS | 500 GB | ~$25 |

### Azure Bastion (optional — needed for RDP to Admin subnet)
| Environment | SKU | Est. Cost/month |
|---|---|---|
| dev | Basic | ~$140 (skip if using VPN) |
| test | Basic | ~$140 |
| prod | Standard | ~$175 |

> Recommendation: omit Bastion in dev/test and use a VPN or Just-in-Time VM access to reduce cost.

### Public IP Addresses
| Item | Rate | Cost/month |
|---|---|---|
| 1 x Standard PIP (per env) | $0.005/hr | ~$3.65 |

---

## Total Monthly Estimates

| Environment | App GW | Storage | PIP | Peering | Bastion* | **Total** |
|---|---|---|---|---|---|---|
| dev | $145 | $5 | $4 | $2 | $0* | **~$156** |
| test | $145 | $5 | $4 | $2 | $0* | **~$156** |
| prod | $290 | $25 | $4 | $5 | $175 | **~$499** |
| **All 3 envs** | | | | | | **~$811/mo** |

*Bastion excluded from dev/test above; add ~$140/env if required.

---

## Cost Optimisation Tips

| Tip | Saving |
|---|---|
| Shut down dev App Gateway overnight (autoscale min=0) | ~40% of dev cost |
| Use Basic Bastion SKU for dev/test | $35/mo vs $175 |
| Use LRS storage everywhere | ~50% storage saving |
| Reserved instances for prod App Gateway (1-yr) | ~20-30% discount |
| Enable Azure Cost Alerts at 80% of budget | No cost, prevents surprises |

---

## Quick Commands to Get Live Estimates

```bash
# What-if with cost estimate (az CLI)
az deployment sub what-if \
  --location eastus \
  --template-file infrastructure/main.bicep \
  --parameters infrastructure/parameters/prod.bicepparam

# OR use Azure Pricing Calculator API
curl -X POST https://prices.azure.com/api/retail/prices \
  -H 'Content-Type: application/json' \
  --data '{"$filter": "serviceName eq \'Application Gateway\' and armRegionName eq \'eastus\'" }'
```
