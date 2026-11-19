@echo off
docker run --rm -v gta2w:/w -v "%~dp0dock\in":/in:ro -v "%~dp0dock_out":/out debian:bookworm bash /in/k318.sh > "%~dp0log_dk318.txt" 2>&1
echo DKDONE >> "%~dp0log_dk318.txt"
