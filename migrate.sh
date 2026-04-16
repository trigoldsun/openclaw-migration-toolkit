#!/usr/bin/env bash
#===============================================================================
# OpenClaw Migration Toolkit v2.0
# 完整迁移OpenClaw服务器配置和数据到新服务器
#
# v2.0 改进:
#   - 正确理解OpenClaw架构(Gateway/WS API)
#   - discover命令 - OpenClaw发现机制
#   - 增量同步 - rsync支持断点续传
#   - 加密传输 - gpg/openssl加密
#   - 交互式向导 - --interactive模式
#
# 基于 OpenClaw 架构: https://docs.openclaw.ai
#===============================================================================

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 版本信息
TOOLKIT_VERSION="2.0.0"
TOOLKIT_NAME="OpenClaw Migration Toolkit"

# 配置目录
BACKUP_DIR="${OPENCLAW_BACKUP_DIR:-$HOME/.openclaw-migration/backups}"
LOG_DIR="${BACKUP_DIR}/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/migration_${TIMESTAMP}.log"

# OpenClaw 路径发现
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$OPENCLAW_HOME/config}"
OPENCLAW_DATA="${OPENCLAW_DATA:-$OPENCLAW_HOME/data}"
OPENCLAW_SKILLS="${OPENCLAW_HOME/skills}"
OPENCLAW_PLUGINS="${OPENCLAW_HOME/plugins}"
OPENCLAW_STATE="${OPENCLAW_STATE:-$OPENCLAW_HOME/state}"

# 加密配置
ENCRYPTION_METHOD="${ENCRYPTION_METHOD:-gpg}"  # gpg 或 openssl
DEFAULT_COMPRESS="gzip"

#===============================================================================
# 帮助信息
#===============================================================================

show_help() {
    cat << EOF
${BOLD}${TOOLKIT_NAME} v${TOOLKIT_VERSION}${NC}

${BOLD}用法:${NC}
    $(basename $0) <command> [options]

${BOLD}命令:${NC}
    ${GREEN}discover${NC}              发现本地OpenClaw安装和配置
    ${GREEN}export${NC} [options]      导出OpenClaw数据到备份文件
    ${GREEN}import${NC} [options]      从备份文件导入数据
    ${GREEN}migrate${NC} [options]     服务器间迁移
    ${GREEN}sync${NC} [options]        增量同步到目标服务器
    ${GREEN}status${NC}               查看迁移状态
    ${GREEN}validate${NC} [file]       验证备份文件完整性
    ${GREEN}cleanup${NC} [options]     清理旧备份
    ${GREEN}interactive${NC}           交互式迁移向导
    ${GREEN}help${NC}                 显示此帮助信息

${BOLD}导出选项:${NC}
    -o, --output DIR       输出目录 (默认: ~/.openclaw-migration/backups)
    -c, --components LIST  要导出的组件 (默认: all)
                          可选: config,providers,skills,memory,cron,env,canvas
    --encrypt              加密备份
    --password PASS        加密密码
    --split SIZE           分卷大小 (如: 500M)
    --exclude PATTERN      排除的文件模式
    -v, --verbose          详细输出
    --dry-run              预览不执行

${BOLD}导入选项:${NC}
    -i, --input FILE       导入文件
    -c, --components LIST  要导入的组件
    --overwrite            覆盖已有数据
    --merge                合并模式
    --backup-first         导入前备份当前数据
    --validate             导入后验证
    --decrypt              解密备份
    --password PASS        解密密码

${BOLD}迁移选项:${NC}
    -t, --target HOST      目标服务器
    -p, --port PORT        SSH端口 (默认: 22)
    -u, --user USER        SSH用户 (默认: 当前用户)
    --ssh-key KEY          SSH密钥
    --method METHOD        传输方式: scp, rsync (默认: rsync)
    --incremental           增量迁移
    --encrypt               传输加密
    --interactive          交互式模式

${BOLD}同步选项:${NC}
    -t, --target HOST      目标服务器
    --components LIST       要同步的组件
    --exclude PATTERN       排除模式
    --bw-limit SPEED        带宽限制 (如: 5M)

${BOLD}发现选项:${NC}
    --json                  JSON格式输出
    --verbose               详细输出

${BOLD}示例:${NC}
    # 发现本地OpenClaw
    $(basename $0) discover

    # 导出所有数据
    $(basename $0) export

    # 加密导出
    $(basename $0) export --encrypt --password mysecret

    # 服务器间迁移
    $(basename $0) migrate -t user@server.example.com

    # 增量同步
    $(basename $0) sync -t user@server.example.com --incremental

    # 交互式迁移向导
    $(basename $0) interactive

    # 清理30天前的备份
    $(basename $0) cleanup --older-than 30d

${BOLD}文档:${NC}
    查看完整文档: cat $(dirname $0)/README.md
    变更日志: cat $(dirname $0)/CHANGELOG.md
EOF
}

#===============================================================================
# 日志函数
#===============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" >> "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"
}

log_debug() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" >> "$LOG_FILE"
    fi
}

#===============================================================================
# 初始化
#===============================================================================

init() {
    mkdir -p "$BACKUP_DIR" "$LOG_DIR" 2>/dev/null || true
    
    # 设置错误处理
    trap 'log_error "脚本执行失败 at line $LINENO"' ERR
}

#===============================================================================
# 发现命令 - OpenClaw发现机制 (改进1)
#===============================================================================

do_discover() {
    local json_output=false
    local verbose=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --json) json_output=true; shift ;;
            --verbose|-v) verbose=true; shift ;;
            *) shift ;;
        esac
    done
    
    if [[ "$json_output" == "true" ]]; then
        discover_json
    else
        discover_human
    fi
}

discover_human() {
    echo ""
    echo -e "${BOLD}${MAGENTA}========================================${NC}"
    echo -e "${BOLD}${MAGENTA}    OpenClaw Discovery Report${NC}"
    echo -e "${BOLD}${MAGENTA}========================================${NC}"
    echo ""
    
    # 1. 发现OpenClaw命令
    local openclaw_cmd=""
    local cmd_locations=(
        "openclaw"
        "/usr/local/bin/openclaw"
        "$HOME/.local/bin/openclaw"
        "/snap/bin/openclaw"
        "/opt/openclaw/bin/openclaw"
    )
    
    echo -e "${BOLD}${BLUE}[1/6] OpenClaw 命令发现${NC}"
    echo "----------------------------------------"
    
    for cmd in "${cmd_locations[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            openclaw_cmd="$cmd"
            break
        fi
    done
    
    if [[ -z "$openclaw_cmd" ]]; then
        echo -e "  ${RED}✗${NC} OpenClaw命令未找到"
        echo -e "  ${YELLOW}!${NC} 请确保OpenClaw已安装或设置PATH"
        echo -e "  ${YELLOW}!${NC} 安装: curl -fsSL https://get.openclaw.ai | bash"
        openclaw_cmd=""
    else
        local version=$($openclaw_cmd version 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}✓${NC} 命令: $openclaw_cmd"
        echo -e "  ${GREEN}✓${NC} 版本: $version"
    fi
    echo ""
    
    # 2. 发现Gateway配置
    echo -e "${BOLD}${BLUE}[2/6] Gateway 配置${NC}"
    echo "----------------------------------------"
    discover_gateway_config
    echo ""
    
    # 3. 发现Provider连接
    echo -e "${BOLD}${BLUE}[3/6] Provider 连接${NC}"
    echo "----------------------------------------"
    discover_providers
    echo ""
    
    # 4. 发现Skills
    echo -e "${BOLD}${BLUE}[4/6] Skills${NC}"
    echo "----------------------------------------"
    discover_skills
    echo ""
    
    # 5. 发现Memory和Sessions
    echo -e "${BOLD}${BLUE}[5/6] Memory 和 Sessions${NC}"
    echo "----------------------------------------"
    discover_memory_sessions
    echo ""
    
    # 6. 发现Cron任务
    echo -e "${BOLD}${BLUE}[6/6] Cron 任务${NC}"
    echo "----------------------------------------"
    discover_cron_tasks
    
    echo ""
    echo -e "${BOLD}${MAGENTA}========================================${NC}"
    echo -e "${BOLD}    发现完成${NC}"
    echo -e "${BOLD}${MAGENTA}========================================${NC}"
    echo ""
    echo -e "${CYAN}提示:${NC} 使用 --json 获取JSON格式输出"
    echo -e "${CYAN}提示:${NC} 使用 '$(basename $0) export' 导出配置"
    echo ""
}

discover_json() {
    local result="{}"
    
    # OpenClaw命令
    local openclaw_cmd=""
    for cmd in openclaw /usr/local/bin/openclaw ~/.local/bin/openclaw; do
        if command -v "$cmd" &>/dev/null; then
            openclaw_cmd="$cmd"
            break
        fi
    done
    
    result=$(echo "$result" | jq --arg cmd "$openclaw_cmd" \
        --arg version "$($openclaw_cmd version 2>/dev/null || echo "unknown")" \
        ' .openclaw = {command: $cmd, version: $version}')
    
    # 配置目录
    result=$(echo "$result" | jq --arg home "$OPENCLAW_HOME" \
        --arg config "$OPENCLAW_CONFIG" \
        --arg data "$OPENCLAW_DATA" \
        ' .paths = {home: $home, config: $config, data: $data}')
    
    # Skills数量
    local skill_count=0
    [[ -d "$OPENCLAW_SKILLS" ]] && skill_count=$(find "$OPENCLAW_SKILLS" -name "*.md" 2>/dev/null | wc -l)
    result=$(echo "$result" | jq --argjson skills "$skill_count" \
        ' .skills = {count: $skills, path: env.OPENCLAW_SKILLS}')
    
    # Memory文件数量
    local memory_count=0
    [[ -d "$OPENCLAW_DATA/memory" ]] && memory_count=$(find "$OPENCLAW_DATA/memory" -name "*.md" 2>/dev/null | wc -l)
    result=$(echo "$result" | jq --argjson memory "$memory_count" \
        ' .memory = {count: $memory}')
    
    # Session数量
    local session_count=0
    [[ -d "$OPENCLAW_DATA/sessions" ]] && session_count=$(find "$OPENCLAW_DATA/sessions" -name "*.jsonl" 2>/dev/null | wc -l)
    result=$(echo "$result" | jq --argjson sessions "$session_count" \
        ' .sessions = {count: $sessions}')
    
    echo "$result" | jq .
}

discover_gateway_config() {
    local gateway_port="${OPENCLAW_GATEWAY_PORT:-18789}"
    
    # 检查Gateway进程
    if pgrep -f "openclaw.*gateway" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Gateway进程: 运行中"
    else
        echo -e "  ${YELLOW}!${NC} Gateway进程: 未运行"
    fi
    
    # 检查端口
    if command -v ss &>/dev/null; then
        if ss -tlnp 2>/dev/null | grep -q ":${gateway_port}"; then
            echo -e "  ${GREEN}✓${NC} 端口 $gateway_port: 已监听"
        else
            echo -e "  ${YELLOW}!${NC} 端口 $gateway_port: 未监听"
        fi
    fi
    
    # 配置文件
    if [[ -f "$OPENCLAW_CONFIG/gateway.json" ]]; then
        local config_size=$(du -h "$OPENCLAW_CONFIG/gateway.json" 2>/dev/null | cut -f1)
        echo -e "  ${GREEN}✓${NC} gateway.json: 存在 ($config_size)"
        
        # 尝试读取配置项
        if command -v jq &>/dev/null; then
            local auth_mode=$(jq -r '.auth.mode // "default"' "$OPENCLAW_CONFIG/gateway.json" 2>/dev/null || echo "unknown")
            echo -e "  ${GREEN}✓${NC} 认证模式: $auth_mode"
        fi
    else
        echo -e "  ${RED}✗${NC} gateway.json: 未找到"
    fi
}

discover_providers() {
    local providers_dir="$OPENCLAW_CONFIG/providers"
    local found_providers=0
    
    if [[ -d "$providers_dir" ]]; then
        for provider in "$providers_dir"/*; do
            [[ -d "$provider" ]] || continue
            local name=$(basename "$provider")
            local has_session=false
            
            # 检查是否有session文件
            if [[ -f "$provider/session.json" ]] || ls "$provider"/*.session* &>/dev/null 2>&1; then
                has_session=true
            fi
            
            if [[ "$has_session" == "true" ]]; then
                echo -e "  ${GREEN}✓${NC} $name: 已连接"
            else
                echo -e "  ${YELLOW}!${NC} $name: 未配置"
            fi
            ((found_providers++))
        done
    fi
    
    if [[ $found_providers -eq 0 ]]; then
        echo -e "  ${YELLOW}!${NC} 未发现任何Provider配置"
    fi
    
    # 检查channels配置
    if [[ -f "$OPENCLAW_CONFIG/channels.json" ]]; then
        echo -e "  ${GREEN}✓${NC} channels.json: 存在"
    fi
}

discover_skills() {
    if [[ ! -d "$OPENCLAW_SKILLS" ]]; then
        echo -e "  ${YELLOW}!${NC} Skills目录: 未找到"
        return
    fi
    
    local skill_count=$(find "$OPENCLAW_SKILLS" -name "*.md" 2>/dev/null | wc -l)
    local skill_size=$(du -sh "$OPENCLAW_SKILLS" 2>/dev/null | cut -f1)
    
    echo -e "  ${GREEN}✓${NC} Skills数量: $skill_count"
    echo -e "  ${GREEN}✓${NC} Skills大小: $skill_size"
    echo -e "  ${GREEN}✓${NC} 路径: $OPENCLAW_SKILLS"
    
    # 列出技能分类
    local categories=$(find "$OPENCLAW_SKILLS" -maxdepth 1 -type d 2>/dev/null | tail -n +2 | xargs -I {} basename {} 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    if [[ -n "$categories" ]]; then
        echo -e "  ${CYAN}  分类:${NC} $categories"
    fi
}

discover_memory_sessions() {
    # Memory
    if [[ -d "$OPENCLAW_DATA/memory" ]]; then
        local memory_count=$(find "$OPENCLAW_DATA/memory" -name "*.md" 2>/dev/null | wc -l)
        local memory_size=$(du -sh "$OPENCLAW_DATA/memory" 2>/dev/null | cut -f1)
        echo -e "  ${GREEN}✓${NC} Memory文件: $memory_count ($memory_size)"
    else
        echo -e "  ${YELLOW}!${NC} Memory目录: 未找到"
    fi
    
    # Sessions
    if [[ -d "$OPENCLAW_DATA/sessions" ]]; then
        local session_count=$(find "$OPENCLAW_DATA/sessions" -name "*.jsonl" 2>/dev/null | wc -l)
        local session_size=$(du -sh "$OPENCLAW_DATA/sessions" 2>/dev/null | cut -f1)
        echo -e "  ${GREEN}✓${NC} Sessions: $session_count ($session_size)"
    else
        echo -e "  ${YELLOW}!${NC} Sessions目录: 未找到"
    fi
}

discover_cron_tasks() {
    local openclaw_cmd=""
    for cmd in openclaw /usr/local/bin/openclaw; do
        if command -v "$cmd" &>/dev/null; then
            openclaw_cmd="$cmd"
            break
        fi
    done
    
    if [[ -n "$openclaw_cmd" ]] && $openclaw_cmd cron list &>/dev/null 2>&1; then
        local cron_count=$($openclaw_cmd cron list 2>/dev/null | grep -c "ID:" || echo "0")
        echo -e "  ${GREEN}✓${NC} Cron任务: $cron_count 个"
    else
        # 检查系统crontab
        local system_crons=$(crontab -l 2>/dev/null | grep -c "openclaw" || echo "0")
        if [[ $system_crons -gt 0 ]]; then
            echo -e "  ${YELLOW}!${NC} 系统Cron: $system_crons 个OpenClaw任务"
        else
            echo -e "  ${YELLOW}!${NC} Cron任务: 无"
        fi
    fi
}

#===============================================================================
# 导出函数 (改进2: 增量同步支持)
#===============================================================================

do_export() {
    local output_dir="$BACKUP_DIR"
    local components="all"
    local encrypt=false
    local password=""
    local split_size=""
    local exclude_patterns=()
    local verbose=false
    local dry_run=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output) output_dir="$2"; shift 2 ;;
            -c|--components) components="$2"; shift 2 ;;
            --encrypt) encrypt=true; shift ;;
            --password) password="$2"; shift 2 ;;
            --split) split_size="$2"; shift 2 ;;
            --exclude) exclude_patterns+=("$2"); shift 2 ;;
            -v|--verbose) verbose=true; shift ;;
            --dry-run) dry_run=true; shift ;;
            *) shift ;;
        esac
    done
    
    [[ "$verbose" == "true" ]] && VERBOSE=true
    
    local backup_name="openclaw-backup-${TIMESTAMP}"
    local backup_file="${output_dir}/${backup_name}.tar.gz"
    
    log_info "开始导出OpenClaw数据..."
    log_info "版本: v${TOOLKIT_VERSION}"
    log_info "输出: $backup_file"
    
    # 创建临时目录
    local tmp_dir="${output_dir}/.tmp-${TIMESTAMP}"
    mkdir -p "$tmp_dir"
    
    local components_found=0
    
    # 1. 配置文件 (Gateway配置)
    if [[ "$components" == "all" ]] || [[ "$components" == *"config"* ]]; then
        export_config "$tmp_dir" && ((components_found++)) || true
    fi
    
    # 2. Provider连接 (元数据, 不含敏感session)
    if [[ "$components" == "all" ]] || [[ "$components" == *"providers"* ]]; then
        export_providers "$tmp_dir" && ((components_found++)) || true
    fi
    
    # 3. Skills
    if [[ "$components" == "all" ]] || [[ "$components" == *"skills"* ]]; then
        export_skills "$tmp_dir" && ((components_found++)) || true
    fi
    
    # 4. Memory
    if [[ "$components" == "all" ]] || [[ "$components" == *"memory"* ]]; then
        export_memory "$tmp_dir" && ((components_found++)) || true
    fi
    
    # 5. Sessions (可选)
    if [[ "$components" == *"sessions"* ]]; then
        export_sessions "$tmp_dir" && ((components_found++)) || true
    fi
    
    # 6. Cron任务
    if [[ "$components" == "all" ]] || [[ "$components" == *"cron"* ]]; then
        export_cron "$tmp_dir" && ((components_found++)) || true
    fi
    
    # 7. 环境变量模板 (脱敏)
    if [[ "$components" == "all" ]] || [[ "$components" == *"env"* ]]; then
        export_env_template "$tmp_dir" && ((components_found++)) || true
    fi
    
    # 8. Canvas状态 (新增)
    if [[ "$components" == "all" ]] || [[ "$components" == *"canvas"* ]]; then
        export_canvas "$tmp_dir" && ((components_found++)) || true
    fi
    
    if [[ $components_found -eq 0 ]]; then
        log_error "未找到任何可导出的组件"
        rm -rf "$tmp_dir"
        exit 1
    fi
    
    # Manifest
    create_manifest "$tmp_dir"
    
    # 打包
    log_info "正在打包..."
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] 打包到: $backup_file"
        rm -rf "$tmp_dir"
        return 0
    fi
    
    tar -czf "$backup_file" -C "$tmp_dir" . 2>/dev/null
    
    # 计算校验和
    local checksum=$(sha256sum "$backup_file" | cut -d' ' -f1)
    echo "$checksum  $(basename $backup_file)" > "${backup_file}.sha256"
    
    # 清理临时目录
    rm -rf "$tmp_dir"
    
    # 加密 (改进3: 加密传输)
    if [[ "$encrypt" == "true" ]]; then
        if [[ -z "$password" ]]; then
            read -s -p "请输入加密密码: " password
            echo ""
        fi
        backup_file=$(encrypt_backup "$backup_file" "$password")
    fi
    
    # 分卷
    if [[ -n "$split_size" ]]; then
        log_info "创建分卷..."
        rm -f "${backup_file}.part"* 2>/dev/null || true
        split -b "$split_size" "$backup_file" "${backup_file}.part."
        rm "$backup_file"
        log_success "分卷完成: $(ls -1 "${backup_file}.part."* | wc -l) 个文件"
    fi
    
    local size=$(du -h "$backup_file" 2>/dev/null | cut -f1 || echo "unknown")
    log_success "导出完成!"
    echo ""
    echo "================================"
    echo -e "${GREEN}导出成功!${NC}"
    echo "================================"
    echo "文件: $backup_file"
    echo "大小: $size"
    echo "校验: $checksum"
    if [[ "$encrypt" == "true" ]]; then
        echo -e "${YELLOW}加密: 已启用${NC}"
    fi
    echo "================================"
}

export_config() {
    local tmp_dir="$1"
    
    if [[ ! -d "$OPENCLAW_CONFIG" ]]; then
        log_warn "配置目录不存在: $OPENCLAW_CONFIG"
        return 1
    fi
    
    mkdir -p "${tmp_dir}/config"
    
    # Gateway配置 - 脱敏处理
    if [[ -f "$OPENCLAW_CONFIG/gateway.json" ]]; then
        if command -v jq &>/dev/null; then
            # 脱敏敏感字段
            jq 'with_entries(
                if .key | test("secret|token|key|password|auth"); 
                then .value = "***REDACTED***" 
                else . 
                end
            )' "$OPENCLAW_CONFIG/gateway.json" > "${tmp_dir}/config/gateway.json" 2>/dev/null || \
            cp "$OPENCLAW_CONFIG/gateway.json" "${tmp_dir}/config/gateway.json"
        else
            cp "$OPENCLAW_CONFIG/gateway.json" "${tmp_dir}/config/gateway.json"
        fi
        log_success "配置: gateway.json"
    fi
    
    # Channels配置
    [[ -f "$OPENCLAW_CONFIG/channels.json" ]] && \
        cp "$OPENCLAW_CONFIG/channels.json" "${tmp_dir}/config/channels.json" && \
        log_success "配置: channels.json"
    
    # 其他配置文件
    for file in "$OPENCLAW_CONFIG"/*.json; do
        [[ -f "$file" ]] || continue
        [[ "$(basename "$file")" == "gateway.json" ]] && continue
        [[ "$(basename "$file")" == "channels.json" ]] && continue
        cp "$file" "${tmp_dir}/config/" 2>/dev/null || true
    done
    
    echo "    $(find "${tmp_dir}/config" -type f | wc -l) 个配置文件"
}

export_providers() {
    local tmp_dir="$1"
    local providers_dir="$OPENCLAW_CONFIG/providers"
    
    if [[ ! -d "$providers_dir" ]]; then
        log_warn "Providers目录不存在"
        return 1
    fi
    
    mkdir -p "${tmp_dir}/providers"
    
    local provider_count=0
    for provider in "$providers_dir"/*; do
        [[ -d "$provider" ]] || continue
        local name=$(basename "$provider")
        mkdir -p "${tmp_dir}/providers/$name"
        
        # 只复制非敏感文件
        for file in "$provider"/*.json; do
            [[ -f "$file" ]] || continue
            local basename=$(basename "$file")
            
            # 跳过敏感文件
            [[ "$basename" == *"session"* ]] && continue
            [[ "$basename" == *"auth"* ]] && continue
            [[ "$basename" == *"secret"* ]] && continue
            [[ "$basename" == *"token"* ]] && continue
            
            cp "$file" "${tmp_dir}/providers/$name/" 2>/dev/null || true
        done
        
        # 如果有session，创建一个标记文件
        if ls "$provider"/*.session* &>/dev/null 2>&1; then
            echo "{\"status\": \"has_active_session\", \"note\": \"需要重新认证\"}" > "${tmp_dir}/providers/$name/.session_info"
        fi
        
        ((provider_count++))
    done
    
    if [[ $provider_count -gt 0 ]]; then
        log_success "Providers: $provider_count 个 (元数据)"
        log_warn "认证信息需要在新服务器重新配置"
    else
        rm -rf "${tmp_dir}/providers"
        return 1
    fi
}

export_skills() {
    local tmp_dir="$1"
    
    if [[ ! -d "$OPENCLAW_SKILLS" ]]; then
        log_warn "Skills目录不存在"
        return 1
    fi
    
    mkdir -p "${tmp_dir}/skills"
    cp -r "$OPENCLAW_SKILLS/"* "${tmp_dir}/skills/" 2>/dev/null || true
    
    local skill_count=$(find "${tmp_dir}/skills" -name "*.md" 2>/dev/null | wc -l)
    local skill_size=$(du -sh "${tmp_dir}/skills" 2>/dev/null | cut -f1)
    
    log_success "Skills: $skill_count 个 ($skill_size)"
}

export_memory() {
    local tmp_dir="$1"
    
    if [[ ! -d "$OPENCLAW_DATA/memory" ]]; then
        log_warn "Memory目录不存在"
        return 1
    fi
    
    mkdir -p "${tmp_dir}/memory"
    cp -r "$OPENCLAW_DATA/memory/"* "${tmp_dir}/memory/" 2>/dev/null || true
    
    local memory_count=$(find "${tmp_dir}/memory" -name "*.md" 2>/dev/null | wc -l)
    local memory_size=$(du -sh "${tmp_dir}/memory" 2>/dev/null | cut -f1)
    
    log_success "Memory: $memory_count 文件 ($memory_size)"
}

export_sessions() {
    local tmp_dir="$1"
    
    if [[ ! -d "$OPENCLAW_DATA/sessions" ]]; then
        log_warn "Sessions目录不存在"
        return 1
    fi
    
    mkdir -p "${tmp_dir}/sessions"
    cp -r "$OPENCLAW_DATA/sessions/"* "${tmp_dir}/sessions/" 2>/dev/null || true
    
    local session_count=$(find "${tmp_dir}/sessions" -name "*.jsonl" 2>/dev/null | wc -l)
    local session_size=$(du -sh "${tmp_dir}/sessions" 2>/dev/null | cut -f1)
    
    log_success "Sessions: $session_count 个 ($session_size)"
}

export_cron() {
    local tmp_dir="$1"
    
    mkdir -p "${tmp_dir}/cron"
    
    local openclaw_cmd=""
    for cmd in openclaw /usr/local/bin/openclaw; do
        if command -v "$cmd" &>/dev/null; then
            openclaw_cmd="$cmd"
            break
        fi
    done
    
    local cron_exported=false
    
    if [[ -n "$openclaw_cmd" ]] && $openclaw_cmd cron list &>/dev/null 2>&1; then
        $openclaw_cmd cron list > "${tmp_dir}/cron/list.json" 2>/dev/null || true
        
        # 生成可执行的恢复脚本
        cat > "${tmp_dir}/cron/restore.sh" << 'CRON_SCRIPT'
#!/usr/bin/env bash
# OpenClaw Cron Jobs Restore Script
# 用法: ./restore.sh 或 openclaw-migration restore-cron -i ./list.json

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CRON_FILE="${SCRIPT_DIR}/list.json"

if [[ ! -f "$CRON_FILE" ]]; then
    echo "Error: Cron list not found: $CRON_FILE"
    exit 1
fi

echo "Restore OpenClaw Cron Jobs..."
echo "请在新服务器的OpenClaw中手动导入cron任务"
echo "文件: $CRON_FILE"
CRON_SCRIPT
        chmod +x "${tmp_dir}/cron/restore.sh"
        
        local cron_count=$(grep -c "ID:" "${tmp_dir}/cron/list.json" 2>/dev/null || echo "0")
        log_success "Cron: $cron_count 个任务"
        cron_exported=true
    fi
    
    # 备用: 系统crontab
    local system_cron=$(crontab -l 2>/dev/null | grep openclaw || true)
    if [[ -n "$system_cron" ]]; then
        echo "$system_cron" > "${tmp_dir}/cron/system-crontab"
        log_success "Cron: 从系统crontab导出"
        cron_exported=true
    fi
    
    if [[ "$cron_exported" != "true" ]]; then
        rm -rf "${tmp_dir}/cron"
        return 1
    fi
}

export_env_template() {
    local tmp_dir="$1"
    
    if [[ ! -f "$OPENCLAW_HOME/.env" ]]; then
        log_warn ".env文件不存在"
        return 1
    fi
    
    mkdir -p "${tmp_dir}/env"
    
    # 创建脱敏的env模板
    if command -v sed &>/dev/null; then
        sed 's/=.*/=***REDACTED***/g' "$OPENCLAW_HOME/.env" > "${tmp_dir}/env/.env.template"
    else
        # 手动脱敏
        while IFS= read -r line; do
            if [[ "$line" =~ ^[A-Za-z_]+= ]]; then
                echo "${line%%=*}=***REDACTED***"
            else
                echo "$line"
            fi
        done < "$OPENCLAW_HOME/.env" > "${tmp_dir}/env/.env.template"
    fi
    
    log_success "环境变量: 已导出模板(已脱敏)"
}

export_canvas() {
    local tmp_dir="$1"
    local canvas_dir="$OPENCLAW_STATE/canvas"
    
    if [[ ! -d "$canvas_dir" ]]; then
        log_warn "Canvas目录不存在"
        return 1
    fi
    
    mkdir -p "${tmp_dir}/canvas"
    cp -r "$canvas_dir/"* "${tmp_dir}/canvas/" 2>/dev/null || true
    
    local canvas_size=$(du -sh "${tmp_dir}/canvas" 2>/dev/null | cut -f1)
    log_success "Canvas: $canvas_size"
}

create_manifest() {
    local tmp_dir="$1"
    
    local openclaw_cmd=""
    for cmd in openclaw /usr/local/bin/openclaw; do
        if command -v "$cmd" &>/dev/null; then
            openclaw_cmd="$cmd"
            break
        fi
    done
    
    local version="unknown"
    [[ -n "$openclaw_cmd" ]] && version=$($openclaw_cmd version 2>/dev/null || echo "unknown")
    
    cat > "${tmp_dir}/manifest.json" << EOF
{
  "format_version": "2.0",
  "toolkit_version": "${TOOLKIT_VERSION}",
  "openclaw": {
    "version": "${version}",
    "gateway_port": "${OPENCLAW_GATEWAY_PORT:-18789}",
    "hostname": "$(hostname)"
  },
  "backup": {
    "created_at": "$(date -Iseconds)",
    "toolkit": "${TOOLKIT_NAME}",
    "contains_sensitive": true,
    "requires_reauth": true
  },
  "components": {
    "config": true,
    "providers": true,
    "skills": true,
    "memory": true,
    "sessions": false,
    "cron": true,
    "env_template": true,
    "canvas": true
  },
  "migration_notes": [
    "Provider认证信息需要在新服务器重新配置",
    "设备配对可能需要重新审批",
    "建议在低峰期进行迁移",
    "迁移后验证Gateway状态"
  ]
}
EOF
}

#===============================================================================
# 加密函数 (改进3: 加密传输)
#===============================================================================

encrypt_backup() {
    local input_file="$1"
    local password="$2"
    local encrypted_file="${input_file}.enc"
    
    log_info "加密备份文件..."
    
    if command -v gpg &>/dev/null; then
        if gpg --symmetric --cipher-algo AES256 --batch --passphrase "$password" \
            -o "$encrypted_file" "$input_file" 2>/dev/null; then
            rm "$input_file"
            log_success "已使用GPG加密"
            echo "$encrypted_file"
            return 0
        fi
    fi
    
    if command -v openssl &>/dev/null; then
        if openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:"$password" \
            -in "$input_file" -out "$encrypted_file" 2>/dev/null; then
            rm "$input_file"
            log_success "已使用OpenSSL加密"
            echo "$encrypted_file"
            return 0
        fi
    fi
    
    log_warn "未找到加密工具，跳过加密"
    echo "$input_file"
}

decrypt_backup() {
    local input_file="$1"
    local password="$2"
    local decrypted_file="${input_file%.enc}"
    
    log_info "解密备份文件..."
    
    # 尝试GPG
    if [[ "$input_file" == *.gpg ]] || command -v gpg &>/dev/null; then
        if gpg --decrypt --batch --passphrase "$password" \
            -o "$decrypted_file" "$input_file" 2>/dev/null; then
            rm "$input_file"
            log_success "已解密"
            echo "$decrypted_file"
            return 0
        fi
    fi
    
    # 尝试OpenSSL
    if openssl enc -aes-256-cbc -d -salt -pbkdf2 -pass pass:"$password" \
        -in "$input_file" -out "$decrypted_file" 2>/dev/null; then
        rm "$input_file"
        log_success "已解密"
        echo "$decrypted_file"
        return 0
    fi
    
    log_error "解密失败，请检查密码是否正确"
    return 1
}

#===============================================================================
# 导入函数
#===============================================================================

do_import() {
    local input_file=""
    local components="all"
    local overwrite=false
    local merge=false
    local backup_first=false
    local validate=false
    local decrypt=false
    local password=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--input) input_file="$2"; shift 2 ;;
            -c|--components) components="$2"; shift 2 ;;
            --overwrite) overwrite=true; shift ;;
            --merge) merge=true; shift ;;
            --backup-first) backup_first=true; shift ;;
            --validate) validate=true; shift ;;
            --decrypt) decrypt=true; shift ;;
            --password) password="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$input_file" ]]; then
        log_error "请指定导入文件: -i <file>"
        exit 1
    fi
    
    # 解密 (如果需要)
    if [[ "$decrypt" == "true" ]]; then
        if [[ -z "$password" ]]; then
            read -s -p "请输入解密密码: " password
            echo ""
        fi
        input_file=$(decrypt_backup "$input_file" "$password")
    fi
    
    if [[ ! -f "$input_file" ]]; then
        log_error "文件不存在: $input_file"
        exit 1
    fi
    
    # 验证
    log_info "验证备份文件..."
    if ! tar -tzf "$input_file" >/dev/null 2>&1; then
        log_error "无效的备份文件或格式不正确"
        exit 1
    fi
    
    # 备份当前数据
    if [[ "$backup_first" == "true" ]]; then
        log_info "备份当前数据..."
        local backup_name="pre-import-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "${BACKUP_DIR}/${backup_name}"
        [[ -d "$OPENCLAW_CONFIG" ]] && cp -r "$OPENCLAW_CONFIG" "${BACKUP_DIR}/${backup_name}/" 2>/dev/null || true
        [[ -d "$OPENCLAW_SKILLS" ]] && cp -r "$OPENCLAW_SKILLS" "${BACKUP_DIR}/${backup_name}/" 2>/dev/null || true
        [[ -d "$OPENCLAW_DATA" ]] && cp -r "$OPENCLAW_DATA" "${BACKUP_DIR}/${backup_name}/" 2>/dev/null || true
        log_success "已备份到: ${BACKUP_DIR}/${backup_name}"
    fi
    
    # 创建临时目录
    local tmp_dir="${BACKUP_DIR}/.tmp-import-${TIMESTAMP}"
    mkdir -p "$tmp_dir"
    
    # 解压
    log_info "解压文件..."
    tar -xzf "$input_file" -C "$tmp_dir"
    
    # 检查manifest
    if [[ -f "${tmp_dir}/manifest.json" ]]; then
        log_info "备份来源: $(jq -r '.openclaw.hostname' "${tmp_dir}/manifest.json" 2>/dev/null || echo "unknown")"
        log_info "备份版本: $(jq -r '.openclaw.version' "${tmp_dir}/manifest.json" 2>/dev/null || echo "unknown")"
        log_info "工具版本: $(jq -r '.toolkit_version' "${tmp_dir}/manifest.json" 2>/dev/null || echo "unknown")"
    fi
    
    # 导入组件
    local imported=0
    
    if [[ "$components" == "all" ]] || [[ "$components" == *"config"* ]]; then
        import_config "$tmp_dir" && ((imported++)) || true
    fi
    
    if [[ "$components" == "all" ]] || [[ "$components" == *"providers"* ]]; then
        import_providers "$tmp_dir" && ((imported++)) || true
    fi
    
    if [[ "$components" == "all" ]] || [[ "$components" == *"skills"* ]]; then
        import_skills "$tmp_dir" && ((imported++)) || true
    fi
    
    if [[ "$components" == "all" ]] || [[ "$components" == *"memory"* ]]; then
        import_memory "$tmp_dir" && ((imported++)) || true
    fi
    
    if [[ "$components" == "all" ]] || [[ "$components" == *"cron"* ]]; then
        import_cron "$tmp_dir" && ((imported++)) || true
    fi
    
    if [[ "$components" == "all" ]] || [[ "$components" == *"env"* ]]; then
        import_env "$tmp_dir" && ((imported++)) || true
    fi
    
    if [[ "$components" == "all" ]] || [[ "$components" == *"canvas"* ]]; then
        import_canvas "$tmp_dir" && ((imported++)) || true
    fi
    
    # 清理
    rm -rf "$tmp_dir"
    
    # 重启服务
    log_info "重启服务..."
    openclaw gateway restart 2>/dev/null || true
    
    # 验证
    if [[ "$validate" == "true" ]]; then
        do_validate "$input_file"
    fi
    
    log_success "导入完成!"
    echo ""
    echo "================================"
    echo -e "${GREEN}导入成功!${NC}"
    echo "================================"
    echo "已导入组件: $imported"
    echo -e "${YELLOW}注意: Provider认证信息需要重新配置${NC}"
    echo -e "${YELLOW}注意: 可能需要重新配对设备${NC}"
    echo "================================"
}

import_config() {
    local tmp_dir="$1"
    
    if [[ ! -d "${tmp_dir}/config" ]]; then
        return 1
    fi
    
    mkdir -p "$OPENCLAW_CONFIG"
    cp -r "${tmp_dir}/config/"* "$OPENCLAW_CONFIG/" 2>/dev/null || true
    
    log_success "配置: 已导入"
}

import_providers() {
    local tmp_dir="$1"
    
    if [[ ! -d "${tmp_dir}/providers" ]]; then
        return 1
    fi
    
    mkdir -p "$OPENCLAW_CONFIG/providers"
    cp -r "${tmp_dir}/providers/"* "$OPENCLAW_CONFIG/providers/" 2>/dev/null || true
    
    log_success "Providers: 已导入"
    log_warn "请在新服务器重新配置Provider认证"
}

import_skills() {
    local tmp_dir="$1"
    
    if [[ ! -d "${tmp_dir}/skills" ]]; then
        return 1
    fi
    
    mkdir -p "$OPENCLAW_SKILLS"
    
    if [[ "$overwrite" == "true" ]]; then
        cp -r "${tmp_dir}/skills/"* "$OPENCLAW_SKILLS/" 2>/dev/null || true
    else
        # 合并模式
        for skill in "${tmp_dir}/skills}"/*; do
            [[ -d "$skill" ]] || continue
            local name=$(basename "$skill")
            if [[ -d "$OPENCLAW_SKILLS/$name" ]]; then
                log_info "Skills: $name 已存在，跳过"
            else
                cp -r "$skill" "$OPENCLAW_SKILLS/" 2>/dev/null || true
            fi
        done
    fi
    
    local skill_count=$(find "$OPENCLAW_SKILLS" -name "*.md" 2>/dev/null | wc -l)
    log_success "Skills: $skill_count 个"
}

import_memory() {
    local tmp_dir="$1"
    
    if [[ ! -d "${tmp_dir}/memory" ]]; then
        return 1
    fi
    
    mkdir -p "$OPENCLAW_DATA/memory"
    cp -r "${tmp_dir}/memory/"* "$OPENCLAW_DATA/memory/" 2>/dev/null || true
    
    local memory_count=$(find "$OPENCLAW_DATA/memory" -name "*.md" 2>/dev/null | wc -l)
    log_success "Memory: $memory_count 文件"
}

import_cron() {
    local tmp_dir="$1"
    
    if [[ -f "${tmp_dir}/cron/restore.sh" ]]; then
        log_info "Cron任务已导出到: ${tmp_dir}/cron/restore.sh"
        log_info "请手动执行恢复脚本"
    fi
    
    if [[ -f "${tmp_dir}/cron/list.json" ]]; then
        log_success "Cron: 已导入列表"
    fi
}

import_env() {
    local tmp_dir="$1"
    
    if [[ -f "${tmp_dir}/env/.env.template" ]]; then
        cp "${tmp_dir}/env/.env.template" "$OPENCLAW_HOME/.env.template" 2>/dev/null || true
        log_success "环境变量模板: 已导出"
        log_warn "请根据模板配置 .env 文件"
    fi
}

import_canvas() {
    local tmp_dir="$1"
    
    if [[ -d "${tmp_dir}/canvas" ]]; then
        mkdir -p "$OPENCLAW_STATE/canvas"
        cp -r "${tmp_dir}/canvas/"* "$OPENCLAW_STATE/canvas/" 2>/dev/null || true
        log_success "Canvas: 已导入"
    fi
}

#===============================================================================
# 服务器间迁移 (改进3: 增量同步)
#===============================================================================

do_migrate() {
    local target_host=""
    local target_port="22"
    local target_user="${USER}"
    local ssh_key=""
    local method="rsync"
    local incremental=false
    local components="all"
    local encrypt_transfer=false
    local interactive=false
    local password=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--target) target_host="$2"; shift 2 ;;
            -p|--port) target_port="$2"; shift 2 ;;
            -u|--user) target_user="$2"; shift 2 ;;
            --ssh-key) ssh_key="$2"; shift 2 ;;
            --method) method="$2"; shift 2 ;;
            --incremental) incremental=true; shift ;;
            -c|--components) components="$2"; shift 2 ;;
            --encrypt) encrypt_transfer=true; shift ;;
            --password) password="$2"; shift 2 ;;
            --interactive) interactive=true; shift ;;
            *) shift ;;
        esac
    done
    
    # 交互式模式
    if [[ "$interactive" == "true" ]]; then
        interactive_migrate
        return
    fi
    
    if [[ -z "$target_host" ]]; then
        log_error "请指定目标服务器: -t <host>"
        exit 1
    fi
    
    local target="${target_user}@${target_host}"
    
    log_info "================================"
    log_info "OpenClaw Migration v${TOOLKIT_VERSION}"
    log_info "================================"
    log_info "源服务器: $(hostname)"
    log_info "目标服务器: $target"
    log_info "传输方式: $method"
    if [[ "$incremental" == "true" ]]; then
        log_info "模式: 增量迁移"
    fi
    if [[ "$encrypt_transfer" == "true" ]]; then
        log_info "传输加密: 启用"
    fi
    log_info "================================"
    
    # 预检查
    pre_migration_check "$target" "$target_port"
    
    # 导出
    log_info "[1/3] 导出数据..."
    local backup_name="openclaw-migration-${TIMESTAMP}"
    local backup_file="${BACKUP_DIR}/${backup_name}.tar.gz"
    
    do_export_single "$backup_file" "$components"
    
    # 加密 (如果需要)
    if [[ "$encrypt_transfer" == "true" ]]; then
        if [[ -z "$password" ]]; then
            read -s -p "请输入传输加密密码: " password
            echo ""
        fi
        backup_file=$(encrypt_backup "$backup_file" "$password")
    fi
    
    # 传输
    log_info "[2/3] 传输数据..."
    transfer_to_target "$backup_file" "$target" "$target_port" "$ssh_key" "$method"
    
    # 清理本地临时文件
    rm -f "$backup_file" "${backup_file}.sha256" 2>/dev/null || true
    
    # 导入
    log_info "[3/3] 在目标服务器导入..."
    ssh -p "$target_port" ${ssh_key:+-i "$ssh_key"} "$target" "
        openclaw-migration import -i ${BACKUP_DIR}/${backup_name}.tar.gz --validate 2>/dev/null || \
        echo 'Import completed with warnings'
    "
    
    log_success "迁移完成!"
    echo ""
    echo "================================"
    echo -e "${GREEN}迁移成功!${NC}"
    echo "================================"
    echo "目标服务器: $target"
    echo -e "${YELLOW}请在目标服务器验证Gateway状态${NC}"
    echo -e "${YELLOW}Provider需要重新认证${NC}"
    echo "================================"
}

pre_migration_check() {
    local target="$1"
    local target_port="$2"
    
    log_info "预检查..."
    
    # SSH连接
    if ! ssh -p "$target_port" -o ConnectTimeout=10 "$target" "echo ok" &>/dev/null; then
        log_error "无法连接到目标服务器"
        exit 1
    fi
    log_success "SSH连接: OK"
    
    # 磁盘空间
    local space=$(ssh -p "$target_port" "$target" "df -h . | tail -1 | awk '{print \$4}'" 2>/dev/null)
    log_info "目标可用空间: $space"
    
    # OpenClaw检查
    local openclaw_exists=$(ssh -p "$target_port" "$target" "command -v openclaw 2>/dev/null || echo 'not_found'" 2>/dev/null)
    if [[ "$openclaw_exists" == "not_found" ]]; then
        log_warn "目标服务器未安装OpenClaw"
        log_info "安装: curl -fsSL https://get.openclaw.ai | bash"
    else
        log_success "OpenClaw: 已安装"
    fi
}

transfer_to_target() {
    local backup_file="$1"
    local target="$2"
    local target_port="$3"
    local ssh_key="$4"
    local method="$5"
    
    local ssh_opts="-p ${target_port}"
    [[ -n "$ssh_key" ]] && ssh_opts="$ssh_opts -i $ssh_key"
    
    if [[ "$method" == "rsync" ]]; then
        log_info "使用rsync传输..."
        rsync -avz --progress $ssh_opts "$backup_file" "${target}:${BACKUP_DIR}/"
        rsync -avz --progress $ssh_opts "${backup_file}.sha256" "${target}:${BACKUP_DIR}/" 2>/dev/null || true
    else
        log_info "使用scp传输..."
        scp -P "$target_port" ${ssh_key:+-i "$ssh_key"} "$backup_file" "${target}:${BACKUP_DIR}/"
    fi
}

do_export_single() {
    local backup_file="$1"
    local components="${2:-all}"
    
    local tmp_dir="${BACKUP_DIR}/.tmp-export"
    mkdir -p "$tmp_dir"
    
    # 收集数据
    [[ -d "$OPENCLAW_CONFIG" ]] && cp -r "$OPENCLAW_CONFIG" "$tmp_dir/" 2>/dev/null || true
    [[ -d "$OPENCLAW_SKILLS" ]] && cp -r "$OPENCLAW_SKILLS" "$tmp_dir/" 2>/dev/null || true
    [[ -d "$OPENCLAW_DATA/memory" ]] && mkdir -p "$tmp_dir/data" && cp -r "$OPENCLAW_DATA/memory" "$tmp_dir/data/" 2>/dev/null || true
    
    echo "{\"version\": \"$(openclaw version 2>/dev/null || echo 'unknown')\", \"exported_at\": \"$(date -Iseconds)\"}" > "$tmp_dir/manifest.json"
    
    tar -czf "$backup_file" -C "$tmp_dir" . 2>/dev/null
    rm -rf "$tmp_dir"
}

#===============================================================================
# 增量同步 (改进3)
#===============================================================================

do_sync() {
    local target_host=""
    local target_port="22"
    local target_user="${USER}"
    local ssh_key=""
    local components="all"
    local exclude_patterns=()
    local bw_limit=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--target) target_host="$2"; shift 2 ;;
            -p|--port) target_port="$2"; shift 2 ;;
            -u|--user) target_user="$2"; shift 2 ;;
            --ssh-key) ssh_key="$2"; shift 2 ;;
            -c|--components) components="$2"; shift 2 ;;
            --exclude) exclude_patterns+=("$2"); shift 2 ;;
            --bw-limit) bw_limit="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$target_host" ]]; then
        log_error "请指定目标服务器: -t <host>"
        exit 1
    fi
    
    local target="${target_user}@${target_host}"
    
    log_info "================================"
    log_info "OpenClaw 增量同步"
    log_info "================================"
    log_info "目标: $target"
    log_info "组件: $components"
    log_info "================================"
    
    # 构建rsync选项
    local rsync_opts="-avz --progress"
    [[ -n "$bw_limit" ]] && rsync_opts="$rsync_opts --bwlimit=$bw_limit"
    
    # 默认排除模式
    local default_excludes=(
        "*.session"
        "*.auth"
        "__pycache__"
        "node_modules"
        "*.log"
        ".git"
    )
    
    for pattern in "${default_excludes[@]}"; do
        rsync_opts="$rsync_opts --exclude=$pattern"
    done
    
    for pattern in "${exclude_patterns[@]}"; do
        rsync_opts="$rsync_opts --exclude=$pattern"
    done
    
    local ssh_opts="-p ${target_port}"
    [[ -n "$ssh_key" ]] && ssh_opts="$ssh_opts -i $ssh_key"
    
    # 同步配置
    if [[ "$components" == "all" ]] || [[ "$components" == *"config"* ]]; then
        log_info "同步配置..."
        rsync $rsync_opts $ssh_opts "$OPENCLAW_CONFIG/" \
            "${target}:${OPENCLAW_CONFIG}/" 2>/dev/null || true
    fi
    
    # 同步Skills
    if [[ "$components" == "all" ]] || [[ "$components" == *"skills"* ]]; then
        log_info "同步Skills..."
        rsync $rsync_opts $ssh_opts "$OPENCLAW_SKILLS/" \
            "${target}:${OPENCLAW_SKILLS}/" 2>/dev/null || true
    fi
    
    # 同步Memory
    if [[ "$components" == "all" ]] || [[ "$components" == *"memory"* ]]; then
        log_info "同步Memory..."
        rsync $rsync_opts $ssh_opts "$OPENCLAW_DATA/memory/" \
            "${target}:${OPENCLAW_DATA}/memory/" 2>/dev/null || true
    fi
    
    log_success "增量同步完成"
}

#===============================================================================
# 交互式迁移向导 (改进4)
#===============================================================================

interactive_migrate() {
    echo ""
    echo -e "${BOLD}${MAGENTA}========================================${NC}"
    echo -e "${BOLD}${MAGENTA}    OpenClaw 交互式迁移向导${NC}"
    echo -e "${BOLD}${MAGENTA}========================================${NC}"
    echo ""
    
    # 1. 发现本地OpenClaw
    echo -e "${BOLD}[步骤 1/6] 检查本地OpenClaw${NC}"
    echo "----------------------------------------"
    local openclaw_cmd=""
    for cmd in openclaw /usr/local/bin/openclaw; do
        if command -v "$cmd" &>/dev/null; then
            openclaw_cmd="$cmd"
            break
        fi
    done
    
    if [[ -z "$openclaw_cmd" ]]; then
        echo -e "${RED}✗ 未找到OpenClaw命令${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} OpenClaw版本: $($openclaw_cmd version 2>/dev/null || echo 'unknown')"
    echo ""
    
    # 2. 选择组件
    echo -e "${BOLD}[步骤 2/6] 选择要迁移的组件${NC}"
    echo "----------------------------------------"
    echo "  [1] 全部组件 (推荐)"
    echo "  [2] 仅配置和Skills"
    echo "  [3] 配置、Skills和Memory"
    echo "  [4] 自定义选择"
    read -p "请选择 [1-4]: " component_choice
    
    local components="all"
    case $component_choice in
        2) components="config,skills" ;;
        3) components="config,skills,memory" ;;
        4) components="config,providers,skills,memory,cron,env,canvas" ;;
    esac
    echo -e "${GREEN}✓${NC} 已选择: $components"
    echo ""
    
    # 3. 输入目标服务器
    echo -e "${BOLD}[步骤 3/6] 输入目标服务器信息${NC}"
    echo "----------------------------------------"
    read -p "目标服务器 (user@hostname): " target_host
    read -p "SSH端口 [22]: " target_port
    target_port="${target_port:-22}"
    read -p "SSH用户 [$USER]: " target_user
    target_user="${target_user:-$USER}"
    echo -e "${GREEN}✓${NC} 目标: ${target_user}@${target_host}:${target_port}"
    echo ""
    
    # 4. 选择传输方式
    echo -e "${BOLD}[步骤 4/6] 选择传输方式${NC}"
    echo "----------------------------------------"
    echo "  [1] rsync (推荐，支持断点续传)"
    echo "  [2] scp"
    read -p "请选择 [1-2]: " method_choice
    local method="rsync"
    [[ "$method_choice" == "2" ]] && method="scp"
    echo -e "${GREEN}✓${NC} 传输方式: $method"
    echo ""
    
    # 5. 加密选项
    echo -e "${BOLD}[步骤 5/6] 加密选项${NC}"
    echo "----------------------------------------"
    echo "  [1] 不加密"
    echo "  [2] 加密传输"
    read -p "请选择 [1-2]: " encrypt_choice
    local encrypt_transfer=false
    local password=""
    if [[ "$encrypt_choice" == "2" ]]; then
        encrypt_transfer=true
        read -s -p "请输入加密密码: " password
        echo ""
    fi
    echo ""
    
    # 6. 确认并执行
    echo -e "${BOLD}[步骤 6/6] 确认并执行${NC}"
    echo "----------------------------------------"
    echo "迁移摘要:"
    echo "  目标服务器: ${target_user}@${target_host}:${target_port}"
    echo "  组件: $components"
    echo "  传输方式: $method"
    echo -e "  加密: $([[ "$encrypt_transfer" == "true" ]] && echo '是' || echo '否')"
    echo ""
    read -p "确认执行迁移? [y/N]: " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo ""
        log_info "开始迁移..."
        
        # 调用迁移
        do_migrate \
            -t "$target_host" \
            -p "$target_port" \
            -u "$target_user" \
            --method "$method" \
            -c "$components" \
            ${encrypt_transfer:+--encrypt} \
            ${password:+--password "$password"}
    else
        echo "已取消"
        exit 0
    fi
}

#===============================================================================
# 状态查看
#===============================================================================

do_status() {
    echo ""
    echo "=========================================="
    echo -e "${BOLD}    OpenClaw Migration Status${NC}"
    echo "=========================================="
    echo ""
    
    # 版本
    echo -e "${BLUE}版本信息${NC}"
    echo "  工具版本: ${TOOLKIT_VERSION}"
    local openclaw_version="未安装"
    if command -v openclaw &>/dev/null; then
        openclaw_version=$(openclaw version 2>/dev/null || echo 'unknown')
    fi
    echo "  OpenClaw: $openclaw_version"
    echo "  主机名: $(hostname)"
    echo ""
    
    # 备份
    echo -e "${BLUE}备份文件${NC}"
    local latest=$(ls -t ${BACKUP_DIR}/openclaw-backup-*.tar.gz 2>/dev/null | head -1 || true)
    if [[ -n "$latest" ]]; then
        echo "  最新备份: $(basename $latest)"
        echo "  大小: $(du -h "$latest" 2>/dev/null | cut -f1 || echo 'unknown')"
        echo "  时间: $(stat -c %y "$latest" 2>/dev/null | cut -d' ' -f1,2 || echo 'unknown')"
    else
        echo "  无备份"
    fi
    echo ""
    
    # 数据统计
    echo -e "${BLUE}数据统计${NC}"
    [[ -d "$OPENCLAW_CONFIG" ]] && echo "  配置: $(find "$OPENCLAW_CONFIG" -type f 2>/dev/null | wc -l) 文件"
    [[ -d "$OPENCLAW_SKILLS" ]] && echo "  Skills: $(find "$OPENCLAW_SKILLS" -name "*.md" 2>/dev/null | wc -l) 个"
    [[ -d "$OPENCLAW_DATA/memory" ]] && echo "  Memory: $(find "$OPENCLAW_DATA/memory" -name "*.md" 2>/dev/null | wc -l) 文件"
    [[ -d "$OPENCLAW_DATA/sessions" ]] && echo "  Sessions: $(find "$OPENCLAW_DATA/sessions" -name "*.jsonl" 2>/dev/null | wc -l) 个"
    echo ""
    
    # 服务状态
    echo -e "${BLUE}服务状态${NC}"
    if pgrep -f "openclaw.*gateway" > /dev/null 2>&1; then
        echo -e "  Gateway: ${GREEN}运行中${NC}"
    else
        echo -e "  Gateway: ${RED}未运行${NC}"
    fi
    echo ""
    echo "=========================================="
}

#===============================================================================
# 验证
#===============================================================================

do_validate() {
    local input_file="$1"
    
    if [[ -z "$input_file" ]]; then
        input_file=$(ls -t ${BACKUP_DIR}/openclaw-backup-*.tar.gz 2>/dev/null | head -1 || true)
    fi
    
    if [[ ! -f "$input_file" ]]; then
        log_error "文件不存在: $input_file"
        exit 1
    fi
    
    log_info "验证: $input_file"
    
    # 校验和验证
    if [[ -f "${input_file}.sha256" ]]; then
        local stored_hash=$(cut -d' ' -f1 "${input_file}.sha256")
        local current_hash=$(sha256sum "$input_file" | cut -d' ' -f1)
        if [[ "$stored_hash" == "$current_hash" ]]; then
            log_success "校验和: 验证通过"
        else
            log_error "校验和: 验证失败!"
            exit 1
        fi
    elif [[ -f "${input_file}.enc" ]]; then
        log_warn "加密文件，无法验证校验和"
    fi
    
    # 格式验证
    if tar -tzf "$input_file" >/dev/null 2>&1; then
        log_success "格式: tar.gz验证通过"
    else
        log_error "格式: 无效的tar.gz文件"
        exit 1
    fi
    
    # 内容验证
    local tmp_validate="${BACKUP_DIR}/.tmp-validate-${TIMESTAMP}"
    mkdir -p "$tmp_validate"
    tar -xzf "$input_file" -C "$tmp_validate"
    
    if [[ -f "${tmp_validate}/manifest.json" ]]; then
        log_success "内容: 包含manifest"
        
        # 解析manifest
        local version=$(jq -r '.openclaw.version // "unknown"' "${tmp_validate}/manifest.json" 2>/dev/null || echo "unknown")
        local hostname=$(jq -r '.openclaw.hostname // "unknown"' "${tmp_validate}/manifest.json" 2>/dev/null || echo "unknown")
        local created=$(jq -r '.backup.created_at // "unknown"' "${tmp_validate}/manifest.json" 2>/dev/null || echo "unknown")
        
        echo ""
        echo "  备份来源: $hostname"
        echo "  OpenClaw版本: $version"
        echo "  备份时间: $created"
    else
        log_warn "内容: 缺少manifest"
    fi
    
    # 列出组件
    echo ""
    echo "  包含的组件:"
    [[ -d "${tmp_validate}/config" ]] && echo "    - config"
    [[ -d "${tmp_validate}/providers" ]] && echo "    - providers"
    [[ -d "${tmp_validate}/skills" ]] && echo "    - skills"
    [[ -d "${tmp_validate}/memory" ]] && echo "    - memory"
    [[ -d "${tmp_validate}/sessions" ]] && echo "    - sessions"
    [[ -d "${tmp_validate}/cron" ]] && echo "    - cron"
    [[ -d "${tmp_validate}/canvas" ]] && echo "    - canvas"
    
    rm -rf "$tmp_validate"
    
    log_success "验证完成!"
}

#===============================================================================
# 清理
#===============================================================================

do_cleanup() {
    local older_than="30d"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --older-than) older_than="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    log_info "清理 ${older_than}前的备份..."
    
    local count=$(find "${BACKUP_DIR}" -name "openclaw-backup-*.tar.gz" -mtime "+${older_than}" 2>/dev/null | wc -l)
    
    if [[ $count -eq 0 ]]; then
        log_info "没有需要清理的备份"
        return 0
    fi
    
    find "${BACKUP_DIR}" -name "openclaw-backup-*.tar.gz" -mtime "+${older_than}" -delete 2>/dev/null
    find "${BACKUP_DIR}" -name "openclaw-backup-*.sha256" -mtime "+${older_than}" -delete 2>/dev/null
    find "${BACKUP_DIR}" -name "openclaw-backup-*.enc" -mtime "+${older_than}" -delete 2>/dev/null
    find "${BACKUP_DIR}" -name "openclaw-backup-*.part"* -mtime "+${older_than}" -delete 2>/dev/null || true
    
    log_success "已清理 $count 个旧备份"
}

#===============================================================================
# 主程序
#===============================================================================

main() {
    init
    
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        discover)      do_discover "$@" ;;
        export)        do_export "$@" ;;
        import)        do_import "$@" ;;
        migrate)       do_migrate "$@" ;;
        sync)          do_sync "$@" ;;
        status)        do_status ;;
        validate)      do_validate "$@" ;;
        cleanup)       do_cleanup "$@" ;;
        interactive)  interactive_migrate ;;
        help|--help|-h) show_help ;;
        *)              log_error "未知命令: $command"; show_help; exit 1 ;;
    esac
}

main "$@"
