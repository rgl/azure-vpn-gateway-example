# see https://github.com/hashicorp/terraform
terraform {
  required_version = "~> 0.12.24"
}

# see https://github.com/terraform-providers/terraform-provider-azurerm
provider "azurerm" {
  version = "~> 2.4.0"
  features {}
}

# NB you can test the relative speed from you browser to a location using https://azurespeedtest.azurewebsites.net/
# get the available locations with: az account list-locations --output table
variable "location" {
  default = "France Central" # see https://azure.microsoft.com/en-us/global-infrastructure/france/
}

# NB this name must be unique within the Azure subscription.
#    all the other names must be unique within this resource group.
variable "resource_group_name" {
  default = "rgl-vpn-gateway-example"
}

variable "tags" {
  type = map

  default = {
    owner = "rgl"
  }
}

variable "admin_username" {
  default = "rgl"
}

variable "admin_password" {
  default = "HeyH0Password"
}

# NB when you run make terraform-apply this is set from the TF_VAR_admin_ssh_key_data environment variable, which comes from the ~/.ssh/id_rsa.pub file.
variable "admin_ssh_key_data" {}

# NB you can change this with the TF_VAR_home_gateway_shared_key environment variable.
# NB use at least a 128-bit (16-bytes) key, e.g., generate one with: openssl rand -hex 16
variable "home_gateway_shared_key" {
  default = "1cb70637b2cd1ca8959fc0668ef6fb55"
}

variable "home_gateway_public_address" {
  default = "1.1.1.1" # NB you need to change this to your actual home gateway/vpn-device public address.
}

output "gateway_ip_address" {
  value = azurerm_public_ip.gateway.ip_address
}

output "ubuntu_ip_address" {
  value = azurerm_network_interface.ubuntu.private_ip_address
}

output "windows_ip_address" {
  value = azurerm_network_interface.windows.private_ip_address
}

resource "azurerm_resource_group" "example" {
  name     = var.resource_group_name # NB this name must be unique within the Azure subscription.
  location = var.location
  tags     = var.tags
}

# NB this generates a single random number for the resource group.
resource "random_id" "example" {
  keepers = {
    resource_group = azurerm_resource_group.example.name
  }

  byte_length = 10
}

resource "azurerm_storage_account" "diagnostics" {
  # NB this name must be globally unique as all the azure storage accounts share the same namespace.
  # NB this name must be at most 24 characters long.
  name = "diag${random_id.example.hex}"

  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_virtual_network" "example" {
  name                = "example"
  address_space       = ["10.101.0.0/16"]
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"                           # NB you MUST use this name. See the VPN Gateway FAQ.
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefix       = "10.101.1.0/24"
}

resource "azurerm_subnet" "backend" {
  name                 = "backend"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefix       = "10.101.2.0/24"
}

# NB do not try to get the azurerm_public_ip.gateway.fqdn value because
#    it always resolves to 255.255.255.255. instead, the gateway address
#    is obtained with make show-vpn-client-configuration.
resource "azurerm_public_ip" "gateway" {
  name                = "gateway"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  allocation_method   = "Dynamic"
}

resource "azurerm_virtual_network_gateway" "gateway" {
  name                = "gateway"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  type          = "Vpn"
  vpn_type      = "RouteBased"
  active_active = false
  enable_bgp    = false
  sku           = "VpnGw1"     # NB Basic sku does not support IKEv2.

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.gateway.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }

  vpn_client_configuration {
    address_space        = ["172.31.0.0/16"]
    vpn_client_protocols = ["SSTP", "IkeV2"] # NB IKEv2 is not supported by the Basic sku gateway.

    root_certificate {
      name             = "example-ca"
      public_cert_data = filebase64("shared/example-ca/example-ca-crt.der")
    }
  }
}

resource "azurerm_local_network_gateway" "home" {
  name                = "home"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  gateway_address     = var.home_gateway_public_address
  address_space       = ["192.168.0.0/16"]
}

resource "azurerm_virtual_network_gateway_connection" "home" {
  name                = "home"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.gateway.id
  local_network_gateway_id   = azurerm_local_network_gateway.home.id

  shared_key = var.home_gateway_shared_key

  # NB there is no way to change the ike sa lifetime from its fixed value of 28800 seconds.
  # see https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-about-vpn-devices#ipsec
  # see https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-ipsecikepolicy-rm-powershell
  # see https://www.terraform.io/docs/providers/azurerm/r/virtual_network_gateway_connection.html
  ipsec_policy {
    dh_group         = "DHGroup2048"
    ike_encryption   = "AES128"
    ike_integrity    = "SHA256"
    ipsec_encryption = "AES128"
    ipsec_integrity  = "SHA256"
    pfs_group        = "PFS2048"
    sa_datasize      = 104857600  # [KB] (104857600KB = 100GB)
    sa_lifetime      = 27000      # [Seconds] (27000s = 7.5h)
  }
}

resource "azurerm_network_interface" "ubuntu" {
  name                = "ubuntu"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location

  ip_configuration {
    name                          = "ubuntu"
    subnet_id                     = azurerm_subnet.backend.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.101.2.4" # NB Azure reserves the first four addresses in each subnet address range, so do not use those.
  }
}

resource "azurerm_virtual_machine" "ubuntu" {
  name                  = "ubuntu"
  resource_group_name   = azurerm_resource_group.example.name
  location              = azurerm_resource_group.example.location
  network_interface_ids = [azurerm_network_interface.ubuntu.id]
  vm_size               = "Standard_DS1_v2"

  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  storage_os_disk {
    name          = "ubuntu_os"
    caching       = "ReadWrite" # TODO is this advisable?
    create_option = "FromImage"

    #disk_size_gb      = "60" # this is optional. # TODO change this?
    managed_disk_type = "StandardSSD_LRS" # Locally Redundant Storage.
  }

  # see https://docs.microsoft.com/en-us/azure/virtual-machines/linux/cli-ps-findimage
  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  # NB this disk will not be initialized.
  #    so, you must format it yourself.
  # TODO add a provision step to initialize the disk.
  storage_data_disk {
    name              = "ubuntu_data"
    caching           = "ReadWrite"       # TODO is this advisable?
    create_option     = "Empty"
    disk_size_gb      = "10"
    lun               = 0
    managed_disk_type = "StandardSSD_LRS"
  }

  os_profile {
    computer_name  = "ubuntu"
    admin_username = var.admin_username
    admin_password = var.admin_password
  }

  os_profile_linux_config {
    disable_password_authentication = false

    ssh_keys {
      path     = "/home/${var.admin_username}/.ssh/authorized_keys"
      key_data = var.admin_ssh_key_data
    }
  }

  boot_diagnostics {
    enabled     = true
    storage_uri = azurerm_storage_account.diagnostics.primary_blob_endpoint
  }
}

resource "azurerm_network_interface" "windows" {
  name                = "windows"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location

  ip_configuration {
    name                          = "windows"
    subnet_id                     = azurerm_subnet.backend.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.101.2.5" # NB Azure reserves the first four addresses in each subnet address range, so do not use those.
  }
}

resource "azurerm_virtual_machine" "windows" {
  name                  = "windows"
  resource_group_name   = azurerm_resource_group.example.name
  location              = azurerm_resource_group.example.location
  network_interface_ids = [azurerm_network_interface.windows.id]
  vm_size               = "Standard_DS1_v2"

  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  storage_os_disk {
    name          = "windows_os"
    caching       = "ReadWrite" # TODO is this advisable?
    create_option = "FromImage"

    #disk_size_gb      = "60" # this is optional. # TODO change this?
    managed_disk_type = "StandardSSD_LRS" # Locally Redundant Storage.
  }

  # see https://docs.microsoft.com/en-us/azure/virtual-machines/windows/cli-ps-findimage
  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  # NB this disk will not be initialized.
  #    so, you must format it yourself.
  # TODO add a provision step to initialize the disk.
  storage_data_disk {
    name              = "windows_data"
    caching           = "ReadWrite"       # TODO is this advisable?
    create_option     = "Empty"
    disk_size_gb      = "10"
    lun               = 0
    managed_disk_type = "StandardSSD_LRS"
  }

  os_profile {
    computer_name  = "windows"
    admin_username = var.admin_username
    admin_password = var.admin_password
  }

  os_profile_windows_config {
    provision_vm_agent = false
    enable_automatic_upgrades = false
    timezone = "GMT Standard Time"
  }

  boot_diagnostics {
    enabled     = true
    storage_uri = azurerm_storage_account.diagnostics.primary_blob_endpoint
  }
}
