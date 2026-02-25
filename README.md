# Azure Platform Agent - Installation Guide

## Description

**Azure Platform Agent** is a Model Context Protocol (MCP) server that enables secure, compliant Azure resource deployment directly from VS Code using GitHub Copilot Chat. This agent helps you create compliant Azure resources with automatic security compliance orchestration.

### Capabilities

#### Azure Authentication & Account
1. **Azure Login** - Login to Azure with browser authentication
2. **List Subscriptions** - List accessible Azure subscriptions
3. **Set Subscription** - Set active subscription context
4. **Get Current User** - Get current subscription, tenant, and user info

#### Azure Resource Management
5. **Create Resource Groups** - Create Azure resource groups with project tagging
6. **Create Compliant Resources** - Deploy Azure resources with automatic compliance features:
   - Storage Accounts (ADLS Gen2)
   - Key Vaults
   - Azure OpenAI
   - AI Search
   - AI Content Safety
   - AI Document Intelligence
   - AI Language Service
   - Cosmos DB
   - Log Analytics Workspaces
   - User Assigned Managed Identity (UAMI)
   - Network Security Perimeter (NSP)
   - Fabric Capacity
   - Container Registry (ACR)
   - Function App (Flex Consumption)
   - Public IP
   - Azure Data Factory
   - Azure Synapse Analytics
   - Network Security Group (NSG)
   - Virtual Network (VNet)
   - Subnet
   - Private Endpoint
   - Logic App (Consumption)
7. **Get Resource Info** - Query resources, resource groups, and properties
8. **Get Activity Log** - Retrieve activity logs for auditing
9. **Update Tags** - Add, update, or replace resource tags

#### Azure Security & Networking
10. **Activate PIM Roles** - Activate eligible Privileged Identity Management roles
11. **Assign RBAC Roles** - Assign RBAC roles to SPNs/Managed Identities
12. **List Roles** - List active or eligible PIM roles

#### Azure DevOps Integration
13. **List DevOps Projects** - View all projects in an organization
14. **List DevOps Repositories** - View all repositories in a project
15. **Create DevOps Projects** - Set up new Azure DevOps projects
16. **Create DevOps Repositories** - Add new Git repositories to existing projects
17. **Create DevOps Branches** - Create branches in repositories from base branches
18. **Create DevOps Pipelines** - Create and configure Azure Pipelines from YAML files
19. **Deploy Pipeline YAML** - Deploy pipeline templates (credscan, 1ES) to repositories
20. **Deploy Custom YAML** - Deploy custom YAML content directly to repositories
21. **Assign ADO Roles** - Assign security group roles in Azure DevOps

#### Microsoft Fabric Integration
22. **Create Fabric Workspaces** - Create workspaces in Fabric capacities
23. **Assign Fabric Roles** - Assign workspace roles (Admin/Contributor/Member/Viewer)
24. **List Fabric Permissions** - View workspace permissions and access levels
25. **Attach Workspace to Git** - Connect Fabric workspaces to Azure DevOps repositories
26. **Create Managed Private Endpoint** - Create managed private endpoint for secure connectivity
27. **List Managed Private Endpoints** - List managed private endpoints in workspace

#### Agent Help
28. **Show Agent Instructions** - Display complete agent documentation and usage guide 
---

## Prerequisites

Before installing the Azure Platform Agent, ensure you have the following installed:

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
- Azure CLI authenticated (`az login` or `az login --allow-no-subscriptions`)

### Fabric Requirements

- Access to Microsoft Fabric workspaces
- Appropriate permissions to create and manage workspaces
- Fabric capacity available for workspace creation
- ADO Available for GIT integration
- Azure CLI authenticated (`az login` or `az login --allow-no-subscriptions`)

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
    "servers": {
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

## Usage Examples

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
- Deploy compliant resources
- Configure Log Analytics diagnostic settings
- Apply security best practices and compliance controls

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
deploy credscan pipeline yaml to MyRepo in pipelines folder
```

#### Deploy Custom YAML
```
deploy custom yaml content to MyRepo
```

#### Create a Pipeline
```
create pipeline named MyPipeline-1ES for MyRepo
```

#### Create Pipeline with Custom YAML Path
```
create pipeline named "Source Branch Validation" for MyRepo with yaml path pipelines/sourcebranchvalidation.yml
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
