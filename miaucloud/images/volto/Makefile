build:
	sudo podman build -t miaucloud-nixos/kingofsweden-volto:latest .

test:
	podman run --rm -it -p 3000:3000 \
		-e RAZZLE_API_PATH="https://kingofsweden.info" \
		-e RAZZLE_INTERNAL_API_PATH="https://kingofsweden.info" \
		miaucloud-nixos/kingofsweden-volto:latest
