sudo docker run -d \
    --name caddy \
    --privileged \
    --restart=unless-stopped \
    --network=host \
    -v $(pwd)/Caddyfile:/etc/caddy/Caddyfile:ro \
    -v /var/run/tailscale/tailscaled.sock:/var/run/tailscale/tailscaled.sock \
    caddy:latest
