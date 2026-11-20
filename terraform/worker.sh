#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

hostnamectl set-hostname kube-worker
swapoff -a
sed -i '/^[^#].*[[:space:]]swap[[:space:]]/ s/^/#/' /etc/fstab

apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=300 update
apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=300 install -y ca-certificates curl gpg unzip ec2-instance-connect
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

curl --retry 5 -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --update

aws ec2 wait instance-status-ok --region ${region} --instance-ids ${master-id}
JOIN_DIRECTORY=$(mktemp -d /root/phonebook-join.XXXXXX)
JOIN_KEY="$JOIN_DIRECTORY/id_rsa"
trap 'rm -rf "$JOIN_DIRECTORY"' EXIT
ssh-keygen -t rsa -b 3072 -f "$JOIN_KEY" -q -N ""

join_command=""
for attempt in $(seq 1 60); do
  if aws ec2-instance-connect send-ssh-public-key \
    --region ${region} \
    --availability-zone ${master-zone} \
    --instance-id ${master-id} \
    --instance-os-user ubuntu \
    --ssh-public-key "file://$JOIN_KEY.pub" > /dev/null; then
    join_command=$(ssh \
      -o ConnectTimeout=10 \
      -o IdentitiesOnly=yes \
      -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile="$JOIN_DIRECTORY/known_hosts" \
      -i "$JOIN_KEY" ubuntu@${master-private} \
      'sudo kubeadm token create --ttl 30m --print-join-command') || true
    if [ -n "$join_command" ]; then
      break
    fi
  fi
  sleep 10
done

if [ -z "$join_command" ]; then
  echo "Could not obtain the worker join command from the master."
  exit 1
fi

bash -c "$join_command"
