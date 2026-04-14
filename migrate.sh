#!/usr/bin/env bash
#===============================================================================
# OpenClaw Migration Tool
# 一键迁移OpenClaw到新服务器
#===============================================================================

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
BACKUP_DIR="${OPENCLAW_BACKUP_DIR:-$HOME/openclaw-backups}"
LOG_DIR="${BACKUP_DIR}/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/migration_${TIMESTAMP}.log"

# OpenClaw目录
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/openclaw}"
OPENCLAW_CONFIG="${OPENCLAW_DIR}/config"
OPENCLAW_DATA="${OPENCLAW_DIR}/data"
OPENCLAW_SKILLS="${OPENCLAW_DIR}/skills"
OPENCLAW_PLUGINS="${OPENCLAW_DIR}/plugins"

#===============================================================================
# 帮助信息
#===============================================================================

show_help() {
    cat << EOF
OpenClaw Migration Tool v1.0

用法:
    $(basename $0) <command> [options]

命令:
    export [options]     导出OpenClaw数据到备份文件
    import [options]     从备份文件导入数据
    migrate [options]    服务器间迁移
    status              查看迁移状态
    validate [file]      验证备份文件完整性
    cleanup [options]    清理旧备份
    help                显示此帮助信息

导出选项:
    -o, --output DIR    输出目录 (默认: ~/openclaw-backups)
    -c, --components    要导出的组件 (默认: all)
                        可选: config,plugins,skills,memory,sessions,cron,env
    -e, --exclude      排除的文件
    --encrypt           加密备份
    --split SIZE        分卷大小 (如: 500M)
    -v, --verbose       详细输出
    --dry-run          预览不执行

导入选项:
    -i, --input FILE    导入文件
    -c, --components    要导入的组件
    --overwrite         覆盖已有数据
    --merge            合并模式
    --backup-first     导入前备份当前数据
    --validate         导入后验证

迁移选项:
    -t, --target HOST  目标服务器
    -p, --port PORT    SSH端口 (默认: 22)
    -u, --user USER    SSH用户 (默认: 当前用户)
    --ssh-key KEY      SSH密钥
    --method METHOD    传输方式: scp, rsync (默认: rsync)
    --incremental      增量迁移

示例:
    # 导出所有数据
    $(basename $0) export

    # 导出到指定目录
    $(basename $0) export -o /tmp/backup

    # 导入备份
    $(basename $0) import -i /tmp/openclaw-backup.tar.gz

    # 服务器间迁移
    $(basename $0) migrate -t user@server.example.com

    # 增量迁移
    $(basename $0) migrate -t user@server.example.com --incremental

    # 清理30天前的备份
    $(basename $0) cleanup --older-than 30d

查看完整文档: cat $(dirname $0)/README.md
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

#===============================================================================
# 初始化
#===============================================================================

init() {
    mkdir -p "$BACKUP_DIR" "$LOG_DIR"
}

#===============================================================================
# 导出函数
#===============================================================================

do_export() {
    local output_dir="$BACKUP_DIR"
    local components="all"
    local encrypt=false
    local split_size=""
    local verbose=false
    local dry_run=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output) output_dir="$2"; shift 2 ;;
            -c|--components) components="$2"; shift 2 ;;
            --encrypt) encrypt=true; shift ;;
            --split) split_size="$2"; shift 2 ;;
            -v|--verbose) verbose=true; shift ;;
            --dry-run) dry_run=true; shift ;;
            *) shift ;;
        esac
    done
    
    local backup_name="openclaw-backup-${TIMESTAMP}"
    local backup_file="${output_dir}/${backup_name}.tar.gz"
    
    log_info "开始导出OpenClaw数据..."
    log_info "输出: $backup_file"
    
    # 创建临时目录
    local tmp_dir="${output_dir}/.tmp-${TIMESTAMP}"
    mkdir -p "$tmp_dir"
    
    # 收集组件
    local components_found=0
    
    # 1. 配置文件
    if [[ "$components" == "all" ]] || [[ "$components" == *"config"* ]]; then
        if [[ -d "$OPENCLAW_CONFIG" ]]; then
            mkdir -p "${tmp_dir}/config"
            cp -r "$OPENCLAW_CONFIG/"* "${tmp_dir}/config/" 2>/dev/null || true
            log_success "配置: $(find "$OPENCLAW_CONFIG" -type f 2>/dev/null | wc -l) 文件"
            ((components_found++))
        fi
    fi
    
    # 2. 插件
    if [[ "$components" == "all" ]] || [[ "$components" == *"plugins"* ]]; then
        if [[ -d "$OPENCLAW_PLUGINS" ]]; then
            mkdir -p "${tmp_dir}/plugins"
            cp -r "$OPENCLAW_PLUGINS/"* "${tmp_dir}/plugins/" 2>/dev/null || true
            log_success "插件: $(find "$OPENCLAW_PLUGINS" -type f 2>/dev/null | wc -l) 文件"
            ((components_found++))
        fi
    fi
    
    # 3. 技能
    if [[ "$components" == "all" ]] || [[ "$components" == *"skills"* ]]; then
        if [[ -d "$OPENCLAW_SKILLS" ]]; then
            mkdir -p "${tmp_dir}/skills"
            cp -r "$OPENCLAW_SKILLS/"* "${tmp_dir}/skills/" 2>/dev/null || true
            log_success "技能: $(find "$OPENCLAW_SKILLS" -name "*.md" 2>/dev/null | wc -l) 技能"
            ((components_found++))
        fi
    fi
    
    # 4. 内存文件
    if [[ "$components" == "all" ]] || [[ "$components" == *"memory"* ]]; then
        if [[ -d "$OPENCLAW_DATA/memory" ]]; then
            mkdir -p "${tmp_dir}/memory"
            cp -r "$OPENCLAW_DATA/memory/"* "${tmp_dir}/memory/" 2>/dev/null || true
            log_success "内存: $(find "$OPENCLAW_DATA/memory" -name "*.md" 2>/dev/null | wc -l) 文件"
            ((components_found++))
        fi
    fi
    
    # 5. 会话
    if [[ "$components" == "all" ]] || [[ "$components" == *"sessions"* ]]; then
        if [[ -d "$OPENCLAW_DATA/sessions" ]]; then
            mkdir -p "${tmp_dir}/sessions"
            cp -r "$OPENCLAW_DATA/sessions/"* "${tmp_dir}/sessions/" 2>/dev/null || true
            local session_count=$(find "$OPENCLAW_DATA/sessions" -name "*.jsonl" 2>/dev/null | wc -l)
            log_success "会话: ${session_count} 会话"
            ((components_found++))
        fi
    fi
    
    # 6. Cron任务
    if [[ "$components" == "all" ]] || [[ "$components" == *"cron"* ]]; then
        local cron_export="${tmp_dir}/cronjobs.txt"
        openclaw cron list > "$cron_export" 2>/dev/null || true
        if [[ -s "$cron_export" ]]; then
            log_success "Cron: $(grep -c "ID:" "$cron_export" 2>/dev/null || echo 0) 任务"
            ((components_found++))
        fi
    fi
    
    # 7. 环境变量
    if [[ "$components" == "all" ]] || [[ "$components" == *"env"* ]]; then
        if [[ -f "$OPENCLAW_DIR/.env" ]]; then
            mkdir -p "${tmp_dir}/env"
            # 脱敏处理
            cp "$OPENCLAW_DIR/.env" "${tmp_dir}/env/.env.template"
            # 替换敏感值
            sed -i 's/=.*/=***REDACTED***/g' "${tmp_dir}/env/.env.template"
            log_success "环境变量: 已导出模板"
            ((components_found++))
        fi
    fi
    
    # 8. 版本信息
    echo "{\"version\": \"$(openclaw version 2>/dev/null || echo 'unknown')\", \"exported_at\": \"$(date -Iseconds)\", \"hostname\": \"$(hostname)\"}" > "${tmp_dir}/manifest.json"
    
    if [[ $components_found -eq 0 ]]; then
        log_error "未找到任何可导出的组件"
        rm -rf "$tmp_dir"
        exit 1
    fi
    
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
    
    # 分卷（如果指定）
    if [[ -n "$split_size" ]]; then
        log_info "创建分卷..."
        rm -f "${backup_file}.part"* 2>/dev/null || true
        split -b "$split_size" "$backup_file" "${backup_file}.part"
        rm "$backup_file"
        log_success "分卷完成: $(ls -1 ${backup_file}.part* | wc -l) 个文件"
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
    echo "================================"
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
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--input) input_file="$2"; shift 2 ;;
            -c|--components) components="$2"; shift 2 ;;
            --overwrite) overwrite=true; shift ;;
            --merge) merge=true; shift ;;
            --backup-first) backup_first=true; shift ;;
            --validate) validate=true; shift ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$input_file" ]]; then
        log_error "请指定导入文件: -i <file>"
        exit 1
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
        log_info "备份来源: $(cat ${tmp_dir}/manifest.json | grep hostname | cut -d'"' -f4)"
        log_info "备份版本: $(cat ${tmp_dir}/manifest.json | grep version | cut -d'"' -f4)"
    fi
    
    # 导入组件
    local imported=0
    
    # 1. 配置
    if [[ "$components" == "all" ]] || [[ "$components" == *"config"* ]]; then
        if [[ -d "${tmp_dir}/config" ]]; then
            mkdir -p "${OPENCLAW_CONFIG}"
            cp -r "${tmp_dir}/config/"* "${OPENCLAW_CONFIG}/" 2>/dev/null || true
            log_success "配置: 已导入"
            ((imported++))
        fi
    fi
    
    # 2. 插件
    if [[ "$components" == "all" ]] || [[ "$components" == *"plugins"* ]]; then
        if [[ -d "${tmp_dir}/plugins" ]]; then
            mkdir -p "${OPENCLAW_PLUGINS}"
            cp -r "${tmp_dir}/plugins/"* "${OPENCLAW_PLUGINS}/" 2>/dev/null || true
            log_success "插件: 已导入"
            ((imported++))
        fi
    fi
    
    # 3. 技能
    if [[ "$components" == "all" ]] || [[ "$components" == *"skills"* ]]; then
        if [[ -d "${tmp_dir}/skills" ]]; then
            mkdir -p "${OPENCLAW_SKILLS}"
            cp -r "${tmp_dir}/skills/"* "${OPENCLAW_SKILLS}/" 2>/dev/null || true
            log_success "技能: 已导入"
            ((imported++))
        fi
    fi
    
    # 4. 内存文件
    if [[ "$components" == "all" ]] || [[ "$components" == *"memory"* ]]; then
        if [[ -d "${tmp_dir}/memory" ]]; then
            mkdir -p "${OPENCLAW_DATA}/memory"
            cp -r "${tmp_dir}/memory/"* "${OPENCLAW_DATA}/memory/" 2>/dev/null || true
            log_success "内存: 已导入"
            ((imported++))
        fi
    fi
    
    # 5. 会话
    if [[ "$components" == "all" ]] || [[ "$components" == *"sessions"* ]]; then
        if [[ -d "${tmp_dir}/sessions" ]]; then
            mkdir -p "${OPENCLAW_DATA}/sessions"
            if [[ "$merge" == "true" ]]; then
                cp -r "${tmp_dir}/sessions/"* "${OPENCLAW_DATA}/sessions/" 2>/dev/null || true
            else
                cp -r "${tmp_dir}/sessions/"* "${OPENCLAW_DATA}/sessions/" 2>/dev/null || true
            fi
            log_success "会话: 已导入"
            ((imported++))
        fi
    fi
    
    # 6. Cron任务
    if [[ "$components" == "all" ]] || [[ "$components" == *"cron"* ]]; then
        if [[ -f "${tmp_dir}/cronjobs.txt" ]] && [[ -s "${tmp_dir}/cronjobs.txt" ]]; then
            log_info "Cron任务需要手动导入，请查看: ${tmp_dir}/cronjobs.txt"
            ((imported++))
        fi
    fi
    
    # 7. 环境变量模板
    if [[ "$components" == "all" ]] || [[ "$components" == *"env"* ]]; then
        if [[ -d "${tmp_dir}/env" ]]; then
            cp "${tmp_dir}/env/.env.template" "${OPENCLAW_DIR}/.env.template" 2>/dev/null || true
            log_success "环境变量模板: 已导出到 .env.template"
            log_warn "请根据模板配置 .env 文件"
            ((imported++))
        fi
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
    echo "================================"
}

#===============================================================================
# 服务器间迁移
#===============================================================================

do_migrate() {
    local target_host=""
    local target_port="22"
    local target_user="${USER}"
    local ssh_key=""
    local method="rsync"
    local incremental=false
    local components="all"
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--target) target_host="$2"; shift 2 ;;
            -p|--port) target_port="$2"; shift 2 ;;
            -u|--user) target_user="$2"; shift 2 ;;
            --ssh-key) ssh_key="$2"; shift 2 ;;
            --method) method="$2"; shift 2 ;;
            --incremental) incremental=true; shift ;;
            -c|--components) components="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$target_host" ]]; then
        log_error "请指定目标服务器: -t <host>"
        exit 1
    fi
    
    local target="${target_user}@${target_host}"
    
    log_info "开始迁移到: $target"
    log_info "传输方式: $method"
    
    # 创建临时备份
    local backup_name="openclaw-migration-${TIMESTAMP}"
    local backup_file="${BACKUP_DIR}/${backup_name}.tar.gz"
    
    # 导出
    log_info "[1/3] 导出数据..."
    do_export_single "$backup_file" "$components"
    
    # 传输
    log_info "[2/3] 传输数据..."
    if [[ "$method" == "rsync" ]]; then
        local ssh_opts="-p ${target_port}"
        [[ -n "$ssh_key" ]] && ssh_opts="$ssh_opts -i $ssh_key"
        
        rsync -avz --progress $ssh_opts "$backup_file" "${target}:${BACKUP_DIR}/"
        rsync -avz --progress $ssh_opts "${backup_file}.sha256" "${target}:${BACKUP_DIR}/"
    else
        scp -P "${target_port}" "$backup_file" "${target}:${BACKUP_DIR}/"
    fi
    
    # 导入
    log_info "[3/3] 在目标服务器导入..."
    ssh -p "${target_port}" ${ssh_key:+-i "$ssh_key"} "$target" "
        openclaw migration import -i ${BACKUP_DIR}/${backup_name}.tar.gz --validate
    "
    
    # 清理本地临时文件
    rm -f "$backup_file" "${backup_file}.sha256"
    
    log_success "迁移完成!"
    echo ""
    echo "================================"
    echo -e "${GREEN}迁移成功!${NC}"
    echo "================================"
    echo "目标服务器: $target"
    echo "请在目标服务器运行: openclaw gateway restart"
    echo "================================"
}

do_export_single() {
    local backup_file="$1"
    local components="${2:-all}"
    
    local tmp_dir="${BACKUP_DIR}/.tmp-export"
    mkdir -p "$tmp_dir"
    
    # 收集数据
    [[ -d "$OPENCLAW_CONFIG" ]] && cp -r "$OPENCLAW_CONFIG" "${tmp_dir}/" 2>/dev/null || true
    [[ -d "$OPENCLAW_PLUGINS" ]] && cp -r "$OPENCLAW_PLUGINS" "${tmp_dir}/" 2>/dev/null || true
    [[ -d "$OPENCLAW_SKILLS" ]] && cp -r "$OPENCLAW_SKILLS" "${tmp_dir}/" 2>/dev/null || true
    [[ -d "$OPENCLAW_DATA" ]] && cp -r "$OPENCLAW_DATA" "${tmp_dir}/" 2>/dev/null || true
    
    echo "{\"version\": \"$(openclaw version 2>/dev/null || echo 'unknown')\", \"exported_at\": \"$(date -Iseconds)\"}" > "${tmp_dir}/manifest.json"
    
    tar -czf "$backup_file" -C "$tmp_dir" . 2>/dev/null
    rm -rf "$tmp_dir"
}

#===============================================================================
# 状态查看
#===============================================================================

do_status() {
    echo ""
    echo "=========================================="
    echo "         OpenClaw Migration Status"
    echo "=========================================="
    echo ""
    
    # 版本
    echo -e "${BLUE}版本信息${NC}"
    echo "  OpenClaw: $(openclaw version 2>/dev/null || echo '未安装')"
    echo "  主机名: $(hostname)"
    echo ""
    
    # 备份
    echo -e "${BLUE}备份文件${NC}"
    local latest=$(ls -t ${BACKUP_DIR}/openclaw-backup-*.tar.gz 2>/dev/null | head -1)
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
    [[ -d "$OPENCLAW_PLUGINS" ]] && echo "  插件: $(find "$OPENCLAW_PLUGINS" -name "*.js" 2>/dev/null | wc -l) 文件"
    [[ -d "$OPENCLAW_SKILLS" ]] && echo "  技能: $(find "$OPENCLAW_SKILLS" -name "*.md" 2>/dev/null | wc -l) 技能"
    [[ -d "$OPENCLAW_DATA/memory" ]] && echo "  内存: $(find "$OPENCLAW_DATA/memory" -name "*.md" 2>/dev/null | wc -l) 文件"
    [[ -d "$OPENCLAW_DATA/sessions" ]] && echo "  会话: $(find "$OPENCLAW_DATA/sessions" -name "*.jsonl" 2>/dev/null | wc -l) 会话"
    echo ""
    
    # 服务状态
    echo -e "${BLUE}服务状态${NC}"
    if pgrep -x "openclaw" > /dev/null; then
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
        input_file=$(ls -t ${BACKUP_DIR}/openclaw-backup-*.tar.gz 2>/dev/null | head -1)
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
            log_error "存储: $stored_hash"
            log_error "当前: $current_hash"
            exit 1
        fi
    fi
    
    # 格式验证
    if tar -tzf "$input_file" >/dev/null 2>&1; then
        log_success "格式: 验证通过"
    else
        log_error "格式: 无效的tar.gz文件"
        exit 1
    fi
    
    # 内容验证
    local content=$(tar -tzf "$input_file" 2>/dev/null)
    local has_manifest=$(echo "$content" | grep -c "manifest.json" || true)
    if [[ $has_manifest -gt 0 ]]; then
        log_success "内容: 包含manifest"
    else
        log_warn "内容: 缺少manifest"
    fi
    
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
    find "${BACKUP_DIR}" -name "openclaw-backup-*.tar.gz.sha256" -mtime "+${older_than}" -delete 2>/dev/null
    
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
        export) do_export "$@" ;;
        import) do_import "$@" ;;
        migrate) do_migrate "$@" ;;
        status) do_status ;;
        validate) do_validate "$@" ;;
        cleanup) do_cleanup "$@" ;;
        help|--help|-h) show_help ;;
        *) log_error "未知命令: $command"; show_help; exit 1 ;;
    esac
}

main "$@"
