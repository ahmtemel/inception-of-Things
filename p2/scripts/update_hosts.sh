#!/bin/bash
# Bu script vagrant up sonrası HOST Mac'te çalışır
# /etc/hosts'a domain girişlerini ekler (zaten varsa tekrar eklemez)

HOSTS_FILE="/etc/hosts"
IP="192.168.56.110"

add_host() {
  local domain="$1"
  if grep -q "$domain" "$HOSTS_FILE"; then
    echo "Already exists: $domain"
  else
    echo "$IP $domain" | sudo tee -a "$HOSTS_FILE" > /dev/null
    echo "Added: $IP $domain"
  fi
}

add_host "app1.com"
add_host "app2.com"
add_host "app3.com"
add_host "denden.com"

echo "Done: /etc/hosts updated."
