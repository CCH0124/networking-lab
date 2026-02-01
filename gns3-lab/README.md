```bash
docker run  -d --name gns3-office --net=host --privileged -v gns3-data-office:/home/gns3/GNS3  gns3/gns3-server
```

```bash
docker run  -d     --name gns3     --net=host --privileged     -e BRIDGE_ADDRESS="172.21.1.1/24"     -v gns3-data:/data     jsimonetti/gns3-server:latest
```