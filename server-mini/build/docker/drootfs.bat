@echo off
set L=%~dp0log_drootfs.txt
docker rm -f gta2rootfs >nul 2>&1
docker run --platform linux/arm64 --name gta2rootfs -v "%~dp0dock\in":/in:ro ubuntu:24.04 bash /in/rootfs.sh > "%L%" 2>&1
docker export gta2rootfs | docker run --rm -i -v "%~dp0dock\in":/in:ro -v "%~dp0dock_out":/out debian:bookworm bash /in/mkimg.sh >> "%L%" 2>&1
echo DRDONE >> "%L%"
