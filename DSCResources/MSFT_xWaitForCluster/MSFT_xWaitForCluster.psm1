$currentPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Debug -Message "CurrentPath: $currentPath"

# Load Common Code
Import-Module $currentPath\..\..\xFailoverClusterHelper.psm1 -Verbose:$false -ErrorAction Stop

function Get-TargetResource
{
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name,

		[parameter(Mandatory = $true)]
		[System.String]
		$FirstNode,

		[parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$SetupCredential,

        [ValidateRange(1,[Uint64]::MaxValue)]
        [Uint64]
        $RetryIntervalSec = 1, 

        [Uint32]
        $RetryCount = 0
	)

    @{
        Name = $Name
        FirstNode = $FirstNode
        RetryIntervalSec = $RetryIntervalSec
        RetryCount = $RetryCount
    }
}


function Set-TargetResource
{
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name,

		[parameter(Mandatory = $true)]
		[System.String]
		$FirstNode,

		[parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$SetupCredential,

        [ValidateRange(1,[Uint64]::MaxValue)]
        [Uint64]
        $RetryIntervalSec = 1, 

        [Uint32]
        $RetryCount = 0
	)

    $ClusterFound = $false
    Write-Verbose -Message "Checking for cluster $Name ..."

    for($count = 0; $count -lt $RetryCount; $count++)
    {
        $ClusterGroup = Get-WmiObject -Class MSCluster_ResourceGroup -Namespace root/mscluster -ComputerName $FirstNode -Credential $SetupCredential -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq "Cluster Group"}
        if ($ClusterGroup -ne $Null)
        {
            $ClusterName = Get-WmiObject -Namespace root/mscluster -Query "Associators of {$ClusterGroup} Where ResultClass=MSCluster_Resource" -ComputerName $FirstNode -Credential $SetupCredential -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq "Cluster Name"}
            if ($ClusterName.State -eq 2)
            {
                $result = $true
            }
            else
            {
                $result = $false
            }
        }
        else
        {
            $result = $false
        }
        if($result)
        {
            Write-Verbose -Message "Found cluster $Name"
            $ClusterFound = $true
            break
        }
        else
        {
            Write-Verbose -Message "Cluster $Name not found. Will retry again after $RetryIntervalSec sec"
            Start-Sleep -Seconds $RetryIntervalSec
        }
    }

    if(!($ClusterFound))
    {
        throw New-TerminatingError -ErrorType ClusterNotFoundAfterSeconds -FormatArgs @($Name,$count,$RetryIntervalSec) -ErrorCategory ObjectNotFound 
    }
}

function Test-TargetResource
{
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name,

		[parameter(Mandatory = $true)]
		[System.String]
		$FirstNode,

		[parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$SetupCredential,

        [ValidateRange(1,[Uint64]::MaxValue)]
        [Uint64]
        $RetryIntervalSec = 1, 

        [Uint32]
        $RetryCount = 0
	)

    Write-Verbose -Message "Checking for cluster $Name ..."
    if((Get-Cluster -ErrorAction SilentlyContinue).Name -eq $Name)
    {
        Write-Verbose "Node is in cluster $Name"
        $return = $true
    }
    else
    {
        $ClusterGroup = Get-WmiObject -Class MSCluster_ResourceGroup -Namespace root/mscluster -ComputerName $FirstNode -Credential $SetupCredential -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq "Cluster Group"}
        if ($ClusterGroup -ne $Null)
        {
            $ClusterName = Get-WmiObject -Namespace root/mscluster -Query "Associators of {$ClusterGroup} Where ResultClass=MSCluster_Resource" -ComputerName $FirstNode -Credential $SetupCredential -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq "Cluster Name"}
            if ($ClusterName.State -eq 2)
            {
                Write-Verbose "Cluster name $Name is ready"
                $return = $true
            }
            else
            {
                Write-Verbose "Cluster name $Name is not ready"
                $return = $false
            }
        }
        else
        {
            Write-Verbose "Cluster $Name is not present"
            $return = $false
        }
    }

    $return
}


Export-ModuleMember -Function *-TargetResource