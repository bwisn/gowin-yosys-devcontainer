Fixing permissions to the USB serial (run on host):
```bash
sudo tee /etc/udev/rules.d/99-usb-serial-dev.rules <<EOF
SUBSYSTEM=="tty", MODE="0666"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger
```