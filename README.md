# Azure customazuremcpagent MCP Agent - Installation Guide

## Description

**Azure customazuremcpagent MCP Agent** is a Model Context Protocol (MCP) server that enables secure, compliant Azure resource deployment directly from VS Code using GitHub Copilot Chat. This agent helps you create customazuremcpagent compliant Azure resources with automatic compliance orchestration.

### Capabilities

#### Azure Resource Management
1. **List Azure Permissions** - View your active RBAC role assignments and access levels
2. **List Azure Resources** - Browse resources across subscriptions and resource groups
3. **Create Resource Groups** - Create Azure resource groups with project tagging
4. **Create customazuremcpagent-Compliant Resources** - Deploy Azure resources with automatic compliance features:
   - Storage Accounts (ADLS Gen2)
   - Key Vaults
   - Azure OpenAI
   - AI Search
   - AI Foundry
   - Cosmos DB
   - Log Analytics Workspaces
   - Network Security Perimeters (NSP)
   - User Assigned Managed Identity (UAMI)
   - Fabric Capacity
5. **Add Diagnostic Settings** - Configure Log Analytics monitoring for resources
6. **NSP Attachment** - Configure Network Security Perimeter attachment for supported resources

#### Azure DevOps Integration
7. **Create DevOps Projects** - Set up new Azure DevOps projects with initial repositories
8. **Create DevOps Repositories** - Add new Git repositories to existing projects
9. **Create DevOps Branches** - Create branches in repositories from base branches
10. **Deploy Pipeline YAML** - Deploy pipeline templates (CodeQL, 1ES) to repositories
11. **Create DevOps Pipelines** - Create and configure Azure Pipelines from YAML files
12. **List DevOps Projects** - View all projects in an organization
13. **List DevOps Repositories** - View all repositories in a project

#### Microsoft Fabric Integration
14. **Create Fabric Workspaces** - Create workspaces in Fabric capacities
15. **Attach Workspace to Git** - Connect Fabric workspaces to Azure DevOps repositories
16. **List Fabric Permissions** - View workspace permissions and access levels 
---

## Prerequisites

Before installing the Azure customazuremcpagent MCP Agent, ensure you have the following installed:

### Required Software

1. **Visual Studio Code** - [Download](https://code.visualstudio.com/download)
2. **PowerShell Core (pwsh)** - [Download](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows?view=powershell-7.5)
3. **Azure CLI** - [Download](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows?view=azure-cli-latest&pivots=winget)
4. **Python 3.10+** - [Download](https://www.python.org/downloads/)
5. **uvx** - [Download](https://docs.astral.sh/uv/getting-started/installation/)
6. **GitHub Copilot Chat Extension** - [Install from VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot-chat)

### Azure Requirements

- Active Azure subscription
- Appropriate Azure RBAC permissions for resource creation
- Azure CLI authenticated (`az login`)
- Set context for one subscription (`az account set --subscription <subscriptionid>`)

### ADO Requirements

- Access to Azure DevOps organization
- Project Collection Admin permissions for creating projects
- Project Admin permissions for creating repositories, and pipelines
- Azure CLI authenticated (`az login` or `allow-no-subscriptions`)

### Fabric Requirements

- Access to Microsoft Fabric workspaces
- Appropriate permissions to create and manage workspaces
- Fabric capacity available for workspace creation
- ADO Available for GIT integration
- Azure CLI authenticated (`az login` or `allow-no-subscriptions`)

---

## Installation Steps

### Step 1: Open GitHub Copilot Chat

1. Launch **Visual Studio Code**
2. Open **GitHub Copilot Chat** (click the chat icon in the sidebar or press `Ctrl+Alt+I`)

### Step 2: Access MCP Tools Menu

1. In the Copilot Chat window, click on the **🔧 Tools** button
2. Select **"Install MCP Server from PyPI"** or similar option

### Step 3: Install the Package

1. When prompted for the package name, enter:
   ```
   customazuremcpagent
   ```
2. Select the **latest version** when prompted
3. Wait for the installation to complete

### Step 4: Configure MCP Settings
Add the following configuration to the `mcp.json` file:

```json
{
    "mcpServers": {
        "customazuremcpagent": {
            "type": "stdio",
            "command": "uvx",
            "args": [
                "customazuremcpagent==1.0.0"
            ]
        }
    }
}
```

> **Note**: Replace `1.0.0` with the latest version number you installed.

### Step 5: Restart VS Code

1. Close and reopen Visual Studio Code to load the MCP server configuration
2. Open GitHub Copilot Chat again
3. Select the MCP Tool installed

### Step 6: Verify Installation

In GitHub Copilot Chat, type:
```
show menu
```

You should see the available actions menu confirming successful installation.

---

## 💡 Usage Examples

### Azure Resource Management

#### List Your Azure Permissions
```
list my azure permissions
```

#### List Azure Resources
```
list resources in resource-group-name
```

#### Create a Resource Group
```
create resource group named my-rg in eastus for project MyProject
```

#### Create a Storage Account
```
create storage account
```

#### Create a Key Vault
```
create key vault
```

The agent will interactively prompt you for required parameters and automatically:
- ✅ Deploy the customazuremcpagent compliant resources
- ✅ Configure Log Analytics diagnostic settings
- ✅ Apply security best practices and compliance controls

### Azure DevOps Operations

#### Create a DevOps Project
```
create azure devops project named MyProject with repo MainRepo in organization myorg
```

#### Create a DevOps Repository
```
create devops repository named MyRepo in project MyProject
```

#### Create a Branch
```
create branch feature/new-feature from main in MyRepo
```

#### Deploy Pipeline YAML
```
deploy codeql pipeline yaml to MyRepo in pipelines folder
```

#### Create a Pipeline
```
create pipeline named MyPipeline-1ES for MyRepo
```

#### List DevOps Projects
```
list all devops projects in organization myorg
```

#### List DevOps Repositories
```
list all repos in project MyProject
```

### Microsoft Fabric Operations

#### List Fabric Permissions
```
list my fabric permissions
```

#### Create a Fabric Workspace
```
create fabric workspace named MyWorkspace in capacity /subscriptions/.../capacities/mycapacity
```

#### Attach Workspace to Git
```
attach fabric workspace to azure devops git
```

---

### Azure CLI Authentication

Ensure you're logged into Azure CLI:
```bash
az login
az account show
```

### PowerShell Core Required

This agent requires PowerShell Core (pwsh), not Windows PowerShell. Verify:
```bash
pwsh --version
```
---

## 📄 License

MIT License - see LICENSE file for details
