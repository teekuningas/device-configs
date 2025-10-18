sudo docker run -d \
    --name ollama  \
    --network=host \
    --restart=unless-stopped \
    -e OLLAMA_KEEP_ALIVE=180 \
    -e OLLAMA_CONTEXT_LENGTH=2048 \
    -e OLLAMA_NUM_THREADS=2 \
    -e OLLAMA_MAX_LOADED=1 \
    -v /opt/ollama:/root/.ollama \
    docker.io/ollama/ollama:0.12.6
