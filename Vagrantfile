Vagrant.configure("2") do |config|
  
  # Base image (Ubuntu 22.04 LTS)
  config.vm.box = "bento/ubuntu-22.04"
  config.vm.box_version = "202502.21.0"
  config.vm.hostname = "flaskstarterlab"

  # Forwarded ports: access app on localhost
  config.vm.network "forwarded_port", guest: 80, host: 8080
  config.vm.network "forwarded_port", guest: 8000, host: 8000

  # VM resources
  config.vm.provider "virtualbox" do |vb|
    vb.name = "FlaskStarterLabVM"
    vb.memory = 1024
    vb.cpus = 2
  end

  # Provisioning with shell script
  config.vm.provision "shell", path: "provision.sh"

end
