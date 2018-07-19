function Resolve-CustomerManifest
{
    # NOTE: Customer configuration file is largest file in C:\EceStore
    $customerManifestList = @()
    $customerManifestList += (Get-ChildItem -Path "C:\EceStore" -Filter "????????-????-????-????-????????????" -Recurse -File | Sort-Object Length -Descending).FullName
    foreach ($customerManifest in $customerManifestList)
    {
        if ($customerManifest -and (Test-Path -Path $customerManifest -PathType Leaf))
        {
            return $customerManifest
        }
    }
 
    return $null
}
 
function Get-VMHostNames([string]$customerManifest)
{
    $vmHostNames = @()
 
    if ($customerManifest)
    {
        Write-Verbose -Message "Using customer manifest '$customerManifest'." -Verbose
        $Configuration = [xml](Get-Content -Path $customerManifest)
        $bareMetalRole = $Configuration.CustomerConfiguration.SelectSingleNode("//Role[@Id='BareMetal']")
        $vmHostNames = $bareMetalRole.Nodes.Node.Name
    }
    else
    {
        Write-Warning -Message "Customer manifest '$customerManifest' not available."
        $vmHostNames = (Get-VMHost).Name
    }
 
    return $vmHostNames
}
 
function Get-VMList([string[]]$vmHostNames)
{
    $virtualMachines = @()
    foreach ($vmHostName in $vmHostNames)
    {
        Write-Verbose -Message "VMHost: $vmHostName" -Verbose
        $vmHost = Get-VMHost -ComputerName $vmHostName
 
        $vms = Get-VM -ComputerName $vmHost.ComputerName
        foreach ($vm in $vms)
        {
            $virtualMachines += $vm
        }
    }
    return $virtualMachines
}
 
function Test-RegisterWithAzure
{
    param(
        [Parameter(Mandatory = $true)]
        [PSCredential] $CloudAdminCredential,
 
        [Parameter(Mandatory = $true)]
        [String] $AzureSubscriptionId,
 
        [Parameter(Mandatory = $true)]
        [String] $AzureAccountId,
 
        [Parameter(Mandatory = $true)]
        [String] $AzurePassword,

        [Parameter(Mandatory = $true)]
        [String] $AzureDirectoryTenantName,
  
        [Parameter(Mandatory = $false)]
        [String] $ResourceGroupName = 'azurestack',
 
        [Parameter(Mandatory = $false)]
        [String] $ResourceGroupLocation = 'westcentralus',
 
        [Parameter(Mandatory = $false)]
        [String] $RegistrationName,
 
        [Parameter(Mandatory = $false)]
        [String] $AzureEnvironment = 'AzureCloud',
 
        [Parameter(Mandatory = $false)]
        [ValidateSet('Capacity', 'PayAsYouUse', 'Development')]
        [string] $BillingModel = 'Development',
 
        [Parameter(Mandatory=$false)]
        [switch] $MarketplaceSyndicationEnabled = $true,
 
        [Parameter(Mandatory=$false)]
        [switch] $UsageReportingEnabled = $true,
 
        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [string] $AgreementNumber
    )
 
    # Required to get JeaComputerName
    Import-Module -Name Hyper-V -ErrorAction Stop -Verbose:$false 4>$null
 
    $azureCredential = New-Object System.Management.Automation.PSCredential($AzureAccountId,(ConvertTo-SecureString -String $AzurePassword -AsPlainText -Force));
    Login-AzureRmAccount -Credential $azureCredential -SubscriptionId $AzureSubscriptionId
 
    $customerManifest = Resolve-CustomerManifest 
    $vmHostNames = Get-VMHostNames -customerManifest $customerManifest
    Write-Host "Hosts: $vmHostNames"
    $ListOfVms = Get-VMList -vmHostNames $vmHostNames
    $JeaComputerName = ($ListOfVms | Where-Object {$_.Name -ilike "*ERCS*"}).VmName
    if ($JeaComputerName.Count -gt 1)
    {
        $JeaComputerName = $JeaComputerName[0]
    }
 
    #
    # Download latest script from github
    #
 
    $retryCount = 0
    $opSuccessful = $false
    $maxRetries = 3
    $sleepSeconds = 10
    $message = ""
 
    do {
        $scriptUri = "https://raw.githubusercontent.com/Azure/AzureStack-Tools/vnext/Registration/RegisterWithAzure.psm1"
        $registerScriptPath = "$env:SystemDrive\CloudDeployment\Setup\Activation\Bridge\RegisterWithAzure.psm1"
        Write-Verbose "Downloading registration script from github: $scriptUri"
        Write-Verbose "Registration script path: $registerScriptPath"
 
        try {
            Invoke-WebRequest -Uri $scriptUri -OutFile $registerScriptPath
            $opSuccessful = $true
            Write-Verbose "script successfully downloaded"
        }
 
        catch {
            $message = "Exception occurred during download of registration script: $_`r`n$($_.Exception)`r`n"
            Write-Verbose $message 
            Write-Verbose "Failed to invoke web request on $scriptUri. Retrying in $sleepSeconds seconds"
            $retryCount++
           Start-Sleep -Seconds $sleepSeconds
        }
 
    } while ((-not $opSuccessful) -and ($retryCount -lt $maxRetries))
 
    if($opSuccessful = $false){
        Write-Verbose $message
        $message = "Failed to download registration script from github after $maxRetries attempts."
        throw $message
    }
 
    #
    # Invoke script
    #
    
    # Always test with refresh token
    Write-Verbose "Running registration with refresh token and user credentials"
    Import-Module  $registerScriptPath

    $scriptParams = @{
    PrivilegedEndpointCredential            = $CloudAdminCredential
   # AzureSubscriptionId             = $AzureSubscriptionId
    PrivilegedEndpoint                 = $JeaComputerName
   # AzureDirectoryTenantName        = $AzureDirectoryTenantName  
    #ResourceGroupName               = $ResourceGroupName
    #ResourceGroupLocation           = $ResourceGroupLocation
   # RegistrationName                = $RegistrationName
   # AzureEnvironment                = $AzureEnvironment
    BillingModel                    = $BillingModel
    MarketPlaceSyndicationEnabled   = $MarketplaceSyndicationEnabled
    UsageReportingEnabled           = $UsageReportingEnabled
    AgreementNumber                 = $AgreementNumber
    }
 
    Write-Verbose "Params: $(ConvertTo-Json $scriptParams)" -Verbose
 
    try {
        Set-AzsRegistration @scriptParams -Verbose
        Write-Verbose "Registration completed successfully"
    }
    catch {
        $message = "Exception occurred while attempting to register with Azure: $_`r`n$($_.Exception)"
        throw $message
    }
}
 
#################################################
## Main ##
 
$azureInstalled = (Get-Module -ListAvailable | where-Object {$_.Name -like “Azure*”})
 
if (-not $azureInstalled)
{
    Install-Module -Name AzureRm.BootStrapper
    Use-AzureRmProfile -Profile 2017-03-09-profile -Force
}
 
$cloudAdminCredential = New-Object System.Management.Automation.PSCredential("CloudAdmin",(ConvertTo-SecureString -String "!!123abc" -AsPlainText -Force))
$azureSubscriptionId = "5c17413c-1135-479b-a046-847e1ef9fbeb"
$azureAccountId = "serviceadmin@msazurestack.onmicrosoft.com"
$azurePassword = "User@123"
$ResourceGroupName = "AzS-Register-StandAloneTest"
$ResourceName = "Registration-StandAloneTest"
$AzureDirectoryTenantName = "msazurestack.onmicrosoft.com"
Test-RegisterWithAzure -CloudAdminCredential $cloudAdminCredential -AzureSubscriptionId $azureSubscriptionId -AzureAccountId $azureAccountId -AzurePassword $azurePassword -AzureDirectoryTenantName $AzureDirectoryTenantName -ResourceGroupName $ResourceGroupName -RegistrationName $ResourceName
