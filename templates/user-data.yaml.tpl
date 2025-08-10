#cloud-config
hostname: ${hostname}
fqdn: ${fqdn}
prefer_fqdn_over_hostname: true
create_hostname_file: true
manage_etc_hosts: true
users:
  - name: ${username}
    groups:
      - sudo
      - docker
    shell: /bin/bash
    ssh_authorized_keys:
      - ${ssh_public_key} 
    sudo: ALL=(ALL) NOPASSWD:ALL
packages:
  - curl
  - docker.io
  - unzip
  - python3
  - python3-pip
  - python3-venv
  - pylint
  - qemu-guest-agent
  - net-tools
  - openjdk-21-jre-headless
write_files:
  - path: /etc/systemd/system/jenkins-agent.service
    permissions: '0600'
    owner: jenkins:jenkins
    content: |
      [Unit]
      Description=Jenkins JNLP Agent
      After=network.target docker.service

      [Service]
      Type=simple
      User=jenkins
      WorkingDirectory=/opt/jenkins
      ExecStart=/usr/bin/java -jar /opt/jenkins/agent.jar -url ${master_url} -secret ${secret} -name "${hostname}" -workDir "${working_dir}"
      Restart=always

      [Install]
      WantedBy=multi-user.target
runcmd:
  # set timezone for EST
  - timedatectl set-timezone America/Toronto
  # enable and start qemu-guest-agent
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  # allow docker without sudo for jenkins
  - usermod -aG docker jenkins
  # create directory for Jenkins agent
  - mkdir -p /opt/jenkins
  - chown jenkins:jenkins /opt/jenkins
  # download Jenkins agent JAR
  - curl -o /opt/jenkins/agent.jar ${master_url}/jnlpJars/agent.jar
  - chown jenkins:jenkins /opt/jenkins/agent.jar
  # reload systemd and enable the jenkins-agent service
  - systemctl daemon-reexec
  - systemctl daemon-reload
  - systemctl enable jenkins-agent
  - systemctl start jenkins-agent
  # install hadolint
  - curl -sSL https://github.com/hadolint/hadolint/releases/download/v2.12.0/hadolint-Linux-x86_64 -o /usr/local/bin/hadolint
  - chmod +x /usr/local/bin/hadolint
  # install trivy
  - curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
  # user-data-cloud-config done
  - echo "done" > /var/log/user-data-cloud-config.done