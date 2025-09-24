# How to start MQTT publisher

Make the necessary configurations:
- Add MQTT broker in `docker-compose.yml`
  ```yaml
  mqtt-broker:
    image: eclipse-mosquitto
    container_name: mqtt-broker
    networks:
      - mraas
    ports:
      - "1883:1883"
    volumes:
      - ./apps/${SAMPLE_APP}/configs/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro
  ```

- Add MQTT broker to reverse proxy's depends_on. 
  ```yaml
  nginx::
    depends_on:
      - mqtt-broker
  ```

- `MQTT_HOST` and `MQTT_PORT` environment variable must be set for DL Streamer Pipeline Server prior to sending this curl request.
    You can add them to the `environments` for DL Streamer Pipeline Server section in `docker-compose.yml`.
    ```yaml
    dlstreamer-pipeline-server:
      environment:
        MQTT_HOST: nginx-reverse-proxy
        MQTT_PORT: 1883
    ```

Bring the services up. Restart them if already running.

    ```sh
    docker compose down # if already running
    docker compose up -d
    ```

The below CURL command publishes metadata to the MQTT broker and sends frames over WebRTC for streaming.

Assuming broker is running in the same host over port `1883`, replace the `<HOST_IP>` field with your system IP address.  
WebRTC Stream will be accessible at `http://<HOST_IP>:8889/mqttstream`.

```sh
curl http://<HOST_IP>:8080/pipelines/user_defined_pipelines/pallet_defect_detection_mqtt -X POST -H 'Content-Type: application/json' -d '{
    "source": {
        "uri": "file:///home/pipeline-server/resources/videos/warehouse.avi",
        "type": "uri"
    },
    "destination": {
        "metadata": {
            "type": "mqtt",
            "publish_frame":true,
            "topic": "pallet_defect_detection"
        },
        "frame": {
            "type": "webrtc",
            "peer-id": "mqttstream",
            "overlay": false
        }
    },
    "parameters": {
        "detection-properties": {
            "model": "/home/pipeline-server/resources/models/pallet-defect-detection/deployment/Detection/model/model.xml",
            "device": "CPU"
        }
    }
}'
```
In the above curl command set `publish_frame` to false if you don't want frames sent over MQTT. Metadata will be sent over MQTT.

Output can be viewed on MQTT subscriber as shown below.

```sh
docker run -it --rm \
  --network industrial-edge-insights-vision_mraas \
  --entrypoint mosquitto_sub \
  eclipse-mosquitto:latest \
  -h mqtt-broker -p 1883 -t pallet_defect_detection

# Note: Update --network above if it is different in your execution. Network can be found using: docker network ls
```