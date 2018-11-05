all: architecture.png terraform-apply

terraform-init: shared/example-ca/example-ca-crt.der
	CHECKPOINT_DISABLE=1 \
	TF_LOG=DEBUG \
	TF_LOG_PATH=terraform.log \
	terraform init

terraform-apply: shared/example-ca/example-ca-crt.der
	rm -f shared/vpn-client.zip
	CHECKPOINT_DISABLE=1 \
	TF_LOG=DEBUG \
	TF_LOG_PATH=terraform.log \
	TF_VAR_admin_ssh_key_data="$(shell cat ~/.ssh/id_rsa.pub)" \
	time terraform apply
	terraform output ubuntu_ip_address >shared/ubuntu_ip_address.txt
	$(MAKE) shared/vpn-client.zip

terraform-destroy: shared/example-ca/example-ca-crt.der
	CHECKPOINT_DISABLE=1 \
	TF_LOG=DEBUG \
	TF_LOG_PATH=terraform.log \
	TF_VAR_admin_ssh_key_data="$(shell cat ~/.ssh/id_rsa.pub)" \
	time terraform destroy

terraform-destroy-gateway: shared/example-ca/example-ca-crt.der
	CHECKPOINT_DISABLE=1 \
	TF_LOG=DEBUG \
	TF_LOG_PATH=terraform.log \
	TF_VAR_admin_ssh_key_data="$(shell cat ~/.ssh/id_rsa.pub)" \
	time terraform destroy -target azurerm_virtual_network_gateway.example

terraform-destroy-ubuntu: shared/example-ca/example-ca-crt.der
	CHECKPOINT_DISABLE=1 \
	TF_LOG=DEBUG \
	TF_LOG_PATH=terraform.log \
	TF_VAR_admin_ssh_key_data="$(shell cat ~/.ssh/id_rsa.pub)" \
	time terraform destroy -target azurerm_virtual_machine.ubuntu

show-p2s-vpn-client-configuration: shared/vpn-client.zip
	@unzip -l shared/vpn-client.zip
	@echo "VPN Server: $$(unzip -p shared/vpn-client.zip Generic/VpnSettings.xml | xmlstarlet sel -t -v /VpnProfile/VpnServer)"
	@echo "VPN Server CA $$(unzip -p shared/vpn-client.zip Generic/VpnSettings.xml | xmlstarlet sel -t -v /VpnProfile/CaCert | base64 --decode | openssl x509 -noout -text -inform der)"
	@#echo "VPN Server Root $$(unzip -p shared/vpn-client.zip Generic/VpnServerRoot.cer | openssl x509 -noout -text -inform der)"

shared/vpn-client.zip:
	./provision-vpn-client.sh

shared/example-ca/example-ca-crt.der:
	./provision-certificates.sh

architecture.png: architecture.uxf
	java -jar ~/Applications/Umlet/umlet.jar \
		-action=convert \
		-format=png \
		-filename=$< \
		-output=$@.tmp
	pngquant --ext .png --force $@.tmp.png
	mv $@.tmp.png $@

.PHONY: terraform-init terraform-apply terraform-destroy-gateway show-p2s-vpn-client-configuration
