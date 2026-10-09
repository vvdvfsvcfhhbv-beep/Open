#!/bin/bash
# ─────────────────────────────────────────────
#  Railway · OpenCode + SSH  —  supervised startup
#  Ubuntu 24.04 · PID-based watchdog (no health-check polling)
# ─────────────────────────────────────────────

APP_PORT=${PORT:-8080}
SSH_PORT=2222
[ "$APP_PORT" = "$SSH_PORT" ] && APP_PORT=8080

# یه رمز برای همه — SSH و OpenCode هر دو از همین استفاده می‌کنن
SSH_PASSWORD=${SSH_PASSWORD:-changeme123}
export OPENCODE_SERVER_USERNAME="root"
export OPENCODE_SERVER_PASSWORD="$SSH_PASSWORD"

# PATH همیشه global — opencode بعد از نصب اینجاست
export PATH="$HOME/.opencode/bin:$PATH"

# جلوگیری از باز شدن مرورگر:
# ۱. fake xdg-open که هیچ کاری نمی‌کنه
mkdir -p /usr/local/bin
cat > /usr/local/bin/xdg-open << 'XDGEOF'
#!/bin/bash
# headless stub — silently ignore browser-open requests
exit 0
XDGEOF
chmod +x /usr/local/bin/xdg-open

# ۲. متغیرهای محیطی headless
export BROWSER=none
export DISPLAY=""

# ── Install OpenCode (once per container lifetime) ───
if ! command -v opencode >/dev/null 2>&1; then
  echo "📥 Installing OpenCode..."
  curl -fsSL https://opencode.ai/install | bash 2>&1 | grep -i "installed\|successfully\|error" || true
  echo "✓ OpenCode installed"
fi

# Persist across redeploys — mount a Railway Volume at this path
mkdir -p /root/.local/share/opencode

# ── SSH ──────────────────────────────────────
cat > /etc/ssh/sshd_config << SSHEOF
Port $SSH_PORT
PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords no
UsePAM no
X11Forwarding no
PrintMotd no
Subsystem sftp /usr/lib/openssh/sftp-server
SSHEOF

echo "root:$SSH_PASSWORD" | chpasswd

echo "════════════════════════════════"
echo "  OpenCode + SSH"
echo "  App port : $APP_PORT"
echo "  SSH port : $SSH_PORT"
echo "  SSH user : root"
echo "  SSH pass : $SSH_PASSWORD"
echo "  OC  pass : $SSH_PASSWORD"
echo "════════════════════════════════"

# ── Service launcher helpers ─────────────────

start_sshd() {
  /usr/sbin/sshd -D -f /etc/ssh/sshd_config &
  SSHD_PID=$!
  echo "$(date -u +%T) [sshd]     started (pid $SSHD_PID)"
}

start_app() {
  opencode web --port "$APP_PORT" --hostname 0.0.0.0 &
  APP_PID=$!
  echo "$(date -u +%T) [opencode] started (pid $APP_PID)"
}

# ── Start both services ───────────────────────
start_sshd
start_app

# ── PID-only watchdog ─────────────────────────
while true; do
  sleep 5

  if ! kill -0 "$SSHD_PID" 2>/dev/null; then
    echo "$(date -u +%T) [sshd]     exited — restarting"
    start_sshd
  fi

  if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "$(date -u +%T) [opencode] exited — restarting"
    start_app
  fi
done
