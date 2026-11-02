# roles/dc01/files/create_gpo.ps1
# Run by the "Create the GPOs" task in roles/dc01/tasks/gpo.yml through
# ansible.windows.win_powershell (path:), once per entry in ad_gpos.
# No Ansible module can create a GPO, so this uses Microsoft's New-GPO.
#
# Creates the GPO if none with this name exists, and keeps its comment up to
# date. It reads first and only writes when something differs, so Ansible
# reports "changed" only for real changes. SupportsShouldProcess lets it run
# in --check mode, where it reports changes without making them.
#
# Why files/ and not templates/: an Ansible template (.j2) is for files that
# Ansible fills in with variables before use. This script has no variables
# in its text; Ansible passes the values as parameters (the param block
# below, set by `parameters:` in the task). So it is a plain file, the same
# on every run, and can be read or tested on its own.
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)][string]$Name,
    [string]$Comment
)
$Ansible.Changed = $false
$gpo = Get-GPO -All | Where-Object DisplayName -eq $Name

if (-not $gpo) {
    if ($PSCmdlet.ShouldProcess($Name, 'Create GPO')) {
        New-GPO -Name $Name -Comment $Comment | Out-Null
    }
    $Ansible.Changed = $true
}
elseif ("$($gpo.Description)" -ne $Comment) {
    if ($PSCmdlet.ShouldProcess($Name, 'Update GPO comment')) {
        $gpo.Description = $Comment
    }
    $Ansible.Changed = $true
}
