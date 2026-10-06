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

# husky-ad-lite

**Active Directory Enumeration — OSCP-Safe Edition**
*Enumerate everything. Execute nothing. Copy-paste when ready.*

Built by [The Husky Hacker](https://thehuskyhacker.com) — designed for the OSCP exam where you need full control over what runs.

---

## What Is This?

husky-ad-lite is the cautious sibling of [husky-ad](https://github.com/TheHuskyHacker/HuskyAD). It runs the same LDAP enumeration to **identify** vulnerable accounts, misconfigurations, and attack paths — but instead of auto-executing attacks, it **prints copy-paste commands** so you decide exactly when each one fires.

If you're worried about tripping an OSCP exam restriction or want to keep a clean audit trail of what you ran and when, this is the version to use.

## husky-ad vs husky-ad-lite

| Feature | husky-ad (Full) | husky-ad-lite |
|---------|----------------|---------------|
| LDAP enumeration | Auto | Auto |
| User/group/computer enum | Auto | Auto |
| SMB share listing | Auto | Auto |
| Password policy | Auto | Auto |
| Delegation checks | Auto | Auto |
| LAPS/GMSA reads | Auto | Auto |
| AS-REP Roasting | **Auto-executes** impacket | **Prints command** |
| Kerberoasting | **Auto-executes** impacket | **Prints command** |
| Share spidering | **Auto-executes** netexec | **Prints command** |
| GPP password modules | **Auto-executes** netexec | **Prints command** |
| BloodHound collection | **Auto-executes** | **Prints command** |
| EternalBlue scan | **Auto-executes** nmap | **Prints command** |
| Print Spooler check | **Auto-executes** rpcclient | **Prints command** |
| WebDAV check | **Auto-executes** netexec | **Prints command** |
| MSSQL/RDP discovery | **Auto-executes** netexec | **Prints command** |

**TL;DR:** Lite uses LDAP to find targets, then hands you the commands. Full runs them for you.

## Quick Start

```bash
chmod +x husky-ad-lite.sh

# Authenticated
./husky-ad-lite.sh -d corp.local -c 10.10.10.10 -u jsmith -p 'Password123!'

# Pass-the-hash
./husky-ad-lite.sh -d corp.local -c 10.10.10.10 -u admin -H aad3b435b51404eeaad3b435b51404ee

# Null session
./husky-ad-lite.sh -d corp.local -c 10.10.10.10

# Extended checks (prints more commands)
./husky-ad-lite.sh -d corp.local -c 10.10.10.10 -u jsmith -p 'Password123!' -f
```

## Usage

```
Usage: ./husky-ad-lite.sh -d <domain> -c <dc_ip> [-u <user>] [-p <pass>] [-H <hash>] [-o <outdir>] [-f]

  -d    Domain name (e.g., corp.local)
  -c    Domain Controller IP
  -u    Username (optional — null session if omitted)
  -p    Password
  -H    NTLM hash (pass-the-hash)
  -o    Output directory (default: ./husky_ad_loot)
  -f    Full scan — extended enumeration checks
  -q    Quiet mode (findings only)
```

## How It Works

### Step 1: Enumerate (automatic)

The script runs LDAP queries to identify:

- **AS-REP Roastable users** — `(userAccountControl:1.2.840.113556.1.4.803:=4194304)` finds accounts without Kerberos preauthentication
- **Kerberoastable accounts** — Finds user accounts with `servicePrincipalName` set (filters out computers and krbtgt)
- **All the same enumeration** as the full version — users, groups, shares, delegation, LAPS, GMSA, trusts, GPOs, DNS

### Step 2: Print commands (you decide)

For every attack vector found, the script prints the exact command:

```
  >>> COPY-PASTE COMMAND <<<
  impacket-GetNPUsers 'corp.local/jsmith:Password123!' -dc-ip 10.10.10.10 -request -outputfile ./husky_ad_loot/asrep_hashes.txt
```

### Step 3: Command Cheat Sheet

At the end, every copy-paste command is collected into one summary section so you can run them sequentially:

```
  ╔═══════════════════════════════════════════════════╗
  ║ COMMAND CHEAT SHEET — Copy & Paste
  ╚═══════════════════════════════════════════════════╝

  1. impacket-GetNPUsers 'corp.local/jsmith:...' -dc-ip 10.10.10.10 -request ...
  2. impacket-GetUserSPNs 'corp.local/jsmith:...' -dc-ip 10.10.10.10 -request ...
  3. bloodhound-python -u 'jsmith' -p '...' -d 'corp.local' -ns 10.10.10.10 -c All ...
  ...
```

## What It Checks

### Auto-Enumerated (runs automatically)

| # | Section | What It Does |
|---|---------|-------------|
| 1 | **Sniffing the Territory** | Domain info, naming contexts, functional level, null session test |
| 2 | **Tracking the Pack** | User enumeration — RID brute, descriptions (password hunting), admin accounts |
| 3 | **Testing the Fence** | Password policy — lockout threshold, complexity, min length |
| 4 | **Cracking Bones** | LDAP identifies AS-REP roastable and Kerberoastable targets |
| 5 | **Raiding the Den** | SMB share listing — readable/writable shares |
| 6 | **Finding the Weak Link** | Delegation — unconstrained, constrained, RBCD; MachineAccountQuota |
| 7 | **Digging Up Bones** | LAPS v1 and v2 password reads |
| 8 | **Buried Treasure** | GMSA account discovery and password reads |
| 9 | **The Alpha Dogs** | Privileged group membership enumeration |
| 10 | **Mapping the Territory** | Computer objects, legacy OS detection |
| 11 | **Neighboring Packs** | Domain/forest trusts |
| 12 | **Sniffing Policy** | GPO enumeration |
| 13 | **Howling at DNS** | Zone transfer attempts, ADIDNS dumps |
| 14 | **Trying the Door** | WinRM and SMB admin access checks |

### Copy-Paste Only (prints commands for you to run)

| Command | When It Prints |
|---------|---------------|
| `impacket-GetNPUsers -request` | AS-REP roastable users found via LDAP |
| `impacket-GetUserSPNs -request` | Kerberoastable accounts found via LDAP |
| `hashcat -m 18200 / -m 13100` | After AS-REP / Kerberoast targets found |
| `netexec -M spider_plus` | With `-f` flag (full scan) |
| `netexec -M gpp_password` | GPOs found in domain |
| `netexec -M gpp_autologin` | GPOs found in domain |
| `bloodhound-python -c All` | Always (when creds available) |
| `netexec mssql` | With `-f` flag |
| `netexec rdp` | With `-f` flag |
| `nmap --script smb-vuln-ms17-010` | With `-f` flag |
| `rpcclient 'getprinter'` | With `-f` flag |
| `netexec -M webdav` | With `-f` flag |

## Output Tags

| Tag | Meaning |
|-----|---------|
| `[SNIFF]` | Informational finding — noted for context |
| `[GROWL]` | Warning — worth investigating |
| `[BITE!]` | Critical — immediate escalation path |
| `[TRACK]` | Info — general enumeration data |
| `[WHIFF]` | Check failed or returned nothing |

## Output Directory

All enumeration output is saved to `./husky_ad_loot/` (configurable with `-o`):

```
husky_ad_loot/
├── smb_info.txt
├── naming_contexts.txt
├── users.txt
├── user_descriptions.txt
├── asrep_targets.txt        ← users identified via LDAP (no hashes)
├── kerberoast_targets.txt   ← SPNs identified via LDAP (no hashes)
├── smb_shares.txt
├── constrained_delegation.txt
├── laps_passwords.txt
├── gmsa_accounts.txt
├── computers.txt
├── domain_trusts.txt
├── gpos.txt
└── dns_records.csv
```

## OSCP Notes

- **Zero auto-attacks** — every offensive tool is a printed command, not an executed one
- **Zero modules** — enumeration uses standard Kali tools
- **Full control** — you decide what runs and when
- **Audit-friendly** — clear record of what was enumerated vs. what was attacked

## Dependencies

All pre-installed on Kali:
- `ldapsearch` — LDAP queries (core enumeration engine)
- `netexec` (nxc) — SMB share listing, WinRM checks
- `rpcclient` — RPC enumeration, password policy
- `dig` — DNS zone transfers
- `smbclient` — Null session SMB checks

Optional (for copy-paste commands to work):
- `impacket` — GetNPUsers, GetUserSPNs (printed, not auto-run)
- `bloodhound-python` — BloodHound collection (printed, not auto-run)
- `bloodyAD` — ACL and GMSA checks
- `adidnsdump` — ADIDNS record dumps

## Author

**The Husky Hacker**
- GitHub: [github.com/HackingHusky](https://github.com/HackingHusky)
- Site: [thehuskyhacker.com](https://thehuskyhacker.com)
- Blog: [husky-hacker-read.com](https://husky-hacker-read.com)

*"The domain is a forest. Be the wolf."*
