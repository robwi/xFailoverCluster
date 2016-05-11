$currentPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Debug -Message "CurrentPath: $currentPath"

# Load Common Code
Import-Module $currentPath\..\..\xFailoverClusterHelper.psm1 -Verbose:$false -ErrorAction Stop


function Get-ClusterNetworkNameResource
{
	[CmdletBinding()]
	[OutputType([System.String[]])]
    param
    (
		[parameter(Mandatory = $true)]
		[System.String]
		$Name
    )

    $ClusterNameResource = Get-ClusterResource -Verbose:$false | Where-Object {($_.ResourceType -eq 'Network Name')} | Where-Object {($_ | Get-ClusterParameter -Name 'Name' -Verbose:$false).Value -eq $Name}

    $ClusterNameResource
}


function Get-ClusterNetworkNameIPAddress
{
	[CmdletBinding()]
	[OutputType([System.String[]])]
    param
    (
		[parameter(Mandatory = $true)]
		[System.String]
		$Name
    )

    $ClusterNameResource = Get-ClusterNetworkNameResource -Name $Name
    $ClusterGroup = Get-ClusterGroup -Name $ClusterNameResource.OwnerGroup.Name -Verbose:$false
    $ClusterIPAddressResource = Get-ClusterResource -InputObject $ClusterGroup -Verbose:$false | Where-Object {$_.ResourceType -eq 'IP Address'}
    $ClusterIPAddress = $ClusterIPAddressResource | Get-ClusterParameter -Name 'Address' -Verbose:$false

    $ClusterIPAddress.Value
}


function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name
	)

    @{
        Name = $Name
        IPAddress = @(Get-ClusterNetworkNameIPAddress -Name $Name)
    }
}


function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name,

        [System.Boolean]
        $Update,

        [ValidateRange(1,[Uint64]::MaxValue)]
        [Uint64]
        $RetryIntervalSec = 1, 

        [Uint32]
        $RetryCount = 0
	)

    $ClusterNameResource = Get-ClusterNetworkNameResource -Name $Name
    
    for($count = 0; $count -lt $RetryCount; $count++)
    {
        if($Update)
        {
            Write-Verbose -Message "Executing Update-ClusterNetworkNameResource for cluster network name $Name"
            $null = Update-ClusterNetworkNameResource -InputObject $ClusterNameResource -Verbose:$false
        }
        if(Test-TargetResource -Name $Name)
        {
            break
        }
        else
        {
            if(($count + 1) -lt $RetryCount)
            {
                Write-Verbose -Message "Cluster network name $Name not correct in DNS. Will retry again after $RetryIntervalSec sec"
                Start-Sleep -Seconds $RetryIntervalSec
            }
        }
    }

    if(!(Test-TargetResource -Name $Name))
    {
        throw New-TerminatingError -ErrorType ClusterNotFoundAfterSeconds -FormatArgs @($Name,$count,$RetryIntervalSec) -ErrorCategory ObjectNotFound 
    }
}


function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name,

        [System.Boolean]
        $Update,

        [ValidateRange(1,[Uint64]::MaxValue)]
        [Uint64]
        $RetryIntervalSec = 1, 

        [Uint32]
        $RetryCount = 0
	)

    $ClusterNetworkNameIPAddresses = (Get-TargetResource -Name $Name).IPAddress
    $Domain = (Get-CimInstance -ClassName Win32_ComputerSystem -Verbose:$false).Domain

    if($DNS = (Resolve-DnsName -Name "$Name.$Domain" -DnsOnly -ErrorAction SilentlyContinue -Verbose:$false).IPAddress)
    {
        $return = $true
        foreach($ClusterNetworkNameIPAddress in $ClusterNetworkNameIPAddresses)
        {
            if($DNS -notcontains $ClusterNetworkNameIPAddress)
            {
                Write-Verbose "$Name in DNS does not include $ClusterNetworkNameIPAddress"
                $return = $false
            }
        }
    }
    else
    {
        Write-Verbose "$Name is not registered in DNS"
        $return = $false
    }

    $return
}


Export-ModuleMember -Function *-TargetResource