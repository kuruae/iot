FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl wget git vim fish \
    ca-certificates gnupg lsb-release \
    apt-transport-https \
    openssh-client \
    net-tools iputils-ping \
    bash-completion \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl \
    -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl

RUN curl -fsSL https://github.com/k3s-io/k3s/releases/latest/download/k3s \
    -o /usr/local/bin/k3s && chmod +x /usr/local/bin/k3s

RUN curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable" \
    > /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

RUN wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com jammy main" \
    > /etc/apt/sources.list.d/hashicorp.list && \
    apt-get update && apt-get install -y vagrant && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /iot

CMD ["/bin/fish"]
