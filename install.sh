#!/bin/bash
# ============================================================
#  BotCloud — Script de Instalação Automática
#  Execute com: bash install.sh
#  Compatível com Ubuntu 20.04/22.04 (Oracle Cloud, etc)
# ============================================================

set -e

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info()  { echo -e "${BLUE}[→]${NC} $1"; }

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   BotCloud — Instalação Automática       ║"
echo "║   Admin: jefersonrotello@gmail.com       ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── VERIFICAÇÕES ──────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  error "Execute como root: sudo bash install.sh"
fi

OS=$(lsb_release -si 2>/dev/null || echo "Unknown")
if [[ "$OS" != "Ubuntu" && "$OS" != "Debian" ]]; then
  warn "Sistema não testado ($OS). Continuando mesmo assim..."
fi

# ── PEGAR IP PÚBLICO ──────────────────────────────────────
PUBLIC_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "SEU_IP")
log "IP público detectado: $PUBLIC_IP"

# ── DOMÍNIO ───────────────────────────────────────────────
echo ""
read -p "Digite seu domínio (ou deixe vazio para usar o IP): " DOMAIN
if [ -z "$DOMAIN" ]; then
  DOMAIN=$PUBLIC_IP
  warn "Usando IP diretamente: $DOMAIN"
else
  log "Domínio configurado: $DOMAIN"
fi

# ── SENHA ADMIN ───────────────────────────────────────────
read -s -p "Defina a senha do painel admin: " ADMIN_PASS
echo ""
log "Senha admin configurada"

# ── ATUALIZAR SISTEMA ─────────────────────────────────────
echo ""
info "Atualizando sistema..."
apt-get update -qq && apt-get upgrade -y -qq
log "Sistema atualizado"

# ── INSTALAR NODE.JS 20 ───────────────────────────────────
info "Instalando Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
apt-get install -y nodejs -qq
log "Node.js $(node -v) instalado"

# ── INSTALAR PM2 ──────────────────────────────────────────
info "Instalando PM2 (gerenciador de processos)..."
npm install -g pm2 -q
pm2 startup ubuntu -u root --hp /root > /dev/null 2>&1
log "PM2 instalado"

# ── INSTALAR NGINX ────────────────────────────────────────
info "Instalando Nginx (proxy reverso)..."
apt-get install -y nginx -qq
log "Nginx instalado"

# ── INSTALAR CERTBOT (SSL) ────────────────────────────────
if [[ "$DOMAIN" != "$PUBLIC_IP" ]]; then
  info "Instalando Certbot para SSL grátis..."
  apt-get install -y certbot python3-certbot-nginx -qq
  log "Certbot instalado"
fi

# ── INSTALAR GIT ──────────────────────────────────────────
apt-get install -y git curl wget unzip -qq
log "Ferramentas instaladas"

# ── CRIAR DIRETÓRIO DO PROJETO ────────────────────────────
info "Criando estrutura do BotCloud..."
mkdir -p /opt/botcloud/{backend,frontend,data,sessions,logs,backups}
cd /opt/botcloud

# ── CRIAR PACKAGE.JSON DO BACKEND ────────────────────────
cat > /opt/botcloud/backend/package.json << 'EOF'
{
  "name": "botcloud-backend",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": { "start": "node server.js" },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "ws": "^8.14.2",
    "uuid": "^9.0.0",
    "fs-extra": "^11.1.1",
    "bcryptjs": "^2.4.3",
    "jsonwebtoken": "^9.0.2",
    "nodemailer": "^6.9.7",
    "node-cron": "^3.0.3",
    "mercadopago": "^2.0.6",
    "@whiskeysockets/baileys": "^6.5.0",
    "qrcode": "^1.5.3",
    "pino": "^8.15.0"
  }
}
EOF

# ── INSTALAR DEPENDÊNCIAS ─────────────────────────────────
info "Instalando dependências Node.js..."
cd /opt/botcloud/backend && npm install -q
log "Dependências instaladas"

# ── CRIAR ARQUIVO .ENV ────────────────────────────────────
cat > /opt/botcloud/backend/.env << EOF
PORT=4000
DOMAIN=$DOMAIN
ADMIN_EMAIL=jefersonrotello@gmail.com
ADMIN_PASS=$ADMIN_PASS
JWT_SECRET=$(openssl rand -hex 32)
MP_ACCESS_TOKEN=COLOQUE_SEU_TOKEN_AQUI
MP_PUBLIC_KEY=COLOQUE_SUA_CHAVE_AQUI
NODE_ENV=production
EOF
log "Arquivo .env criado"

# ── CONFIGURAR NGINX ──────────────────────────────────────
info "Configurando Nginx..."

cat > /etc/nginx/sites-available/botcloud << EOF
server {
    listen 80;
    server_name $DOMAIN;

    # Frontend
    location / {
        root /opt/botcloud/frontend;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }

    # API Backend
    location /api {
        proxy_pass http://localhost:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_cache_bypass \$http_upgrade;
    }

    # WebSocket (logs em tempo real)
    location /ws {
        proxy_pass http://localhost:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
    }

    client_max_body_size 50M;
}
EOF

ln -sf /etc/nginx/sites-available/botcloud /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx
log "Nginx configurado"

# ── SSL GRÁTIS ────────────────────────────────────────────
if [[ "$DOMAIN" != "$PUBLIC_IP" ]]; then
  info "Configurando SSL (HTTPS grátis)..."
  certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m jefersonrotello@gmail.com > /dev/null 2>&1
  log "SSL configurado — site rodando em https://$DOMAIN"
fi

# ── CONFIGURAR FIREWALL ───────────────────────────────────
info "Configurando firewall..."
ufw allow OpenSSH > /dev/null 2>&1
ufw allow 'Nginx Full' > /dev/null 2>&1
ufw --force enable > /dev/null 2>&1
log "Firewall configurado"

# ── SCRIPT DE BACKUP AUTOMÁTICO ───────────────────────────
cat > /opt/botcloud/backup.sh << 'BEOF'
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M)
tar -czf /opt/botcloud/backups/backup_$DATE.tar.gz /opt/botcloud/data /opt/botcloud/backend/sessions 2>/dev/null
# Mantém apenas os últimos 7 backups
ls -t /opt/botcloud/backups/backup_*.tar.gz | tail -n +8 | xargs rm -f 2>/dev/null
echo "Backup $DATE concluído"
BEOF
chmod +x /opt/botcloud/backup.sh

# Cron: backup todo dia às 3h da manhã
(crontab -l 2>/dev/null; echo "0 3 * * * /opt/botcloud/backup.sh >> /opt/botcloud/logs/backup.log 2>&1") | crontab -
log "Backup automático configurado (todo dia às 3h)"

# ── INICIAR BACKEND COM PM2 ───────────────────────────────
info "Iniciando BotCloud com PM2..."
cd /opt/botcloud/backend
pm2 start server.js --name "botcloud-backend" --max-memory-restart 500M
pm2 save > /dev/null 2>&1
log "Backend rodando com PM2"

# ── SCRIPT DE ATUALIZAÇÃO ─────────────────────────────────
cat > /opt/botcloud/update.sh << 'UEOF'
#!/bin/bash
echo "Atualizando BotCloud..."
cd /opt/botcloud/backend
pm2 stop botcloud-backend
npm install -q
pm2 start botcloud-backend
echo "Atualização concluída!"
UEOF
chmod +x /opt/botcloud/update.sh

# ── CRIAR SCRIPT DE MONITORAMENTO ────────────────────────
cat > /opt/botcloud/status.sh << 'SEOF'
#!/bin/bash
echo "=== BotCloud Status ==="
echo "PM2 Processos:"
pm2 list
echo ""
echo "Nginx:"
systemctl status nginx --no-pager -l | head -5
echo ""
echo "Uso de recursos:"
free -h
df -h /
SEOF
chmod +x /opt/botcloud/status.sh

# ── FINALIZADO ────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   ✅  BotCloud instalado com sucesso!                ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}🌐 Acesse sua plataforma:${NC}"
if [[ "$DOMAIN" != "$PUBLIC_IP" ]]; then
  echo "   https://$DOMAIN"
else
  echo "   http://$PUBLIC_IP"
fi
echo ""
echo -e "${GREEN}🔐 Painel Admin:${NC}"
echo "   Email: jefersonrotello@gmail.com"
echo "   Senha: (a que você definiu)"
echo ""
echo -e "${YELLOW}⚠️  Próximos passos:${NC}"
echo "   1. Copie os arquivos HTML para /opt/botcloud/frontend/"
echo "   2. Configure o Token do Mercado Pago em /opt/botcloud/backend/.env"
echo "   3. Acesse o painel admin e configure os planos"
echo ""
echo -e "${BLUE}📋 Comandos úteis:${NC}"
echo "   pm2 logs botcloud-backend    → ver logs ao vivo"
echo "   pm2 restart botcloud-backend → reiniciar"
echo "   bash /opt/botcloud/status.sh → ver status geral"
echo "   bash /opt/botcloud/backup.sh → fazer backup manual"
echo ""
