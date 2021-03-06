$currentPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Debug -Message "CurrentPath: $currentPath"

# Load Common Code
Import-Module $currentPath\..\..\xFailoverClusterHelper.psm1 -Verbose:$false -ErrorAction Stop

try
{
    if(!(Get-Module 'FailoverClusters'))
    {
        Write-Verbose "Importing VirtualMachineManager Module"
           
        $CurrentVerbose = $VerbosePreference
        $VerbosePreference = "SilentlyContinue"
        $null = Import-Module FailoverClusters -ErrorAction Stop
        $VerbosePreference = $CurrentVerbose
    }
}
catch
{
    Write-Verbose "Problem with importing FailoverClusters on ""$env:ComputerName"".  Ensure Windows Failover Clustering is installed correctly." -Verbose

    throw $_
}

function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
        [Parameter(Mandatory=$true)]
        [String] 
        $ClusterName,

        [UInt32] 
        $ClusterLogSizeInMB,

        [UInt32] 
        $ShutdownTimeoutInMinutes,

        [UInt32] 
        $DatabaseReadWriteMode
	)

    Write-Verbose "Getting Cluster ""$ClusterName""."

    $cluster = Get-Cluster -Name $ClusterName -ErrorAction Stop

    $returnValue = @{
        ClusterName=$ClusterName
        ClusterLogSizeInMB=$cluster.ClusterLogSize
        ShutdownTimeoutInMinutes=$cluster.ShutdownTimeoutInMinutes
        DatabaseReadWriteMode=$cluster.DatabaseReadWriteMode
	}

	$returnValue
}

function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
        [Parameter(Mandatory=$true)]
        [String] 
        $ClusterName,

        [UInt32] 
        $ClusterLogSizeInMB,

        [UInt32] 
        $ShutdownTimeoutInMinutes,

        [UInt32] 
        $DatabaseReadWriteMode
	)
    
    Write-Verbose "Getting Cluster ""$ClusterName""."
    $cluster = Get-Cluster -Name $ClusterName -ErrorAction Stop

    if($ClusterLogSizeInMB)
    {
        Write-Verbose "Setting ClusterLogSize to ""$ClusterLogSizeInMB"" from ""$($cluster.ClusterLogSize)""."
        $cluster.ClusterLogSize = $ClusterLogSizeInMB
    }

    if($ShutdownTimeoutInMinutes)
    {
        Write-Verbose "Setting ShutdownTimeoutInMinutes to ""$ShutdownTimeoutInMinutes"" from ""$($cluster.ShutdownTimeoutInMinutes)""."
        $cluster.ShutdownTimeoutInMinutes = $ShutdownTimeoutInMinutes
    }

    if($DatabaseReadWriteMode)
    {
        Write-Verbose "Setting DatabaseReadWriteMode to ""$DatabaseReadWriteMode"" from ""$($cluster.DatabaseReadWriteMode)""."
        $cluster.DatabaseReadWriteMode = $DatabaseReadWriteMode
    }

    # For now call Test at the end of Set
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
        [Parameter(Mandatory=$true)]
        [String] 
        $ClusterName,

        [UInt32] 
        $ClusterLogSizeInMB,

        [UInt32] 
        $ShutdownTimeoutInMinutes,

        [UInt32] 
        $DatabaseReadWriteMode
	)
    
    $clusterResult = ((Get-TargetResource @PSBoundParameters))

    Write-Verbose "Running Tests on Cluster Properties."

    $result = $true

    if($ClusterLogSizeInMB)
    {
        if($clusterResult.ClusterLogSizeInMB -ne $ClusterLogSizeInMB)
        {
            Write-Verbose "Expected ClusterLogSize: ""$ClusterLogSizeInMB"" Actual: ""$($clusterResult.ClusterLogSizeInMB)""."
            $result = $false
        }
    }

    if($ShutdownTimeoutInMinutes)
    {
        if($clusterResult.ShutdownTimeoutInMinutes -ne $ShutdownTimeoutInMinutes)
        {
            Write-Verbose "Expected ShutdownTimeoutInMinutes: ""$ShutdownTimeoutInMinutes"" Actual: ""$($clusterResult.ShutdownTimeoutInMinutes)""."
            $result = $false
        }
    }

    if($DatabaseReadWriteMode)
    {
        if($clusterResult.DatabaseReadWriteMode -ne $DatabaseReadWriteMode)
        {
            Write-Verbose "Expected DatabaseReadWriteMode: ""$DatabaseReadWriteMode"" Actual: ""$($clusterResult.DatabaseReadWriteMode)""."
            $result = $false
        }
    }

	$result
}

Export-ModuleMember -Function *-TargetResource