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
		$DiskFriendlyName,

		[parameter(Mandatory = $true)]
		[AllowEmptyString()]
        [System.String]
		$DiskNumbers
	)

    Write-Verbose "Get disks with friendly name `"$DiskFriendlyName`""
    $Disks = GetDisks -DiskFriendlyName $DiskFriendlyName -DiskNumbers $DiskNumbers
    Write-Verbose "Get cluster disk names"
    $ClusterDisks = GetClusterDisks -DiskFriendlyName $DiskFriendlyName -DiskNumbers $DiskNumbers
    Write-Verbose "Get cluster shared volumes"
    $ClusterSharedVolumes = Get-ClusterSharedVolume

    $Count = 0
    foreach($Disk in $Disks)
    {
        $ClusterDisk = $ClusterDisks | Where-Object {$_.DiskNumber -eq $Disk.Number}
        if($ClusterSharedVolumes | Where-Object {$_.Name -eq $ClusterDisk.ClusterDisk})
        {
            $MountPoint = ($ClusterSharedVolumes | Where-Object {$_.Name -eq $ClusterDisk.ClusterDisk}).SharedVolumeInfo.FriendlyVolumeName
            Write-Verbose "Disk $($Disk.Number) is a cluster shared volume on $($ClusterDisk.ClusterDisk) at $MountPoint"
            $Count++
        }
        else
        {
            Write-Verbose "Disk $($Disk.Number) is not a cluster shared volume"
        }
    }

	$returnValue = @{
		DiskFriendlyName = $DiskFriendlyName
		Count = $Count
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
		$DiskFriendlyName,

		[parameter(Mandatory = $true)]
		[AllowEmptyString()]
        [System.String]
		$DiskNumbers
	)

    Write-Verbose "Get disks with friendly name `"$DiskFriendlyName`""
    $Disks = GetDisks -DiskFriendlyName $DiskFriendlyName -DiskNumbers $DiskNumbers
    Write-Verbose "Get cluster disk names"
    $ClusterDisks = GetClusterDisks -DiskFriendlyName $DiskFriendlyName -DiskNumbers $DiskNumbers
    Write-Verbose "Get cluster shared volumes"
    $ClusterSharedVolumes = Get-ClusterSharedVolume

    foreach($Disk in $Disks)
    {
        $ClusterDisk = $ClusterDisks | Where-Object {$_.DiskNumber -eq $Disk.Number}
        if($ClusterDisk)
        {
            if($ClusterSharedVolumes | Where-Object {$_.Name -eq $ClusterDisk.ClusterDisk})
            {
                $MountPoint = ($ClusterSharedVolumes | Where-Object {$_.Name -eq $ClusterDisk.ClusterDisk}).SharedVolumeInfo.FriendlyVolumeName
                Write-Verbose "Disk $($Disk.Number) is a cluster shared volume on $($ClusterDisk.ClusterDisk) at $MountPoint"
            }
            else
            {
                $ClusterResource = Get-ClusterResource -Name $ClusterDisk.ClusterDisk
                if($ClusterResource)
                {
                    $ClusterSharedVolume = Add-ClusterSharedVolume -InputObject $ClusterResource
                    if ($ClusterSharedVolume)
                    {
                        $MountPoint = $ClusterSharedVolume.SharedVolumeInfo.FriendlyVolumeName
                        Write-Verbose "Disk $($Disk.Number) is now a cluster shared volume on $($ClusterDisk.ClusterDisk) at $MountPoint"
                    }
                }
            }
        }
    }    

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
		$DiskFriendlyName,

		[parameter(Mandatory = $true)]
        [AllowEmptyString()]
		[System.String]
		$DiskNumbers
	)

    $result = ((Get-TargetResource -DiskFriendlyName $DiskFriendlyName -DiskNumbers $DiskNumbers).Count -eq @(GetDisks -DiskFriendlyName $DiskFriendlyName -DiskNumbers $DiskNumbers).Count)

    $result
}


function GetDisks
{
    param
    (
		[parameter(Mandatory = $true)]
		[System.String]
		$DiskFriendlyName,

		[parameter(Mandatory = $true)]
        [AllowEmptyString()]
		[System.String]
		$DiskNumbers
    )

    $Disks = @()
    $DiskNumbersToGet = @()
    foreach($DiskNumber in $DiskNumbers.Split(","))
    {
        if ($DiskNumber.Contains("-"))
        {
            $DiskNumberRange = $DiskNumber.Split("-")
            if($DiskNumber.Trim("-").Contains("-"))
            {
                $DiskNumberRangeStart = $DiskNumberRange[0]
                $DiskNumberRangeEnd = $DiskNumberRange[1]
            }
            else
            {
                if($DiskNumber.SubString(0,1) -eq "-")
                {
                    $DiskNumberRangeStart = 1
                    $DiskNumberRangeEnd = $DiskNumberRange[1]
                }
                else
                {
                    $DiskNumberRangeStart = $DiskNumberRange[0]
                    $DiskNumberRangeEnd = ((Get-Disk).Number | Sort-Object -Descending)[0]
                }
            }
            $DiskNumbersToGet += @($DiskNumberRangeStart..$DiskNumberRangeEnd)
        }
        else
        {
            $DiskNumbersToGet += $DiskNumber
        }
    }
    if ([String]::IsNullOrEmpty($DiskNumbersToGet))
    {
        $Disks = Get-Disk -FriendlyName $DiskFriendlyName -ErrorAction SilentlyContinue
    }
    else
    {
        $DiskNumbersToGet = $DiskNumbersToGet | Sort-Object
        foreach($DiskNumber in $DiskNumbersToGet)
        {
            $Disks += Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue | Where-Object {$_.FriendlyName -eq $DiskFriendlyName}
        }
    }

    $Disks | Sort-Object {$_.Number}
}


function GetClusterDisks
{
    $returnValue = @()
    $DiskResources = Get-WmiObject -Class MSCluster_Resource -Namespace root/mscluster | Where-Object {$_.Type -eq "Physical Disk"}
    foreach($DiskResource in $DiskResources)
    {
        $Disks = Get-WmiObject -Namespace root/mscluster -Query "Associators of {$DiskResource} Where ResultClass=MSCluster_Disk"
        foreach($Disk in $Disks)
        {
            $returnValue += @{
                DiskNumber = $Disk.Number
                ClusterDisk = $DiskResource.Name
            }
        }
    }

    $returnValue
}


Export-ModuleMember -Function *-TargetResource