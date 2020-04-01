all: architecture.png terraform-apply

terraform-init: shared/example-ca/example-ca-crt.der
	CHECKPOINT_DISABLE=1 \
	TF_LOG=TRACE \
	TF_LOG_PATH=terraform.log \
	terraform init
	CHECKPOINT_DISABLE=1 \
	terraform -v

terraform-apply: shared/example-ca/example-ca-crt.der ~/.ssh/id_rsa
	rm -f shared/vpn-client.zip
	CHECKPOINT_DISABLE=1 \
	TF_LOG=TRACE \
	TF_LOG_PATH=terraform.log \
	TF_VAR_admin_ssh_key_data="$(shell cat ~/.ssh/id_rsa.pub)" \
	time terraform apply
	terraform output ubuntu_ip_address >shared/ubuntu_ip_address.txt
	terraform output windows_ip_address >shared/windows_ip_address.txt
	$(MAKE) shared/vpn-client.zip

terraform-destroy: shared/example-ca/example-ca-crt.der
	CHECKPOINT_DISABLE=1 \
	TF_LOG=TRACE \
	TF_LOG_PATH=terraform.log \
	TF_VAR_admin_ssh_key_data="$(shell cat ~/.ssh/id_rsa.pub)" \
	time terraform destroy

terraform-destroy-gateway: shared/example-ca/example-ca-crt.der
	CHECKPOINT_DISABLE=1 \
	TF_LOG=TRACE \
	TF_LOG_PATH=terraform.log \
	TF_VAR_admin_ssh_key_data="$(shell cat ~/.ssh/id_rsa.pub)" \
	time terraform destroy -target azurerm_virtual_network_gateway.example

terraform-destroy-ubuntu: shared/example-ca/example-ca-crt.der
	CHECKPOINT_DISABLE=1 \
	TF_LOG=TRACE \
	TF_LOG_PATH=terraform.log \
	TF_VAR_admin_ssh_key_data="$(shell cat ~/.ssh/id_rsa.pub)" \
	time terraform destroy -target azurerm_virtual_machine.ubuntu

show-p2s-vpn-client-configuration: shared/vpn-client.zip
	@unzip -l shared/vpn-client.zip
	@echo "VPN Server: $$(unzip -p shared/vpn-client.zip '*VpnSettings.xml' | xmlstarlet sel -t -v /VpnProfile/VpnServer)"
	@echo "VPN Server CA $$(unzip -p shared/vpn-client.zip '*VpnSettings.xml' | xmlstarlet sel -t -v /VpnProfile/CaCert | base64 --decode | openssl x509 -noout -text -inform der)"
	@#echo "VPN Server Root $$(unzip -p shared/vpn-client.zip '*VpnServerRoot.cer' | openssl x509 -noout -text -inform der)"

shared/vpn-client.zip:
	./provision-vpn-client.sh

shared/example-ca/example-ca-crt.der:
	./provision-certificates.sh

~/.ssh/id_rsa:
	ssh-keygen -f $@ -t rsa -b 2048 -C "$$USER@$$(hostname --fqdn)" -N ''

architecture.png: architecture.uxf
	java -jar ~/Applications/Umlet/umlet.jar \
		-action=convert \
		-format=png \
		-filename=$< \
		-output=$@.tmp
	pngquant --ext .png --force $@.tmp.png
	mv $@.tmp.png $@

.PHONY: terraform-init terraform-apply terraform-destroy-gateway show-p2s-vpn-client-configuration
