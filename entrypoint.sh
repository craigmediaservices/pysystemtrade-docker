#!/bin/bash

# Load environment variables from .env file
set -a
[ -f .env ] && . .env
set +a

# Enable debugging
set -x

# Function to run as root
run_as_root() {
    # Remove potential stale lock files
    rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
    rm -f /tmp/.X2-lock /tmp/.X11-unix/X2

    echo "Starting SSH service..."
    service ssh start

    echo "Starting cron..."
    service cron start

    echo "Starting VNC..."
    mkdir -p /home/trader/.vnc
    echo ${VNC_PASSWORD} | vncpasswd -f > /home/trader/.vnc/passwd
    chmod 600 /home/trader/.vnc/passwd
    chown -R trader:trader /home/trader/.vnc

    echo "Starting supervisord..."
    supervisord -c /etc/supervisor/supervisord.conf

    echo "Switching to trader..."
    exec gosu trader "$0" trader_tasks
}

# Function to run as trader
run_as_trader() {
    #Setup environment
    source /home/trader/.env
    
    #Make .profile executable
    chmod +rx $HOME/.profile

    # Start VNC server
    vncserver :2 -geometry 1680x1050 -depth 24 || echo "Failed to start VNC server"
    # Set the DISPLAY variable for GUI applications
    export DISPLAY=:2

    # Start IBC Gateway
    bash /opt/ibc/gatewaystart.sh &

    #Startup for PySystemTrade and the Dashboard
    /home/trader/pysystemtrade/sysproduction/linux/scripts/startup  >> /home/trader/echos/startup.txt 2>&1
    /home/trader/pysystemtrade/private/dashboard >> /home/trader/echos/dashboard.txt 2>&1


    # Monitoring loop
    while true; do

      if ! pgrep -x "Xtightvnc" > /dev/null; then
        echo "Restarting VNC server..."
        vncserver :2 -geometry 1680x1050 -depth 24
      fi

      sleep 60
    done
}

# Main script execution
if [ "$1" = "trader_tasks" ]; then
    run_as_trader
else
    run_as_root
fi

