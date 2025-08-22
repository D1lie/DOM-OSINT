#!/usr/bin/env bash
# DOM OSINT - Advanced Bash-based OSINT Framework
# Auto-installs dependencies, handles API keys, retries on errors, and exports reports.

# =============== Configuration ==================
CONFIG_DIR="$HOME/.config/domosint"
CONFIG_FILE="$CONFIG_DIR/config.env"
API_KEYS="$CONFIG_DIR/api_keys.env"
LOGDIR="$CONFIG_DIR/logs"
MODULES_DIR="$CONFIG_DIR/modules"
DATA_DIR="$CONFIG_DIR/data"
TOR_PROXY="socks5://127.0.0.1:9050"

# Create necessary directories
mkdir -p "$CONFIG_DIR" "$LOGDIR" "$MODULES_DIR" "$DATA_DIR"

# =============== Core Configuration ==================
CONFIG="$CONFIG_FILE"
LOGFILE="$LOGDIR/domosint_debug_$(date +%Y%m%d_%H%M%S).log"
REPORT_HTML="domosint_report_$(date +%Y%m%d_%H%M%S).html"
REPORT_JSON="domosint_data_$(date +%Y%m%d_%H%M%S).json"
CORRELATION_DB="$DATA_DIR/correlation.db"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============== Dependency Check ==================
REQUIRED_TOOLS=(curl jq whois dig exiftool sqlite3 tor torsocks python3)
RECOMMENDED_TOOLS=(nmap theharvester recon-ng photon dnsrecon sublist3r)

check_dependencies() {
    missing_tools=()
    for t in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$t" &>/dev/null; then
            missing_tools+=("$t")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${YELLOW}[*] Installing missing tools: ${missing_tools[*]}${NC}"
        sudo apt-get update -qq
        sudo apt-get install -y "${missing_tools[@]}"
    fi
    
    # Check for recommended tools
    missing_recommended=()
    for t in "${RECOMMENDED_TOOLS[@]}"; do
        if ! command -v "$t" &>/dev/null; then
            missing_recommended+=("$t")
        fi
    done
    
    if [ ${#missing_recommended[@]} -gt 0 ]; then
        echo -e "${YELLOW}[!] Recommended tools missing: ${missing_recommended[*]}${NC}"
        echo -e "${YELLOW}[!] Consider installing them for enhanced functionality${NC}"
    fi
}

# =============== API Keys Management ==================
setup_api_keys() {
    declare -A api_services=(
        ["HIBP_API_KEY"]="Have I Been Pwned"
        ["SHODAN_API_KEY"]="Shodan"
        ["VIRUSTOTAL_API_KEY"]="VirusTotal"
        ["CENSYS_API_ID"]="Censys ID"
        ["CENSYS_API_SECRET"]="Censys Secret"
        ["SECURITYTRAILS_API_KEY"]="SecurityTrails"
        ["HUNTER_API_KEY"]="Hunter.io"
        ["DEHASHED_API_KEY"]="Dehashed"
        ["DEHASHED_EMAIL"]="Dehashed Email"
        ["ABUSEIPDB_API_KEY"]="AbuseIPDB"
        ["GREYNOISE_API_KEY"]="GreyNoise"
    )
    
    if [ -f "$API_KEYS" ]; then
        source "$API_KEYS"
    fi
    
    echo -e "${BLUE}[*] API Key Configuration${NC}"
    for key in "${!api_services[@]}"; do
        current_val=$(eval echo \$$key)
        if [ -z "$current_val" ]; then
            read -p "Do you want to add ${api_services[$key]} API key? (y/N): " ans
            if [[ "$ans" =~ ^[Yy]$ ]]; then
                read -p "Enter $key: " input
                echo "export $key=\"$input\"" >> "$API_KEYS"
                export $key="$input"
            fi
        else
            echo -e "${GREEN}[✓] ${api_services[$key]} API key found${NC}"
        fi
    done
}

# =============== Stealth Configuration ==================
setup_stealth() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << EOF
# DOM OSINT Configuration
STEALTH_MODE=0
USE_TOR=0
REQUEST_DELAY=1
MAX_RETRIES=3
USER_AGENTS="$CONFIG_DIR/user_agents.txt"
PROXY_LIST="$CONFIG_DIR/proxies.txt"
EOF
    fi
    
    source "$CONFIG_FILE"
    
    # Create user agents file if it doesn't exist
    if [ ! -f "$USER_AGENTS" ]; then
        cat > "$USER_AGENTS" << EOF
Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36
Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Safari/605.1.15
Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.107 Safari/537.36
Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1
EOF
    fi
    
    # Check if Tor is available and running
    if [ $USE_TOR -eq 1 ] && ! pgrep -x "tor" > /dev/null; then
        echo -e "${YELLOW}[!] Tor is configured but not running. Starting Tor...${NC}"
        tor &
        sleep 10
    fi
}

# =============== Banner ==================
banner() {
    clear
    cat << "EOF"

██████╗  ██████╗ ███╗   ███╗     ██████╗ ███████╗██╗███╗   ██╗████████╗
██╔══██╗██╔═══██╗████╗ ████║    ██╔═══██╗██╔════╝██║████╗  ██║╚══██╔══╝
██║  ██║██║   ██║██╔████╔██║    ██║   ██║███████╗██║██╔██╗ ██║   ██║   
██║  ██║██║   ██║██║╚██╔╝██║    ██║   ██║╚════██║██║██║╚██╗██║   ██║   
██████╔╝╚██████╔╝██║ ╚═╝ ██║    ╚██████╔╝███████║██║██║ ╚████║   ██║   
╚═════╝  ╚═════╝ ╚═╝     ╚═╝     ╚═════╝ ╚══════╝╚═╝╚═╝  ╚═══╝   ╚═╝   
                                                                       
                   🔎 DOM OSINT – Advanced Bash OSINT Framework 🔎
                         API-aware  • Correlation • Reports

EOF
}

# =============== Core Functions ==================
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
    echo -e "$1"
}

get_random_ua() {
    if [ -f "$USER_AGENTS" ]; then
        shuf -n 1 "$USER_AGENTS"
    else
        echo "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
    fi
}

stealth_request() {
    local url=$1
    local ua=$(get_random_ua)
    local cmd="curl -s -L -A \"$ua\""
    
    if [ $USE_TOR -eq 1 ]; then
        cmd="torsocks $cmd"
    elif [ -f "$PROXY_LIST" ] && [ -s "$PROXY_LIST" ]; then
        local proxy=$(shuf -n 1 "$PROXY_LIST")
        cmd="$cmd --proxy $proxy"
    fi
    
    if [ $STEALTH_MODE -eq 1 ]; then
        sleep $((REQUEST_DELAY + RANDOM % 3))
    fi
    
    eval "$cmd \"$url\""
}

run_module() {
    local module_name="$1"
    local module_command="$2"
    local retries=${3:-$MAX_RETRIES}
    local attempt=1
    local success=0
    local output=""
    
    log "${BLUE}[*] Running module: $module_name${NC}"
    
    while [ $attempt -le $retries ] && [ $success -eq 0 ]; do
        output=$(eval "$module_command" 2>&1)
        local exit_code=$?
        
        if [ $exit_code -eq 0 ] && [ -n "$output" ]; then
            success=1
            log "${GREEN}[✓] $module_name succeeded on attempt $attempt${NC}"
        else
            log "${YELLOW}[!] $module_name attempt $attempt failed${NC}"
            sleep $((attempt * 2))
            ((attempt++))
        fi
    done
    
    if [ $success -eq 0 ]; then
        log "${RED}[X] $module_name failed after $retries attempts${NC}"
    fi
    
    echo "$output"
}

# =============== Data Correlation Database ==================
init_correlation_db() {
    if [ ! -f "$CORRELATION_DB" ]; then
        sqlite3 "$CORRELATION_DB" << EOF
CREATE TABLE entities (
    id INTEGER PRIMARY KEY,
    type TEXT NOT NULL,
    value TEXT NOT NULL,
    source TEXT NOT NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(type, value, source)
);

CREATE TABLE relationships (
    id INTEGER PRIMARY KEY,
    source_id INTEGER,
    target_id INTEGER,
    relationship_type TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (source_id) REFERENCES entities (id),
    FOREIGN KEY (target_id) REFERENCES entities (id)
);

CREATE TABLE data (
    id INTEGER PRIMARY KEY,
    entity_id INTEGER,
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (entity_id) REFERENCES entities (id)
);
EOF
    fi
}

correlate_data() {
    local entity_type="$1"
    local entity_value="$2"
    local source="$3"
    local data="$4"
    
    # Insert entity
    local entity_id=$(sqlite3 "$CORRELATION_DB" \
        "INSERT OR IGNORE INTO entities (type, value, source) VALUES ('$entity_type', '$entity_value', '$source'); \
        SELECT id FROM entities WHERE type='$entity_type' AND value='$entity_value';")
    
    # Insert data
    while IFS= read -r line; do
        if [[ $line == *":"* ]]; then
            local key=$(echo "$line" | cut -d: -f1 | xargs)
            local value=$(echo "$line" | cut -d: -f2- | xargs)
            sqlite3 "$CORRELATION_DB" \
                "INSERT INTO data (entity_id, key, value) VALUES ($entity_id, '$key', '$value');"
        fi
    done <<< "$data"
}

# =============== Reporting Functions ==================
generate_report() {
    log "${BLUE}[*] Generating comprehensive report...${NC}"
    
    # Export correlation data to JSON
    sqlite3 -json "$CORRELATION_DB" \
        "SELECT * FROM entities;" > entities.json
    sqlite3 -json "$CORRELATION_DB" \
        "SELECT * FROM relationships;" > relationships.json
    sqlite3 -json "$CORRELATION_DB" \
        "SELECT * FROM data;" > data.json
    
    # Create HTML report
    cat > "$REPORT_HTML" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DOM OSINT Report</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/vis/4.21.0/vis.min.js"></script>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/vis/4.21.0/vis.min.css" />
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .entity { border: 1px solid #ddd; padding: 15px; margin: 10px 0; border-radius: 5px; }
        .relationship { color: #888; font-style: italic; }
        .chart-container { width: 50%; height: 300px; float: left; }
    </style>
</head>
<body>
    <h1>DOM OSINT Report</h1>
    <p>Generated on $(date)</p>
    
    <h2>Data Overview</h2>
    <div id="visualization"></div>
    
    <h2>Entities Found</h2>
    <div id="entities">
EOF

    # Add entities to report
    while IFS="|" read -r id type value source timestamp; do
        echo "<div class='entity'><h3>$type: $value</h3><p>Source: $source | Found: $timestamp</p>" >> "$REPORT_HTML"
        
        # Add associated data
        local data=$(sqlite3 "$CORRELATION_DB" \
            "SELECT key, value FROM data WHERE entity_id=$id;")
        if [ -n "$data" ]; then
            echo "<ul>" >> "$REPORT_HTML"
            echo "$data" | while read -r line; do
                IFS="|" read -r key value <<< "$line"
                echo "<li><strong>$key:</strong> $value</li>" >> "$REPORT_HTML"
            done
            echo "</ul>" >> "$REPORT_HTML"
        fi
        echo "</div>" >> "$REPORT_HTML"
    done < <(sqlite3 -separator "|" "$CORRELATION_DB" "SELECT * FROM entities;")
    
    cat >> "$REPORT_HTML" << EOF
    </div>
    
    <script>
        // Load visualization data
        var entities = $([ -f entities.json ] && cat entities.json || echo "[]");
        var relationships = $([ -f relationships.json ] && cat relationships.json || echo "[]");
        
        // Create nodes and edges for visualization
        var nodes = new vis.DataSet(entities.map(function(e) {
            return { id: e.id, label: e.value, group: e.type };
        }));
        
        var edges = new vis.DataSet(relationships.map(function(r) {
            return { from: r.source_id, to: r.target_id, label: r.relationship_type };
        }));
        
        var container = document.getElementById('visualization');
        var data = { nodes: nodes, edges: edges };
        var options = {};
        var network = new vis.Network(container, data, options);
    </script>
</body>
</html>
EOF

    log "${GREEN}[✓] Report generated: $REPORT_HTML${NC}"
}

# =============== Module System ==================
load_modules() {
    local module_type="$1"
    for module in "$MODULES_DIR/$module_type"/*.sh; do
        if [ -f "$module" ]; then
            source "$module"
        fi
    done
}

# =============== Main Execution ==================
main() {
    banner
    check_dependencies
    setup_api_keys
    setup_stealth
    init_correlation_db
    
    # Load all module types
    for module_type in reconnaissance scanning analysis; do
        if [ -d "$MODULES_DIR/$module_type" ]; then
            load_modules "$module_type"
        fi
    done
    
    # Display main menu
    while true; do
        echo -e "\n${BLUE}===== 🔍 DOM OSINT Main Menu =====${NC}"
        echo "1) Reconnaissance Modules"
        echo "2) Scanning Modules"
        echo "3) Analysis & Correlation"
        echo "4) Generate Report"
        echo "5) Configuration"
        echo "6) Exit"
        read -p "Select option: " opt
        
        case $opt in
            1) reconnaissance_menu ;;
            2) scanning_menu ;;
            3) analysis_menu ;;
            4) generate_report ;;
            5) configuration_menu ;;
            6) 
                echo -e "${GREEN}[+] Report saved to: $REPORT_HTML${NC}"
                echo -e "${GREEN}[+] Data saved to: $CORRELATION_DB${NC}"
                exit 0 
                ;;
            *) echo -e "${RED}[!] Invalid option${NC}" ;;
        esac
    done
}

# =============== Menu Functions ==================
reconnaissance_menu() {
    echo -e "\n${BLUE}===== 🔍 Reconnaissance Modules =====${NC}"
    echo "1) Domain Investigation"
    echo "2) Email Analysis"
    echo "3) Username Recon"
    echo "4) IP Investigation"
    echo "5) Phone OSINT"
    echo "6) Back to Main Menu"
    read -p "Select option: " opt
    
    case $opt in
        1) domain_investigation ;;
        2) email_analysis ;;
        3) username_recon ;;
        4) ip_investigation ;;
        5) phone_osint ;;
        6) return ;;
        *) echo -e "${RED}[!] Invalid option${NC}" ;;
    esac
}

# =============== Module Implementations ==================
domain_investigation() {
    read -p "Enter domain: " domain
    log "${BLUE}[*] Investigating domain: $domain${NC}"
    
    # WHOIS lookup
    whois_data=$(run_module "WHOIS" "whois $domain")
    correlate_data "domain" "$domain" "whois" "$whois_data"
    
    # DNS enumeration
    dns_data=$(run_module "DNS" "dig $domain ANY +nocmd")
    correlate_data "domain" "$domain" "dns" "$dns_data"
    
    # Subdomain discovery (using built-in tools and APIs if available)
    if [ -n "$SECURITYTRAILS_API_KEY" ]; then
        subdomains=$(run_module "SecurityTrails" \
            "curl -s -H 'APIKEY: $SECURITYTRAILS_API_KEY' 'https://api.securitytrails.com/v1/domain/$domain/subdomains' | jq -r '.subdomains[]' | sed 's/\$/.$domain/'")
        correlate_data "subdomain" "$subdomains" "securitytrails" "subdomains"
    fi
    
    # Check for TLS certificates
    tls_data=$(run_module "crt.sh" \
        "curl -s 'https://crt.sh/?q=%25.$domain&output=json' | jq -r '.[].name_value' | sort -u")
    correlate_data "domain" "$domain" "tls_certs" "$tls_data"
}

email_analysis() {
    read -p "Enter email address: " email
    log "${BLUE}[*] Analyzing email: $email${NC}"
    
    # Check breach data
    if [ -n "$HIBP_API_KEY" ]; then
        breach_data=$(run_module "HIBP" \
            "curl -s -H 'hibp-api-key: $HIBP_API_KEY' -H 'user-agent: DOM-OSINT' 'https://haveibeenpwned.com/api/v3/breachedaccount/$email' | jq .")
        correlate_data "email" "$email" "hibp" "$breach_data"
    fi
    
    # Hunter.io email verification
    if [ -n "$HUNTER_API_KEY" ]; then
        hunter_data=$(run_module "Hunter.io" \
            "curl -s 'https://api.hunter.io/v2/email-verifier?email=$email&api_key=$HUNTER_API_KEY' | jq .")
        correlate_data "email" "$email" "hunter" "$hunter_data"
    fi
    
    # Dehashed search (if available)
    if [ -n "$DEHASHED_API_KEY" ] && [ -n "$DEHASHED_EMAIL" ]; then
        dehashed_data=$(run_module "Dehashed" \
            "curl -s -u '$DEHASHED_EMAIL:$DEHASHED_API_KEY' 'https://api.dehashed.com/search?query=email:$email' | jq .")
        correlate_data "email" "$email" "dehashed" "$dehashed_data"
    fi
}

# Additional module implementations would follow similar patterns...

# =============== Initialization ==================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi