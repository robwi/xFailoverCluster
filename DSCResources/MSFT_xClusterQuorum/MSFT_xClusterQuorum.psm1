$currentPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Debug -Message "CurrentPath: $currentPath"

# Load Common Code
Import-Module $currentPath\..\..\xFailoverClusterHelper.psm1 -Verbose:$false -ErrorAction Stop

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

    $Quorum = Get-ClusterQuorum
    switch($Quorum.QuorumType)
    {
        "NodeMajority"
        {
            $QuorumResource = ""
        }
        "NodeAndDiskMajority"
        {
            $QuorumResource = $Quorum.QuorumResource
        }
        "NodeAndFileShareMajority"
        {
            $QuorumResource = ($Quorum.QuorumResource | Get-ClusterParameter -Name "SharePath" | Select-Object -ExpandProperty "Value")
        }
    }

	$returnValue = @{
		Name = $Name
		QuorumType = $Quorum.QuorumType
		QuorumResource = $QuorumResource
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

		[ValidateSet("NodeMajority","NodeAndDiskMajority","NodeAndFileShareMajority")]
		[System.String]
		$QuorumType = "NodeMajority",

		[System.String]
		$QuorumResource
	)

	if(($QuorumType -eq "NodeAndDiskMajority") -and $QuorumResource.Contains("/") -and (($QuorumResource.Split("/")[0] -eq "Drive") -or ($QuorumResource.Split("/")[0]  -eq "Disk") -or ($QuorumResource.Split("/")[0]  -eq "VirtualDiskName")))
    {
        $QuorumResource = GetClusterDisk -QuorumResource $QuorumResource
        if([String]::IsNullOrEmpty($QuorumResource))
        {
            throw "QuorumResource is not a cluster disk!"
        }
    }

    $QuorumAttempt = 0
    do
    {
        $QuorumAttempt++
        Write-Verbose "Setting quorum to $QuorumType $QuorumResource, attempt $QuorumAttempt"
        switch($QuorumType)
        {
            "NodeMajority"
            {
                try
                {
                    Set-ClusterQuorum -NoWitness
                    $QuorumSuccess = $true
                }
                catch
                {
                    $QuorumSuccess = $false
                }
            }
            "NodeAndDiskMajority"
            {
                try
                {
                    Set-ClusterQuorum -DiskWitness $QuorumResource
                    $QuorumSuccess = $true
                }
                catch
                {
                    $QuorumSuccess = $false
                }
            }
            "NodeAndFileShareMajority"
            {
                try
                {
                    Set-ClusterQuorum -FileShareWitness $QuorumResource
                    $QuorumSuccess = $true
                }
                catch
                {
                    $QuorumSuccess = $false
                }
            }
        }
        if(!$QuorumSuccess)
        {
            Write-Verbose "Failed setting quorum to $QuorumType $QuorumResource, pausing 10 seconds"
            Start-Sleep -Seconds 10
        }
    }
    until($QuorumSuccess -or ($QuorumAttempt -gt 10))

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

		[ValidateSet("NodeMajority","NodeAndDiskMajority","NodeAndFileShareMajority")]
		[System.String]
		$QuorumType = "NodeMajority",

		[System.String]
		$QuorumResource
	)

	if(($QuorumType -eq "NodeAndDiskMajority") -and $QuorumResource.Contains("/") -and (($QuorumResource.Split("/")[0] -eq "Drive") -or ($QuorumResource.Split("/")[0]  -eq "Disk") -or ($QuorumResource.Split("/")[0]  -eq "VirtualDiskName")))
    {
        $QuorumResource = GetClusterDisk -QuorumResource $QuorumResource
        if([String]::IsNullOrEmpty($QuorumResource))
        {
            throw New-TerminatingError -ErrorType QuorumResourceNotDisk -ErrorCategory InvalidData
        }
    }

    $Quorum = Get-TargetResource -Name $Name
    if($QuorumType -eq "NodeMajority")
    {
        $result = ($Quorum.QuorumType -eq $QuorumType)
    }
    else
    {
        $result = (($Quorum.QuorumType -eq $QuorumType) -and ($Quorum.QuorumResource -eq $QuorumResource))
    }
	
	$result
}


function GetClusterDisk
{
    param
    (
		[parameter(Mandatory = $true)]
		[System.String]
		$QuorumResource
    )

    $Test = $QuorumResource.Split("/")

    if($Test[0] -eq "VirtualDiskName")
    {
        (Get-WmiObject -Class MSCluster_Resource -Namespace root/mscluster | Where-Object {$_.Name -eq "Cluster Virtual Disk ($($Test[1]))"}).Name
    }
    else
    {
        $DiskResources = Get-WmiObject -Class MSCluster_Resource -Namespace root/mscluster | Where-Object {$_.Type -eq "Physical Disk"}
        foreach($DiskResource in $DiskResources)
        {
            $Disks = Get-WmiObject -Namespace root/mscluster -Query "Associators of {$DiskResource} Where ResultClass=MSCluster_Disk"
            foreach($Disk in $Disks)
            {
                switch($Test[0])
                {
                    "Drive"
                    {
                        $Partitions = Get-WmiObject -Namespace root/mscluster -Query "Associators of {$Disk} Where ResultClass=MSCluster_DiskPartition"
                        foreach($Partition in $Partitions)
                        {
                            if($Partition.Path -eq $Test[1])
                            {
                                $DiskResource.Name
                            }
                        }
                    }
                    "Disk"
                    {
                        if($Disk.Number -eq $Test[1])
                        {
                                if($Test[2])
                            {
                                if ((Get-Disk -Number $Disk.Number).FriendlyName -eq $Test[2])
                                {
                                    $DiskResource.Name
                                }
                            }
                            else
                            {
                                $DiskResource.Name
                            }
                        }
                    }
                }
            }
        }
    }
}


Export-ModuleMember -Function *-TargetResource