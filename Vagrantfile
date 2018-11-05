# to make sure all nodes are created in order, we
# have to force a --no-parallel execution.
ENV['VAGRANT_NO_PARALLEL'] = 'yes'

Vagrant.configure('2') do |config|
  config.vm.provider :libvirt do |lv, config|
    lv.memory = 2048
    lv.cpus = 2
    lv.cpu_mode = 'host-passthrough'
    # lv.nested = true
    lv.keymap = 'pt'
    config.vm.synced_folder '.', '/vagrant', type: 'nfs'
  end

  config.vm.provider :virtualbox do |vb|
    vb.linked_clone = true
    vb.memory = 2048
    vb.cpus = 2
  end

  config.vm.define 'windows-p2s-vpn-client' do |config|
    config.vm.provider :libvirt do |lv, config|
      config.vm.synced_folder '.', '/vagrant', type: 'smb', smb_username: ENV['USER'], smb_password: ENV['VAGRANT_SMB_PASSWORD']
    end
    config.vm.provider :virtualbox do |vb|
    end
    config.vm.box = 'windows-2016-amd64'
    config.vm.hostname = 'windows-vpn-client'
    config.vm.provision :shell, inline: "$env:chocolateyVersion='0.10.11'; iwr https://chocolatey.org/install.ps1 -UseBasicParsing | iex", name: "Install Chocolatey"
    config.vm.provision :shell, path: 'windows/ps.ps1', args: 'provision-base.ps1'
    config.vm.provision :shell, path: 'windows/ps.ps1', args: 'provision-p2s-vpn-client.ps1'
  end
end
