# roles/dc01/files/set_gpo_registry_value.ps1
# Run by the "Set the GPO settings" task in roles/dc01/tasks/gpo.yml through
# ansible.windows.win_powershell (path:), once per GPO setting in ad_gpos.
# No Ansible module can set values inside a GPO, so this uses Microsoft's
# Get-GPRegistryValue / Set-GPRegistryValue.
#
# Sets one registry-based policy value in one GPO. It reads the current
# value first and only writes when it differs, so Ansible reports "changed"
# only for real changes. SupportsShouldProcess lets it run in --check mode,
# where it reports changes without making them.
#
# Why files/ and not templates/: an Ansible template (.j2) is for files that
# Ansible fills in with variables before use. This script has no variables
# in its text; Ansible passes the values as parameters (the param block
# below, set by `parameters:` in the task). So it is a plain file, the same
# on every run, and can be read or tested on its own.
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Key,
    [Parameter(Mandatory)][string]$ValueName,
    [Parameter(Mandatory)][string]$Type,
    [Parameter(Mandatory)][object]$Value
)
$Ansible.Changed = $false

# Numbers must be passed as numbers, lists as string arrays.
switch ($Type) {
    'DWord'       { $Value = [int]$Value }
    'QWord'       { $Value = [long]$Value }
    'MultiString' { $Value = [string[]]$Value }
    default       { $Value = [string]$Value }
}

# Read what the GPO holds now. A missing value (or, in --check mode,
# a GPO not created yet) throws, which just means "not set".
$current = $null
try {
    $current = Get-GPRegistryValue -Name $Name -Key $Key -ValueName $ValueName -ErrorAction Stop
}
catch { }

# String values can come back with a trailing null character; strip it
# before comparing so an unchanged value isn't reported as changed.
$same = $false
if ($current) {
    $currentValue = ($current.Value | ForEach-Object { "$_".TrimEnd([char]0) }) -join "`n"
    $wantedValue = ($Value | ForEach-Object { "$_" }) -join "`n"
    $same = ("$($current.Type)" -eq $Type) -and ($currentValue -eq $wantedValue)
}

if (-not $same) {
    if ($PSCmdlet.ShouldProcess("$Name : $Key\$ValueName", 'Set GPO registry value')) {
        Set-GPRegistryValue -Name $Name -Key $Key -ValueName $ValueName -Type $Type -Value $Value | Out-Null
    }
    $Ansible.Changed = $true
}
