#!/bin/zsh

cat <<'EOF'
================================================================
MT3K Mac Tools — Instalador de Homebrew
================================================================
Esto va a correr el instalador oficial de https://brew.sh
Te va a pedir tu contraseña de admin (para Xcode Command Line Tools
y permisos en /opt/homebrew).

EOF

read -rsp "Pulsa Enter para continuar (Ctrl+C para cancelar)..." _
echo
echo

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

echo
echo "================================================================"
echo "✓ Listo. Volvé a MT3K Mac Tools y pulsá 'Re-verificar'."
echo "================================================================"
read -rsp "Pulsa Enter para cerrar esta ventana..." _
echo
