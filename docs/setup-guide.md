# Setup Guide — Azure Hub-and-Spoke IaC Project

This guide walks you through setting up your local development environment so you can deploy and work with this project from **VS Code on macOS (MacBook Pro)**, **VS Code on Linux (Ubuntu)**, or the **Azure CLI** directly.

---

## What You Are Setting Up

You will install the tools needed to:
- Write and lint Azure Bicep templates in VS Code
- Authenticate to Azure from your terminal
- Run and trigger the GitHub Actions CI/CD pipeline
- Deploy the hub-and-spoke infrastructure to your Azure subscription

---

## Prerequisites — What You Need Before Starting

| Requirement | Details |
|---|---|
| Azure subscription | Free trial or pay-as-you-go — [create one here](https://azure.microsoft.com/en-us/free/) |
| GitHub account | [github.com](https://github.com) — free |
| Admin access on your machine | To install tools |

---

## Option 1 — macOS (MacBook Pro)

### Step 1 — Install Homebrew (macOS package manager)

Homebrew is the easiest way to install developer tools on a Mac.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

> Microsoft reference: [Set up a Mac for Azure development](https://learn.microsoft.com/en-us/azure/developer/intro/azure-developer-overview)

---

### Step 2 — Install Azure CLI

```bash
brew update && brew install azure-cli
```

Verify:
```bash
az --version
```

You should see `azure-cli` with a version number.

> Microsoft reference: [Install Azure CLI on macOS](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-macos)

---

### Step 3 — Install Bicep CLI

```bash
az bicep install
az bicep upgrade
```

Verify:
```bash
az bicep version
```

> Microsoft reference: [Install Bicep tools](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install)

---

### Step 4 — Install Git

macOS ships with Git, but install the latest via Homebrew:

```bash
brew install git
```

Verify:
```bash
git --version
```

> Reference: [Getting Started with Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)

---

### Step 5 — Install GitHub CLI

```bash
brew install gh
```

Authenticate:
```bash
gh auth login
```

Follow the prompts — choose **GitHub.com**, then **HTTPS**, then authenticate via browser.

> Reference: [GitHub CLI documentation](https://cli.github.com/manual/)

---

### Step 6 — Install Visual Studio Code

Download from [code.visualstudio.com](https://code.visualstudio.com/) and drag to Applications.

Or via Homebrew:
```bash
brew install --cask visual-studio-code
```

> Microsoft reference: [VS Code on macOS](https://code.visualstudio.com/docs/setup/mac)

After installing, open VS Code and press `Cmd+Shift+P`, type **Shell Command: Install 'code' command in PATH** — this lets you open VS Code from your terminal with `code .`.

---

### Step 7 — Install VS Code Extensions

Open VS Code and install these extensions (click the Extensions icon on the left sidebar or press `Cmd+Shift+X`):

| Extension | Publisher | Why You Need It |
|---|---|---|
| Bicep | Microsoft | Syntax highlighting, IntelliSense, linting for `.bicep` files |
| Azure Tools | Microsoft | Suite of Azure extensions (account, resources, storage) |
| GitHub Actions | GitHub | View and trigger workflows from VS Code |
| GitLens | GitKraken | Enhanced Git history and blame annotations |
| YAML | Red Hat | Syntax support for GitHub Actions workflow files |

Install via terminal:
```bash
code --install-extension ms-azuretools.vscode-bicep
code --install-extension ms-vscode.vscode-node-azure-pack
code --install-extension github.vscode-github-actions
code --install-extension eamodio.gitlens
code --install-extension redhat.vscode-yaml
```

> Microsoft reference: [Bicep VS Code extension](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/visual-studio-code)

---

### Step 8 — Log in to Azure

```bash
az login
```

A browser window opens. Sign in with your Azure account. Once done, your terminal shows your subscription details.

Set your active subscription:
```bash
az account set --subscription "<your-subscription-name-or-id>"
az account show
```

> Microsoft reference: [Sign in with Azure CLI](https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli)

---

## Option 2 — Linux (Ubuntu 22.04 / 24.04)

### Step 1 — Update your system

```bash
sudo apt update && sudo apt upgrade -y
```

---

### Step 2 — Install Azure CLI

Microsoft provides an official install script:

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

Verify:
```bash
az --version
```

> Microsoft reference: [Install Azure CLI on Linux](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux)

---

### Step 3 — Install Bicep CLI

```bash
az bicep install
az bicep upgrade
```

Verify:
```bash
az bicep version
```

> Microsoft reference: [Install Bicep tools](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install)

---

### Step 4 — Install Git

```bash
sudo apt install git -y
git --version
```

Configure your identity (required for commits):
```bash
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

---

### Step 5 — Install GitHub CLI

```bash
sudo apt install gh -y
```

If `gh` is not found in apt:
```bash
type -p curl >/dev/null || sudo apt install curl -y
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update && sudo apt install gh -y
```

Authenticate:
```bash
gh auth login
```

> Reference: [GitHub CLI on Linux](https://github.com/cli/cli/blob/trunk/docs/install_linux.md)

---

### Step 6 — Install Visual Studio Code

```bash
sudo snap install code --classic
```

Or via Microsoft's apt repository:
```bash
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
sudo apt update && sudo apt install code -y
```

> Microsoft reference: [VS Code on Linux](https://code.visualstudio.com/docs/setup/linux)

---

### Step 7 — Install VS Code Extensions

```bash
code --install-extension ms-azuretools.vscode-bicep
code --install-extension ms-vscode.vscode-node-azure-pack
code --install-extension github.vscode-github-actions
code --install-extension eamodio.gitlens
code --install-extension redhat.vscode-yaml
```

---

### Step 8 — Log in to Azure

```bash
az login
```

If you are on a headless server (no browser), use device code login:
```bash
az login --use-device-code
```

> Microsoft reference: [Sign in with Azure CLI](https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli)

---

## Clone the Repository

Once your tools are installed, clone the project:

```bash
git clone https://github.com/sufideen/azcloudtrain01.git
cd azcloudtrain01
```

Open in VS Code:
```bash
code .
```

---

## Verify Everything Works

Run these checks after setup — all should return version numbers or account info:

```bash
az --version           # Azure CLI
az bicep version       # Bicep
git --version          # Git
gh --version           # GitHub CLI
az account show        # Confirms you are logged in to Azure
gh auth status         # Confirms you are logged in to GitHub
```

---

## Next Steps

| Task | Guide |
|---|---|
| Set up OIDC authentication between Azure and GitHub | [oidc-setup.md](oidc-setup.md) |
| Deploy the dev environment | [rebuild-dev.md](rebuild-dev.md) |
| Understand the architecture | [../infrastructure/docs/architecture.md](../infrastructure/docs/architecture.md) |
| Cost estimates | [../infrastructure/docs/cost-estimate.md](../infrastructure/docs/cost-estimate.md) |

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `az: command not found` | Close and reopen your terminal after install |
| `az login` opens wrong account | Run `az account clear` then `az login` again |
| `az bicep version` returns nothing | Run `az bicep install` first |
| VS Code `code` command not found on Mac | Open VS Code → `Cmd+Shift+P` → "Shell Command: Install 'code' in PATH" |
| `gh auth login` fails | Try `gh auth login --web` or check your firewall/proxy |

---

*For issues with this project, open a GitHub issue at [github.com/sufideen/azcloudtrain01/issues](https://github.com/sufideen/azcloudtrain01/issues)*
