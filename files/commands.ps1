# login to Azure and set ids
az login
$subId = az account show --query id -o tsv
$tenantId = az account show --query tenantId -o tsv
$userId = az ad signed-in-user show --query id -o tsv
$upn = az account show --query user.name -o tsv
$username = az ad user list --upn $upn --query [].displayName -o tsv
$serviceName = "zerotrustapp"
$rg = "rg-$serviceName-dev"

# Create resource group
az group create -l swedencentral -n $rg --tags owner=$username

# Create Entra Id Group
$groupId = az ad group create --display-name "$serviceName contributors" --mail-nickname $serviceName --query id -o tsv
az ad group owner add --group $groupId --owner-object-id $userId
az ad group member add --group $groupId --member-id $userId

# Add Owner role assignment to yourself
# Reason: Need Owner role to be able to assign roles to my managed identity

# Assign Contributor role to Entra Id group scoped on resource group
az role assignment create --role Contributor --subscription $subId --assignee-object-id $groupId --assignee-principal-type Group --scope /subscriptions/$subId/resourceGroups/$rg
$uamiName = "oidc-$servicename-ghwf-dev"
$uamiClientId = az identity create --subscription $subId -g $rg -n $uamiName --query clientId -o tsv
$uamiPrincipalId = az identity show --subscription $subId -g $rg -n $uamiName --query principalId -o tsv
az role assignment create --role Owner --subscription $subId --assignee-object-id $uamiPrincipalId --assignee-principal-type ServicePrincipal --scope /subscriptions/$subId/resourceGroups/$rg

# Login to GitHub
gh auth login
$repo = gh repo view --json nameWithOwner -q ".nameWithOwner"

# Configuring Workload Identity Federation for User-Assigned Managed Identity
$audiences = @("api://AzureADTokenExchange")
$issuer = "https://token.actions.githubusercontent.com"

az identity federated-credential create --identity-name $uamiName -n "mainfic" -g $rg --audiences $audiences --issuer $issuer --subject "repo:$($repo):ref:refs/heads/main" 

gh secret set AZURE_TENANT_ID -b $tenantId --repo $repo # the id for the tenant under the azure organisation
gh secret set AZURE_SUBSCRIPTION_ID -b $subId --repo $repo # the azure subscription id
gh secret set ZEROTRUSTAPP_DEV_AZURE_CLIENT_ID -b $uamiClientId --repo $repo # used for github OIDC authentication in github workflow
gh variable set ZEROTRUSTAPP_DEV_PRINCIPAL_ID -b $uamiPrincipalId --repo $repo # github workflow identity used for role assignments
gh variable set ZEROTRUSTAPP_DEV_GROUP_ID -b $groupId --repo $repo # used to assign roles and permissions to user group for azure resources
gh variable set RG_ZEROTRUSTAPP_DEV -b $rg --repo $repo # resource group name that will be used later in our Github workflow file
