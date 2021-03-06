function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name,

		[parameter(Mandatory = $true)]
		[System.String[]]
		$Networks
	)

    $ExcludedNetworkIDs = (Get-ClusterResourceType -Name 'Virtual Machine' | Get-ClusterParameter -Name 'MigrationExcludeNetworks').Value.Split(';')
    $ClusterNetworks = Get-ClusterNetwork -Cluster $Name | Where-Object {$_.ID -notin $ExcludedNetworkIDs}
    if($ClusterNetworks)
    {
        $Networks = @()
        foreach($ClusterNetwork in $ClusterNetworks)
        {
            $Networks += $ClusterNetwork.Address
        }
    }

	$returnValue = @{
		Name = $Name
		Networks = $Networks
	}

	$returnValue
}


function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name,

		[parameter(Mandatory = $true)]
		[System.String[]]
		$Networks
	)

    $ExcludedNetworkIDs = (Get-ClusterNetwork -Cluster $Name | Where-Object {$_.Address -notin $Networks}).ID
    if($ExcludedNetworkIDs)
    {
        $Value = ([String]::Join(";",$ExcludedNetworkIDs))
    }
    else
    {
        $Value = ""
    }

    Get-ClusterResourceType -Name 'Virtual Machine' | Set-ClusterParameter -Name 'MigrationExcludeNetworks' -Value $Value

    if(!(Test-TargetResource @PSBoundParameters))
    {
        throw New-TerminatingError -ErrorType TestFailedAfterSet -ErrorCategory InvalidResult
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

		[parameter(Mandatory = $true)]
		[System.String[]]
		$Networks
	)

    $LiveMigrationNetworks = Get-TargetResource @PSBoundParameters

	if((Compare-Object -ReferenceObject $Networks -DifferenceObject $LiveMigrationNetworks.Networks) -eq $null)
    {
        $result = $true
    }
    else
    {
        $result = $false
    }

	$result
}


Export-ModuleMember -Function *-TargetResource