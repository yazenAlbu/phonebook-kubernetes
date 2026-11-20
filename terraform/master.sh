#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

hostnamectl set-hostname kube-master
swapoff -a
sed -i '/^[^#].*[[:space:]]swap[[:space:]]/ s/^/#/' /etc/fstab

apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=300 update
apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=300 install -y ca-certificates curl gpg ec2-instance-connect
install -d -m 0755 /etc/apt/keyrings
curl --retry 5 -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key -o /tmp/kubernetes-release.key
gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg /tmp/kubernetes-release.key
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' > /etc/apt/sources.list.d/kubernetes.list
apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=300 update
apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=300 install -y kubelet kubeadm kubectl kubernetes-cni docker.io
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now docker
systemctl enable kubelet
usermod -aG docker ubuntu

cat > /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd
systemctl restart containerd

MASTER_IP=$(hostname -I | awk '{print $1}')
KUBERNETES_VERSION=$(kubeadm version -o short)
kubeadm init --apiserver-advertise-address="$MASTER_IP" --pod-network-cidr=10.244.0.0/16 --kubernetes-version="$KUBERNETES_VERSION"

install -d -m 0700 -o ubuntu -g ubuntu /home/ubuntu/.kube
install -m 0600 -o ubuntu -g ubuntu /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
curl --retry 5 -fsSL https://github.com/flannel-io/flannel/releases/download/v0.28.10/kube-flannel.yml -o /home/ubuntu/kube-flannel.yml
chown ubuntu:ubuntu /home/ubuntu/kube-flannel.yml
su - ubuntu -c 'kubectl apply -f /home/ubuntu/kube-flannel.yml'
