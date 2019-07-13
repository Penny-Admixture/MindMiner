<#
MindMiner  Copyright (C) 2018-2019  Oleg Samsonov aka Quake4
https://github.com/Quake4/MindMiner
License GPL-3.0
#>

Write-Host "MRRFirst: $($global:MRRFirst)"

$PoolInfo = [PoolInfo]::new()
$PoolInfo.Name = (Get-Item $script:MyInvocation.MyCommand.Path).BaseName

$configfile = $PoolInfo.Name + [BaseConfig]::Filename

$Cfg = ReadOrCreatePoolConfig "Do you want to pass a rig to rent on $($PoolInfo.Name)" ([IO.Path]::Combine($PSScriptRoot, $configfile)) @{
	Enabled = $false
	Key = $null
	Secret = $null
	Region = $null
	EnabledAlgorithms = $null
	DisabledAlgorithms = $null
}
if ($global:AskPools -eq $true -or !$Cfg) { return $null }

$PoolInfo.Enabled = $Cfg.Enabled

if (!$Cfg.Enabled) { return $PoolInfo }

try {
	$servers = Get-UrlAsJson "https://www.miningrigrentals.com/api/v2/info/servers"
	if (!$servers -or !$servers.success) {
		throw [Exception]::new()
	}
}
catch { return $PoolInfo }

if ([string]::IsNullOrWhiteSpace($Cfg.Region)) {
	$Cfg.Region = "us-central"
	switch ($Config.Region) {
		"$([eRegion]::Europe)" { $Cfg.Region = "eu" }
		"$([eRegion]::China)" { $Cfg.Region = "ap" }
		"$([eRegion]::Japan)" { $Cfg.Region = "ap" }
	}
	if ($Cfg.Region -eq "eu") {
		[string] $locale = "$($Cfg.Region)-$((Get-Host).CurrentCulture.TwoLetterISOLanguageName)"
		if ($servers.data | Where-Object { $_.region -match $locale }) {
			$Cfg.Region = $locale
		}
	}
}
$server = $servers.data | Where-Object { $_.region -match $Cfg.Region } | Select-Object -First 1	

if (!$server -or $server.Length -gt 1) {
	$servers = $servers.data | Select-Object -ExpandProperty region
	Write-Host "Set `"Region`" parameter from list ($(Get-Join ", " $servers)) in the configuration file `"$configfile`" or disable the $($PoolInfo.Name)." -ForegroundColor Yellow
	return $null;
}

if ($global:MRRFirst) {
	# info as standart pool as fake pool
	$PoolInfo.HasAnswer = $true
	$PoolInfo.AnswerTime = [DateTime]::Now
	$PoolInfo.Algorithms.Add([PoolAlgorithmInfo] @{
		Name = $PoolInfo.Name
		Algorithm = "MiningRigRentals"
		Profit = 1
		Info = "Fake"
		Protocol = "stratum+tcp"
		Host = $server.name
		Port = $server.port
		PortUnsecure = $server.port
		User = [Config]::MRRLoginPlaceholder
		Password = [Config]::WorkerNamePlaceholder
	})
	return $PoolInfo
}
else {
	if ([string]::IsNullOrWhiteSpace($Cfg.Key) -or [string]::IsNullOrWhiteSpace($Cfg.Secret)) {
		Write-Host "Fill in the `"Key`" and `"Secret`" parameters in the configuration file `"$configfile`" or disable the $($PoolInfo.Name)." -ForegroundColor Yellow
		return $null
	}

	try {
		$algos = Get-UrlAsJson "https://www.miningrigrentals.com/api/v2/info/algos"
		if (!$algos -or !$algos.success) {
			throw [Exception]::new()
		}
	}
	catch { return $PoolInfo }


	$algos.data | ForEach-Object {
		$Algo = $_
		$Pool_Algorithm = Get-Algo ($Algo.name) $false
		if ($Pool_Algorithm -and (!$Cfg.EnabledAlgorithms -or $Cfg.EnabledAlgorithms -contains $Pool_Algorithm) -and $Cfg.DisabledAlgorithms -notcontains $Pool_Algorithm) {
			$Algo.suggested_price.unit = $Algo.suggested_price.unit.ToLower().TrimEnd("h*day")
			$Profit = [decimal]$Algo.suggested_price.amount / [MultipleUnit]::ToValueInvariant("1", $Algo.suggested_price.unit)
			$PoolInfo.Algorithms.Add([PoolAlgorithmInfo] @{
				Name = $PoolInfo.Name
				Algorithm = $Pool_Algorithm
				Profit = $Profit
				Info = "$($Algo.stats.rented.rigs)/$($Algo.stats.available.rigs)"
				Protocol = "stratum+tcp"
				Host = $server.name
				Port = $server.port
				PortUnsecure = $server.port
				User = [Config]::MRRLoginPlaceholder
				Password = [Config]::WorkerNamePlaceholder
			})
		}
	}

	try {
		$mrr = [MRR]::new($Cfg.Key, $Cfg.Secret);
		$mrr.Debug = $true;
		$result = $mrr.Get("/whoami")
		if (!$result.authed) {
			Write-Host "MRR: Not authorized! Check Key and Secret." -ForegroundColor Yellow
			return $null;
		}
		[Config]::MRRLogin = "$($result.username).$($result.userid)"
		if ($result.permissions.rigs -ne "yes") {
			Write-Host "MRR: Need grant `"Manage Rigs`"." -ForegroundColor Yellow
			return $null;
		}

		# check rigs

		# $AllAlgos.Miners -contains $Pool_Algorithm

		$result = $mrr.Get("/rig/mine") | Where-Object { $_.name -match $Config.WorkerName }
		if ($result) {

		}
		else {
			# create rigs on all algos
		}

		# if rented
		$rented = $null
		$rented
	}
	catch {
		Write-Host $_
	}
	finally {
		if ($mrr) {	$mrr.Dispose() }
	}	
}
